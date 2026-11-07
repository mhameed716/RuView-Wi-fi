import '../../data/models/gait_profile.dart';
import '../../data/models/posture.dart';
import '../../data/models/sensing_frame.dart';
import '../../data/models/sleep_summary.dart';
import 'fall_detector.dart';
import 'gait_analyzer.dart';
import 'intrusion_detector.dart';
import 'posture_estimator.dart';
import 'safety_state.dart';
import 'sleep_monitor.dart';

/// المحرّك الموحّد للرصد المتقدم.
///
/// يجمع خمس قدرات في خط واحد يُغذّى بإطارات الاستشعار:
///  1. تقدير الوضعية (HAR).
///  2. بصمة المشية (تسجيل/تعرّف استرشادي).
///  3. كشف السقوط.
///  4. وضع الحراسة الأمنية (تسلل).
///  5. مراقبة النوم والعلامات الحيوية (بما فيها اضطراب التنفس).
///
/// المحرّك **نقي** (بلا Flutter ولا شبكة) لذلك يمكن اختباره مباشرة، ويُصدر
/// [SafetySignal] لكل حدث يستحق التسجيل في سجل الأنشطة.
class SafetyMonitor {
  SafetyMonitor({
    FallDetector? fallDetector,
    GaitAnalyzer? gaitAnalyzer,
    SleepMonitor? sleepMonitor,
    IntrusionDetector? intrusionDetector,
    this.gaitSimilarityThreshold = 0.82,
    this.requiredGaitStreak = 2,
    this.gaitEvaluationInterval = const Duration(seconds: 2),
  })  : _fallDetector = fallDetector ?? FallDetector(),
        _gaitAnalyzer = gaitAnalyzer ?? GaitAnalyzer(),
        _sleepMonitor = sleepMonitor ?? SleepMonitor(),
        _intrusionDetector = intrusionDetector ?? IntrusionDetector();

  /// أدنى تشابه لقبول مطابقة المشية.
  final double gaitSimilarityThreshold;

  /// عدد المطابقات المتتالية المطلوبة لتثبيت الهوية (يمنع الوميض).
  final int requiredGaitStreak;

  /// أقل مدة بين تقييمَي مطابقة.
  final Duration gaitEvaluationInterval;

  /// أقل مدة بين إشارتَي تغيّر وضعية (يمنع إغراق السجل عند التذبذب).
  static const Duration postureSignalGate = Duration(seconds: 3);

  /// أقل مدة بين إشارتَي تغيّر حالة النوم.
  static const Duration sleepSignalGate = Duration(seconds: 15);

  final FallDetector _fallDetector;
  final GaitAnalyzer _gaitAnalyzer;
  final SleepMonitor _sleepMonitor;
  final IntrusionDetector _intrusionDetector;

  final Map<String, int> _streaks = <String, int>{};
  List<GaitProfile> _profiles = <GaitProfile>[];

  SafetyState _state = const SafetyState();
  DateTime? _lastGaitEvaluationAt;
  DateTime? _lastPostureSignalAt;
  DateTime? _lastSleepSignalAt;

  SafetyState get state => _state;

  /// تفعيل/إيقاف وضع الحراسة الأمنية.
  List<SafetySignal> setIntrusionArmed(bool armed, {DateTime? now}) {
    final DateTime at = now ?? DateTime.now();
    _intrusionDetector.setArmed(armed, now: at);
    _state = _state.copyWith(
      intrusionArmed: armed,
      armedAt: armed ? at : null,
      clearIntrusionAlert: !armed,
    );
    return <SafetySignal>[
      SafetySignal(
        kind: armed ? SafetySignalKind.armed : SafetySignalKind.disarmed,
        title: armed ? 'تم تفعيل وضع الحراسة الأمنية' : 'تم إيقاف وضع الحراسة',
        detail: armed
            ? 'أي حركة بعد ${_intrusionDetector.armDelay.inSeconds} ثانية ستُعتبر تسللًا'
            : null,
      ),
    ];
  }

  /// تحميل بصمات المشية المحفوظة.
  void setGaitProfiles(List<GaitProfile> profiles) {
    _profiles = List<GaitProfile>.unmodifiable(profiles);
    _state = _state.copyWith(gaitProfiles: _profiles);
  }

  List<GaitProfile> get gaitProfiles => _profiles;

