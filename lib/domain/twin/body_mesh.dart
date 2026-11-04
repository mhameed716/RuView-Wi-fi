import 'dart:math' as math;

import '../../core/utils/num_utils.dart';
import 'body_shape.dart';
import 'vec3.dart';

/// سطح الجسم (يُحدّد المادة/اللون في الرسم والشيدر).
enum BodySurface {
  skin(0xFFE3B08B, 'جلد'),
  shirt(0xFF1E8FA8, 'قميص'),
  pants(0xFF20313C, 'بنطال'),
  shoes(0xFF101B22, 'حذاء');

  const BodySurface(this.albedo, this.arabicLabel);

  final int albedo;
  final String arabicLabel;
}

/// مجسّم جسم شبكي (three.js-style mesh) مبني إجرائيًا من [BodyShape] والمفاصل.
///
/// بديل حقيقي عن «المجسمات الثابتة»: كل تغيّر في معاملات β ينتج رؤوسًا
/// مختلفة، فتظهر الأكتاف عريضة/ضيقة والساقان طويلتان/قصيرتان فعليًا.
class BodyMesh {
  const BodyMesh({
    required this.vertices,
    required this.triangles,
    required this.triangleSurfaces,
    required this.joints,
    required this.shape,
  });

  static const BodyMesh empty = BodyMesh(
    vertices: <Vec3>[],
    triangles: <int>[],
    triangleSurfaces: <BodySurface>[],
    joints: <String, Vec3>{},
    shape: BodyShape.average,
  );

  final List<Vec3> vertices;

  /// فهارس مثلثات مسطّحة (3 فهارس لكل مثلث).
  final List<int> triangles;

  /// سطح كل مثلث (بنفس ترتيب `triangles ~/ 3`).
  final List<BodySurface> triangleSurfaces;

  final Map<String, Vec3> joints;

  final BodyShape shape;

  bool get isEmpty => vertices.isEmpty || triangles.isEmpty;

  int get triangleCount => triangles.length ~/ 3;

  int get vertexCount => vertices.length;

  /// طاقة لابلاسيان المتوسطة: مقياس «خشونة» الشبكة.
  ///
  /// تستخدمها طبقة تنعيم السطح (shape completion) ولها عتبة في الاختبارات.
  double get laplacianEnergy {
    if (vertices.isEmpty) return 0;
    final Map<int, Set<int>> neighbours = <int, Set<int>>{};
    for (int i = 0; i < triangles.length; i += 3) {
      final int a = triangles[i];
      final int b = triangles[i + 1];
      final int c = triangles[i + 2];
      neighbours.putIfAbsent(a, () => <int>{}).addAll(<int>[b, c]);
      neighbours.putIfAbsent(b, () => <int>{}).addAll(<int>[a, c]);
      neighbours.putIfAbsent(c, () => <int>{}).addAll(<int>[a, b]);
    }

    double total = 0;
    int counted = 0;
    neighbours.forEach((int index, Set<int> ring) {
      if (ring.isEmpty || index >= vertices.length) return;
      Vec3 sum = Vec3.zero;
      for (final int other in ring) {
        if (other < vertices.length) sum += vertices[other];
      }
      final Vec3 average = sum * (1 / ring.length);
      total += (vertices[index] - average).length;
      counted++;
    });
    return counted == 0 ? 0 : total / counted;
  }

  ({Vec3 min, Vec3 max}) get bounds {
    if (vertices.isEmpty) {
      return (min: Vec3.zero, max: Vec3.zero);
    }
    double minX = vertices.first.x;
    double minY = vertices.first.y;
    double minZ = vertices.first.z;
    double maxX = minX;
    double maxY = minY;
    double maxZ = minZ;
    for (final Vec3 v in vertices) {
      minX = math.min(minX, v.x);
      minY = math.min(minY, v.y);
      minZ = math.min(minZ, v.z);
      maxX = math.max(maxX, v.x);
      maxY = math.max(maxY, v.y);
      maxZ = math.max(maxZ, v.z);
    }
    return (
      min: Vec3(minX, minY, minZ),
      max: Vec3(maxX, maxY, maxZ),
    );
  }

