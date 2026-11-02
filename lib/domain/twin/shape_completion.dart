import 'dart:math' as math;

import '../../core/utils/num_utils.dart';
import '../../data/models/posture.dart';
import 'body_mesh.dart';
import 'body_shape.dart';
import 'vec3.dart';

/// نتيجة إكمال الشكل: مفاصل كاملة + نسبة ما رُصد فعلًا من CSI.
class ShapeCompletionResult {
  const ShapeCompletionResult({
    required this.joints,
    required this.observed,
    required this.synthesized,
    required this.score,
  });

  final Map<String, Vec3> joints;
  final int observed;
  final int synthesized;

  /// نسبة المفاصل المرصودة إلى الإجمالي (0..1).
  final double score;

  static ShapeCompletionResult empty() => const ShapeCompletionResult(
        joints: <String, Vec3>{},
        observed: 0,
        synthesized: 0,
        score: 0,
      );
}

/// طبقة «التوليد التنبئي» (Generative Prior) لإكمال ما لا تراه موجات الواي فاي.
///
/// الواي فاي يعطي عادةً جذعًا ومفاصل قليلة؛ الأطراف تُغطّى بضجيج الانعكاسات.
/// هنا نعمل على مستويين:
///
///  1. **إكمال المفاصل**: الأطراف المفقودة تُولَّد من نسب أنثروبومترية +
///     تماثل الجسم (سابقة قبلية = prior)، فتصبح الأطراف متناسقة بدل نقاط عشوائية.
///  2. **تنعيم السطح**: تنعيم لابلاسي متكرر (Taubin λ/μ) يعمل كبديل خفيف عن
///     نموذج انتشار كامل: يزيل النتوءات الناتجة عن ضجيج CSI ويُعيد للجسم
///     انحناءاته الطبيعية، مع الحفاظ على الحجم.
class ShapeCompleter {
  const ShapeCompleter._();

  /// المفاصل القياسية (COCO 17 + جذع/رأس).
  static const List<String> canonicalJoints = <String>[
    'nose',
    'left_eye',
    'right_eye',
    'left_ear',
    'right_ear',
    'left_shoulder',
    'right_shoulder',
    'left_elbow',
    'right_elbow',
    'left_wrist',
    'right_wrist',
    'left_hip',
    'right_hip',
    'left_knee',
    'right_knee',
    'left_ankle',
    'right_ankle',
  ];

