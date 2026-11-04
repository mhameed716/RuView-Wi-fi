import 'dart:math' as math;

import '../../core/utils/num_utils.dart';
import 'body_shape.dart';

/// «توأم مسبق»: ملف جسم رقمي لشخص معروف داخل المكان.
///
/// يُنشأ مرة واحدة عند أول رصد، ثم يُستدعى تلقائيًا في كل مرة يدخل فيها
/// الشخص نفسه — فتُبنى مجسّمته فورًا بدل إعادة التخمين من الصفر.
class BodyProfile {
  const BodyProfile({
    required this.id,
    required this.label,
    required this.shape,
    required this.signature,
    required this.enrolledAt,
    this.samples = 1,
  });

  factory BodyProfile.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('ملف جسم غير صالح');
    }
    final int enrolledMs = json['enrolled_at'] is num
        ? (json['enrolled_at'] as num).toInt()
        : DateTime.now().millisecondsSinceEpoch;
    return BodyProfile(
      id: json['id'] is String ? json['id'] as String : 'body',
      label: json['label'] is String ? json['label'] as String : 'شخص',
      shape: BodyShape.fromJson(json['shape']),
      signature: BodySignature.fromJson(json['signature']),
      enrolledAt: DateTime.fromMillisecondsSinceEpoch(enrolledMs),
      samples: json['samples'] is num ? (json['samples'] as num).toInt() : 1,
    );
  }

  final String id;
  final String label;
  final BodyShape shape;
  final BodySignature signature;
  final DateTime enrolledAt;

  /// عدد المرات التي أُكّد فيها الملف (يزداد مع كل تطابق مستقر).
  final int samples;

  BodyProfile copyWith({
    String? label,
    BodyShape? shape,
    BodySignature? signature,
    int? samples,
  }) {
    return BodyProfile(
      id: id,
      label: label ?? this.label,
      shape: shape ?? this.shape,
      signature: signature ?? this.signature,
      enrolledAt: enrolledAt,
      samples: samples ?? this.samples,
    );
  }

  /// دمج قياس جديد في الملف (متوسط متحرك) — يجعل التوأم يتحسّن مع الوقت.
  BodyProfile merged(BodyShape next, BodySignature nextSignature) {
    final double w = 1 / math.max(2, samples + 1);
    BodyShape blend(BodyShape a, BodyShape b) => a.copyWith(
          heightM: a.heightM + (b.heightM - a.heightM) * w,
          shoulderM: a.shoulderM + (b.shoulderM - a.shoulderM) * w,
          chestM: a.chestM + (b.chestM - a.chestM) * w,
          waistM: a.waistM + (b.waistM - a.waistM) * w,
          hipM: a.hipM + (b.hipM - a.hipM) * w,
          armM: a.armM + (b.armM - a.armM) * w,
          legM: a.legM + (b.legM - a.legM) * w,
          muscle: a.muscle + (b.muscle - a.muscle) * w,
          confidence: NumUtils.clamp01(a.confidence + 0.05),
        );

    return BodyProfile(
      id: id,
      label: label,
      shape: blend(shape, next),
      signature: nextSignature,
      enrolledAt: enrolledAt,
      samples: samples + 1,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'shape': shape.toJson(),
        'signature': signature.toJson(),
        'enrolled_at': enrolledAt.millisecondsSinceEpoch,
        'samples': samples,
      };

  @override
  String toString() => 'BodyProfile($label, ${shape.heightM.toStringAsFixed(2)}m)';
}

/// نتيجة مطابقة توأم.
class BodyMatch {
  const BodyMatch({required this.profile, required this.score});

  final BodyProfile profile;

  /// جودة المطابقة (0..1).
  final double score;
}

/// مطابق «بصمة القياسات الجسدية».
class BodyRecognizer {
  const BodyRecognizer._();

  /// أدنى تشابه مقبول لاعتبار الشخص معروفًا.
  static const double defaultThreshold = 0.66;

  static BodyMatch? match(
    BodySignature signature,
    List<BodyProfile> profiles, {
    double threshold = defaultThreshold,
  }) {
    BodyMatch? best;
    for (final BodyProfile profile in profiles) {
      final double score = 1 - signature.distanceTo(profile.signature);
      if (best == null || score > best.score) {
        best = BodyMatch(profile: profile, score: NumUtils.clamp01(score));
      }
    }
    if (best == null || best.score < threshold) return null;
    return best;
  }

  /// توليد معرّف ثابت من البصمة (لا يتغيّر مع التحديثات الطفيفة).
  static String fingerprint(BodySignature signature) {
    final int h = (signature.heightM * 100).round();
    final int s = (signature.shoulderRatio * 1000).round();
    final int hp = (signature.hipRatio * 1000).round();
    return 'body-${h}-${s}-${hp}';
  }
}
