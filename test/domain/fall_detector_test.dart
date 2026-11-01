import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/models/posture.dart';
import 'package:ruview_wifi/domain/monitoring/fall_detector.dart';
import 'package:ruview_wifi/domain/monitoring/safety_state.dart';

void main() {
  group('FallDetector', () {
    final DateTime t0 = DateTime(2026, 1, 1, 20, 30);

    test('يرصد الانتقال السريع من الوقوف إلى الأرض مع حركة عنيفة', () {
      final FallDetector detector = FallDetector();

      expect(
        detector.evaluate(
          posture: PostureKind.standing,
          motionIntensity: 0.2,
          now: t0,
        ),
        isNull,
      );

      final FallAlert? alert = detector.evaluate(
        posture: PostureKind.lying,
        motionIntensity: 0.9,
        now: t0.add(const Duration(milliseconds: 800)),
      );

      expect(alert, isNotNull);
      expect(alert!.posture, PostureKind.lying);
      expect(alert.confidence, greaterThanOrEqualTo(0.6));
      expect(alert.isCritical, isTrue);
      expect(alert.reason, contains('انتقال سريع'));
    });

    test('يقبل إبلاغ الخادم عن سقوط بثقة عالية', () {
      final FallDetector detector = FallDetector();

      final FallAlert? alert = detector.evaluate(
        posture: PostureKind.fallen,
        motionIntensity: 0.1,
        now: t0,
        serverReportedFall: true,
      );

      expect(alert, isNotNull);
      expect(alert!.confidence, 0.95);
      expect(alert.reason, contains('خادم RuView'));
    });

    test('لا يعتبر النزول البطيء سقوطًا', () {
      final FallDetector detector = FallDetector();

      detector.evaluate(
        posture: PostureKind.standing,
        motionIntensity: 0.2,
        now: t0,
      );

      final FallAlert? alert = detector.evaluate(
        posture: PostureKind.lying,
        motionIntensity: 0.9,
        now: t0.add(const Duration(seconds: 6)),
      );

      expect(alert, isNull);
    });

    test('يشترط حركة عنيفة عند الانتقال من الجلوس', () {
      final FallDetector detector = FallDetector();

      detector.evaluate(
        posture: PostureKind.sitting,
        motionIntensity: 0.15,
        now: t0,
      );

      expect(
        detector.evaluate(
          posture: PostureKind.lying,
          motionIntensity: 0.6,
          now: t0.add(const Duration(milliseconds: 700)),
        ),
        isNull,
      );

      expect(
        detector.evaluate(
          posture: PostureKind.lying,
          motionIntensity: 0.85,
          now: t0.add(const Duration(milliseconds: 900)),
        ),
        isNotNull,
      );
    });

    test('يمنع تكرار التنبيه خلال فترة التهدئة', () {
      final FallDetector detector = FallDetector();

      detector.evaluate(
        posture: PostureKind.standing,
        motionIntensity: 0.2,
        now: t0,
      );
      expect(
        detector.evaluate(
          posture: PostureKind.lying,
          motionIntensity: 0.9,
          now: t0.add(const Duration(seconds: 1)),
        ),
        isNotNull,
      );

      detector.evaluate(
        posture: PostureKind.standing,
        motionIntensity: 0.2,
        now: t0.add(const Duration(seconds: 5)),
      );
      expect(
        detector.evaluate(
          posture: PostureKind.lying,
          motionIntensity: 0.9,
          now: t0.add(const Duration(seconds: 6)),
        ),
        isNull,
      );
    });

    test('reset يمحو الحالة السابقة', () {
      final FallDetector detector = FallDetector();

      detector.evaluate(
        posture: PostureKind.standing,
        motionIntensity: 0.2,
        now: t0,
      );
      detector.reset();

      expect(
        detector.evaluate(
          posture: PostureKind.lying,
          motionIntensity: 0.9,
          now: t0.add(const Duration(milliseconds: 500)),
        ),
        isNull,
      );
      expect(detector.lastAlert, isNull);
    });
  });
}
