import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../models/connection_settings.dart';
import '../models/connection_status.dart';
import 'sensing_transport.dart';

/// عميل بيانات الاستشعار من بوابة RuView.
///
/// لماذا ليس WebSocket فقط؟ لأن البوابات في الواقع ثلاثة أنواع:
///  1. بوابة RuView على `ws://host:8765/ws/sensing` (المسار الرسمي للاستشعار).
///  2. خادم الوضعية على `ws://host:8000/api/v1/stream/pose` (DensePose).
///  3. خادم يرفض ترقية WebSocket لكنه يخدم REST
///     (`GET /api/v1/sensing/latest`) — وهذا حال كثير من الإعدادات خلف
///     بروكسي/جدار ناري يمنع الترقية.
///
/// لذلك يجرّب العميل المسارين ثم ينتقل تلقائيًا إلى **وضع REST** بدل أن يظل
/// يعيد المحاولة بلا نهاية. وكل سبب فشل يُترجم إلى رسالة عربية صريحة تحمل
/// رمز HTTP، حتى يعرف المستخدم أن المنفذ ليس بوابة RuView أصلًا.
class WebSocketSensingTransport implements SensingTransport {
  WebSocketSensingTransport({
    this.connectTimeout = const Duration(seconds: 8),
    this.pingInterval = const Duration(seconds: 20),
    this.maxRetries = 0,
    this.pollInterval = const Duration(milliseconds: 300),
    this.restTimeout = const Duration(seconds: 3),
    this.onFrameRate,
  });

  /// مهلة فتح الاتصال.
  final Duration connectTimeout;

  /// فترة ping للتحقق من حياة الاتصال.
  final Duration pingInterval;

  /// 0 = محاولات غير محدودة (مع سقف زمني 30 ثانية بين المحاولات).
  final int maxRetries;

  /// فترة استطلاع REST عند تعذّر WebSocket.
  final Duration pollInterval;

  /// مهلة طلب REST الواحد (أقصر من مهلة WS كي لا يتعلّق الاكتشاف).
  final Duration restTimeout;

  /// مراقب اختياري لمعدل وصول الإطارات (Hz).
  final void Function(double hz)? onFrameRate;

  /// مسارات WebSocket التي تدعمها بوابات RuView.
  static const List<String> wsPaths = <String>[
    '/ws/sensing',
    '/api/v1/stream/pose',
  ];

  /// مسار REST البديل (يوفر أحدث إطار استشعار).
  static const String restPath = '/api/v1/sensing/latest';

  /// أقصى عدد إخفاقات متتالية في وضع REST قبل إعادة المحاولة من جديد.
  static const int restFailureLimit = 3;

  final StreamController<TransportEvent> _events =
      StreamController<TransportEvent>.broadcast();
  final math.Random _random = math.Random();

  WebSocket? _socket;
  HttpClient? _client;
  HttpClient? _restClient;
  ConnectionSettings? _settings;
  Timer? _retryTimer;
  Timer? _restTimer;
  bool _disposed = false;
  bool _manuallyClosed = false;
  bool _restMode = false;
  int _restFailures = 0;
  int _pathIndex = 0;
  int _attempt = 0;
  int _epoch = 0;
  DateTime? _lastFrameAt;
  double _frameRate = 0;

  static const List<int> _backoffSeconds = <int>[1, 2, 4, 8, 15, 30];

  @override
  Stream<TransportEvent> get events => _events.stream;

  @override
  bool get isActive => _socket != null || _restMode;

  /// هل نعمل الآن عبر استطلاع REST بدل WebSocket؟
  bool get usesRestFallback => _restMode;

  double get frameRateHz => _frameRate;

  @override
  Future<void> connect(ConnectionSettings settings) async {
    _settings = settings;
    _manuallyClosed = false;
    _attempt = 0;
    _pathIndex = 0;
    _stopRest();
    await _open();
  }

