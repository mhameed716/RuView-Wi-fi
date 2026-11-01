import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/l10n/ar_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/num_utils.dart';
import '../../data/models/activity_event.dart';
import '../../data/models/connection_status.dart';
import '../../data/models/sensing_frame.dart';
import '../../data/models/vital_signs.dart';
import '../../data/repositories/sensing_repository.dart';
import 'activity_rules.dart';

/// ViewModel لوحة الرصد: يستقبل إطارات الاستشعار، ينعّم العلامات الحيوية،
/// يستنتج الأحداث، ويقدّم حالة جاهزة للرسم (رادار، مؤشرات، سجل).
class SensingViewModel extends ChangeNotifier {
  SensingViewModel({required SensingDataSource repository})
      : _repository = repository {
    _framesSubscription = _repository.frames.listen(_handleFrame);
    _connectionSubscription =
        _repository.connection.listen(_handleConnectionSnapshot);
    _staleTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkStale());
  }

  static const int maxEvents = 60;
  static const Duration staleAfter = Duration(seconds: 6);

  final SensingDataSource _repository;
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
      _signalHistory.clear();
      _motionHistory.clear();
      _breathingHistory.clear();
      _breathingAverage.reset();
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
