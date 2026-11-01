import 'dart:math' as math;

import '../../core/utils/num_utils.dart';
import 'json_read.dart';

/// بصمة مشية شخص: متجه ميزات مستخرج من إيقاع حركة CSI.
///
/// الفكرة: لكل شخص إيقاع خطوات مختلف (سرعة، انتظام، ترددات سائدة). نجمع
/// متجهًا ميزيًا من نافذة زمنية أثناء الحركة، ثم نقارن متجهات لاحقة بالبصمات
/// المسجّلة بزاوية جيب التمام (تشابه 0..1).
class GaitFeatureVector {
  const GaitFeatureVector({
    required this.motionMean,
    required this.motionStd,
    required this.dominantHz,
    required this.changeRate,
    required this.variance,
    required this.samples,
  });

  factory GaitFeatureVector.fromJson(Map<String, dynamic> json) {
    return GaitFeatureVector(
      motionMean: JsonRead.asDouble(json['motion_mean']),
      motionStd: JsonRead.asDouble(json['motion_std']),
      dominantHz: JsonRead.asDouble(json['dominant_hz']),
      changeRate: JsonRead.asDouble(json['change_rate']),
      variance: JsonRead.asDouble(json['variance']),
      samples: JsonRead.asInt(json['samples']),
    );
  }

  final double motionMean;
  final double motionStd;
  final double dominantHz;
  final double changeRate;
  final double variance;
  final int samples;

  List<double> toVector() => <double>[
        motionMean,
        motionStd,
        dominantHz * 4, // وزن التردد السائد لأن قيمته أصغر بمقدار رتبة
        changeRate * 6,
        variance / 4,
      ];

  /// تشابه جيب تمام بين بصمتين (0 = مختلف تمامًا، 1 = متطابق).
  double similarityTo(GaitFeatureVector other) {
    final List<double> a = toVector();
    final List<double> b = other.toVector();
    double dot = 0;
    double normA = 0;
    double normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA <= 0 || normB <= 0) return 0;
    return NumUtils.clamp01(dot / math.sqrt(normA * normB));
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'motion_mean': motionMean,
        'motion_std': motionStd,
        'dominant_hz': dominantHz,
        'change_rate': changeRate,
        'variance': variance,
        'samples': samples,
      };
}

/// بصمة مشية محفوظة لشخص معروف.
class GaitProfile {
  const GaitProfile({
    required this.id,
    required this.name,
    required this.vector,
    required this.enrolledAt,
  });

  factory GaitProfile.fromJson(Map<String, dynamic> json) {
    final Object? rawVector = json['vector'];
    return GaitProfile(
      id: JsonRead.asString(json['id'], 'profile'),
      name: JsonRead.asString(json['name'], 'شخص'),
      vector: rawVector is Map
          ? GaitFeatureVector.fromJson(JsonRead.asMap(rawVector))
          : const GaitFeatureVector(
              motionMean: 0,
              motionStd: 0,
              dominantHz: 0,
              changeRate: 0,
              variance: 0,
              samples: 0,
            ),
      enrolledAt: DateTime.fromMillisecondsSinceEpoch(
        JsonRead.asInt(json['enrolled_at'], DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  final String id;
  final String name;
  final GaitFeatureVector vector;
  final DateTime enrolledAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'vector': vector.toJson(),
        'enrolled_at': enrolledAt.millisecondsSinceEpoch,
      };

  GaitProfile copyWith({String? name}) => GaitProfile(
        id: id,
        name: name ?? this.name,
        vector: vector,
        enrolledAt: enrolledAt,
      );
}
