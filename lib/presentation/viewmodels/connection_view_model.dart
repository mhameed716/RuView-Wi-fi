import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../../core/l10n/ar_strings.dart';
import '../../data/models/connection_settings.dart';
import '../../data/models/connection_status.dart';
import '../../data/models/sensing_frame.dart';
import '../../data/repositories/sensing_repository.dart';
import '../../data/services/lan_scanner.dart';
import '../../data/services/network_preferences_repository.dart';
import '../../data/services/settings_repository.dart';

/// مرحلة الاكتشاف التلقائي المعروضة في الواجهة.
enum DiscoveryPhase { idle, searching, found, connecting, connected, notFound, failed }

/// ViewModel شاشة لوحة التحكم: يملك حالة نموذج الاتصال، ويترجم أحداث
/// المستودع إلى حالة واجهة قابلة للعرض (حالة، مدة، معدل تحديث، أخطاء).
class ConnectionViewModel extends ChangeNotifier {
  ConnectionViewModel({
    required SensingRepository repository,
    required SettingsRepository settingsRepository,
    LanScanner? scanner,
    NetworkPreferencesRepository? networkPreferences,
    NetworkWatcher? networkWatcher,
    bool enableAutoDiscovery = true,
  })  : _enableAutoDiscovery = enableAutoDiscovery,
        _repository = repository,
        _settingsRepository = settingsRepository,
        _scanner = scanner ?? LanScanner(),
        _networkPreferences =
            networkPreferences ?? NetworkPreferencesRepository(),
        _networkWatcher = networkWatcher ?? NetworkWatcher();

  final SensingRepository _repository;
  final SettingsRepository _settingsRepository;
  final LanScanner _scanner;
  final NetworkPreferencesRepository _networkPreferences;
  final NetworkWatcher _networkWatcher;

  /// تعطيل الاكتشاف (للاختبارات أو التشغيل اليدوي الصرف).
  final bool _enableAutoDiscovery;

  StreamSubscription<ConnectionSnapshot>? _connectionSubscription;
  StreamSubscription<SensingFrame>? _framesSubscription;
  Timer? _ticker;

  bool _initialized = false;
  bool _disposed = false;

  // نموذج النموذج (form state)
  String _host = '192.168.1.100';
  String _portText = '8765';
  TransportKind _transport = TransportKind.webSocket;
  String _authToken = '';
  bool _secure = false;
  bool _showValidation = false;
  String? _formMessage;

  // ── الاكتشاف والاتصال التلقائي ──────────────────────────────────────────
  bool _autoConnect = true;
  bool _autoBusy = false;
  DiscoveryPhase _phase = DiscoveryPhase.idle;
  List<LanCandidate> _candidates = const <LanCandidate>[];
  NetworkContext _network = NetworkContext.offline;
  DateTime? _lastScanAt;
  String? _autoMessage;
  LanCandidate? _lastEndpoint;
  Completer<bool>? _pendingConnect;
  Timer? _autoRetryTimer;
  int _autoAttempts = 0;

  // حالة الاتصال
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _statusMessage;
  String? _errorMessage;
  DateTime? _connectedSince;
  Duration? _retryIn;
  int _attempt = 0;

  // قياسات حيّة
  int _frameCount = 0;
  DateTime? _lastFrameAt;
  double _frameRateHz = 0;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isInitialized => _initialized;
  bool get isBusy => _status.isBusy;
  bool get isConnected => _status.isLive;
  ConnectionStatus get status => _status;
  String? get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  Duration? get retryIn => _retryIn;
  int get attempt => _attempt;
  int get frameCount => _frameCount;
  double get frameRateHz => _frameRateHz;
  DateTime? get lastFrameAt => _lastFrameAt;

  String get host => _host;
  String get portText => _portText;
  TransportKind get transport => _transport;
  String get authToken => _authToken;
  bool get secure => _secure;
  String? get formMessage => _formMessage;
  bool get showValidation => _showValidation;

