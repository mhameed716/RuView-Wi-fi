import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/models/gait_profile.dart';
import 'package:ruview_wifi/data/models/posture.dart';
import 'package:ruview_wifi/data/models/sensing_frame.dart';
import 'package:ruview_wifi/domain/monitoring/safety_monitor.dart';
import 'package:ruview_wifi/domain/monitoring/safety_state.dart';

SensingFrame frame({
  String? posture,
  bool presence = true,
  String motionLevel = 'present_moving',
  double motionPower = 0.5,
  double dominantHz = 1.6,
  double? breathing,
  DateTime? at,
}) {
  return SensingFrame.fromJson(
    <String, dynamic>{
      'type': 'sensing_update',
      'features': <String, dynamic>{
        'motion_band_power': motionPower,
        'dominant_freq_hz': dominantHz,
        'variance': 2.0,
      },
      'classification': <String, dynamic>{
        'motion_level': motionLevel,
        'presence': presence,
        'confidence': 0.88,
      },
      if (posture != null) 'posture': posture,
      if (breathing != null)
        'vital_signs': <String, dynamic>{'breathing_rate_bpm': breathing},
    },
    receivedAt: at ?? DateTime(2026, 1, 1, 12),
  );
}

void main() {
  group('SafetyMonitor', () {
    final DateTime t0 = DateTime(2026, 1, 1, 12, 0);

    test('يصدر إشارة تغيّر الوضعية ويحدّث الحالة', () {
      final SafetyMonitor monitor = SafetyMonitor();

      final List<SafetySignal> signals = monitor.ingest(
        frame(posture: 'sitting', at: t0),
        motionIntensity: 0.3,
        breathingRate: null,
        now: t0,
      );

      expect(signals.any((SafetySignal s) => s.kind == SafetySignalKind.postureChanged), isTrue);
      expect(monitor.state.posture, PostureKind.sitting);
      expect(monitor.state.postureSource, PostureSource.server);
      expect(monitor.state.postureConfidence, greaterThan(0.5));
    });

    test('يصدر تنبيه سقوط ويُلغى عند الاعتراف به', () {
      final SafetyMonitor monitor = SafetyMonitor();

      monitor.ingest(
        frame(posture: 'standing', motionLevel: 'present_still', at: t0),
        motionIntensity: 0.2,
        breathingRate: null,
        now: t0,
      );

      final DateTime fallAt = t0.add(const Duration(milliseconds: 700));
      final List<SafetySignal> signals = monitor.ingest(
        frame(posture: 'fallen', motionPower: 0.9, at: fallAt),
        motionIntensity: 0.9,
        breathingRate: null,
        now: fallAt,
      );

      final SafetySignal fall = signals.firstWhere(
        (SafetySignal s) => s.kind == SafetySignalKind.fall,
      );
      expect(fall.kind.isCritical, isTrue);
      expect(monitor.state.hasFallAlert, isTrue);

      monitor.acknowledgeFall();
      expect(monitor.state.hasFallAlert, isFalse);
    });

    test('تفعيل الحراسة يصدر إشارة ويسمح برصد التسلل', () {
      final SafetyMonitor monitor = SafetyMonitor();

      final List<SafetySignal> armed =
          monitor.setIntrusionArmed(true, now: t0);
      expect(armed.single.kind, SafetySignalKind.armed);
      expect(monitor.state.intrusionArmed, isTrue);

      final DateTime later = t0.add(const Duration(seconds: 25));
      final List<SafetySignal> signals = monitor.ingest(
        frame(at: later),
        motionIntensity: 0.6,
        breathingRate: null,
        now: later,
      );

      expect(
        signals.any((SafetySignal s) => s.kind == SafetySignalKind.intrusion),
        isTrue,
      );
      expect(monitor.state.lastIntrusionAt, isNotNull);

      monitor.acknowledgeIntrusion();
      expect(monitor.state.intrusionAlert, isNull);

      final List<SafetySignal> disarmed =
          monitor.setIntrusionArmed(false, now: later);
      expect(disarmed.single.kind, SafetySignalKind.disarmed);
    });

    test('يسجّل بصمة مشية بعد اكتمال نافذة الحركة', () {
      final SafetyMonitor monitor = SafetyMonitor();

      expect(monitor.enrollGait('أحمد', now: t0), isNull);

      for (int i = 0; i < 20; i++) {
        final DateTime at = t0.add(Duration(milliseconds: 400 * i));
        monitor.ingest(
          frame(motionPower: 0.5 + (i.isEven ? 0.08 : -0.05), at: at),
          motionIntensity: 0.6,
          breathingRate: null,
          now: at,
        );
      }

      final GaitProfile? profile = monitor.enrollGait(
        'أحمد',
        now: t0.add(const Duration(seconds: 9)),
      );

      expect(profile, isNotNull);
      expect(profile!.name, 'أحمد');
      expect(profile.vector.samples, greaterThanOrEqualTo(15));
      expect(monitor.gaitProfiles, hasLength(1));

      monitor.removeGaitProfile(profile.id);
      expect(monitor.gaitProfiles, isEmpty);
    });

    test('يتعرّف على بصمة مسجّلة بعد ثبات المطابقة', () {
      final SafetyMonitor monitor = SafetyMonitor(
        gaitEvaluationInterval: Duration.zero,
        requiredGaitStreak: 1,
      );

      for (int i = 0; i < 20; i++) {
        final DateTime at = t0.add(Duration(milliseconds: 400 * i));
        monitor.ingest(
          frame(motionPower: 0.5 + (i.isEven ? 0.08 : -0.05), at: at),
          motionIntensity: 0.6,
          breathingRate: null,
          now: at,
        );
      }
      final GaitProfile? profile =
          monitor.enrollGait('سارة', now: t0.add(const Duration(seconds: 9)));
      expect(profile, isNotNull);
      expect(monitor.gaitProfiles, hasLength(1));

      // نافذة جديدة بنفس نمط الحركة ⇒ تشابه عالٍ ومطابقة مؤكدة.
      bool recognized = false;
      final DateTime later = t0.add(const Duration(seconds: 30));
      for (int i = 0; i < 20; i++) {
        final DateTime at = later.add(Duration(milliseconds: 400 * i));
        final List<SafetySignal> signals = monitor.ingest(
          frame(motionPower: 0.5 + (i.isEven ? 0.08 : -0.05), at: at),
          motionIntensity: 0.6,
          breathingRate: null,
          now: at,
        );
        recognized = recognized ||
            signals.any(
              (SafetySignal s) => s.kind == SafetySignalKind.gaitRecognized,
            );
      }

      expect(recognized, isTrue);
      expect(monitor.state.gaitMatch?.profile.name, 'سارة');
    });

    test('يبدأ جلسة نوم عند الاستلقاء مع تنفس', () {
      final SafetyMonitor monitor = SafetyMonitor();

      for (int second = 0; second <= 5; second++) {
        final DateTime at = t0.add(Duration(seconds: second));
        monitor.ingest(
          frame(
            posture: 'lying',
            motionLevel: 'present_still',
            motionPower: 0.05,
            at: at,
          ),
          motionIntensity: 0.05,
          breathingRate: 15,
          now: at,
        );
      }

      expect(monitor.state.sleep.samples, greaterThan(0));
      expect(monitor.state.sleep.isMonitoring, isTrue);
      expect(monitor.state.sleep.state.isSleeping, isTrue);
    });
  });
}
