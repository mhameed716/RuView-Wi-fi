import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../models/connection_settings.dart';
import '../models/connection_status.dart';
import 'sensing_transport.dart';

/// عميل WebSocket لمسار `/ws/sensing` في بوابة RuView.
///
/// المزايا:
///  • مصادقة Bearer على ترقية الاتصال (مقبول للعملاء الأصليين — ADR-272).
///  • إعادة اتصال تلقائي بتباعد أسّي مع تشويش عشوائي.
///  • إبقاء الاتصال حيًّا عبر ping دوري (يكشف الشبكة الميتة).
///  • تحويل أخطاء الشبكة إلى رسائل عربية مفهومة.
class WebSocketSensingTransport implements SensingTransport {
  WebSocketSensingTransport({
    this.connectTimeout = const Duration(seconds: 8),
    this.pingInterval = const Duration(seconds: 20),
    this.maxRetries = 0,
    this.onFrameRate,
  });

  /// مهلة فتح الاتصال.
  final Duration connectTimeout;

  /// فترة ping للتحقق من حياة الاتصال.
  final Duration pingInterval;

  /// 0 = محاولات غير محدودة (مع سقف زمني 30 ثانية بين المحاولات).
  final int maxRetries;

  /// مراقب اختياري لمعدل وصول الإطارات (Hz).
  final void Function(double hz)? onFrameRate;

  final StreamController<TransportEvent> _events =
      StreamController<TransportEvent>.broadcast();
  final math.Random _random = math.Random();

  WebSocket? _socket;
  HttpClient? _client;
  ConnectionSettings? _settings;
  Timer? _retryTimer;
  bool _disposed = false;
  bool _manuallyClosed = false;
  int _attempt = 0;
  int _epoch = 0;
  DateTime? _lastFrameAt;
  double _frameRate = 0;

  static const List<int> _backoffSeconds = <int>[1, 2, 4, 8, 15, 30];

  @override
  Stream<TransportEvent> get events => _events.stream;

  @override
  bool get isActive => _socket != null;

  double get frameRateHz => _frameRate;

  @override
  Future<void> connect(ConnectionSettings settings) async {
    _settings = settings;
    _manuallyClosed = false;
    _attempt = 0;
    await _open();
  }

  Future<void> _open() async {
    if (_disposed || _manuallyClosed) return;
    final ConnectionSettings? settings = _settings;
    if (settings == null) return;

    final Uri? uri = settings.webSocketUri;
    if (uri == null) {
      _emit(TransportEvent.failed('عنوان أو منفذ غير صالح'));
      return;
    }

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
      _emit(TransportEvent.failed('انتهت مهلة الاتصال (${connectTimeout.inSeconds} ث)'));
      _scheduleReconnect();
    } catch (error) {
      _closeQuietly();
      _emit(TransportEvent.failed(_humanize(error)));
      _scheduleReconnect();
    }
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
      if (decoded is Map<String, dynamic>) {
        _registerFrameTick();
        _emit(TransportEvent.data(decoded));
      } else if (decoded is Map) {
        _registerFrameTick();
        _emit(
          TransportEvent.data(
            decoded.map<String, dynamic>(
              (Object? key, Object? value) =>
                  MapEntry<String, dynamic>('$key', value),
            ),
          ),
        );
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
    if (_disposed || _manuallyClosed) return;
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
    _closeQuietly();
    await _events.close();
  }

  void _emit(TransportEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  /// تحويل أخطاء المقابس إلى رسائل عربية قابلة للتنفيذ.
  static String _humanize(Object error) {
    if (error is TimeoutException) {
      return 'انتهت مهلة الاتصال بالخادم';
    }
    if (error is SocketException) {
      final String? code = error.osError?.message;
      if (code != null && code.isNotEmpty) {
        return 'تعذّر الوصول إلى الخادم — $code';
      }
      return 'تعذّر الوصول إلى الخادم، تحقّق من الشبكة';
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
