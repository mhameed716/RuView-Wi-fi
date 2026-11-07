import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/models/posture.dart';
import 'package:ruview_wifi/data/models/sensing_frame.dart';
import 'package:ruview_wifi/domain/twin/body_mesh.dart';
import 'package:ruview_wifi/domain/twin/body_shape.dart';
import 'package:ruview_wifi/domain/twin/shape_completion.dart';
import 'package:ruview_wifi/domain/twin/vec3.dart';

PoseKeypoint kp(String name, double x, double y) => PoseKeypoint(
      name: name,
      x: x,
      y: y,
      z: 0,
      confidence: 0.9,
    );

void main() {
  group('BodyMeshBuilder', () {
    test('يبني شبكة صالحة من جسم متوسط', () {
      final BodyMesh mesh = BodyMeshBuilder.build(
        joints: BodyDefaults.neutralJoints(BodyShape.average),
        shape: BodyShape.average,
      );

      expect(mesh.isEmpty, isFalse);
      expect(mesh.vertexCount, greaterThan(60));
      expect(mesh.triangleCount, greaterThan(60));
      expect(mesh.triangleSurfaces.length, mesh.triangleCount);
      expect(mesh.laplacianEnergy.isFinite, isTrue);
      expect(mesh.heightM, closeTo(BodyShape.average.heightM, 0.12));
      for (final Vec3 vertex in mesh.vertices) {
        expect(vertex.isFinite, isTrue);
      }
    });

    test('الطول الأكبر ينتج مجسّمًا أطول (بارامتري لا ثابت)', () {
      final BodyShape tall = BodyShape.average.copyWith(heightM: 1.94);
      final BodyShape short = BodyShape.average.copyWith(heightM: 1.58);

      final BodyMesh tallMesh = BodyMeshBuilder.build(
        joints: BodyDefaults.neutralJoints(tall),
        shape: tall,
      );
      final BodyMesh shortMesh = BodyMeshBuilder.build(
        joints: BodyDefaults.neutralJoints(short),
        shape: short,
      );

      expect(tallMesh.heightM, greaterThan(shortMesh.heightM));
    });

    test('الأكتاف الأعرض تُنتج شبكة أعرض', () {
      final BodyShape broad = BodyShape.average.copyWith(shoulderM: 0.52);
      final BodyShape narrow = BodyShape.average.copyWith(shoulderM: 0.34);

      final BodyMesh broadMesh = BodyMeshBuilder.build(
        joints: BodyDefaults.neutralJoints(broad),
        shape: broad,
      );
      final BodyMesh narrowMesh = BodyMeshBuilder.build(
        joints: BodyDefaults.neutralJoints(narrow),
        shape: narrow,
      );

      final double broadWidth = broadMesh.bounds.max.x - broadMesh.bounds.min.x;
      final double narrowWidth =
          narrowMesh.bounds.max.x - narrowMesh.bounds.min.x;
      expect(broadWidth, greaterThan(narrowWidth));
    });
  });

  group('ShapeCompleter', () {
    test('يكمل الأطراف الناقصة من الجذع فقط', () {
      final Map<String, Vec3> observed = <String, Vec3>{
        'left_shoulder': const Vec3(0.21, 1.42, 0),
        'right_shoulder': const Vec3(-0.21, 1.42, 0),
        'left_hip': const Vec3(0.12, 0.92, 0),
        'right_hip': const Vec3(-0.12, 0.92, 0),
      };

      final ShapeCompletionResult result = ShapeCompleter.complete(
        observed: observed,
        shape: BodyShape.average,
        posture: PostureKind.standing,
      );

      for (final String joint in ShapeCompleter.canonicalJoints) {
        expect(
          result.joints.containsKey(joint),
          isTrue,
          reason: 'المفصل الناقص: $joint',
        );
      }
      expect(result.observed, 4);
      expect(result.synthesized, greaterThan(0));
      expect(result.score, greaterThan(0));
      expect(result.score, lessThan(1));

      // تماثل الأطراف الناتجة (سابقة الجسم المتناظر).
      final Vec3 leftElbow = result.joints['left_elbow']!;
      final Vec3 rightElbow = result.joints['right_elbow']!;
      expect(leftElbow.x, closeTo(-rightElbow.x, 1e-6));

      // الرُكبتان تحت الحوض، والكاحلان تحت الرُكبتين.
      expect(result.joints['left_knee']!.y, lessThan(result.joints['left_hip']!.y));
      expect(
        result.joints['left_ankle']!.y,
        lessThan(result.joints['left_knee']!.y),
      );
    });

    test('التنعيم يقلّل خشونة السطح ويحافظ على الطول', () {
      final BodyMesh mesh = BodyMeshBuilder.build(
        joints: BodyDefaults.neutralJoints(BodyShape.average),
        shape: BodyShape.average,
      );
      final double before = mesh.laplacianEnergy;
      final double heightBefore = mesh.heightM;

      final BodyMesh smoothed = ShapeCompleter.smooth(mesh, iterations: 2);

      expect(smoothed.vertexCount, mesh.vertexCount);
      // التنعيم لا يزيد الخشونة، وقد غيّر السطح فعليًا.
      expect(smoothed.laplacianEnergy, lessThanOrEqualTo(before));
      expect(smoothed.vertices, isNot(equals(mesh.vertices)));
      expect(smoothed.heightM, closeTo(heightBefore, heightBefore * 0.05));
      for (final Vec3 vertex in smoothed.vertices) {
        expect(vertex.isFinite, isTrue);
      }
    });

    test('الوضعية الجالسة تثني الأطراف للأمام', () {
      final Map<String, Vec3> observed = <String, Vec3>{
        'left_shoulder': const Vec3(0.21, 1.1, 0),
        'right_shoulder': const Vec3(-0.21, 1.1, 0),
        'left_hip': const Vec3(0.12, 0.72, 0),
        'right_hip': const Vec3(-0.12, 0.72, 0),
      };

      final ShapeCompletionResult sitting = ShapeCompleter.complete(
        observed: observed,
        shape: BodyShape.average,
        posture: PostureKind.sitting,
      );
      final ShapeCompletionResult standing = ShapeCompleter.complete(
        observed: observed,
        shape: BodyShape.average,
        posture: PostureKind.standing,
      );

      expect(
        sitting.joints['left_knee']!.z,
        greaterThan(standing.joints['left_knee']!.z),
      );
    });
  });

  group('هيكل من CSI', () {
    test('الإكمال يعمل على مفاصل مشتقة من إطار حقيقي', () {
      final List<PoseKeypoint> keypoints = <PoseKeypoint>[
        kp('nose', 0.5, 0.1),
        kp('left_shoulder', 0.42, 0.24),
        kp('right_shoulder', 0.58, 0.24),
        kp('left_hip', 0.45, 0.52),
        kp('right_hip', 0.55, 0.52),
      ];
      final BodyShape shape = BodyShapeEstimator.estimate(
        keypoints: keypoints,
        posture: PostureKind.standing,
      );
      final Map<String, Vec3> projected = JointProjector.project(
        keypoints: keypoints,
        shape: shape,
      );
      final ShapeCompletionResult result = ShapeCompleter.complete(
        observed: projected,
        shape: shape,
        posture: PostureKind.standing,
      );

      final BodyMesh mesh = BodyMeshBuilder.build(
        joints: result.joints,
        shape: shape,
      );
      expect(mesh.isEmpty, isFalse);
      expect(result.joints.length, greaterThan(projected.length));
    });
  });
}