  /// آخر متجه مشية صالح (يُستخدم للتسجيل).
  GaitFeatureVector? currentGaitVector({DateTime? now}) =>
      _gaitAnalyzer.currentVector(now ?? DateTime.now());

  /// تسجيل بصمة مشية جديدة بالاسم المعطى. تُرجع `null` إن لم تكتمل النافذة.
  GaitProfile? enrollGait(String name, {DateTime? now}) {
    final DateTime at = now ?? DateTime.now();
    final GaitFeatureVector? vector = _gaitAnalyzer.currentVector(at);
    if (vector == null) return null;

    final String trimmed = name.trim();
    final GaitProfile profile = GaitProfile(
      id: 'gait_${at.millisecondsSinceEpoch}',
      name: trimmed.isEmpty ? 'شخص ${_profiles.length + 1}' : trimmed,
      vector: vector,
      enrolledAt: at,
    );
    _profiles = List<GaitProfile>.unmodifiable(<GaitProfile>[..._profiles, profile]);
    _state = _state.copyWith(gaitProfiles: _profiles);
    return profile;
  }

  /// حذف بصمة.
  void removeGaitProfile(String id) {
    _profiles = List<GaitProfile>.unmodifiable(
      _profiles.where((GaitProfile profile) => profile.id != id),
    );
    _state = _state.copyWith(gaitProfiles: _profiles);
  }

  /// إلغاء تنبيه السقوط الظاهر (مع بقاء السجل).
  void acknowledgeFall() {
    _state = _state.copyWith(clearFallAlert: true);
  }

  /// إلغاء تنبيه التسلل الظاهر.
  void acknowledgeIntrusion() {
    _state = _state.copyWith(clearIntrusionAlert: true);
  }

