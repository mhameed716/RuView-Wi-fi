import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/models/posture.dart';
import 'package:ruview_wifi/data/models/sensing_frame.dart';
import 'package:ruview_wifi/domain/twin/body_profile.dart';
import 'package:ruview_wifi/domain/twin/body_shape.dart';
import 'package:ruview_wifi/domain/twin/vec3.dart';

PoseKeypoint keypoint(String name, double x, double y) => PoseKeypoint(
      name: name,
      x: x,
      y: y,
      z: 0,
      confidence: 0.9,
    );

List<PoseKeypoint> standingSkeleton() => <PoseKeypoint>[
      keypoint('nose', 0.5, 0.1),
      keypoint('left_shoulder', 0.42, 0.24),
      keypoint('right_shoulder', 0.58, 0.24),
      keypoint('left_hip', 0.45, 0.52),
      keypoint('right_hip', 0.55, 0.52),
      keypoint('left_knee', 0.46, 0.72),
      keypoint('right_knee', 0.54, 0.72),
      keypoint('left_ankle', 0.47, 0.92),
      keypoint('right_ankle', 0.53, 0.92),
    ];

void main() {
  group('BodyShape', () {
    test('القياسات الأساسية موجودة ومعاملات β عشرية', () {
      const BodyShape shape = BodyShape.average;

      expect(shape.measurements.length, greaterThanOrEqualTo(8));
      expect(shape.betas.length, 10);
      expect(shape.betaLabel, contains('β'));
      expect(shape.estimatedMassKg, greaterThan(40));
      expect(shape.buildLabel, isNotEmpty);
    });

    test('الدمج مع شكل آخر يقع بين القيمتين', () {
      const BodyShape tall = BodyShape(
        heightM: 1.9,
        shoulderM: 0.48,
        chestM: 1.06,
        waistM: 0.86,
        hipM: 1.0,
        armM: 0.68,
        legM: 0.9,
        muscle: 0.6,
      );

      final BodyShape mixed = BodyShape.average.mixed(tall, 0.5);
      expect(mixed.heightM, greaterThan(BodyShape.average.heightM));
      expect(mixed.heightM, lessThan(tall.heightM));
    });

    test('JSON ذهاب وعودة يحفظ القياسات', () {
      const BodyShape shape = BodyShape(
        heightM: 1.81,
        shoulderM: 0.45,
        chestM: 1.02,
        waistM: 0.84,
        hipM: 0.98,
        armM: 0.65,
        legM: 0.86,
        muscle: 0.5,
      );

      final BodyShape restored = BodyShape.fromJson(shape.toJson());
      expect(restored.heightM, closeTo(1.81, 1e-9));
      expect(restored.waistM, closeTo(0.84, 1e-9));
    });
  });

  group('BodyShapeEstimator', () {
    test('يقدّر الطول والشكل من هيكل واقف', () {
      final BodyShape shape = BodyShapeEstimator.estimate(
        keypoints: standingSkeleton(),
        posture: PostureKind.standing,
      );

      expect(shape.heightM, greaterThan(1.4));
      expect(shape.heightM, lessThan(2.1));
      expect(shape.shoulderM, greaterThan(0.25));
      expect(shape.confidence, greaterThan(0.2));
      expect(shape.waistM, greaterThan(0.5));
    });

    test('بلا مفاصل يعيد الجسم المتوسط', () {
      final BodyShape shape = BodyShapeEstimator.estimate(
        keypoints: const <PoseKeypoint>[],
      );

      expect(shape.heightM, BodyShape.average.heightM);
    });

    test('الإسقاط الميتري ينتج إحداثيات منتظمة (الرأس أعلى من الكاحل)', () {
      final BodyShape shape = BodyShapeEstimator.estimate(
        keypoints: standingSkeleton(),
      );
      final Map<String, Vec3> joints = JointProjector.project(
        keypoints: standingSkeleton(),
        shape: shape,
      );

      expect(joints.length, standingSkeleton().length);
      final Vec3 ankle = joints['left_ankle']!;
      final Vec3 head = joints['nose']!;
      final Vec3 hip = joints['left_hip']!;
      expect(ankle.y, lessThan(head.y));
      expect(hip.y, greaterThan(ankle.y));
      expect(head.y, closeTo(shape.heightM * 0.9, shape.heightM * 0.25));
    });
  });

  group('BodyRecognizer', () {
    test('يتعرّف على البصمة نفسها ويرفض المختلفة', () {
      final BodySignature signature = BodySignature.fromShape(
        BodyShape.average,
        gaitVector: const <double>[1, 2, 3, 4, 5],
      );
      final BodyProfile profile = BodyProfile(
        id: 'p1',
        label: 'سالم',
        shape: BodyShape.average,
        signature: signature,
        enrolledAt: DateTime(2026, 2, 1),
      );

      final BodyMatch? same = BodyRecognizer.match(signature, <BodyProfile>[profile]);
      expect(same, isNotNull);
      expect(same!.profile.id, 'p1');
      expect(same.score, greaterThan(0.9));

      final BodySignature other = BodySignature.fromShape(
        BodyShape.average.copyWith(heightM: 1.95, shoulderM: 0.5),
        gaitVector: const <double>[5, 4, 3, 2, 1],
      );
      expect(BodyRecognizer.match(other, <BodyProfile>[profile]), isNull);
    });
  });
}