  Future<void> _open() async {
    if (_disposed || _manuallyClosed || _restMode) return;
    final ConnectionSettings? settings = _settings;
    if (settings == null) return;

    final Uri? base = settings.webSocketUri;
    if (base == null) {
      _emit(TransportEvent.failed('عنوان أو منفذ غير صالح'));
      return;
    }

    final Uri uri = _pathIndex == 0
        ? base
        : base.replace(path: wsPaths[_pathIndex]);
    final int epoch = ++_epoch;
    _emit(TransportEvent.connecting());

    try {
      final HttpClient client = HttpClient()..connectionTimeout = connectTimeout;
      _client = client;

      final WebSocket socket = await WebSocket.connect(
        uri.toString(),
        headers: settings.authHeaders,
        customClient: client,
      ).timeout(connectTimeout);

      // تجاهل اتصالًا وصل متأخرًا بعد إلغاء المستخدم أو محاولة أحدث.
      if (_disposed || _manuallyClosed || epoch != _epoch) {
        unawaited(socket.close(1000, 'superseded'));
        return;
      }

      _stopRest();
      _pathIndex = 0;
      _socket = socket;
      socket.pingInterval = pingInterval;
      _attempt = 0;
      _emit(TransportEvent.connected(message: settings.endpointLabel));

      socket.listen(
        _handlePayload,
        onError: (Object error, StackTrace stackTrace) {
          _emit(TransportEvent.failed(_humanize(error)));
          _handleClosed();
        },
        onDone: _handleClosed,
        cancelOnError: false,
      );
    } on TimeoutException {
      _closeQuietly();
      await _handleOpenFailure(
        uri,
        error: null,
        transient: true,
        message: 'انتهت مهلة الاتصال (${connectTimeout.inSeconds} ث)',
      );
    } catch (error) {
      _closeQuietly();
      await _handleOpenFailure(
        uri,
        error: error,
        transient: error is SocketException,
      );
    }
  }

  /// فشل فتح WebSocket: جرّب المسار التالي، ثم REST، ثم أعلن سببًا صريحًا.
  Future<void> _handleOpenFailure(
    Uri uri, {
    required Object? error,
    required bool transient,
    String? message,
  }) async {
    if (_disposed || _manuallyClosed) return;

    final int? status = await _probeStatus(uri);
    // «رفض» = الخادم موجود لكنه لم يرقِّ الاتصال (ليست مشكلة شبكة عابرة).
    final bool rejected = error is WebSocketException ||
        (status != null && status != HttpStatus.switchingProtocols);
    final bool permanent = rejected && !transient;

    if (permanent && _pathIndex < wsPaths.length - 1) {
      _pathIndex++;
      await _open();
      return;
    }

    if (permanent) {
      final String reason =
          status == null ? _humanize(error) : _describeStatus(status);
      if (await _tryRestMode(reason)) return;
      _emit(TransportEvent.failed(reason));
      return; // رفض دائم: لا فائدة من إعادة المحاولة كل 30 ثانية.
    }

    _emit(TransportEvent.failed(message ?? _humanize(error)));
    if (transient) _scheduleReconnect();
  }

