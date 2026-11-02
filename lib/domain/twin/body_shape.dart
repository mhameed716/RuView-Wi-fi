import 'dart:math' as math;

import '../../core/utils/num_utils.dart';
import '../../data/models/posture.dart';
import '../../data/models/sensing_frame.dart';
import 'vec3.dart';

/// قياس واحد معروض في لوحة القياسات الجسدية.
class BodyMeasurement {
  const BodyMeasurement({required this.label, required this.value, this.hint});

  final String label;
  final String value;
  final String? hint;
}

/// نموذج جسم بارامتري بأسلوب **SMPL / SMPL-X**.
///
/// النموذج الحقيقي يستخدم مئات المعاملات (betas) مُدرَّبة على مسح بشري ضخم.
/// هنا نستخدم تمثيلًا مضغوطًا (10 معاملات β) مشتقًا من قياسات CSI:
/// الطول، عرض الكتفين، محيطات الصدر/الخصر/الحوض، أطوال الذراعين والساقين،
/// وكتلة العضلات. هذه المعاملات تُغذّي مولّد المجسّم في `body_mesh.dart`،
/// فيتغيّر شكل الجسم (نحيلًا/رياضيًا/ممتلئًا/طويلًا/قصيرًا) بدل مجسّم ثابت.
class BodyShape {
  const BodyShape({
    required this.heightM,
    required this.shoulderM,
    required this.chestM,
    required this.waistM,
    required this.hipM,
    required this.armM,
    required this.legM,
    required this.muscle,
    this.confidence = 0.5,
  });

  /// جسم «متوسط» يُستخدم كسابقة (prior) عند غياب قياسات كافية.
  static const BodyShape average = BodyShape(
    heightM: 1.72,
    shoulderM: 0.42,
    chestM: 0.98,
    waistM: 0.82,
    hipM: 0.96,
    armM: 0.62,
    legM: 0.82,
    muscle: 0.45,
    confidence: 0.3,
  );

  factory BodyShape.fromJson(Object? json) {
    if (json is! Map) return average;
    double read(String key, double fallback) {
      final Object? value = json[key];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? fallback;
      return fallback;
    }

    return BodyShape(
      heightM: read('height_m', average.heightM),
      shoulderM: read('shoulder_m', average.shoulderM),
      chestM: read('chest_m', average.chestM),
      waistM: read('waist_m', average.waistM),
      hipM: read('hip_m', average.hipM),
      armM: read('arm_m', average.armM),
      legM: read('leg_m', average.legM),
      muscle: read('muscle', average.muscle),
      confidence: read('confidence', average.confidence),
    );
  }

  /// الطول الكلي (م).
  final double heightM;

  /// عرض الكتفين (م).
  final double shoulderM;

  /// محيط الصدر (م).
  final double chestM;

  /// محيط الخصر (م).
  final double waistM;

  /// محيط الحوض (م).
  final double hipM;

  /// طول الذراع (م).
  final double armM;

  /// طول الساق (م).
  final double legM;

  /// كتلة العضلات (0..1) — تتحكم في انتفاخ العضد والفخذ.
  final double muscle;

  /// ثقة تقدير الشكل (0..1).
  final double confidence;

  BodyShape copyWith({
    double? heightM,
    double? shoulderM,
    double? chestM,
    double? waistM,
    double? hipM,
    double? armM,
    double? legM,
    double? muscle,
    double? confidence,
  }) {
    return BodyShape(
      heightM: heightM ?? this.heightM,
      shoulderM: shoulderM ?? this.shoulderM,
      chestM: chestM ?? this.chestM,
      waistM: waistM ?? this.waistM,
      hipM: hipM ?? this.hipM,
      armM: armM ?? this.armM,
      legM: legM ?? this.legM,
      muscle: muscle ?? this.muscle,
      confidence: confidence ?? this.confidence,
    );
  }

