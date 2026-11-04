import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/models/posture.dart';
import 'package:ruview_wifi/data/models/sleep_summary.dart';
import 'package:ruview_wifi/domain/monitoring/sleep_monitor.dart';

void main() {
  group('SleepMonitor', () {
    final DateTime t0 = DateTime(2026, 1, 1, 22, 30);

    SleepSummary feed(
      SleepMonitor monitor, {
      required DateTime from,
      required Duration until,
      double breathing = 15,
      double motion = 0.05,
      bool presence = true,
    }) {
      SleepSummary summary = const SleepSummary();
      for (int second = 0; second <= until.inSeconds; second++) {
        summary = monitor.ingest(
          hasPresence: presence,
          posture: PostureKind.lying,
          breathingRate: breathing,
          motionIntensity: motion,
          now: from.add(Duration(seconds: second)),
        );
      }
      return summary;
    }

    test('لا يبدأ جلسة بلا وجود أو استلقاء', () {
      final SleepMonitor monitor = SleepMonitor();

      final SleepSummary summary = monitor.ingest(
        hasPresence: false,
        posture: PostureKind.standing,
        breathingRate: null,
        motionIntensity: 0.4,
        now: t0,
      );

      expect(summary.state, SleepState.absent);
      expect(summary.isMonitoring, isFalse);
      expect(summary.qualityScore, 0);
    });

    test('يستنتج نومًا عميقًا عند تنفس منتظم وسكون', () {
      final SleepMonitor monitor = SleepMonitor();

      SleepSummary summary = const SleepSummary();
      for (int second = 0; second <= 90; second++) {
        // تنفس منتظم مع تذبذب طفيف (نفس الشهيق/الزفير).
        final double breathing = second.isEven ? 15.0 : 15.4;
        summary = monitor.ingest(
          hasPresence: true,
          posture: PostureKind.lying,
          breathingRate: breathing,
          motionIntensity: 0.05,
          now: t0.add(Duration(seconds: second)),
        );
      }

      expect(summary.state, SleepState.deep);
      expect(summary.isMonitoring, isTrue);
      expect(summary.averageBreathing, closeTo(15.2, 0.2));
      expect(summary.breathingVariability, lessThan(1.2));
      expect(summary.apneaEvents, 0);
      expect(summary.qualityScore, greaterThan(70));
      expect(summary.session.inSeconds, greaterThanOrEqualTo(60));
    });

    test('يرصد اضطراب التنفس عند غياب الإشارة أكثر من 25 ثانية', () {
      final SleepMonitor monitor = SleepMonitor();

      // تنفس لمدة 10 ثوانٍ.
      feed(monitor, from: t0, until: const Duration(seconds: 10));
      // ثم انقطاع كامل مع بقاء الشخص مستلقيًا وساكنًا.
      SleepSummary summary = const SleepSummary();
      for (int second = 11; second <= 45; second++) {
        summary = monitor.ingest(
          hasPresence: true,
          posture: PostureKind.lying,
          breathingRate: null,
          motionIntensity: 0.03,
          now: t0.add(Duration(seconds: second)),
        );
      }

      expect(summary.apneaEvents, greaterThanOrEqualTo(1));
      expect(summary.state, SleepState.disturbed);
      expect(summary.qualityScore, lessThan(90));
    });

    test('يعتبر الحركة الملحوظة استيقاظًا', () {
      final SleepMonitor monitor = SleepMonitor();

      final SleepSummary summary = monitor.ingest(
        hasPresence: true,
        posture: PostureKind.lying,
        breathingRate: 16,
        motionIntensity: 0.6,
        now: t0,
      );

      expect(summary.state, SleepState.awake);
    });

    test('reset يعيد الحالة إلى البداية', () {
      final SleepMonitor monitor = SleepMonitor();

      feed(monitor, from: t0, until: const Duration(seconds: 20));
      expect(monitor.apneaEvents, 0);

      monitor.reset();
      final SleepSummary summary = monitor.ingest(
        hasPresence: true,
        posture: PostureKind.lying,
        breathingRate: 15,
        motionIntensity: 0.05,
        now: t0.add(const Duration(minutes: 5)),
      );

      expect(summary.samples, 1);
      expect(summary.apneaEvents, 0);
      expect(summary.state, SleepState.light);
    });
  });
}