  /// هل الخادم يردّ على نفس المسار عبر HTTP؟ نستخدم رمز الحالة للتشخيص.
  Future<int?> _probeStatus(Uri uri) async {
    final bool secure = _settings?.secure == true;
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2);
    try {
      final Uri httpUri = uri.replace(scheme: secure ? 'https' : 'http');
      final HttpClientRequest request = await client
          .getUrl(httpUri)
          .timeout(const Duration(seconds: 2));
      request.headers.set('User-Agent', 'RuView-WiFi/1.4');
      final HttpClientResponse response =
          await request.close().timeout(const Duration(seconds: 2));
      final int status = response.statusCode;
      await response.drain<void>();
      return status;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Uri? get _restUri {
    final ConnectionSettings? settings = _settings;
    if (settings == null || !settings.isValid) return null;
    return Uri(
      scheme: settings.secure ? 'https' : 'http',
      host: settings.host.trim(),
      port: settings.port,
      path: restPath,
    );
  }

  /// يحاول تشغيل وضع REST. يعيد `true` إذا وصل إطار صالح.
  Future<bool> _tryRestMode(String reason) async {
    final Map<String, dynamic>? first = await _fetchLatest();
    if (first == null || _disposed || _manuallyClosed) return false;

    _restMode = true;
    _restFailures = 0;
    _registerFrameTick();
    _emit(
      TransportEvent.connected(
        message: 'وضع REST — $reason',
      ),
    );
    _emit(TransportEvent.data(first));

    _restTimer?.cancel();
    _restTimer = Timer.periodic(pollInterval, (_) => unawaited(_pollOnce()));
    return true;
  }

  Future<void> _pollOnce() async {
    if (_disposed || _manuallyClosed || !_restMode) return;
    final Map<String, dynamic>? frame = await _fetchLatest();
    if (frame == null) {
      _restFailures++;
      if (_restFailures >= restFailureLimit) {
        _stopRest();
        _pathIndex = 0;
        _emit(
          TransportEvent.failed(
            'توقّف وضع REST — الخادم لم يُرسل بيانات ($restFailureLimit محاولات)',
          ),
        );
        _scheduleReconnect();
      }
      return;
    }
    _restFailures = 0;
    _registerFrameTick();
    _emit(TransportEvent.data(frame));
  }

  Future<Map<String, dynamic>?> _fetchLatest() async {
    final Uri? uri = _restUri;
    if (uri == null) return null;
    try {
      final HttpClient client =
          _restClient ??= HttpClient()..connectionTimeout = restTimeout;
      final HttpClientRequest request =
          await client.getUrl(uri).timeout(restTimeout);
      request.headers.set('User-Agent', 'RuView-WiFi/1.4');
      final String? token = _settings?.authToken.trim();
      if (token != null && token.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer $token');
      }
      final HttpClientResponse response =
          await request.close().timeout(restTimeout);
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      final String body =
          await response.transform(utf8.decoder).join().timeout(restTimeout);
      final Object? decoded = jsonDecode(body);
      final Map<String, dynamic>? map = _asStringMap(decoded);
      if (map == null || !_looksLikeSensing(map)) return null;
      return map;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _asStringMap(Object? decoded) {
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map<String, dynamic>(
        (Object? key, Object? value) => MapEntry<String, dynamic>('$key', value),
      );
    }
    return null;
  }

  static bool _looksLikeSensing(Map<String, dynamic> map) {
    final Object? type = map['type'];
    if (type is String && type == 'sensing_update') return true;
    return map.containsKey('classification') ||
        map.containsKey('features') ||
        map.containsKey('nodes') ||
        map.containsKey('persons');
  }

  void _handlePayload(Object? payload) {
    if (payload is String) {
      _decodeText(payload);
      return;
    }
    if (payload is List<int>) {
      // بعض البوابات ترسل JSON داخل إطار ثنائي.
      try {
        _decodeText(utf8.decode(payload));
      } catch (_) {
        // تجاهل الحزم الثنائية غير المدعومة على WebSocket.
      }
    }
  }

  void _decodeText(String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return;
    try {
      final Object? decoded = jsonDecode(trimmed);
      final Map<String, dynamic>? map = _asStringMap(decoded);
      if (map != null) {
        _registerFrameTick();
        _emit(TransportEvent.data(map));
      }
    } catch (_) {
      // ليست حزمة استشعار — يمكن أن تكون رسالة ترحيب نصية من الخادم.
    }
  }

  void _registerFrameTick() {
    final DateTime now = DateTime.now();
    final DateTime? previous = _lastFrameAt;
    _lastFrameAt = now;
    if (previous == null) return;
    final double deltaSeconds =
        now.difference(previous).inMicroseconds / Duration.microsecondsPerSecond;
    if (deltaSeconds <= 0) return;
    final double instant = 1 / deltaSeconds;
    _frameRate = _frameRate == 0 ? instant : _frameRate * 0.8 + instant * 0.2;
    onFrameRate?.call(_frameRate);
  }

  void _handleClosed() {
    if (_socket == null) return;
    _socket = null;
    _client = null;
    if (_disposed || _manuallyClosed) {
      _emit(TransportEvent.disconnected());
      return;
    }
    _emit(TransportEvent.disconnected(message: 'انقطع الاتصال بالخادم'));
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _manuallyClosed || _restMode) return;
    if (maxRetries > 0 && _attempt >= maxRetries) {
      _emit(TransportEvent.failed('تعذّر الاتصال بعد $_attempt محاولات'));
      return;
    }
    _attempt++;
    final int index = math.min(_attempt - 1, _backoffSeconds.length - 1);
    final int baseSeconds = _backoffSeconds[index];
    final int jitterMs = _random.nextInt(400);
    final Duration delay = Duration(seconds: baseSeconds, milliseconds: jitterMs);

    _emit(
      TransportEvent.reconnecting(
        retryIn: delay,
        attempt: _attempt,
        message: 'محاولة $_attempt بعد ${delay.inSeconds} ث',
      ),
    );

    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      unawaited(_open());
    });
  }

  void _stopRest() {
    _restTimer?.cancel();
    _restTimer = null;
    _restMode = false;
    _restFailures = 0;
    _restClient?.close(force: true);
    _restClient = null;
  }

  void _closeQuietly() {
    final WebSocket? socket = _socket;
    _socket = null;
    _client?.close(force: true);
    _client = null;
    if (socket != null) {
      unawaited(socket.close(1000, 'closing'));
    }
  }

  @override
  Future<void> disconnect() async {
    _manuallyClosed = true;
    _epoch++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _stopRest();
    final WebSocket? socket = _socket;
    if (socket != null) {
      try {
        await socket.close(1000, 'client disconnect');
      } catch (_) {
        // الإغلاق القسري مقبول هنا.
      }
    }
    _closeQuietly();
    _emit(TransportEvent.disconnected());
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _manuallyClosed = true;
    _retryTimer?.cancel();
    _stopRest();
    _closeQuietly();
    await _events.close();
  }

  void _emit(TransportEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  /// رسالة عربية صريحة حسب رمز HTTP الفعلي.
  static String _describeStatus(int? status) {
    if (status == null) return 'تعذّر الوصول إلى الخادم، تحقّق من الشبكة';
    if (status == 401 || status == 403) {
      return 'رفض الخادم الاتصال ($status) — تحقّق من رمز الوصول';
    }
    if (status == 404) {
      return 'لا يوجد مسار WebSocket على هذا المنفذ (404) — '
          'هذا المنفذ ليس بوابة RuView، جرّب 8765 أو 3000 أو 3001';
    }
    if (status == 426) {
      return 'الخادم يطلب ترقية WebSocket (426) — المسار مختلف، جرّب مسارًا آخر';
    }
    return 'الخادم يردّ HTTP $status ولا يرقّي الاتصال إلى WebSocket — '
        'هذا ليس منفذ بوابة RuView (8765 / 3000 / 3001)';
  }

  /// ترجمة أخطاء نظام التشغيل الشائعة إلى عربية صريحة + خطوة تالية.
  ///
  /// سبب الإصلاح: كانت الرسالة تظهر مختلطة مثل «تعذّر الوصول إلى الخادم —
  /// Connection refused»، وهي لا تخبر المستخدم أن المنفذ مغلق أصلًا.
  static String _humanizeSocket(String code) {
    final String lower = code.toLowerCase();
    if (lower.contains('refused')) {
      return 'المنفذ مغلق على هذا الجهاز: لا يوجد أي خادم يستمع عليه. '
          'شغّل بوابة RuView أو استخدم الوضع التجريبي';
    }
    if (lower.contains('timed out') || lower.contains('timeout')) {
      return 'لا ردّ من الجهاز (مهلة) — قد يمنع جدار الحماية هذا المنفذ';
    }
    if (lower.contains('unreachable') || lower.contains('no route')) {
      return 'الجهاز غير قابل للوصول — تأكّد أنك على نفس الشبكة';
    }
    if (lower.contains('reset') || lower.contains('abort')) {
      return 'قُطع الاتصال فورًا — الخادم يرفض هذا المنفذ أو يحجبه وسيط';
    }
    return code.isEmpty
        ? 'تعذّر الوصول إلى الخادم، تحقّق من الشبكة'
        : 'تعذّر الوصول إلى الخادم — $code';
  }

  /// تحويل أخطاء المقابس إلى رسائل عربية قابلة للتنفيذ.
  static String _humanize(Object? error) {
    if (error == null) return 'تعذّر فتح الاتصال بالخادم';
    if (error is TimeoutException) {
      return 'انتهت مهلة الاتصال بالخادم';
    }
    if (error is SocketException) {
      final String code =
          (error.osError?.message ?? error.message).trim();
      return _humanizeSocket(code);
    }
    if (error is WebSocketException) {
      final String message = error.message;
      if (message.contains('401')) {
        return 'رفض الخادم الاتصال: رمز الوصول غير صحيح (401)';
      }
      if (message.contains('404')) {
        return 'المسار /ws/sensing غير موجود على هذا الخادم (404)';
      }
      return message.isEmpty ? 'فشل تبادل WebSocket' : 'فشل WebSocket: $message';
    }
    if (error is HandshakeException) {
      return 'تعذّر إنشاء اتصال آمن (wss) — تحقّق من شهادة الخادم';
    }
    if (error is HttpException) {
      return 'خطأ HTTP: ${error.message}';
    }
    return 'خطأ غير متوقع: $error';
  }
}