  /// يكمل المفاصل الناقصة ويعيد خريطة كاملة.
  static ShapeCompletionResult complete({
    required Map<String, Vec3> observed,
    required BodyShape shape,
    PostureKind posture = PostureKind.unknown,
  }) {
    final int observedCount = observed.length;
    if (observed.isEmpty) {
      return ShapeCompletionResult(
        joints: BodyDefaults.neutralJoints(shape),
        observed: 0,
        synthesized: canonicalJoints.length + 2,
        score: 0,
      );
    }

    final Map<String, Vec3> next = Map<String, Vec3>.of(observed);

    Vec3? pick(String name) => next[name];

    void setIfMissing(String name, Vec3 value) {
      if (!next.containsKey(name)) next[name] = value;
    }

    final double torsoLength = shape.heightM * BodyShapeEstimator.torsoToHeight;

    // 1) الجذع.
    Vec3? pelvis = pick('pelvis');
    final Vec3? leftHip = pick('left_hip');
    final Vec3? rightHip = pick('right_hip');
    if (pelvis == null && leftHip != null && rightHip != null) {
      pelvis = (leftHip + rightHip) * 0.5;
    }

    Vec3? neck = pick('neck');
    final Vec3? leftShoulder = pick('left_shoulder');
    final Vec3? rightShoulder = pick('right_shoulder');
    if (neck == null && leftShoulder != null && rightShoulder != null) {
      neck = (leftShoulder + rightShoulder) * 0.5;
    }

    // محور الجسم: يُستنتج من المتاح، وإلا فعمودي.
    Vec3 bodyAxis = Vec3.up;
    if (pelvis != null && neck != null && (neck - pelvis).length > 0.1) {
      bodyAxis = (neck - pelvis).normalized();
    } else if (posture == PostureKind.lying || posture == PostureKind.fallen) {
      bodyAxis = Vec3(1, 0, 0);
    }

    pelvis ??= neck != null
        ? neck - bodyAxis * torsoLength
        : Vec3(0, shape.heightM * 0.52, 0);
    neck ??= pelvis + bodyAxis * torsoLength;

    setIfMissing('pelvis', pelvis);
    setIfMissing('neck', neck);

    // 2) الكتفان/الحوض: تماثل الجسم (سابقة قوية).
    final double halfShoulder = shape.shoulderM / 2;
    Vec3 across;
    if (bodyAxis.y.abs() > 0.9) {
      across = Vec3(1, 0, 0);
    } else {
      across = Vec3(0, 1, 0).cross(bodyAxis).normalized();
      if (across == Vec3.zero) across = Vec3(1, 0, 0);
    }

    if (pick('left_shoulder') == null && pick('right_shoulder') == null) {
      setIfMissing('left_shoulder', neck + across * halfShoulder);
      setIfMissing('right_shoulder', neck - across * halfShoulder);
    } else if (pick('left_shoulder') == null) {
      final Vec3 mirror = _mirror(pick('right_shoulder')!, neck, across);
      setIfMissing('left_shoulder', mirror);
    } else if (pick('right_shoulder') == null) {
      final Vec3 mirror = _mirror(pick('left_shoulder')!, neck, across);
      setIfMissing('right_shoulder', mirror);
    }

    final double halfHip = shape.hipRadius * 0.82;
    if (pick('left_hip') == null && pick('right_hip') == null) {
      setIfMissing('left_hip', pelvis + across * halfHip);
      setIfMissing('right_hip', pelvis - across * halfHip);
    } else if (pick('left_hip') == null) {
      setIfMissing('left_hip', _mirror(pick('right_hip')!, pelvis, across));
    } else if (pick('right_hip') == null) {
      setIfMissing('right_hip', _mirror(pick('left_hip')!, pelvis, across));
    }

    // 3) الرأس.
    final Vec3 headTop = neck + bodyAxis * (shape.heightM * 0.12);
    setIfMissing('nose', neck + bodyAxis * (shape.heightM * 0.09) + Vec3(0, 0, 0.04));
    setIfMissing('left_ear', headTop - bodyAxis * (shape.heightM * 0.03) + across * 0.05);
    setIfMissing('right_ear', headTop - bodyAxis * (shape.heightM * 0.03) - across * 0.05);

    // 4) الأطراف: اتجاه يتغيّر حسب الوضعية.
    final ({Vec3 upper, Vec3 lower}) armDir = _armDirection(posture, across, bodyAxis);
    final ({Vec3 upper, Vec3 lower}) legDir = _legDirection(posture, across, bodyAxis);

    final double upperArm = shape.armM * 0.52;
    final double foreArm = shape.armM * 0.46;
    final double thigh = shape.legM * 0.52;
    final double shin = shape.legM * 0.46;

    for (final String side in <String>['left', 'right']) {
      final double sign = side == 'left' ? 1 : -1;
      final Vec3? shoulder = pick('${side}_shoulder');
      final Vec3? hip = pick('${side}_hip');
      if (shoulder == null || hip == null) continue;

      final Vec3 elbow = pick('${side}_elbow') ??
          shoulder + _scaled(armDir.upper, sign) * upperArm;
      setIfMissing('${side}_elbow', elbow);
      final Vec3 wrist = pick('${side}_wrist') ??
          elbow + _scaled(armDir.lower, sign) * foreArm;
      setIfMissing('${side}_wrist', wrist);

      final Vec3 knee =
          pick('${side}_knee') ?? hip + _scaled(legDir.upper, sign) * thigh;
      setIfMissing('${side}_knee', knee);
      final Vec3 ankle =
          pick('${side}_ankle') ?? knee + _scaled(legDir.lower, sign) * shin;
      setIfMissing('${side}_ankle', ankle);
    }

    final int total = next.length;
    final double score =
        total == 0 ? 0 : NumUtils.clamp01(observedCount / total);

    return ShapeCompletionResult(
      joints: next,
      observed: observedCount,
      synthesized: math.max(0, total - observedCount),
      score: score,
    );
  }

