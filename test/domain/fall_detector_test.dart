import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/models/posture.dart';
import 'package:ruview_wifi/domain/monitoring/fall_detector.dart';
import 'package:ruview_wifi/domain/monitoring/safety_state.dart';

void main() {
  group('FallDetector', () {
    final DateTime t0 = DateTime(2026, 1, 1, 22, 30);

    test('بلاغ الخادم يرفع تنبيهًا فوريًا بأعلى ثقة', () {
      final FallDetector detector = FallDetector();

      final FallAlert? alert = detector.evaluate(
        posture: PostureKind.unknown,
        motionIntensity: 0,
        now: t0,
        serverReportedFall: true,
      );

      expect(alert, isNotNull);
      expect(alert!.confidence, 0.95);
      expect(alert.posture, PostureKind.fallen);
      expect(alert.reason, contains('RuView'));
      expect(detector.lastAlert, same(alert));
    });

    test('انتقال سريع من الوقوف إلى الاستلقاء مع حركة عنيفة يُكتشف', () {
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
        motionIntensity: 0.8,
        now: t0.add(const Duration(milliseconds: 900)),
      );

      expect(alert, isNotNull);
      expect(alert!.posture, PostureKind.lying);
      expect(alert.confidence, greaterThan(0.55));
      expect(alert.confidence, lessThanOrEqualTo(1.0));
      expect(alert.reason, contains('واقف'));
    });

    test('الانتقال البطيء (أطول من النافذة) ليس سقوطًا', () {
      final FallDetector detector = FallDetector();

      detector.evaluate(
        posture: PostureKind.standing,
        motionIntensity: 0.2,
        now: t0,
      );

      expect(
        detector.evaluate(
          posture: PostureKind.lying,
          motionIntensity: 0.95,
          now: t0.add(const Duration(seconds: 3)),
        ),
        isNull,
      );
    });

    test('الحركة الضعيفة تُلغي الكشف', () {
      final FallDetector detector = FallDetector();

      detector.evaluate(
        posture: PostureKind.walking,
        motionIntensity: 0.6,
        now: t0,
      );

      expect(
        detector.evaluate(
          posture: PostureKind.fallen,
          motionIntensity: 0.3,
          now: t0.add(const Duration(seconds: 1)),
        ),
        isNull,
      );
    });

    test('الجلوس ثم الاستلقاء يتطلب حركة أعنف من الانتقال من الوقوف', () {
      final FallDetector detector = FallDetector();

      detector.evaluate(
        posture: PostureKind.sitting,
        motionIntensity: 0.1,
        now: t0,
      );

      // 0.6 يتجاوز العتبة العامة (0.55) لكنه أقل من عتبة الجلوس (0.75).
      expect(
        detector.evaluate(
          posture: PostureKind.lying,
          motionIntensity: 0.6,
          now: t0.add(const Duration(seconds: 1)),
        ),
        isNull,
      );

      final FallAlert? alert = detector.evaluate(
        posture: PostureKind.lying,
        motionIntensity: 0.8,
        now: t0.add(const Duration(seconds: 2)),
      );

      expect(alert, isNotNull);
      expect(alert!.reason, contains('حركة عنيفة'));
    });

    test('التهدئة تمنع تكرار التنبيه لنفس الحادثة', () {
      final FallDetector detector = FallDetector();

      detector.evaluate(
        posture: PostureKind.standing,
        motionIntensity: 0.3,
        now: t0,
      );

      final FallAlert? first = detector.evaluate(
        posture: PostureKind.lying,
        motionIntensity: 0.9,
        now: t0.add(const Duration(seconds: 1)),
      );
      expect(first, isNotNull);

      detector.evaluate(
        posture: PostureKind.standing,
        motionIntensity: 0.3,
        now: t0.add(const Duration(seconds: 2)),
      );

      // داخل نافذة التهدئة (15 ثانية).
      expect(
        detector.evaluate(
          posture: PostureKind.lying,
          motionIntensity: 0.9,
          now: t0.add(const Duration(seconds: 3)),
        ),
        isNull,
      );

      // بعد انتهاء التهدئة يُسمح بتنبيه جديد.
      detector.evaluate(
        posture: PostureKind.standing,
        motionIntensity: 0.3,
        now: t0.add(const Duration(seconds: 17)),
      );

      final FallAlert? second = detector.evaluate(
        posture: PostureKind.lying,
        motionIntensity: 0.9,
        now: t0.add(const Duration(seconds: 18)),
      );

      expect(second, isNotNull);
      expect(second!.detectedAt, t0.add(const Duration(seconds: 18)));
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