  /// الإعدادات الناتجة من النموذج الحالي.
  ConnectionSettings get draftSettings => ConnectionSettings(
        host: _host.trim(),
        port: int.tryParse(_portText.trim()) ?? 0,
        transport: _transport,
        authToken: _authToken.trim(),
        secure: _secure,
      );

  String? get hostError {
    final String value = _host.trim();
    if (value.isEmpty) return ArStrings.invalidHost;
    return draftSettings.isValidHost ? null : ArStrings.invalidHost;
  }

  String? get portError {
    final int? parsed = int.tryParse(_portText.trim());
    if (parsed == null) return ArStrings.invalidPort;
    if (parsed < 1 || parsed > 65535) return ArStrings.invalidPort;
    return null;
  }

  bool get isFormValid => hostError == null && portError == null;

  bool get canConnect => !isBusy && isFormValid;

  /// مدة الاتصال الحالية.
  Duration get uptime {
    final DateTime? since = _connectedSince;
    if (since == null) return Duration.zero;
    return DateTime.now().difference(since);
  }

  /// هل توقف وصول البيانات رغم بقاء الاتصال مفتوحًا؟
  bool get isDataStale {
    if (!_status.isLive) return false;
    final DateTime? last = _lastFrameAt ?? _connectedSince;
    if (last == null) return false;
    final Duration age = DateTime.now().difference(last);
    return age > const Duration(seconds: 8);
  }

  /// وصف حالة مختصر للعرض.
  String get statusLabel {
    if (_status == ConnectionStatus.connected && _transport == TransportKind.udp) {
      return ArStrings.statusUdpListening;
    }
    if (_status.isLive && isDataStale) return ArStrings.dataStale;
    return _status.arabicLabel;
  }

  String get endpointLabel => draftSettings.endpointLabel;

  /// تحميل الإعدادات المحفوظة وبدء الاستماع للمستودع.
  Future<void> initialize() async {
    if (_initialized) return;
    final ConnectionSettings saved = await _settingsRepository.load();
    _host = saved.host;
    _portText = saved.port.toString();
    _transport = saved.transport;
    _authToken = saved.authToken;
    _secure = saved.secure;

    _autoConnect = await _networkPreferences.loadAutoConnect();
    _lastEndpoint = await _networkPreferences.loadLastEndpoint();

    _connectionSubscription =
        _repository.connection.listen(_handleSnapshot);
    _framesSubscription = _repository.frames.listen(_handleFrame);
    _initialized = true;
    _safeNotify(force: true);

    if (_offlineEnvironment || !_enableAutoDiscovery) return;

    // الاتصال التلقائي: يعمل بمجرّد ارتباط الجهاز بأي شبكة.
    _networkWatcher.start(_handleNetworkUpdate);
    if (_autoConnect) {
      unawaited(runAutoConnect());
    }
  }

  // ── الاكتشاف والاتصال التلقائي ─────────────────────────────────────────
  /// هل الاتصال التلقائي مُفعّل؟
  bool get autoConnect => _autoConnect;

  /// مرحلة الاكتشاف الحالية.
  DiscoveryPhase get discoveryPhase => _phase;

  /// المرشّحون المكتشفون على الشبكة (مرتّبون بالأفضلية).
  List<LanCandidate> get candidates => _candidates;

  /// سياق الشبكة الحالي (العنوان المحلي والبوابة).
  NetworkContext get network => _network;

  String get networkLabel => _network.label;

  DateTime? get lastScanAt => _lastScanAt;

  /// رسالة توضيحية عن نتيجة الاكتشاف.
  String? get autoMessage => _autoMessage;

  /// هل نحن وسط بحث/محاولة اتصال؟
  bool get isDiscovering =>
      _phase == DiscoveryPhase.searching || _phase == DiscoveryPhase.connecting;

  /// آخر نقطة اتصال ناجحة (تُجرَّب أولًا في المرة القادمة).
  LanCandidate? get lastEndpoint => _lastEndpoint;