  double get heightM => bounds.max.y - bounds.min.y;

  BodyMesh withVertices(List<Vec3> next) => BodyMesh(
        vertices: next,
        triangles: triangles,
        triangleSurfaces: triangleSurfaces,
        joints: joints,
        shape: shape,
      );
}

/// يبني شبكة الجسم من المفاصل + معاملات الشكل.
class BodyMeshBuilder {
  const BodyMeshBuilder._();

  /// عدد أضلاع كل حلقة (8 = توازن بين النعومة والتكلفة على الهاتف).
  static const int ringSegments = 8;

  static BodyMesh build({
    required Map<String, Vec3> joints,
    required BodyShape shape,
  }) {
    if (joints.isEmpty) return BodyMesh.empty;

    final _MeshAccumulator acc = _MeshAccumulator();

    Vec3? joint(String name) => joints[name];

    final Vec3? pelvis = joint('pelvis');
    final Vec3? neck = joint('neck');

    if (pelvis != null && neck != null) {
      final double hipR = shape.hipRadius;
      final double waistR = shape.waistRadius;
      final double chestR = shape.chestRadius;
      final double shoulderHalf = shape.shoulderM / 2;

      final Vec3 axis = (neck - pelvis).normalized();
      final double length = (neck - pelvis).length;
      final List<double> t = <double>[0, 0.22, 0.45, 0.7, 0.9, 1.0];
      final List<double> rx = <double>[
        hipR * 1.28,
        hipR * 1.22,
        waistR * 1.1,
        chestR * 1.22,
        shoulderHalf * 0.86,
        shoulderHalf * 0.62,
      ];
      final List<double> rz = <double>[
        hipR * 0.92,
        hipR * 0.86,
        waistR * 0.72,
        chestR * 0.88,
        chestR * 0.72,
        shoulderHalf * 0.42,
      ];

      final List<_Section> sections = <_Section>[];
      for (int i = 0; i < t.length; i++) {
        sections.add(
          _Section(
            center: pelvis + axis * (length * t[i]),
            rx: rx[i],
            rz: rz[i],
            axis: axis,
          ),
        );
      }
      acc.addTube(sections: sections, surface: BodySurface.shirt, capEnd: true);
    }

    // الرأس: كرة بيضاوية فوق الرقبة.
    if (neck != null) {
      final double headR = shape.heightM * 0.077;
      final Vec3 up = Vec3.up;
      final List<_Section> sections = <_Section>[];
      for (int i = 0; i <= 4; i++) {
        final double u = i / 4;
        final double profile = math.sin(math.pi * (0.15 + u * 0.75));
        sections.add(
          _Section(
            center: neck + up * (0.03 + u * headR * 2.2),
            rx: headR * profile * 0.95,
            rz: headR * profile * 0.78,
            axis: up,
          ),
        );
      }
      acc.addTube(sections: sections, surface: BodySurface.skin, capEnd: true);
    }

    void limb({
      required String from,
      required String via,
      required String to,
      required double baseRadius,
      required BodySurface upper,
      required BodySurface lower,
      required double bulge,
    }) {
      final Vec3? a = joint(from);
      final Vec3? b = joint(via);
      final Vec3? c = joint(to);
      if (a == null || b == null || c == null) return;

      final double r = baseRadius * (1 + 0.22 * shape.muscle) * bulge;
      acc.addTube(
        sections: <_Section>[
          _Section(center: a, rx: r * 1.18, rz: r * 1.12, axis: (b - a).normalized()),
          _Section(
            center: a.lerp(b, 0.55),
            rx: r * 1.06,
            rz: r,
            axis: (b - a).normalized(),
          ),
          _Section(center: b, rx: r * 0.86, rz: r * 0.82, axis: (c - b).normalized()),
        ],
        surface: upper,
      );
      acc.addTube(
        sections: <_Section>[
          _Section(center: b, rx: r * 0.84, rz: r * 0.8, axis: (c - b).normalized()),
          _Section(
            center: b.lerp(c, 0.5),
            rx: r * 0.72,
            rz: r * 0.68,
            axis: (c - b).normalized(),
          ),
          _Section(center: c, rx: r * 0.5, rz: r * 0.46, axis: (c - b).normalized()),
        ],
        surface: lower,
        capEnd: true,
      );
    }

    final double armR = shape.armM * 0.072;
    limb(
      from: 'left_shoulder',
      via: 'left_elbow',
      to: 'left_wrist',
      baseRadius: armR,
      upper: BodySurface.shirt,
      lower: BodySurface.skin,
      bulge: 1,
    );
    limb(
      from: 'right_shoulder',
      via: 'right_elbow',
      to: 'right_wrist',
      baseRadius: armR,
      upper: BodySurface.shirt,
      lower: BodySurface.skin,
      bulge: 1,
    );

    final double legR = shape.legM * 0.088;
    limb(
      from: 'left_hip',
      via: 'left_knee',
      to: 'left_ankle',
      baseRadius: legR,
      upper: BodySurface.pants,
      lower: BodySurface.pants,
      bulge: 1.05,
    );
    limb(
      from: 'right_hip',
      via: 'right_knee',
      to: 'right_ankle',
      baseRadius: legR,
      upper: BodySurface.pants,
      lower: BodySurface.pants,
      bulge: 1.05,
    );

    // القدمان: امتداد أفقي أمام الكاحل.
    for (final String side in <String>['left', 'right']) {
      final Vec3? ankle = joint('${side}_ankle');
      if (ankle == null) continue;
      final Vec3 tip = ankle + Vec3(0, -0.015, shape.heightM * 0.075);
      acc.addTube(
        sections: <_Section>[
          _Section(center: ankle, rx: legR * 0.5, rz: legR * 0.55, axis: Vec3.forward),
          _Section(center: tip, rx: legR * 0.45, rz: legR * 0.4, axis: Vec3.forward),
        ],
        surface: BodySurface.shoes,
        capEnd: true,
      );
    }

    return BodyMesh(
      vertices: acc.vertices,
      triangles: acc.triangles,
      triangleSurfaces: acc.surfaces,
      joints: joints,
      shape: shape,
    );
  }

