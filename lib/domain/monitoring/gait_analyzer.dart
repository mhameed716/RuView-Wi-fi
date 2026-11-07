import 'dart:math' as math;

import '../../data/models/gait_profile.dart';
import '../../data/models/sensing_frame.dart';

/// مستخرج ميزات بصمة المشية من إطارات CSI.
///
/// يجمع نافذة زمنية من إطارات «المشي» فقط، ثم يبني متجهًا ميزيًا يمثّل إيقاع
/// الحركة: متوسط طاقة الحركة، تقلّبها، معدل تغيّرها، التردد السائد، والتباين.
///
/// **حدود الصدق:** هذا استخراج ميزات إحصائي خفيف يعمل على ملخّصات الخادم وليس
/// شبكة عصبية للتعرف على الهوية (مثل خط RuView البحثي). التطبيق يسمّيه
/// «بصمة استرشادية» وليس تعريف هوية قضائيًا.
class GaitAnalyzer {
  GaitAnalyzer({
    this.window = const Duration(seconds: 12),
    this.minSamples = 15,
    this.minSpan = const Duration(seconds: 4),
    this.maxSamples = 320,
  });

  final Duration window;
  final int minSamples;
  final Duration minSpan;
  final int maxSamples;

  final List<_GaitSample> _samples = <_GaitSample>[];

  bool get isCollecting =>
      _samples.length >= minSamples && _span >= minSpan;

  int get sampleCount => _samples.length;

  Duration get _span => _samples.length < 2
      ? Duration.zero
      : _samples.last.at.difference(_samples.first.at);

  /// إضافة إطار. تُتجاهل الإطارات الساكنة لأنها لا تحمل بصمة مشية.
  void add(
    SensingFrame frame, {
    required double motionIntensity,
    DateTime? at,
  }) {
    final DateTime time = at ?? frame.receivedAt;
    final bool moving = frame.classification.motionLevel.isMoving ||
        motionIntensity >= 0.45;
    if (!moving || motionIntensity < 0.25) return;

    _samples.add(
      _GaitSample(
        at: time,
        motion: frame.features.motionBandPower,
        dominantHz: frame.features.dominantFreqHz,
        variance: frame.features.variance,
        intensity: motionIntensity,
      ),
    );
    _trim(time);
  }

  /// المتجه الحالي إن كانت النافذة مكتملة، وإلا `null`.
  GaitFeatureVector? currentVector(DateTime now) {
    _trim(now);
    if (!isCollecting) return null;

    final List<double> motions =
        _samples.map((_GaitSample s) => s.motion).toList(growable: false);
    final double mean = motions.reduce((double a, double b) => a + b) / motions.length;
    if (mean <= 0.01) return null;

    double variance = 0;
    for (final double value in motions) {
      final double diff = value - mean;
      variance += diff * diff;
    }
    variance /= motions.length;
    final double std = math.sqrt(variance);

    double changeSum = 0;
    for (int i = 1; i < motions.length; i++) {
      changeSum += (motions[i] - motions[i - 1]).abs();
    }
    final double changeRate = motions.length > 1 ? changeSum / (motions.length - 1) : 0;

    final List<double> frequencies = _samples
        .map((_GaitSample s) => s.dominantHz)
        .where((double hz) => hz > 0)
        .toList(growable: false);
    final double dominant = frequencies.isEmpty
        ? changeRate * 2
        : frequencies.reduce((double a, double b) => a + b) / frequencies.length;

    final double meanVariance =
        _samples.map((_GaitSample s) => s.variance).reduce((double a, double b) => a + b) /
            _samples.length;

    return GaitFeatureVector(
      motionMean: mean,
      motionStd: std,
      dominantHz: dominant,
      changeRate: changeRate,
      variance: meanVariance,
      samples: _samples.length,
    );
  }

  void reset() => _samples.clear();

  void _trim(DateTime now) {
    _samples.removeWhere((_GaitSample sample) => now.difference(sample.at) > window);
    while (_samples.length > maxSamples) {
      _samples.removeAt(0);
    }
  }
}

class _GaitSample {
  const _GaitSample({
    required this.at,
    required this.motion,
    required this.dominantHz,
    required this.variance,
    required this.intensity,
  });

  final DateTime at;
  final double motion;
  final double dominantHz;
  final double variance;
  final double intensity;
}
