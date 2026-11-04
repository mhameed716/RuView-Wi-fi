import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/models/sensing_frame.dart';
import 'package:ruview_wifi/domain/monitoring/intrusion_detector.dart';
import 'package:ruview_wifi/domain/monitoring/safety_state.dart';

SensingFrame frame({
  bool presence = true,
  String motionLevel = 'present_moving',
  double motionPower = 0.5,
  String zone = 'zone_1',
  bool hasPerson = true,
}) {
  return SensingFrame.fromJson(
    <String, dynamic>{
      'type': 'sensing_update',
      'features': <String, dynamic>{'motion_band_power': motionPower},
      'classification': <String, dynamic>{
        'motion_level': motionLevel,
        'presence': presence,
        'confidence': 0.9,
      },
      if (hasPerson)
        'persons': <Map<String, dynamic>>[
          <String, dynamic>{'id': 1, 'confidence': 0.9, 'zone': zone},
        ],
    },
    receivedAt: DateTime(2026, 1, 1, 23),
  );
}

void main() {
  group('IntrusionDetector', () {
    final DateTime t0 = DateTime(2026, 1, 1, 23, 0);

    test('لا يصدر شيئًا وهو غير مسلّح', () {
      final IntrusionDetector detector = IntrusionDetector();

      expect(
        detector.evaluate(
          frame: frame(),
          motionIntensity: 0.8,
          now: t0.add(const Duration(minutes: 1)),
        ),
        isNull,
      );
    });

    test('يتجاهل الحركة خلال مهلة التسليح', () {
      final IntrusionDetector detector = IntrusionDetector();
      detector.setArmed(true, now: t0);

      expect(
        detector.evaluate(
          frame: frame(),
          motionIntensity: 0.8,
          now: t0.add(const Duration(seconds: 10)),
        ),
        isNull,
      );
    });

    test('يرصد الحركة بعد مهلة التسليح ويحدد المنطقة', () {
      final IntrusionDetector detector = IntrusionDetector();
      detector.setArmed(true, now: t0);

      final IntrusionAlert? alert = detector.evaluate(
        frame: frame(),
        motionIntensity: 0.7,
        now: t0.add(const Duration(seconds: 21)),
      );

      expect(alert, isNotNull);
      expect(alert!.zone, 'zone_1');
      expect(alert.confidence, greaterThanOrEqualTo(0.5));
      expect(alert.motionIntensity, closeTo(0.7, 1e-9));
    });

    test('يحترم فترة التهدئة بين التنبيهات', () {
      final IntrusionDetector detector = IntrusionDetector();
      detector.setArmed(true, now: t0);

      expect(
        detector.evaluate(
          frame: frame(),
          motionIntensity: 0.7,
          now: t0.add(const Duration(seconds: 21)),
        ),
        isNotNull,
      );
      expect(
        detector.evaluate(
          frame: frame(),
          motionIntensity: 0.7,
          now: t0.add(const Duration(seconds: 31)),
        ),
        isNull,
      );
      expect(
        detector.evaluate(
          frame: frame(),
          motionIntensity: 0.7,
          now: t0.add(const Duration(seconds: 52)),
        ),
        isNotNull,
      );
    });

    test('إيقاف الحراسة يلغي التنبيهات', () {
      final IntrusionDetector detector = IntrusionDetector();
      detector.setArmed(true, now: t0);
      detector.setArmed(false, now: t0);

      expect(
        detector.evaluate(
          frame: frame(),
          motionIntensity: 0.9,
          now: t0.add(const Duration(minutes: 2)),
        ),
        isNull,
      );
    });

    test('لا يصدر تنبيهًا عند غياب أي حركة أو حضور', () {
      final IntrusionDetector detector = IntrusionDetector();
      detector.setArmed(true, now: t0);

      expect(
        detector.evaluate(
          frame: frame(
            presence: false,
            motionLevel: 'absent',
            motionPower: 0,
            hasPerson: false,
          ),
          motionIntensity: 0.02,
          now: t0.add(const Duration(minutes: 1)),
        ),
        isNull,
      );
    });
  });
}
