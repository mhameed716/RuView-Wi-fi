import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/domain/twin/body_mesh.dart';
import 'package:ruview_wifi/domain/twin/body_shape.dart';
import 'package:ruview_wifi/domain/twin/cloth_simulator.dart';
import 'package:ruview_wifi/domain/twin/vec3.dart';

void main() {
  group('ClothSimulator', () {
    final Map<String, Vec3> joints = BodyDefaults.neutralJoints(
      BodyShape.average,
    );

    test('الارتساء على الكتفين وتثبيت الصف العلوي', () {
      final ClothSimulator cloth = ClothSimulator();
      expect(cloth.isReady, isFalse);

      cloth.reset(joints: joints, shape: BodyShape.average);

      expect(cloth.isReady, isTrue);
      expect(cloth.particleCount, ClothSimulator.defaultCols * ClothSimulator.defaultRows);
      expect(cloth.pinnedCount, ClothSimulator.defaultCols);

      final List<Vec3> before = List<Vec3>.of(cloth.particles);
      for (int i = 0; i < 40; i++) {
        cloth.step(1 / 30, motion: 0.7);
      }

      // الصف العلوي لا يتحرّك أبدًا.
      for (int c = 0; c < ClothSimulator.defaultCols; c++) {
        expect(cloth.particles[c], before[c]);
      }
    });

    test('الحركة تُنتج رفرفة والقيم تبقى محدودة', () {
      final ClothSimulator cloth = ClothSimulator();
      cloth.reset(joints: joints, shape: BodyShape.average);

      for (int i = 0; i < 180; i++) {
        cloth.step(1 / 30, motion: 0.9);
      }

      expect(cloth.flutter, greaterThan(0));
      for (final Vec3 point in cloth.particles) {
        expect(point.isFinite, isTrue);
        expect(point.y, greaterThanOrEqualTo(0));
        expect(point.y, lessThan(2.3));
        expect(point.x.abs(), lessThanOrEqualTo(0.91));
      }
    });

    test('بلا حركة يستقر القماش قريبًا من موضع الارتساء', () {
      final ClothSimulator cloth = ClothSimulator();
      cloth.reset(joints: joints, shape: BodyShape.average);

      for (int i = 0; i < 240; i++) {
        cloth.step(1 / 30);
      }

      double maxOffset = 0;
      for (final Vec3 point in cloth.particles) {
        maxOffset = math.max(maxOffset, point.z.abs());
      }
      expect(maxOffset, lessThan(1.0));
      expect(cloth.flutter, lessThan(0.2));
    });
  });
}