  /// مزج الشكل مع شكل آخر (مثل توأم محفوظ) بنسبة [t].
  BodyShape mixed(BodyShape other, double t) {
    final double w = NumUtils.clamp01(t);
    double mix(double a, double b) => a + (b - a) * w;
    return copyWith(
      heightM: mix(heightM, other.heightM),
      shoulderM: mix(shoulderM, other.shoulderM),
      chestM: mix(chestM, other.chestM),
      waistM: mix(waistM, other.waistM),
      hipM: mix(hipM, other.hipM),
      armM: mix(armM, other.armM),
      legM: mix(legM, other.legM),
      muscle: mix(muscle, other.muscle),
      confidence: mix(confidence, other.confidence),
    );
  }

  /// نصف قطر مكافئ (بمتر) لكل محيط — يُستخدم في توليد حلقات المجسّم.
  double get chestRadius => chestM / (2 * math.pi);

  double get waistRadius => waistM / (2 * math.pi);

  double get hipRadius => hipM / (2 * math.pi);

  /// نسبة الكتف إلى الخصر: مؤشر V-taper (رياضي = أعلى).
  double get taper => waistM <= 0 ? 1 : shoulderM / (waistM / 2.4);

  /// كتلة تقديرية بالكيلوجرام (ليست قياسًا طبيًا).
  double get estimatedMassKg => 55 +
      (heightM - 1.55) * 62 +
      (chestM - 0.92) * 34 +
      (waistM - 0.78) * 22 +
      muscle * 7;

  /// تصنيف البنية بالعربية.
  String get buildLabel {
    final double w = waistM / heightM;
    if (w < 0.44) return 'نحيفة';
    if (w < 0.5) return muscle > 0.55 ? 'رياضية' : 'متوازنة';
    if (w < 0.58) return 'ممتلئة قليلًا';
    return 'ممتلئة';
  }

  /// معاملات β العشرة (مقياس SMPL مصغّر) — تُعرض في الواجهة وترسم الاختلاف
  /// عن الجسم المتوسط: موجب = أضخم، سالب = أنحف.
  List<double> get betas {
    double beta(double value, double reference, double scale) =>
        NumUtils.clampRange((value - reference) / scale, -2.5, 2.5);

    return <double>[
      beta(heightM, average.heightM, 0.09),
      beta(shoulderM, average.shoulderM, 0.03),
      beta(chestM, average.chestM, 0.06),
      beta(waistM, average.waistM, 0.06),
      beta(hipM, average.hipM, 0.05),
      beta(armM, average.armM, 0.04),
      beta(legM, average.legM, 0.05),
      beta(muscle, average.muscle, 0.2),
      NumUtils.clampRange(taper - 1, -1, 1),
      NumUtils.clampRange(confidence - 0.5, -0.5, 0.5),
    ];
  }

  /// نص مختصر للمعاملات: `β +0.7 / −0.2 / …`.
  String get betaLabel {
    final List<double> values = betas.take(5).toList(growable: false);
    final List<String> parts = values.map((double beta) {
      final String sign = beta >= 0 ? '+' : '−';
      return '$sign${beta.abs().toStringAsFixed(1)}';
    }).toList(growable: false);
    return 'β ${parts.join(' / ')}';
  }

  /// جدول القياسات المعروض في لوحة «القياسات الجسدية».
  List<BodyMeasurement> get measurements => <BodyMeasurement>[
        BodyMeasurement(
          label: 'الطول',
          value: '${(heightM * 100).round()} سم',
          hint: 'SMPL: ${heightM.toStringAsFixed(2)} م',
        ),
        BodyMeasurement(
          label: 'عرض الكتفين',
          value: '${(shoulderM * 100).round()} سم',
        ),
        BodyMeasurement(
          label: 'محيط الصدر',
          value: '${(chestM * 100).round()} سم',
        ),
        BodyMeasurement(
          label: 'محيط الخصر',
          value: '${(waistM * 100).round()} سم',
        ),
        BodyMeasurement(
          label: 'محيط الحوض',
          value: '${(hipM * 100).round()} سم',
        ),
        BodyMeasurement(
          label: 'طول الذراع',
          value: '${(armM * 100).round()} سم',
        ),
        BodyMeasurement(
          label: 'طول الساق',
          value: '${(legM * 100).round()} سم',
        ),
        BodyMeasurement(
          label: 'الكتلة التقديرية',
          value: '${estimatedMassKg.round()} كجم',
          hint: 'تقدير من الانعكاسات',
        ),
        BodyMeasurement(label: 'البنية', value: buildLabel),
      ];