  /// شبكة مرجعية «متوسطة» تُستخدم كسابقة في تنعيم/إكمال الشكل.
  static BodyMesh reference({BodyShape shape = BodyShape.average}) {
    return build(joints: BodyDefaults.neutralJoints(shape), shape: shape);
  }
}

/// المفاصل الافتراضية لجسم واقف — تُستخدم عند غياب أي رصد.
class BodyDefaults {
  const BodyDefaults._();

  static Map<String, Vec3> neutralJoints(BodyShape shape) {
    final double h = shape.heightM;
    final double shoulderY = h * 0.82;
    final double hipY = h * 0.52;
    final double kneeY = h * 0.28;
    final double ankleY = h * 0.04;
    final double halfShoulder = shape.shoulderM / 2;
    final double halfHip = shape.hipM / (2 * math.pi) * 0.9;

    return <String, Vec3>{
      'pelvis': Vec3(0, hipY + 0.03, 0),
      'neck': Vec3(0, shoulderY + 0.06, 0),
      'nose': Vec3(0, h * 0.94, 0.03),
      'head_top': Vec3(0, h * 0.985, 0),
      'left_shoulder': Vec3(halfShoulder, shoulderY, 0),
      'right_shoulder': Vec3(-halfShoulder, shoulderY, 0),
      'left_elbow': Vec3(halfShoulder + 0.03, shoulderY - shape.armM * 0.32, 0),
      'right_elbow': Vec3(-halfShoulder - 0.03, shoulderY - shape.armM * 0.32, 0),
      'left_wrist': Vec3(halfShoulder + 0.04, shoulderY - shape.armM * 0.62, 0.02),
      'right_wrist': Vec3(-halfShoulder - 0.04, shoulderY - shape.armM * 0.62, 0.02),
      'left_hip': Vec3(halfHip, hipY, 0),
      'right_hip': Vec3(-halfHip, hipY, 0),
      'left_knee': Vec3(halfHip, kneeY, 0.01),
      'right_knee': Vec3(-halfHip, kneeY, 0.01),
      'left_ankle': Vec3(halfHip, ankleY, 0),
      'right_ankle': Vec3(-halfHip, ankleY, 0),
    };
  }
}

