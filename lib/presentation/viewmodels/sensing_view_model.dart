import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/l10n/ar_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/num_utils.dart';
import '../../data/models/activity_event.dart';
import '../../data/models/connection_status.dart';
import '../../data/models/gait_profile.dart';
import '../../data/models/posture.dart';
import '../../data/models/sensing_frame.dart';
import '../../data/models/sleep_summary.dart';
import '../../data/models/vital_signs.dart';
import '../../data/repositories/sensing_repository.dart';
import '../../data/services/alert_dispatcher.dart';
import '../../data/services/emergency_dialer.dart';
import '../../data/services/monitoring_settings_repository.dart';
import '../../domain/monitoring/safety_monitor.dart';
import '../../domain/monitoring/safety_state.dart';
import '../../domain/twin/body_profile.dart';
import '../../domain/twin/body_shape.dart';
import '../../domain/twin/cloth_simulator.dart';
import '../../domain/twin/room_model.dart';
import '../../domain/twin/twin_engine.dart';
import '../../domain/twin/twin_state.dart';
import '../../domain/twin/vec3.dart';
import '../../data/services/body_profile_repository.dart';
import 'activity_rules.dart';

/// ViewModel لوحة الرصد: يستقبل إطارات الاستشعار، ينعّم العلامات الحيوية،
/// يستنتج الأحداث، ويقدّم حالة جاهزة للرسم (رادار، مؤشرات، سجل).
class SensingViewModel extends ChangeNotifier {
  SensingViewModel({
    required SensingDataSource repository,
    MonitoringSettingsRepository? monitoringSettings,
    AlertDispatcher? alertDispatcher,
    EmergencyDialer? emergencyDialer,
    SafetyMonitor? safetyMonitor,
    TwinEngine? twinEngine,
    BodyProfileRepository? bodyProfileRepository,
  })  : _repository = repository,
        _monitoringSettings =
            monitoringSettings ?? MonitoringSettingsRepository(),
        _alerts = alertDispatcher ?? AlertDispatcher(),
        _dialer = emergencyDialer ?? EmergencyDialer(),
        _safetyMonitor = safetyMonitor ?? SafetyMonitor(),
        _twinEngine = twinEngine ?? TwinEngine(),
        _bodyProfileRepository =
            bodyProfileRepository ?? BodyProfileRepository() {
    _framesSubscription = _repository.frames.listen(_handleFrame);
    _connectionSubscription =
        _repository.connection.listen(_handleConnectionSnapshot);
    _staleTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkStale());
  }

  static const int maxEvents = 60;
  static const Duration staleAfter = Duration(seconds: 6);

  final SensingDataSource _repository;
  final MonitoringSettingsRepository _monitoringSettings;
  final AlertDispatcher _alerts;
  final EmergencyDialer _dialer;
  final SafetyMonitor _safetyMonitor;
  final TwinEngine _twinEngine;
  final BodyProfileRepository _bodyProfileRepository;
  StreamSubscription<SensingFrame>? _framesSubscription;
  StreamSubscription<ConnectionSnapshot>? _connectionSubscription;
  Timer? _staleTimer;

  final List<ActivityEvent> _events = <ActivityEvent>[];
  final SampleRing _breathingHistory = SampleRing(48);
  final SampleRing _motionHistory = SampleRing(48);
  final SampleRing _signalHistory = SampleRing(48);
  final ExponentialMovingAverage _breathingAverage =
      ExponentialMovingAverage(alpha: 0.22);
  final RuleCooldowns _cooldowns = RuleCooldowns();
  final CooldownGate _connectionEventGate = CooldownGate(const Duration(seconds: 4));
  final CooldownGate _staleGate = CooldownGate(const Duration(seconds: 20));

  SensingFrame? _latest;
  SensingFrame? _previous;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  int _nextEventId = 1;
  bool _isStale = false;
  bool _disposed = false;
  bool _safetyInitialized = false;
  String _emergencyNumber = MonitoringSettingsRepository.defaultEmergencyNumber;
  TwinState _twin = TwinState.empty;
  List<BodyProfile> _bodyProfiles = const <BodyProfile>[];
  bool _twinInitialized = false;
  DateTime _lastTwinFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastAlertAt;

  // ── قراءات جاهزة للواجهة ──────────────────────────────────────────────
  SensingFrame? get latestFrame => _latest;

  bool get hasData => _latest != null;

  bool get hasPresence => _latest?.hasPresence ?? false;

  int get personCount => _latest?.personCount ?? 0;

  MotionLevel get motionLevel =>
      _latest?.classification.motionLevel ?? MotionLevel.unknown;

  double get motionIntensity => _latest?.motionIntensity ?? 0;

  double get signalQuality => _latest?.signalQuality ?? 0;

  double get averageRssi => _latest?.averageRssi ?? 0;

  int get nodeCount => _latest?.nodes.length ?? 0;

  VitalSigns? get vitalSigns => _latest?.vitalSigns;

  /// معدل التنفس المنعّم (يُفضّل على القراءة الخام لتقليل الوميض).
  double? get breathingRate {
    if (_breathingAverage.hasValue) return _breathingAverage.value;
    final double? raw = _latest?.breathingRateBpm;
    if (raw == null || raw <= 0) return null;
    return raw;
  }

  BreathingStatus get breathingStatus {
    final double? bpm = breathingRate;
    if (bpm == null || bpm <= 0) return BreathingStatus.unknown;
    if (bpm < VitalSigns.normalMinBpm) return BreathingStatus.slow;
    if (bpm > VitalSigns.normalMaxBpm) return BreathingStatus.fast;
    return BreathingStatus.normal;
  }

  double get breathingRatio => NumUtils.clamp01(
        NumUtils.mapRange(breathingRate ?? 0, 6, 30, 0, 1),
      );

  double get confidence => _latest?.classification.confidence ?? 0;

  DateTime? get lastFrameAt => _latest?.receivedAt;

  bool get isStale => _isStale;

  ConnectionStatus get status => _status;

  bool get isConnected => _status.isLive;

  String get source => _latest?.source ?? '—';

  List<ActivityEvent> get events => List<ActivityEvent>.unmodifiable(_events);

  List<double> get breathingHistory => _breathingHistory.values;

  List<double> get motionHistory => _motionHistory.values;

  List<double> get signalHistory => _signalHistory.values;

  DateTime? get lastAlertAt => _lastAlertAt;

  // ── حالة الرصد المتقدم (وضعية/سقوط/تسلل/مشية/نوم) ────────────────────
  SafetyState get safety => _safetyMonitor.state;

  PostureKind get posture => safety.posture;

  PostureSource get postureSource => safety.postureSource;

  List<PoseKeypoint> get poseKeypoints => safety.keypoints;

  bool get hasSkeleton => safety.hasSkeleton;

  FallAlert? get fallAlert => safety.fallAlert;

  IntrusionAlert? get intrusionAlert => safety.intrusionAlert;

  bool get intrusionArmed => safety.intrusionArmed;

  DateTime? get lastIntrusionAt => safety.lastIntrusionAt;

  SleepSummary get sleep => safety.sleep;

  GaitMatch? get gaitMatch => safety.gaitMatch;

  List<GaitProfile> get gaitProfiles => safety.gaitProfiles;

  bool get gaitCollecting => safety.gaitCollecting;

  String get emergencyNumber => _emergencyNumber;

  /// عدد الأنشطة الأمنية (حراسة + سقوط) في السجل الحالي.
  int get securityIncidentCount => _events
      .where(
        (ActivityEvent event) =>
            event.kind == ActivityKind.security ||
            event.kind == ActivityKind.fall,
      )
      .length;

  /// هل تم تحميل الإعدادات المحفوظة (وضع الحراسة/بصمات المشية)؟
  bool get safetyReady => _safetyInitialized;

  // ── التوأم الراديوي: جسم SMPL + غرفة RF-SLAM ──────────────────────────
  /// اللقطة الكاملة للتوأم (جسم + قماش + غرفة + هوية).
  TwinState get twin => _twin;

  /// الشكل البارامتري الحالي (معاملات β).
  BodyShape get bodyShape => _twin.shape;

  /// خريطة الغرفة والأثاث المستنتجة من الانعكاسات الثابتة.
  RoomModel get room => _twin.room;

  /// نسبة المفاصل المرصودة فعليًا من CSI.
  double get bodyCompletion => _twin.completionScore;

  /// التوأم المحفوظ المطابق حاليًا (إن وُجد).
  BodyMatch? get bodyMatch => _twin.match;

  /// كل التوائم المسجّلة في المكان.
  List<BodyProfile> get bodyProfiles => _bodyProfiles;

  /// هل يوجد جسم مرصود الآن؟
  bool get hasBodyTwin => _twin.hasBody;

  /// جزيئات القماش (للرسم).
  List<Vec3> get clothParticles => _twin.cloth;

  /// وصف الهوية الحالية.
  String get identityLabel => _twin.identityLabel;

  /// هل حُمّلت التوائم المحفوظة؟
  bool get twinReady => _twinInitialized;

  /// إنشاء «توأم مسبق» للشخص المرصود الآن. يرجع `false` إن لا يوجد جسم.
  Future<bool> enrollBodyProfile(String label) async {
    final BodyProfile? profile = _twinEngine.enrollProfile(
      label,
      gait: safety.gaitMatch?.profile.vector,
    );
    if (profile == null) {
      notifyListeners();
      return false;
    }

    _bodyProfiles = List<BodyProfile>.unmodifiable(
      <BodyProfile>[
        ..._bodyProfiles.where((BodyProfile p) => p.id != profile.id),
        profile,
      ],
    );
    _twinEngine.setProfiles(_bodyProfiles);
    await _bodyProfileRepository.save(_bodyProfiles);
    _logLocal(
      kind: ActivityKind.system,
      title: 'تم إنشاء توأم جسدي: ${profile.label}',
      detail: 'الطول التقديري ${(profile.shape.heightM * 100).round()} سم · '
          '${profile.shape.buildLabel}',
      tone: StatusTone.ok,
    );
    notifyListeners();
    return true;
  }

  /// حذف توأم محفوظ.
  Future<void> removeBodyProfile(String id) async {
    final List<BodyProfile> next = _bodyProfiles
        .where((BodyProfile profile) => profile.id != id)
        .toList(growable: false);
    if (next.length == _bodyProfiles.length) return;
    _bodyProfiles = List<BodyProfile>.unmodifiable(next);
    _twinEngine.setProfiles(_bodyProfiles);
    await _bodyProfileRepository.save(_bodyProfiles);
    notifyListeners();
  }

  /// البدء من جديد في مسح الغرفة (عند تغيّر الأثاث أو المكان).
  void resetRoomScan() {
    _twinEngine.resetRoom();
    _twin = _twin.copyWith(room: RoomModel.empty);
    notifyListeners();
  }

  // ── منطق ──────────────────────────────────────────────────────────────
  void _handleFrame(SensingFrame frame) {
    if (_disposed) return;

    _previous = _latest;
    _latest = frame;

    if (_isStale) {
      _isStale = false;
      _addEvent(
        ActivityEvent(
          id: _nextEventId++,
          kind: ActivityKind.system,
          title: ArStrings.eventDataResumed,
          tone: StatusTone.ok,
          timestamp: DateTime.now(),
        ),
      );
    }

    final double? bpm = frame.breathingRateBpm;
    if (bpm != null && bpm > 0) {
      _breathingAverage.add(bpm);
      _breathingHistory.add(bpm);
    }
    _motionHistory.add(frame.motionIntensity);
    _signalHistory.add(frame.signalQuality);

    // الرصد المتقدم أولًا حتى يبقى «أول إطار» في أعلى السجل عند البدء.
    _processSafety(frame);
    _processTwin(frame);
    _evaluateRules(frame);
    notifyListeners();
  }

  void _evaluateRules(SensingFrame frame) {
    final DateTime now = DateTime.now();
    final ActivityContext context = ActivityContext(
      previous: _previous,
      current: frame,
      nextId: () => _nextEventId++,
      now: now,
      cooldown: (String key) => _cooldowns.pass(key, now),
    );

    if (_previous == null) {
      _addEvent(
        ActivityEvent(
          id: _nextEventId++,
          kind: ActivityKind.system,
          title: ArStrings.eventFirstFrame,
          tone: StatusTone.ok,
          detail: frame.source,
          timestamp: now,
        ),
      );
      return;
    }

    for (final ActivityRule rule in ActivityRules.all) {
      final ActivityEvent? event = rule(context);
      if (event != null) {
        _addEvent(event);
      }
    }
  }

  /// تشغيل محرّك الرصد المتقدم على الإطار الحالي وتحويل إشاراته إلى أحداث.
  void _processSafety(SensingFrame frame) {
    final List<SafetySignal> signals = _safetyMonitor.ingest(
      frame,
      motionIntensity: frame.motionIntensity,
      breathingRate: breathingRate,
      now: frame.receivedAt,
    );
    for (final SafetySignal signal in signals) {
      _consumeSignal(signal);
    }
  }

  /// تحديث «التوأم الراديوي»: جسم SMPL + إكمال + تنعيم + قماش + غرفة.
  void _processTwin(SensingFrame frame) {
    if (_disposed) return;
    final DateTime now = frame.receivedAt;
    final Duration elapsed = _lastTwinFrameAt.millisecondsSinceEpoch == 0
        ? const Duration(milliseconds: 33)
        : now.difference(_lastTwinFrameAt);
    _lastTwinFrameAt = now;
    try {
      _twin = _twinEngine.update(
        frame: frame,
        posture: posture,
        keypoints: poseKeypoints,
        gait: safety.gaitMatch?.profile.vector,
        elapsed: elapsed,
      );
    } catch (_) {
      // فشل أي مرحلة من مراحل التوأم لا يجب أن يوقف الرصد الأساسي.
    }
  }

  /// تحميل الإعدادات المحفوظة (وضع الحراسة، رقم الطوارئ، بصمات المشية).
  Future<void> initialize() async {
    if (_safetyInitialized || _disposed) return;
    _safetyInitialized = true;
    try {
      _emergencyNumber = await _monitoringSettings.loadEmergencyNumber();
      final bool wasArmed = await _monitoringSettings.loadIntrusionArmed();
      final List<GaitProfile> profiles =
          await _monitoringSettings.loadGaitProfiles();
      if (_disposed) return;
      _safetyMonitor.setGaitProfiles(profiles);
      _bodyProfiles = await _bodyProfileRepository.load();
      _twinEngine.setProfiles(_bodyProfiles);
      _twinInitialized = true;
      if (wasArmed) {
        _safetyMonitor.setIntrusionArmed(true);
        _logLocal(
          kind: ActivityKind.security,
          title: 'تمت استعادة وضع الحراسة الأمنية',
          detail: 'الوضع كان مفعّلًا قبل إغلاق التطبيق',
          tone: StatusTone.warning,
        );
      }
      unawaited(_alerts.requestPermission());
    } catch (_) {
      // إعدادات غير متاحة (منصّة بلا تخزين) — المتابعة بالقيم الافتراضية.
    }
    notifyListeners();
  }

  /// تفعيل/إيقاف وضع الحراسة الأمنية.
  Future<void> setIntrusionArmed(bool armed) async {
    final List<SafetySignal> signals =
        _safetyMonitor.setIntrusionArmed(armed);
    for (final SafetySignal signal in signals) {
      _consumeSignal(signal);
    }
    notifyListeners();
    await _monitoringSettings.saveIntrusionArmed(armed);
  }

  /// إلغاء إنذار السقوط (دون حذفه من السجل).
  void acknowledgeFall() {
    if (!safety.hasFallAlert) return;
    _safetyMonitor.acknowledgeFall();
    _logLocal(
      kind: ActivityKind.fall,
      title: 'أُلغي إنذار السقوط يدويًا',
      tone: StatusTone.ok,
    );
    notifyListeners();
  }

  void acknowledgeIntrusion() {
    if (safety.intrusionAlert == null) return;
    _safetyMonitor.acknowledgeIntrusion();
    _logLocal(
      kind: ActivityKind.security,
      title: 'أُلغي تنبيه التسلل يدويًا',
      tone: StatusTone.ok,
    );
    notifyListeners();
  }

  /// تسجيل بصمة مشية بالاسم المعطى. ترجع `false` إن لم تكتمل نافذة العينات.
  Future<bool> enrollGait(String name) async {
    final GaitProfile? profile = _safetyMonitor.enrollGait(name);
    if (profile == null) {
      notifyListeners();
      return false;
    }
    _logLocal(
      kind: ActivityKind.gait,
      title: 'تم تسجيل بصمة مشية: ${profile.name}',
      detail: 'نافذة ${profile.vector.samples} عينة حركة',
      tone: StatusTone.ok,
    );
    notifyListeners();
    await _monitoringSettings.saveGaitProfiles(_safetyMonitor.gaitProfiles);
    return true;
  }

  Future<void> removeGaitProfile(String id) async {
    _safetyMonitor.removeGaitProfile(id);
    notifyListeners();
    await _monitoringSettings.saveGaitProfiles(_safetyMonitor.gaitProfiles);
  }

  /// تعديل رقم الطوارئ المستخدم في زر الاتصال.
  Future<bool> setEmergencyNumber(String number) async {
    final String cleaned = EmergencyDialer.sanitize(number);
    if (cleaned.isEmpty) return false;
    _emergencyNumber = cleaned;
    notifyListeners();
    return _monitoringSettings.saveEmergencyNumber(cleaned);
  }

  /// فتح لوحة الاتصال على رقم الطوارئ (لا يتصل تلقائيًا).
  Future<DialOutcome> callEmergency() async {
    final DialOutcome outcome = await _dialer.dial(_emergencyNumber);
    _logLocal(
      kind: ActivityKind.security,
      title: outcome == DialOutcome.dialerOpened
          ? 'فُتح تطبيق الهاتف على رقم الطوارئ $_emergencyNumber'
          : 'تعذّر فتح لوحة الاتصال — تم نسخ الرقم $_emergencyNumber',
      tone: outcome == DialOutcome.dialerOpened
          ? StatusTone.warning
          : StatusTone.idle,
    );
    notifyListeners();
    return outcome;
  }

  void _consumeSignal(SafetySignal signal) {
    _logLocal(
      kind: _activityKindFor(signal.kind),
      title: signal.title,
      detail: signal.detail,
      tone: _toneFor(signal.kind),
    );
    if (!signal.kind.isCritical) return;
    unawaited(
      _alerts.notify(
        title: signal.title,
        body: signal.detail ?? 'رُصد حدث يستدعي الانتباه في الغرفة',
        severity: signal.kind == SafetySignalKind.fall
            ? AlertSeverity.critical
            : AlertSeverity.warning,
      ),
    );
  }

  void _logLocal({
    required ActivityKind kind,
    required String title,
    String? detail,
    StatusTone tone = StatusTone.idle,
  }) {
    _addEvent(
      ActivityEvent(
        id: _nextEventId++,
        kind: kind,
        title: title,
        detail: detail,
        tone: tone,
        timestamp: DateTime.now(),
      ),
    );
  }

  static ActivityKind _activityKindFor(SafetySignalKind kind) =>
      switch (kind) {
        SafetySignalKind.fall => ActivityKind.fall,
        SafetySignalKind.intrusion ||
        SafetySignalKind.armed ||
        SafetySignalKind.disarmed =>
          ActivityKind.security,
        SafetySignalKind.gaitRecognized ||
        SafetySignalKind.gaitEnrolled =>
          ActivityKind.gait,
        SafetySignalKind.apnea || SafetySignalKind.sleepStateChanged =>
          ActivityKind.sleep,
        SafetySignalKind.postureChanged => ActivityKind.posture,
      };

  static StatusTone _toneFor(SafetySignalKind kind) => switch (kind) {
        SafetySignalKind.fall || SafetySignalKind.intrusion => StatusTone.danger,
        SafetySignalKind.apnea || SafetySignalKind.armed => StatusTone.warning,
        SafetySignalKind.disarmed ||
        SafetySignalKind.postureChanged ||
        SafetySignalKind.sleepStateChanged =>
          StatusTone.idle,
        _ => StatusTone.ok,
      };

  void _handleConnectionSnapshot(ConnectionSnapshot snapshot) {
    final ConnectionStatus previous = _status;
    _status = snapshot.status;
    final DateTime now = DateTime.now();

    if (previous == snapshot.status) {
      notifyListeners();
      return;
    }

    switch (snapshot.status) {
      case ConnectionStatus.connected:
        if (_connectionEventGate.tryPass(now)) {
          _addEvent(
            ActivityEvent(
              id: _nextEventId++,
              kind: ActivityKind.connection,
              title: ArStrings.eventConnected,
              detail: snapshot.message,
              tone: StatusTone.ok,
              timestamp: now,
            ),
          );
        }
      case ConnectionStatus.disconnected:
        if (previous.isLive && _connectionEventGate.tryPass(now)) {
          _addEvent(
            ActivityEvent(
              id: _nextEventId++,
              kind: ActivityKind.connection,
              title: ArStrings.eventDisconnected,
              tone: StatusTone.idle,
              timestamp: now,
            ),
          );
        }
      case ConnectionStatus.error:
        _addEvent(
          ActivityEvent(
            id: _nextEventId++,
            kind: ActivityKind.connection,
            title: ArStrings.eventConnectionError,
            detail: snapshot.message,
            tone: StatusTone.danger,
            timestamp: now,
          ),
        );
      case ConnectionStatus.reconnecting:
        if (_connectionEventGate.tryPass(now)) {
          _addEvent(
            ActivityEvent(
              id: _nextEventId++,
              kind: ActivityKind.connection,
              title: ArStrings.eventReconnecting,
              detail: snapshot.message,
              tone: StatusTone.warning,
              timestamp: now,
            ),
          );
        }
      case ConnectionStatus.connecting:
        break;
    }

    if (snapshot.status == ConnectionStatus.disconnected) {
      // لا نُبقي «آخر إطار» بعد الانقطاع: كل القراءات (تنفس، حضور، وضعية)
      // تصبح غير متاحة حتى تصل أول حزمة جديدة بعد إعادة الاتصال.
      _latest = null;
      _previous = null;
      _signalHistory.clear();
      _motionHistory.clear();
      _breathingHistory.clear();
      _breathingAverage.reset();
      _safetyMonitor.reset();
      _isStale = false;
    }

    notifyListeners();
  }

  void _checkStale() {
    if (_disposed || !_status.isLive) return;
    final DateTime? last = _latest?.receivedAt;
    if (last == null) return;
    final bool stale = DateTime.now().difference(last) > staleAfter;
    if (stale == _isStale) return;
    _isStale = stale;
    if (stale && _staleGate.tryPass(DateTime.now())) {
      _addEvent(
        ActivityEvent(
          id: _nextEventId++,
          kind: ActivityKind.signal,
          title: ArStrings.eventDataStale,
          tone: StatusTone.warning,
          timestamp: DateTime.now(),
        ),
      );
    }
    notifyListeners();
  }

  void _addEvent(ActivityEvent event) {
    _events.insert(0, event);
    if (_events.length > maxEvents) {
      _events.removeRange(maxEvents, _events.length);
    }
    _lastAlertAt = event.timestamp;
  }

  /// مسح سجل الأنشطة من الواجهة.
  void clearEvents() {
    _events.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _staleTimer?.cancel();
    unawaited(_framesSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    super.dispose();
  }
}