  /// وصف عربي لحالة الاكتشاف.
  String get discoveryLabel {
    switch (_phase) {
      case DiscoveryPhase.idle:
        return _autoConnect ? 'الاتصال التلقائي جاهز' : 'الاتصال التلقائي متوقف';
      case DiscoveryPhase.searching:
        return 'جارٍ البحث في الشبكة…';
      case DiscoveryPhase.found:
        return 'عُثر على ${_candidates.length} مرشّح';
      case DiscoveryPhase.connecting:
        return 'جارٍ تجربة الاتصال…';
      case DiscoveryPhase.connected:
        return 'متصل تلقائيًا';
      case DiscoveryPhase.notFound:
        return 'لم يُعثر على خادم RuView';
      case DiscoveryPhase.failed:
        return 'تعذّر الاتصال التلقائي';
    }
  }

  /// بيئة الاختبار: نُعطّل الشبكة تمامًا كي لا تعتمد الاختبارات على مقابس.
  static bool get _offlineEnvironment =>
      Platform.environment['FLUTTER_TEST'] == 'true';

  /// تشغيل/إيقاف الاتصال التلقائي (يُحفظ فورًا).
  Future<void> setAutoConnect(bool value) async {
    if (_autoConnect == value) return;
    _autoConnect = value;
    _phase = DiscoveryPhase.idle;
    await _networkPreferences.saveAutoConnect(value);
    _safeNotify(force: true);
    if (value && !isConnected) {
      unawaited(runAutoConnect());
    }
  }

  /// إعادة المسح يدويًا (مسح عميق).
  Future<void> rescan() => runAutoConnect(deep: true, force: true);

  /// اتصال مباشر بمرشّح مكتشف.
  Future<void> connectToCandidate(LanCandidate candidate) async {
    _autoBusy = true;
    _phase = DiscoveryPhase.connecting;
    _safeNotify(force: true);
    try {
      final bool ok = await _connectCandidate(candidate);
      _phase = ok ? DiscoveryPhase.connected : DiscoveryPhase.failed;
      _autoMessage =
          ok ? 'تم الاتصال بـ ${candidate.label}' : ArStrings.autoFailed;
      if (ok) {
        _lastEndpoint = candidate;
        await _networkPreferences.saveLastEndpoint(candidate);
      }
    } finally {
      _autoBusy = false;
      _safeNotify(force: true);
    }
  }

  /// الاكتشاف + الاتصال التلقائي على أي شبكة.
  Future<void> runAutoConnect({bool deep = true, bool force = false}) async {
    if (_disposed || _autoBusy) return;
    if (!_autoConnect && !force) return;
    if (isConnected && !force) return;

    _autoBusy = true;
    _phase = DiscoveryPhase.searching;
    _autoMessage = null;
    _safeNotify(force: true);

    try {
      final NetworkContext context =
          _network.isConnected ? _network : await NetworkContext.detect();
      _network = context;
      if (!context.isConnected) {
        _phase = DiscoveryPhase.notFound;
        _autoMessage = ArStrings.autoNoNetwork;
        return;
      }

      final Set<String> savedHosts = <String>{
        if (_lastEndpoint != null) _lastEndpoint!.host,
        _host,
      };
      final List<LanCandidate> found = await _scanner.scan(
        context: context,
        savedHosts: savedHosts,
        deep: deep,
      );
      _candidates = found;
      _lastScanAt = DateTime.now();

      if (found.isEmpty) {
        _phase = DiscoveryPhase.notFound;
        _autoMessage = ArStrings.autoNotFound;
        return;
      }

      _phase = DiscoveryPhase.found;
      _safeNotify(force: true);
      await _tryCandidates(found.take(4).toList(growable: false));
    } catch (_) {
      _phase = DiscoveryPhase.failed;
      _autoMessage = ArStrings.autoFailed;
    } finally {
      _autoBusy = false;
      _safeNotify(force: true);
    }
  }

