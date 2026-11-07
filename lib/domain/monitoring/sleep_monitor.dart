import 'dart:math' as math;

import '../../core/utils/num_utils.dart';
import '../../data/models/posture.dart';
import '../../data/models/sleep_summary.dart';

/// مراقبة جودة النوم والتنفس (بما فيها احتمال انقطاع النفس).
///
/// يعتمد على:
///   • وجود شخص في وضعية استلقاء (أو سكون تام مع إشارة تنفس) = بدء الجلسة.
///   • استقرار معدل التنفس: الانحراف المعياري منخفض ⇒ نوم أعمق.
///   • غياب إشارة التنفس لمدة [apneaGap] أثناء الجلسة ⇒ حدث اضطراب تنفس.
///   • الحركة العالية ⇒ استيقاظ/تقلّب.
class SleepMonitor {
  SleepMonitor({
    this.apneaGap = const Duration(seconds: 25),
    this.apneaRepeatGuard = const Duration(seconds: 45),
    this.minSessionForDeep = const Duration(seconds: 60),
  });

  /// مدة غياب إشارة التنفس التي تُحتسب اضطرابًا.
  final Duration apneaGap;

  /// منع تكرار احتساب الاضطراب لنفس الفترة.
  final Duration apneaRepeatGuard;

  /// أقل مدة جلسة قبل تصنيف النوم «عميقًا».
  final Duration minSessionForDeep;

  DateTime? _sessionStart;
  DateTime? _lastBreathingAt;
  DateTime? _lastApneaAt;

  final List<double> _breathing = <double>[];
  int _apneaEvents = 0;

  SleepSummary _summary = const SleepSummary();

  SleepSummary get summary => _summary;

  int get apneaEvents => _apneaEvents;

  /// تغذية المحرّك بإطار جديد وإرجاع الملخّص المحدّث.
  SleepSummary ingest({
    required bool hasPresence,
    required PostureKind posture,
    required double? breathingRate,
    required double motionIntensity,
    required DateTime now,
  }) {
    final bool hasBreathing = breathingRate != null && breathingRate > 0;
    final bool inBed = hasPresence &&
        (posture == PostureKind.lying ||
            (hasBreathing && motionIntensity < 0.28));

    if (!inBed) {
      _reset();
      return _summary;
    }

    _sessionStart ??= now;
    if (hasBreathing) {
      _breathing.add(breathingRate);
      _lastBreathingAt = now;
      if (_breathing.length > 900) _breathing.removeAt(0);
    }

    final Duration session = now.difference(_sessionStart!);

    // رصد غياب إشارة التنفس (احتمال انقطاع نفس).
    final DateTime? lastBreathing = _lastBreathingAt;
    if (lastBreathing != null &&
        now.difference(lastBreathing) >= apneaGap &&
        (_lastApneaAt == null ||
            now.difference(_lastApneaAt!) >= apneaRepeatGuard)) {
      _apneaEvents++;
      _lastApneaAt = now;
    }

    final double? average = _breathing.isEmpty
        ? null
        : _breathing.reduce((double a, double b) => a + b) / _breathing.length;

    double variability = 0;
    if (_breathing.length >= 3 && average != null) {
      double variance = 0;
      for (final double value in _breathing) {
        final double diff = value - average;
        variance += diff * diff;
      }
      variability = math.sqrt(variance / _breathing.length);
    }

    final bool apneaRecent = _lastApneaAt != null &&
        now.difference(_lastApneaAt!) <= apneaGap;

    final SleepState state;
    if (motionIntensity >= 0.5) {
      state = SleepState.awake;
    } else if (apneaRecent || variability > 3.5) {
      state = SleepState.disturbed;
    } else if (variability > 0 &&
        variability <= 1.2 &&
        motionIntensity < 0.12 &&
        session >= minSessionForDeep) {
      state = SleepState.deep;
    } else {
      state = SleepState.light;
    }

    // درجة الجودة: تبدأ من 100 وتنقص مع التقلّب والحركة وأحداث الانقطاع.
    final double qualityRatio = NumUtils.clamp01(
      (100 - variability * 7 - motionIntensity * 45 - _apneaEvents * 12) / 100,
    );
    final int quality = (qualityRatio * 100).round();

    _summary = SleepSummary(
      state: state,
      session: session,
      averageBreathing: average,
      breathingVariability: variability,
      apneaEvents: _apneaEvents,
      qualityScore: quality,
      isMonitoring: true,
      samples: _breathing.length,
    );
    return _summary;
  }

  void reset() {
    _reset();
    _summary = const SleepSummary();
  }

  void _reset() {
    _sessionStart = null;
    _lastBreathingAt = null;
    _lastApneaAt = null;
    _breathing.clear();
    _apneaEvents = 0;
    _summary = const SleepSummary();
  }
}