  /// تغذية المحرّك بإطار جديد.
  List<SafetySignal> ingest(
    SensingFrame frame, {
    required double motionIntensity,
    required double? breathingRate,
    DateTime? now,
  }) {
    final DateTime at = now ?? frame.receivedAt;
    final List<SafetySignal> signals = <SafetySignal>[];

    // ── 1) الوضعية ─────────────────────────────────────────────────────
    final PostureEstimate estimate = PostureEstimator.estimate(frame);
    final PostureKind previousPosture = _state.posture;
    final DateTime? lastPostureSignal = _lastPostureSignalAt;
    final bool postureSignalAllowed = lastPostureSignal == null ||
        at.difference(lastPostureSignal) >= postureSignalGate;
    if (estimate.posture.isKnown &&
        estimate.posture != previousPosture &&
        postureSignalAllowed) {
      _lastPostureSignalAt = at;
      signals.add(
        SafetySignal(
          kind: SafetySignalKind.postureChanged,
          title: 'الحالة الحالية: ${estimate.posture.arabicLabel}',
          detail: 'المصدر: ${estimate.source.arabicLabel}',
          confidence: estimate.confidence,
        ),
      );
    }

    // ── 2) السقوط ──────────────────────────────────────────────────────
    final bool serverFall = _serverReportedFall(frame);
    final FallAlert? fall = _fallDetector.evaluate(
      posture: estimate.posture,
      motionIntensity: motionIntensity,
      now: at,
      serverReportedFall: serverFall,
    );
    if (fall != null) {
      _state = _state.copyWith(fallAlert: fall, lastFallAt: fall.detectedAt);
      signals.add(
        SafetySignal(
          kind: SafetySignalKind.fall,
          title: '⚠️ تنبيه طارئ: تم رصد حالة سقوط',
          detail: '${fall.reason} — الثقة ${fall.confidenceLabel}',
          confidence: fall.confidence,
        ),
      );
    }

    // ── 3) التسلل ──────────────────────────────────────────────────────
    final IntrusionAlert? intrusion = _intrusionDetector.evaluate(
      frame: frame,
      motionIntensity: motionIntensity,
      now: at,
    );
    if (intrusion != null) {
      _state = _state.copyWith(
        intrusionAlert: intrusion,
        lastIntrusionAt: intrusion.detectedAt,
      );
      signals.add(
        SafetySignal(
          kind: SafetySignalKind.intrusion,
          title: '🚨 حركة مرصودة في وضع الحراسة',
          detail: 'شدة الحركة ${(intrusion.motionIntensity * 100).round()}%'
              '${intrusion.zone == null ? '' : ' — ${intrusion.zone}'}',
          confidence: intrusion.confidence,
        ),
      );
    }

    // ── 4) المشية ──────────────────────────────────────────────────────
    _gaitAnalyzer.add(frame, motionIntensity: motionIntensity, at: at);
    if (_profiles.isNotEmpty) {
      final DateTime? lastEvaluation = _lastGaitEvaluationAt;
      if (lastEvaluation == null ||
          at.difference(lastEvaluation) >= gaitEvaluationInterval) {
        _lastGaitEvaluationAt = at;
        final GaitMatch? match = _matchGait(at);
        final String? previousId = _state.gaitMatch?.profile.id;
        if (match != null && match.profile.id != previousId) {
          _state = _state.copyWith(gaitMatch: match);
          signals.add(
            SafetySignal(
              kind: SafetySignalKind.gaitRecognized,
              title: 'تعرّف على المشية: ${match.profile.name}',
              detail: 'تشابه ${match.similarityLabel}',
              confidence: match.similarity,
            ),
          );
        }
      }
    }

    // ── 5) النوم والعلامات الحيوية ─────────────────────────────────────
    final SleepSummary previousSleep = _state.sleep;
    final SleepSummary sleep = _sleepMonitor.ingest(
      hasPresence: frame.hasPresence,
      posture: estimate.posture,
      breathingRate: breathingRate,
      motionIntensity: motionIntensity,
      now: at,
    );
    if (sleep.apneaEvents > previousSleep.apneaEvents) {
      signals.add(
        SafetySignal(
          kind: SafetySignalKind.apnea,
          title: 'اضطراب تنفس محتمل أثناء النوم',
          detail: 'انقطعت إشارة التنفس ${_sleepMonitor.apneaGap.inSeconds} ثانية',
          confidence: 0.6,
        ),
      );
    }
    final DateTime? lastSleepSignal = _lastSleepSignalAt;
    final bool sleepSignalAllowed = lastSleepSignal == null ||
        at.difference(lastSleepSignal) >= sleepSignalGate;
    if (sleep.state != previousSleep.state &&
        sleep.state != SleepState.absent &&
        sleep.state != SleepState.awake &&
        sleepSignalAllowed) {
      _lastSleepSignalAt = at;
      signals.add(
        SafetySignal(
          kind: SafetySignalKind.sleepStateChanged,
          title: 'حالة النوم: ${sleep.state.arabicLabel}',
          detail: sleep.state.description,
        ),
      );
    }

    // ── تحديث الحالة الموحّدة ─────────────────────────────────────────
    _state = _state.copyWith(
      posture: estimate.posture.isKnown ? estimate.posture : previousPosture,
      postureSource: estimate.source,
      postureConfidence: estimate.confidence,
      keypoints: estimate.keypoints,
      sleep: sleep,
      gaitProfiles: _profiles,
      gaitCollecting: _gaitAnalyzer.isCollecting,
    );

    return signals;
  }

  void reset() {
    _fallDetector.reset();
    _gaitAnalyzer.reset();
    _sleepMonitor.reset();
    _streaks.clear();
    _lastGaitEvaluationAt = null;
    _lastPostureSignalAt = null;
    _lastSleepSignalAt = null;
    _state = SafetyState(
      intrusionArmed: _state.intrusionArmed,
      armedAt: _state.armedAt,
      gaitProfiles: _profiles,
    );
  }

  GaitMatch? _matchGait(DateTime at) {
    final GaitFeatureVector? vector = _gaitAnalyzer.currentVector(at);
    if (vector == null) return null;

    GaitProfile? best;
    double bestSimilarity = 0;
    for (final GaitProfile profile in _profiles) {
      final double similarity = vector.similarityTo(profile.vector);
      if (similarity > bestSimilarity) {
        bestSimilarity = similarity;
        best = profile;
      }
    }

    if (best == null || bestSimilarity < gaitSimilarityThreshold) {
      _streaks.clear();
      return null;
    }

    final int streak = (_streaks[best.id] ?? 0) + 1;
    _streaks[best.id] = streak;
    if (streak < requiredGaitStreak) return null;

    return GaitMatch(profile: best, similarity: bestSimilarity, matchedAt: at);
  }

  static bool _serverReportedFall(SensingFrame frame) {
    if (PostureKind.fromWire(frame.posture) == PostureKind.fallen) return true;
    for (final PersonDetection person in frame.persons) {
      if (PostureKind.fromWire(person.posture) == PostureKind.fallen) return true;
    }
    return false;
  }
}