  Future<void> _tryCandidates(List<LanCandidate> candidates) async {
    _phase = DiscoveryPhase.connecting;
    for (final LanCandidate candidate in candidates) {
      if (_disposed) return;
      _safeNotify(force: true);
      final bool ok = await _connectCandidate(candidate);
      if (ok) {
        _phase = DiscoveryPhase.connected;
        _autoMessage = 'تم الاتصال تلقائيًا بـ ${candidate.label}';
        _lastEndpoint = candidate;
        _autoAttempts = 0;
        await _networkPreferences.saveLastEndpoint(candidate);
        return;
      }
    }
    _phase = DiscoveryPhase.failed;
    _autoMessage = ArStrings.autoFailed;
  }

  /// يجرّب مرشّحًا واحدًا ويتحقق من وصول بيانات فعلية (لا يكفي فتح المقبس).
  Future<bool> _connectCandidate(LanCandidate candidate) async {
    _host = candidate.host;
    _portText = candidate.port.toString();
    _transport = candidate.transport;
    _errorMessage = null;
    _formMessage = null;
    _safeNotify(force: true);

    final Completer<bool> completer = Completer<bool>();
    _pendingConnect = completer;
    try {
      await _settingsRepository.save(draftSettings);
      await _repository.connect(draftSettings);
    } catch (_) {
      _pendingConnect = null;
      return false;
    }

    final bool live = await Future.any<bool>(<Future<bool>>[
      completer.future,
      Future<bool>.delayed(const Duration(seconds: 9), () => false),
    ]);
    _pendingConnect = null;
    if (!live) {
      await _repository.disconnect();
      return false;
    }

    final int before = _frameCount;
    for (int i = 0; i < 16; i++) {
      if (_disposed) return false;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (_frameCount > before) return true;
      if (!_status.isLive) return false;
    }

    await _repository.disconnect();
    return false;
  }

  void _handleNetworkUpdate(NetworkContext context, bool changed) {
    if (_disposed) return;
    final NetworkContext previous = _network;
    _network = context;
    if (!changed) return;
    if (previous.fingerprint == context.fingerprint) return;

    // شبكة جديدة → أعد المحاولة من الصفر.
    _autoAttempts = 0;
    _autoRetryTimer?.cancel();
    _safeNotify(force: true);
    if (_autoConnect && !isConnected) {
      unawaited(runAutoConnect());
    }
  }

  void _scheduleAutoRetry() {
    if (!_autoConnect || _disposed) return;
    if (_autoAttempts >= 5) return;
    _autoAttempts++;
    final Duration delay = Duration(seconds: 4 * _autoAttempts);
    _autoRetryTimer?.cancel();
    _autoRetryTimer = Timer(delay, () {
      if (_disposed || isConnected) return;
      unawaited(runAutoConnect(deep: false));
    });
  }

  // ── تعديلات النموذج ────────────────────────────────────────────────────
  void setHost(String value) {
    if (_host == value) return;
    _host = value;
    _formMessage = null;
    // بعد محاولة اتصال فاشلة نعرض الخطأ تحت الحقل مباشرة مع كل ضغطة مفتاح.
    _safeNotify(force: _showValidation);
  }

  void setPort(String value) {
    if (_portText == value) return;
    _portText = value;
    _formMessage = null;
    _safeNotify(force: _showValidation);
  }

  void setTransport(TransportKind value) {
    if (_transport == value) return;
    _transport = value;
    // منفذ UDP الافتراضي لعُقد ESP32 في RuView هو 5005.
    if (value == TransportKind.udp && _portText.trim() == '8765') {
      _portText = '5005';
    } else if (value == TransportKind.webSocket &&
        _portText.trim() == '5005') {
      _portText = '8765';
    }
    _safeNotify();
  }

  void setAuthToken(String value) {
    if (_authToken == value) return;
    _authToken = value;
    _safeNotify();
  }

  void setSecure(bool value) {
    if (_secure == value) return;
    _secure = value;
    _safeNotify();
  }

  void revealValidation() {
    if (_showValidation) return;
    _showValidation = true;
    _safeNotify();
  }

  // ── أوامر ─────────────────────────────────────────────────────────────
  /// ضغط زر الاتصال/القطع.
  Future<void> toggleConnection() async {
    if (_status.isLive || _status.isBusy) {
      await disconnect();
    } else {
      await connect();
    }
  }