  Map<String, dynamic> toJson() => <String, dynamic>{
        'height_m': heightM,
        'shoulder_m': shoulderM,
        'chest_m': chestM,
        'waist_m': waistM,
        'hip_m': hipM,
        'arm_m': armM,
        'leg_m': legM,
        'muscle': muscle,
        'confidence': confidence,
      };

  @override
  String toString() => 'BodyShape(${heightM.toStringAsFixed(2)}m, '
      '${buildLabel}, β ${betas.first.toStringAsFixed(1)})';
}

/// بصمة شكلية مستقرة تُستخدم لمطابقة «التوأم المسبق» (Anthropometric Profile).
class BodySignature {
  const BodySignature({
    required this.heightM,
    required this.shoulderRatio,
    required this.hipRatio,
    required this.muscle,
    this.gaitVector = const <double>[],
  });

  factory BodySignature.fromShape(
    BodyShape shape, {
    List<double> gaitVector = const <double>[],
  }) {
    final double h = math.max(0.5, shape.heightM);
    return BodySignature(
      heightM: shape.heightM,
      shoulderRatio: shape.shoulderM / h,
      hipRatio: shape.hipM / h,
      muscle: shape.muscle,
      gaitVector: gaitVector,
    );
  }

  factory BodySignature.fromJson(Object? json) {
    if (json is! Map) {
      return BodySignature.fromShape(BodyShape.average);
    }
    double read(String key) {
      final Object? value = json[key];
      if (value is num) return value.toDouble();
      return 0;
    }

    final Object? rawGait = json['gait'];
    return BodySignature(
      heightM: read('height_m'),
      shoulderRatio: read('shoulder_ratio'),
      hipRatio: read('hip_ratio'),
      muscle: read('muscle'),
      gaitVector: rawGait is List
          ? rawGait.whereType<num>().map((num v) => v.toDouble()).toList()
          : const <double>[],
    );
  }

  /// الطول (م).
  final double heightM;

  /// نسبة عرض الكتفين إلى الطول.
  final double shoulderRatio;

  /// نسبة محيط الحوض إلى الطول.
  final double hipRatio;

  /// كتلة العضلات.
  final double muscle;

  /// متجه ميزات المشية إن توفّر (يُدمج مع الشكل لتقوية التمييز).
  final List<double> gaitVector;

  /// مسافة عدم التشابه (0 = مطابق).
  double distanceTo(BodySignature other) {
    double diff(double a, double b, double scale) =>
        ((a - b).abs() / scale).clamp(0.0, 1.0);

    double gait = 0;
    if (gaitVector.isNotEmpty && other.gaitVector.isNotEmpty) {
      final int n = math.min(gaitVector.length, other.gaitVector.length);
      double dot = 0;
      double na = 0;
      double nb = 0;
      for (int i = 0; i < n; i++) {
        dot += gaitVector[i] * other.gaitVector[i];
        na += gaitVector[i] * gaitVector[i];
        nb += other.gaitVector[i] * other.gaitVector[i];
      }
      if (na > 0 && nb > 0) {
        gait = 1 - NumUtils.clamp01(dot / math.sqrt(na * nb));
      }
    }

    final double shape = diff(heightM, other.heightM, 0.25) * 0.42 +
        diff(shoulderRatio, other.shoulderRatio, 0.10) * 0.24 +
        diff(hipRatio, other.hipRatio, 0.12) * 0.16 +
        diff(muscle, other.muscle, 0.5) * 0.18;

    return NumUtils.clamp01(gait > 0 ? shape * 0.7 + gait * 0.3 : shape);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'height_m': heightM,
        'shoulder_ratio': shoulderRatio,
        'hip_ratio': hipRatio,
        'muscle': muscle,
        'gait': gaitVector,
      };
}

