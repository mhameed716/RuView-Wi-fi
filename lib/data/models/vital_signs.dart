import '../../core/utils/num_utils.dart';
import 'json_read.dart';

/// حالة معدل التنفس مقارنة بالنطاق الطبيعي للبالغين وقت الراحة.
enum BreathingStatus {
  slow('تنفس بطيء'),
  normal('تنفس طبيعي'),
  fast('تنفس سريع'),
  unknown('غير متوفر');

  const BreathingStatus(this.arabicLabel);

  final String arabicLabel;
}

/// العلامات الحيوية المشتقة من CSI كما يبثّها خادم RuView.
///
/// البنية الرسمية: `breathing_rate_bpm`, `heart_rate_bpm`,
/// `breathing_confidence`, `heartbeat_confidence`, `signal_quality`
/// مع دعم الأسماء البديلة التي تستخدمها بعض البوابات/الإصدارات
/// (`breathing_bpm`, `hr_proxy_bpm`, `heart_confidence`).
class VitalSigns {
  const VitalSigns({
    this.breathingRateBpm,
    this.heartRateBpm,
    this.breathingConfidence,
    this.heartConfidence,
    this.signalQuality,
  });

  factory VitalSigns.fromJson(Map<String, dynamic> json) {
    return VitalSigns(
      breathingRateBpm: JsonRead.asOptionalDouble(
        json['breathing_rate_bpm'] ??
            json['breathing_bpm'] ??
            json['breathing_rate'],
      ),
      heartRateBpm: JsonRead.asOptionalDouble(
        json['heart_rate_bpm'] ??
            json['hr_proxy_bpm'] ??
            json['heart_rate'],
      ),
      breathingConfidence: JsonRead.asOptionalDouble(
        json['breathing_confidence'] ?? json['breathing_conf'],
      ),
      heartConfidence: JsonRead.asOptionalDouble(
        json['heartbeat_confidence'] ?? json['heart_confidence'],
      ),
      signalQuality: JsonRead.asOptionalDouble(
        json['signal_quality'] ?? json['confidence'],
      ),
    );
  }

  final double? breathingRateBpm;
  final double? heartRateBpm;
  final double? breathingConfidence;
  final double? heartConfidence;
  final double? signalQuality;

  static const double normalMinBpm = 12;
  static const double normalMaxBpm = 20;

  /// النطاق الطبيعي الموسّع (9–24) قبل إصدار تنبيه.
  static const double hardMinBpm = 9;
  static const double hardMaxBpm = 24;

  bool get hasBreathing => breathingRateBpm != null && breathingRateBpm! > 0;

  bool get hasHeartRate => heartRateBpm != null && heartRateBpm! > 0;

  bool get isEmpty => !hasBreathing && !hasHeartRate;

  BreathingStatus get breathingStatus {
    final double? bpm = breathingRateBpm;
    if (bpm == null || bpm <= 0) return BreathingStatus.unknown;
    if (bpm < normalMinBpm) return BreathingStatus.slow;
    if (bpm > normalMaxBpm) return BreathingStatus.fast;
    return BreathingStatus.normal;
  }

  /// 0..1 لتمثيل القيمة على مقياس 6–30 نفس/دقيقة.
  double get breathingRatio => NumUtils.clamp01(
        NumUtils.mapRange(breathingRateBpm ?? 0, 6, 30, 0, 1),
      );

  double get confidence {
    final double? breathing = breathingConfidence;
    final double? heart = heartConfidence;
    final double? quality = signalQuality;
    final List<double> values = <double>[
      if (breathing != null) breathing,
      if (heart != null) heart,
      if (quality != null) quality,
    ].map((double v) => v > 1 ? v / 100.0 : v).toList(growable: false);
    if (values.isEmpty) return 0;
    final double sum = values.fold<double>(0, (double a, double b) => a + b);
    return NumUtils.clamp01(sum / values.length);
  }
}