class _Section {
  _Section({
    required this.center,
    required this.rx,
    required this.rz,
    required this.axis,
  });

  final Vec3 center;
  final double rx;
  final double rz;
  final Vec3 axis;
}

class _MeshAccumulator {
  final List<Vec3> vertices = <Vec3>[];
  final List<int> triangles = <int>[];
  final List<BodySurface> surfaces = <BodySurface>[];

  void addTube({
    required List<_Section> sections,
    required BodySurface surface,
    bool capEnd = false,
  }) {
    if (sections.length < 2) return;

    final int startIndex = vertices.length;
    for (final _Section section in sections) {
      final Vec3 axis = section.axis.normalized();
      final Vec3 reference =
          axis.y.abs() > 0.9 ? Vec3.forward : Vec3.up;
      Vec3 u = reference.cross(axis).normalized();
      if (u == Vec3.zero) u = Vec3(1, 0, 0);
      final Vec3 v = axis.cross(u).normalized();

      for (int k = 0; k < BodyMeshBuilder.ringSegments; k++) {
        final double angle =
            2 * math.pi * k / BodyMeshBuilder.ringSegments;
        vertices.add(
          section.center.offset(
            u,
            v,
            math.cos(angle) * section.rx,
            math.sin(angle) * section.rz,
          ),
        );
      }
    }

    const int n = BodyMeshBuilder.ringSegments;
    for (int s = 0; s < sections.length - 1; s++) {
      final int base = startIndex + s * n;
      final int next = base + n;
      for (int k = 0; k < n; k++) {
        final int k2 = (k + 1) % n;
        triangles
          ..add(base + k)
          ..add(base + k2)
          ..add(next + k);
        surfaces.add(surface);

        triangles
          ..add(base + k2)
          ..add(next + k2)
          ..add(next + k);
        surfaces.add(surface);
      }
    }

    if (capEnd) {
      final int lastRing = startIndex + (sections.length - 1) * n;
      final Vec3 center = sections.last.center;
      final int centerIndex = vertices.length;
      vertices.add(center);
      for (int k = 0; k < n; k++) {
        final int k2 = (k + 1) % n;
        triangles
          ..add(lastRing + k)
          ..add(lastRing + k2)
          ..add(centerIndex);
        surfaces.add(surface);
      }
    }
  }
}

/// أدوات مشتركة لحساب زوايا الكاميرا والرسم.
class MeshMath {
  const MeshMath._();

  /// تدوير نقطة حول المحور Y (yaw) — لتدوير المجسّم في الواجهة.
  static Vec3 yaw(Vec3 point, double radians) {
    final double c = math.cos(radians);
    final double s = math.sin(radians);
    return Vec3(point.x * c - point.z * s, point.y, point.x * s + point.z * c);
  }

  /// إسقاط منظوري بسيط إلى مستوٍ ثنائي الأبعاد.
  static (double, double, double) project(
    Vec3 point, {
    required double cameraDistance,
    required double focalLength,
  }) {
    final double depth = math.max(0.05, cameraDistance + point.z);
    final double factor = focalLength / depth;
    return (point.x * factor, -point.y * factor, depth);
  }

  /// إضاءة لامبيرية ناعمة + لمعة بسيطة (PBR مبسّط) للّون الناتج.
  static double shade({
    required Vec3 normal,
    required Vec3 lightDirection,
    required double roughness,
  }) {
    final double diffuse = NumUtils.clamp01(normal.normalized().dot(lightDirection.normalized()));
    final double specular =
        math.pow(diffuse, 2 + (1 - NumUtils.clamp01(roughness)) * 24).toDouble();
    return NumUtils.clamp01(0.22 + diffuse * 0.72 + specular * 0.25);
  }
}