/// يستنتج [BodyShape] من مفاصل COCO السبع عشرة القادمة من CSI.
///
/// لا يمكن قياس الطول بالمتر من إحداثيات مصوّرة (0..1) وحدها، لذلك نبني
/// التشابه النسبي بين أطوال الأعضاء (وهي بصمة شكلية قوية) ونُسقطها على مدى
/// بشري واقعي مع درجة ثقة. النتيجة تُعرض بوصفها **تقديرًا** لا قياسًا طبيًا.
class BodyShapeEstimator {
  /// نسب تشريحية متوسطة (نسبة العضو إلى الطول الكلي) — من أدبيات الأنثروبومتريا.
  static const double shoulderToHeight = 0.245;
  static const double hipToHeight = 0.19;
  static const double torsoToHeight = 0.30;
  static const double legToHeight = 0.47;

  static BodyShape estimate({
    required List<PoseKeypoint> keypoints,
    PostureKind posture = PostureKind.unknown,
  }) {
    final Map<String, PoseKeypoint> byName = <String, PoseKeypoint>{
      for (final PoseKeypoint kp in keypoints)
        if (kp.confidence >= 0.2) kp.name: kp,
    };
    double distance(String a, String b) {
      final PoseKeypoint? pa = byName[a];
      final PoseKeypoint? pb = byName[b];
      if (pa == null || pb == null) return 0;
      final double dx = pa.x - pb.x;
      final double dy = pa.y - pb.y;
      return math.sqrt(dx * dx + dy * dy);
    }

    double mid(String a, String b, int axis) {
      final PoseKeypoint? pa = byName[a];
      final PoseKeypoint? pb = byName[b];
      if (pa == null || pb == null) return double.nan;
      return axis == 0 ? (pa.x + pb.x) / 2 : (pa.y + pb.y) / 2;
    }

    double span(String a, String b) {
      final PoseKeypoint? pa = byName[a];
      final PoseKeypoint? pb = byName[b];
      if (pa == null || pb == null) return 0;
      final double dx = pa.x - pb.x;
      final double dy = pa.y - pb.y;
      return math.sqrt(dx * dx + dy * dy);
    }

    final double shoulderSpan = distance('left_shoulder', 'right_shoulder');
    final double hipSpan = distance('left_hip', 'right_hip');

    // محور الجسم: من منتصف الكتفين إلى منتصف الحوض (أو إلى الكاحلين).
    double torsoSpan = 0;
    final double sx = mid('left_shoulder', 'right_shoulder', 0);
    final double sy = mid('left_shoulder', 'right_shoulder', 1);
    final double hx = mid('left_hip', 'right_hip', 0);
    final double hy = mid('left_hip', 'right_hip', 1);
    if (!sx.isNaN && !hx.isNaN) {
      torsoSpan = math.sqrt((sx - hx) * (sx - hx) + (sy - hy) * (sy - hy));
    }

    final double legSpan = span('left_hip', 'left_ankle') == 0
        ? span('right_hip', 'right_ankle')
        : span('left_hip', 'left_ankle');
    final double fullBody = distance('nose', 'left_ankle') == 0
        ? distance('nose', 'right_ankle')
        : distance('nose', 'left_ankle');

    // مرشّحات الطول من كل عضو متاح.
    final List<double> candidates = <double>[];
    void addCandidate(double measured, double ratio) {
      if (measured > 0.01 && ratio > 0) candidates.add(measured / ratio);
    }

    addCandidate(shoulderSpan, shoulderToHeight);
    addCandidate(hipSpan, hipToHeight);
    addCandidate(torsoSpan, torsoToHeight);
    addCandidate(legSpan, legToHeight);
    addCandidate(fullBody, 0.87);

    // وضعية الاستلقاء تُقلب فيها المحاور: الطول يُقاس أفقيًا.
    final bool lying = posture == PostureKind.lying || posture == PostureKind.fallen;
    if (lying) {
      candidates.clear();
      final double horizontal = distance('nose', 'left_ankle') == 0
          ? distance('nose', 'right_ankle')
          : distance('nose', 'left_ankle');
      addCandidate(horizontal, 0.87);
      addCandidate(shoulderSpan, shoulderToHeight);
    }

    if (candidates.isEmpty) {
      return BodyShape.average;
    }

    candidates.sort();
    final double median = candidates[candidates.length ~/ 2];
    final double height = NumUtils.clampRange(median, 1.45, 2.05);

    final double shoulderWidth = NumUtils.clampRange(
      shoulderSpan > 0 ? shoulderSpan / math.max(0.05, torsoSpan) * 0.30 : 0.245,
      0.19,
      0.33,
    );
    final double hipWidth = NumUtils.clampRange(
      hipSpan > 0 ? hipSpan / math.max(0.05, torsoSpan) * 0.30 : 0.19,
      0.15,
      0.30,
    );

    final double shoulderM = shoulderWidth * height;
    final double hipM = hipWidth * height * 2 * math.pi * 0.72;
    final double chestM = shoulderM * 2.55 + 0.16;
    final double taper = NumUtils.clamp01(
      (shoulderM / math.max(0.16, hipWidth * height)) - 0.9,
    );
    final double waistM = NumUtils.clampRange(
      (chestM + hipM) / 2 - 0.06 - taper * 0.10,
      0.58,
      1.35,
    );

    final double muscle = NumUtils.clamp01(
      0.25 + (taper * 0.6) + (shoulderSpan > 0 && torsoSpan > 0
          ? (shoulderSpan / torsoSpan - 0.85) * 0.5
          : 0),
    );

    // ثقة أعلى عند توفّر أعضاء أكثر ووضوح الوضعية.
    final int available = byName.length;
    final double confidence = NumUtils.clamp01(
      0.2 + available / 17 * 0.6 + (lying ? 0 : 0.1),
    );

    return BodyShape(
      heightM: height,
      shoulderM: shoulderM,
      chestM: chestM,
      waistM: waistM,
      hipM: hipM,
      armM: height * 0.36,
      legM: height * 0.47,
      muscle: muscle,
      confidence: confidence,
    );
  }
}

