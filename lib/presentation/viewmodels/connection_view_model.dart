import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/l10n/ar_strings.dart';
import '../../data/models/connection_settings.dart';
import '../../data/models/connection_status.dart';
import '../../data/models/sensing_frame.dart';
import '../../data/repositories/sensing_repository.dart';
import '../../data/services/settings_repository.dart';

/// ViewModel شاشة لوحة التحكم: يملك حالة نموذج الاتصال، ويترجم أحداث
/// المستودع إلى حالة واجهة قابلة للعرض (حالة، مدة، معدل تحديث، أخطاء).
class ConnectionViewModel extends ChangeNotifier {
  ConnectionViewModel({
    required SensingRepository repository,
    required SettingsRepository settingsRepository,
  })  : _repository = repository,
        _settingsRepository = settingsRepository;

  final SensingRepository _repository;
  final SettingsRepository _settingsRepository;

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

    _connectionSubscription =
        _repository.connection.listen(_handleSnapshot);
    _framesSubscription = _repository.frames.listen(_handleFrame);
    _initialized = true;
    _safeNotify();
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
    unawaited(_connectionSubscription?.cancel());
    unawaited(_framesSubscription?.cancel());
    super.dispose();
  }
}