  /// تنعيم لابلاسي (Taubin) لسطح المجسّم: يزيل ضجيج CSI ويحافظ على الحجم.
  static BodyMesh smooth(
    BodyMesh mesh, {
    int iterations = 2,
    double lambda = 0.5,
    double mu = -0.53,
  }) {
    if (mesh.isEmpty || iterations <= 0) return mesh;

    final List<Set<int>> ring = _adjacency(mesh);
    List<Vec3> current = List<Vec3>.of(mesh.vertices);

    List<Vec3> pass(List<Vec3> source, double factor) {
      final List<Vec3> target = List<Vec3>.of(source);
      for (int i = 0; i < source.length; i++) {
        final Set<int> neighbours = ring[i];
        if (neighbours.isEmpty) continue;
        Vec3 sum = Vec3.zero;
        for (final int other in neighbours) {
          sum += source[other];
        }
        final Vec3 average = sum * (1 / neighbours.length);
        target[i] = source[i] + (average - source[i]) * factor;
      }
      return target;
    }

    final ({Vec3 min, Vec3 max}) before = mesh.bounds;
    final double beforeHeight = math.max(0.01, before.max.y - before.min.y);

    for (int i = 0; i < iterations; i++) {
      current = pass(current, lambda);
      current = pass(current, mu);
    }

    // إعادة المعايرة للحفاظ على الطول الكلي (يمنع «انكماش» التنعيم).
    final BodyMesh smoothed = mesh.withVertices(current);
    final ({Vec3 min, Vec3 max}) after = smoothed.bounds;
    final double afterHeight = math.max(0.01, after.max.y - after.min.y);
    final double scaleY = beforeHeight / afterHeight;

    if ((scaleY - 1).abs() > 1e-4) {
      final double centerY = (after.min.y + after.max.y) / 2;
      final List<Vec3> rescaled = current
          .map(
            (Vec3 v) => Vec3(v.x, centerY + (v.y - centerY) * scaleY, v.z),
          )
          .toList(growable: false);
      return mesh.withVertices(rescaled);
    }

    return smoothed;
  }

  static List<Set<int>> _adjacency(BodyMesh mesh) {
    final List<Set<int>> ring =
        List<Set<int>>.generate(mesh.vertices.length, (_) => <int>{});
    for (int i = 0; i < mesh.triangles.length; i += 3) {
      final int a = mesh.triangles[i];
      final int b = mesh.triangles[i + 1];
      final int c = mesh.triangles[i + 2];
      if (a >= ring.length || b >= ring.length || c >= ring.length) continue;
      ring[a].addAll(<int>[b, c]);
      ring[b].addAll(<int>[a, c]);
      ring[c].addAll(<int>[a, b]);
    }
    return ring;
  }

  static Vec3 _mirror(Vec3 point, Vec3 pivot, Vec3 across) {
    final Vec3 relative = point - pivot;
    final double projection = relative.dot(across);
    return point - across * (projection * 2);
  }

  static Vec3 _scaled(Vec3 direction, double sign) =>
      Vec3(direction.x * sign, direction.y, direction.z);

  static ({Vec3 upper, Vec3 lower}) _armDirection(
    PostureKind posture,
    Vec3 across,
    Vec3 bodyAxis,
  ) {
    switch (posture) {
      case PostureKind.sitting:
        return (
          upper: Vec3(across.x * 0.3, -0.45, 0.85),
          lower: Vec3(across.x * 0.1, -0.9, 0.3),
        );
      case PostureKind.lying:
      case PostureKind.fallen:
        return (
          upper: _normalize(Vec3(-bodyAxis.x * 0.7, 0.25, 0.6)),
          lower: _normalize(Vec3(-bodyAxis.x * 0.7, 0.1, 0.7)),
        );
      case PostureKind.bending:
        return (
          upper: _normalize(Vec3(across.x * 0.25, -0.95, 0.2)),
          lower: _normalize(Vec3(across.x * 0.1, -0.95, 0.28)),
        );
      default:
        return (
          upper: _normalize(Vec3(across.x * 0.22, -0.96, 0.06)),
          lower: _normalize(Vec3(across.x * 0.12, -0.98, 0.1)),
        );
    }
  }

  static ({Vec3 upper, Vec3 lower}) _legDirection(
    PostureKind posture,
    Vec3 across,
    Vec3 bodyAxis,
  ) {
    switch (posture) {
      case PostureKind.sitting:
        return (
          upper: _normalize(Vec3(across.x * 0.1, 0.05, 0.99)),
          lower: _normalize(Vec3(0, -0.99, 0.05)),
        );
      case PostureKind.lying:
      case PostureKind.fallen:
        return (
          upper: _normalize(Vec3(bodyAxis.x, 0.05, 0.1)),
          lower: _normalize(Vec3(bodyAxis.x, 0.02, 0.05)),
        );
      default:
        return (
          upper: _normalize(Vec3(across.x * 0.08, -1, 0.02)),
          lower: _normalize(Vec3(across.x * 0.04, -1, 0.01)),
        );
    }
  }

  static Vec3 _normalize(Vec3 value) {
    final Vec3 unit = value.normalized();
    return unit == Vec3.zero ? Vec3.up : unit;
  }
}
