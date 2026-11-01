import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/models/gait_profile.dart';
import 'package:ruview_wifi/data/models/sensing_frame.dart';
import 'package:ruview_wifi/domain/monitoring/gait_analyzer.dart';

SensingFrame movingFrame({double motionPower = 0.5, double dominantHz = 1.6}) {
  return SensingFrame.fromJson(
    <String, dynamic>{
      'type': 'sensing_update',
      'features': <String, dynamic>{
        'motion_band_power': motionPower,
        'dominant_freq_hz': dominantHz,
        'variance': 2.4,
      },
      'classification': <String, dynamic>{
        'motion_level': 'present_moving',
        'presence': true,
        'confidence': 0.9,
      },
    },
    receivedAt: DateTime(2026, 1, 1, 18),
  );
}

void main() {
  group('GaitAnalyzer', () {
    final DateTime t0 = DateTime(2026, 1, 1, 18, 0);

    test('لا ينتج متجهًا قبل اكتمال النافذة', () {
      final GaitAnalyzer analyzer = GaitAnalyzer();

      for (int i = 0; i < 5; i++) {
        analyzer.add(
          movingFrame(motionPower: 0.4 + i * 0.02),
          motionIntensity: 0.6,
          at: t0.add(Duration(milliseconds: 400 * i)),
        );
      }

      expect(analyzer.isCollecting, isFalse);
      expect(analyzer.currentVector(t0.add(const Duration(seconds: 2))), isNull);
    });

    test('يبني متجه ميزات من نافذة مشي كاملة', () {
      final GaitAnalyzer analyzer = GaitAnalyzer();

      for (int i = 0; i < 20; i++) {
        analyzer.add(
          movingFrame(motionPower: 0.5 + (i.isEven ? 0.08 : -0.06)),
          motionIntensity: 0.6,
          at: t0.add(Duration(milliseconds: 400 * i)),
        );
      }

      final GaitFeatureVector? vector =
          analyzer.currentVector(t0.add(const Duration(seconds: 8)));

      expect(vector, isNotNull);
      expect(vector!.samples, greaterThanOrEqualTo(15));
      expect(vector.motionMean, greaterThan(0));
      expect(vector.dominantHz, closeTo(1.6, 1e-9));
      expect(vector.changeRate, greaterThan(0));
      expect(vector.similarityTo(vector), closeTo(1, 1e-6));
    });

    test('يتجاهل الإطارات الساكنة', () {
      final GaitAnalyzer analyzer = GaitAnalyzer();

      for (int i = 0; i < 20; i++) {
        analyzer.add(
          movingFrame(),
          motionIntensity: 0.05,
          at: t0.add(Duration(milliseconds: 400 * i)),
        );
      }

      expect(analyzer.sampleCount, 0);
      expect(analyzer.currentVector(t0), isNull);
    });

    test('ينسى العينات الأقدم من النافذة', () {
      final GaitAnalyzer analyzer = GaitAnalyzer();

      for (int i = 0; i < 20; i++) {
        analyzer.add(
          movingFrame(),
          motionIntensity: 0.6,
          at: t0.add(Duration(milliseconds: 400 * i)),
        );
      }
      expect(analyzer.sampleCount, greaterThanOrEqualTo(15));

      analyzer.add(
        movingFrame(),
        motionIntensity: 0.6,
        at: t0.add(const Duration(seconds: 40)),
      );
      expect(analyzer.sampleCount, 1);
    });

    test('تشابه جيب التمام يميّز البصمات المختلفة', () {
      const GaitFeatureVector walkA = GaitFeatureVector(
        motionMean: 0.55,
        motionStd: 0.12,
        dominantHz: 1.7,
        changeRate: 0.09,
        variance: 2.2,
        samples: 20,
      );
      const GaitFeatureVector walkB = GaitFeatureVector(
        motionMean: 0.56,
        motionStd: 0.11,
        dominantHz: 1.65,
        changeRate: 0.09,
        variance: 2.3,
        samples: 20,
      );
      const GaitFeatureVector other = GaitFeatureVector(
        motionMean: 0.12,
        motionStd: 0.9,
        dominantHz: 4.5,
        changeRate: 0.6,
        variance: 0.2,
        samples: 20,
      );

      expect(walkA.similarityTo(walkB), greaterThan(0.95));
      expect(walkA.similarityTo(other), lessThan(walkA.similarityTo(walkB)));
    });
  });
}