/// يحوّل مفاصل الإطار (0..1) إلى إحداثيات مترية حول نقطة أصل الجسم.
///
/// المحور Y إلى أعلى، X يمينًا، Z عمقًا. مقياس الصورة يأتي من تقدير الطول.
class JointProjector {
  const JointProjector._();

  static Map<String, Vec3> project({
    required List<PoseKeypoint> keypoints,
    required BodyShape shape,
  }) {
    if (keypoints.isEmpty) return const <String, Vec3>{};

    double minX = 1;
    double maxX = 0;
    double minY = 1;
    double maxY = 0;
    for (final PoseKeypoint kp in keypoints) {
      minX = math.min(minX, kp.x);
      maxX = math.max(maxX, kp.x);
      minY = math.min(minY, kp.y);
      maxY = math.max(maxY, kp.y);
    }

    final double width = math.max(0.05, maxX - minX);
    final double height = math.max(0.05, maxY - minY);

    // الأنسب: الربط بين الامتداد الرأسي/الأفقي والطول المقدّر.
    final double span = math.max(width, height);
    final double scale = shape.heightM / math.max(0.3, span * 1.06);
    final double cx = (minX + maxX) / 2;
    final double baseY = maxY;

    final Map<String, Vec3> joints = <String, Vec3>{};
    for (final PoseKeypoint kp in keypoints) {
      joints[kp.name] = Vec3(
        (kp.x - cx) * scale * 2,
        (baseY - kp.y) * scale,
        kp.z * shape.heightM * 0.5,
      );
    }
    return joints;
  }
}
