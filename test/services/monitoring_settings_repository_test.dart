import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/models/gait_profile.dart';
import 'package:ruview_wifi/data/services/alert_dispatcher.dart';
import 'package:ruview_wifi/data/services/emergency_dialer.dart';
import 'package:ruview_wifi/data/services/monitoring_settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const GaitFeatureVector sampleVector = GaitFeatureVector(
  motionMean: 0.52,
  motionStd: 0.11,
  dominantHz: 1.7,
  changeRate: 0.08,
  variance: 2.1,
  samples: 20,
);

GaitProfile sampleProfile({String id = 'gait_1', String name = 'أحمد'}) {
  return GaitProfile(
    id: id,
    name: name,
    vector: sampleVector,
    enrolledAt: DateTime(2026, 1, 1, 20),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MonitoringSettingsRepository', () {
    test('يفعّل وضع الحراسة ويحفظه ويقرأه', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final MonitoringSettingsRepository repository =
          MonitoringSettingsRepository();

      expect(await repository.loadIntrusionArmed(), isFalse);
      expect(await repository.saveIntrusionArmed(true), isTrue);

      // نسخة جديدة تقرأ من التخزين الفعلي (Mock) نفسه.
      final MonitoringSettingsRepository reopened =
          MonitoringSettingsRepository();
      expect(await reopened.loadIntrusionArmed(), isTrue);
    });

    test('يستخدم رقم الطوارئ الافتراضي ثم يحفظ الرقم الجديد', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final MonitoringSettingsRepository repository =
          MonitoringSettingsRepository();

      expect(
        await repository.loadEmergencyNumber(),
        MonitoringSettingsRepository.defaultEmergencyNumber,
      );

      expect(await repository.saveEmergencyNumber('+966 500 000 000'), isTrue);
      expect(await repository.loadEmergencyNumber(), '+966500000000');

      expect(await repository.saveEmergencyNumber('abc'), isFalse);
    });

    test('يحفظ بصمات المشية ويعيد قراءتها', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final MonitoringSettingsRepository repository =
          MonitoringSettingsRepository();

      expect(await repository.loadGaitProfiles(), isEmpty);
      expect(
        await repository.saveGaitProfiles(<GaitProfile>[sampleProfile()]),
        isTrue,
      );

      final List<GaitProfile> loaded =
          await MonitoringSettingsRepository().loadGaitProfiles();
      expect(loaded, hasLength(1));
      expect(loaded.single.name, 'أحمد');
      expect(loaded.single.vector.dominantHz, closeTo(1.7, 1e-9));
      expect(
        loaded.single.enrolledAt,
        DateTime(2026, 1, 1, 20),
      );
    });

    test('يتعامل مع بيانات بصمات تالفة دون استثناء', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        MonitoringSettingsRepository.gaitProfilesKey: 'not-json',
      });

      expect(
        await MonitoringSettingsRepository().loadGaitProfiles(),
        isEmpty,
      );
    });
  });

  group('EmergencyDialer', () {
    test('ينظّف الأرقام من الرموز ويقبل علامة + واحدة', () {
      expect(EmergencyDialer.sanitize('997'), '997');
      expect(EmergencyDialer.sanitize('+966 50 000 0000'), '+966500000000');
      expect(EmergencyDialer.sanitize('+9+9+7'), '+997');
      expect(EmergencyDialer.sanitize('abc'), '');
    });

    test('يعيد رقمًا غير صالح عند تمرير نص بلا أرقام', () async {
      final EmergencyDialer dialer = EmergencyDialer();
      expect(await dialer.dial('لا يوجد رقم'), DialOutcome.invalidNumber);
    });
  });

  group('AlertDispatcher', () {
    test('لا يرمي استثناء عند غياب القنوات الأصلية', () async {
      final AlertDispatcher dispatcher = AlertDispatcher();
      await dispatcher.requestPermission();
      await dispatcher.notify(
        title: 'اختبار',
        body: 'تنبيه اختباري',
        severity: AlertSeverity.critical,
      );
    });
  });
}