  Future<bool> connect() async {
    _showValidation = true;
    _formMessage = null;
    if (!isFormValid) {
      _formMessage = '${hostError ?? ''} ${portError ?? ''}'.trim();
      // ضغط المستخدم على «اتصال» يجب أن يظهر نتيجته فورًا، لذلك نتجاوز
      // خانق التنبيهات (400ms) هنا.
      _safeNotify(force: true);
      return false;
    }

    _errorMessage = null;
    _retryIn = null;
    _attempt = 0;
    final ConnectionSettings settings = draftSettings;
    await _settingsRepository.save(settings);
    await _repository.connect(settings);
    _safeNotify(force: true);
    return true;
  }

  Future<void> disconnect() async {
    await _repository.disconnect();
    _errorMessage = null;
    _phase = DiscoveryPhase.idle;
    _autoMessage = null;
    _autoRetryTimer?.cancel();
    _autoAttempts = 0;
    _safeNotify(force: true);
  }

  /// حفظ الإعدادات دون اتصال (زر الحفظ في البطاقة).
  Future<bool> saveSettings() async {
    final bool ok = await _settingsRepository.save(draftSettings);
    _formMessage = ok ? ArStrings.settingsSaved : 'تعذّر حفظ الإعدادات';
    _safeNotify(force: true);
    return ok;
  }

  void _handleSnapshot(ConnectionSnapshot snapshot) {
    final ConnectionStatus previous = _status;
    _status = snapshot.status;
    _statusMessage = snapshot.message;
    _retryIn = snapshot.retryIn;
    _attempt = snapshot.attempt;

    switch (snapshot.status) {
      case ConnectionStatus.connected:
        _connectedSince ??= DateTime.now();
        _errorMessage = null;
      case ConnectionStatus.error:
        _errorMessage = snapshot.message ?? ArStrings.eventConnectionError;
        _connectedSince = null;
      case ConnectionStatus.disconnected:
        _connectedSince = null;
        _frameRateHz = 0;
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
        if (previous.isLive) _connectedSince = null;
    }

    final Completer<bool>? pending = _pendingConnect;
    if (pending != null && !pending.isCompleted) {
      if (snapshot.status.isLive) {
        pending.complete(true);
      } else if (snapshot.status.hasError) {
        pending.complete(false);
      }
    }

    if (snapshot.status.hasError && previous.isLive) {
      _scheduleAutoRetry();
    }

    _syncTicker();
    _safeNotify(force: true);
  }

  void _handleFrame(SensingFrame frame) {
    _frameCount++;
    final DateTime? previousAt = _lastFrameAt;
    _lastFrameAt = frame.receivedAt;

    if (previousAt != null) {
      final double delta = frame.receivedAt
              .difference(previousAt)
              .inMicroseconds /
          Duration.microsecondsPerSecond;
      if (delta > 0) {
        final double instant = 1 / delta;
        _frameRateHz =
            _frameRateHz == 0 ? instant : _frameRateHz * 0.85 + instant * 0.15;
      }
    }
    // تحديث الواجهة بمعدّل أقصى مرتين في الثانية.
    _safeNotify();
  }

  void _syncTicker() {
    final bool needTicker = _connectedSince != null;
    if (needTicker && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_disposed) return;
        _safeNotify(force: true);
      });
    } else if (!needTicker && _ticker != null) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _safeNotify({bool force = false}) {
    if (_disposed) return;
    final DateTime now = DateTime.now();
    if (!force && now.difference(_lastNotify) < const Duration(milliseconds: 400)) {
      return;
    }
    _lastNotify = now;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _autoRetryTimer?.cancel();
    _networkWatcher.dispose();
    final Completer<bool>? pending = _pendingConnect;
    if (pending != null && !pending.isCompleted) pending.complete(false);
    unawaited(_connectionSubscription?.cancel());
    unawaited(_framesSubscription?.cancel());
    super.dispose();
  }
}
