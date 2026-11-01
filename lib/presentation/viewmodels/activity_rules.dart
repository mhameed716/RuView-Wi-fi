import '../../core/l10n/ar_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/num_utils.dart';
import '../../data/models/activity_event.dart';
import '../../data/models/sensing_frame.dart';
import '../../data/models/vital_signs.dart';

/// قاعدة حدث واحدة: تُرجع حدثًا عند تحقّق الشرط، أو `null`.
typedef ActivityRule = ActivityEvent? Function(ActivityContext context);

/// سياق تقييم القواعد (إطار سابق/حالي + حارس زمني).
class ActivityContext {
  const ActivityContext({
    required this.previous,
    required this.current,
    required this.nextId,
    required this.now,
    required this.cooldown,
  });

  final SensingFrame? previous;
  final SensingFrame current;
  final int Function() nextId;
  final DateTime now;

  /// يمنح تجاوزًا زمنيًا لقاعدة معيّنة حسب مفتاحها.
  final bool Function(String key) cooldown;

  ActivityEvent build({
    required ActivityKind kind,
    required String title,
    required StatusTone tone,
    String? detail,
  }) {
    return ActivityEvent(
      id: nextId(),
      kind: kind,
      title: title,
      detail: detail,
      tone: tone,
      timestamp: now,
    );
  }
}

/// قواعد توليد الأحداث من فروقات الإطارات — منطق نقي قابل للاختبار.
abstract final class ActivityRules {
  static const double weakSignalThreshold = 0.35;

  static final List<ActivityRule> all = <ActivityRule>[
    presenceRule,
    motionRule,
    peopleCountRule,
    breathingRule,
    signalStrengthRule,
  ];

  /// رصد الحضور / مغادرة المنطقة.
  static ActivityEvent? presenceRule(ActivityContext context) {
    final SensingFrame? previous = context.previous;
    final SensingFrame current = context.current;
    if (previous == null) return null;
    if (previous.hasPresence == current.hasPresence) return null;

    if (current.hasPresence) {
      return context.build(
        kind: ActivityKind.presence,
        title: ArStrings.eventPresenceDetected,
        tone: StatusTone.ok,
        detail: current.personCount > 1
            ? '${current.personCount} أشخاص في النطاق'
            : null,
      );
    }
    return context.build(
      kind: ActivityKind.presence,
      title: ArStrings.eventPresenceLost,
      tone: StatusTone.idle,
    );
  }

  /// بدء/توقف الحركة.
  static ActivityEvent? motionRule(ActivityContext context) {
    final SensingFrame? previous = context.previous;
    final SensingFrame current = context.current;
    if (previous == null) return null;

    final bool wasMoving = previous.classification.motionLevel.isMoving;
    final bool isMovingNow = current.classification.motionLevel.isMoving;
    if (wasMoving == isMovingNow) return null;
    if (!context.cooldown('motion')) return null;

    return context.build(
      kind: ActivityKind.motion,
      title: isMovingNow ? ArStrings.eventMotionDetected : ArStrings.eventMotionStopped,
      tone: isMovingNow ? StatusTone.active : StatusTone.ok,
      detail: '${ArStrings.motionIntensity}: ${NumUtils.percent(current.motionIntensity)}',
    );
  }

  /// تغيّر عدد الأشخاص المرصودين.
  static ActivityEvent? peopleCountRule(ActivityContext context) {
    final SensingFrame? previous = context.previous;
    final SensingFrame current = context.current;
    if (previous == null) return null;
    if (previous.personCount == current.personCount) return null;
    if (!current.hasPresence) return null;
    if (!context.cooldown('people')) return null;

    return context.build(
      kind: ActivityKind.presence,
      title: ArStrings.eventPeopleCountChanged,
      tone: StatusTone.active,
      detail: '${current.personCount} ${ArStrings.personDetected}',
    );
  }

  /// حالة التنفس: طبيعي / سريع / بطيء.
  static ActivityEvent? breathingRule(ActivityContext context) {
    final VitalSigns? vitals = context.current.vitalSigns;
    if (vitals == null || !vitals.hasBreathing) return null;

    final BreathingStatus status = vitals.breathingStatus;
    final BreathingStatus previousStatus =
        context.previous?.vitalSigns?.breathingStatus ?? BreathingStatus.unknown;
    if (status == previousStatus || status == BreathingStatus.unknown) {
      return null;
    }
    if (!context.cooldown('breathing')) return null;

    final String label = switch (status) {
      BreathingStatus.normal => ArStrings.eventBreathingNormal,
      BreathingStatus.fast => ArStrings.eventBreathingFast,
      BreathingStatus.slow => ArStrings.eventBreathingSlow,
      BreathingStatus.unknown => ArStrings.eventVitalsLost,
    };

    return context.build(
      kind: ActivityKind.breathing,
      title: label,
      tone: switch (status) {
        BreathingStatus.normal => StatusTone.ok,
        BreathingStatus.fast => StatusTone.warning,
        BreathingStatus.slow => StatusTone.warning,
        BreathingStatus.unknown => StatusTone.idle,
      },
      detail: '${NumUtils.oneDecimal(vitals.breathingRateBpm ?? 0)} '
          '${ArStrings.breathsPerMinute}',
    );
  }

  /// ضعف/استعادة جودة الإشارة.
  static ActivityEvent? signalStrengthRule(ActivityContext context) {
    final double quality = context.current.signalQuality;
    if (quality <= 0) return null;
    final double previousQuality =
        context.previous?.signalQuality ?? weakSignalThreshold;
    final bool wasWeak = previousQuality < weakSignalThreshold;
    final bool isWeak = quality < weakSignalThreshold;
    if (wasWeak == isWeak) return null;
    if (!context.cooldown('signal')) return null;

    return context.build(
      kind: ActivityKind.signal,
      title: isWeak ? ArStrings.eventWeakSignal : ArStrings.eventSignalRecovered,
      tone: isWeak ? StatusTone.warning : StatusTone.ok,
      detail: '${ArStrings.signalQuality}: ${NumUtils.percent(quality)}',
    );
  }

  /// قيم التهيئة الأولية للحرّاس الزمنية لكل قاعدة.
  static Map<String, Duration> get cooldowns => const <String, Duration>{
        'motion': Duration(seconds: 6),
        'people': Duration(seconds: 10),
        'breathing': Duration(seconds: 25),
        'signal': Duration(seconds: 45),
      };
}

/// مجموعة حرّاس زمنية مستخدمة في [ActivityRules].
class RuleCooldowns {
  RuleCooldowns({Map<String, Duration>? overrides})
      : _durations = <String, Duration>{
          ...ActivityRules.cooldowns,
          ...?overrides,
        };

  final Map<String, Duration> _durations;
  final Map<String, CooldownGate> _gates = <String, CooldownGate>{};

  bool pass(String key, DateTime now) {
    final Duration duration = _durations[key] ?? const Duration(seconds: 5);
    final CooldownGate gate =
        _gates.putIfAbsent(key, () => CooldownGate(duration));
    return gate.tryPass(now);
  }

  void reset() {
    for (final CooldownGate gate in _gates.values) {
      gate.reset();
    }
  }
}
