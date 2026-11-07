import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/services/body_profile_repository.dart';
import 'package:ruview_wifi/data/services/lan_scanner.dart';
import 'package:ruview_wifi/data/services/network_preferences_repository.dart';
import 'package:ruview_wifi/domain/twin/body_profile.dart';
import 'package:ruview_wifi/domain/twin/body_shape.dart';
import 'package:shared_preferences/shared_preferences.dart';

BodyProfile profileFor(String label, double height) {
  final BodyShape shape = BodyShape.average.copyWith(heightM: height);
  return BodyProfile(
    id: 'body-$label',
    label: label,
    shape: shape,
    signature: BodySignature.fromShape(shape, gaitVector: const <double>[1, 2, 3]),
    enrolledAt: DateTime(2026, 3, 1),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('BodyProfileRepository', () {
    test('حفظ واسترجاع التوائم', () async {
      final BodyProfileRepository repository = BodyProfileRepository();
      expect(await repository.load(), isEmpty);

      final BodyProfile profile = profileFor('أحمد', 1.79);
      expect(await repository.save(<BodyProfile>[profile]), isTrue);

      final List<BodyProfile> loaded = await BodyProfileRepository().load();
      expect(loaded.length, 1);
      expect(loaded.single.label, 'أحمد');
      expect(loaded.single.shape.heightM, closeTo(1.79, 1e-9));
      expect(loaded.single.signature.gaitVector.length, 3);
    });

    test('بيانات تالفة تعيد قائمة فارغة بلا استثناء', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        BodyProfileRepository.storageKey: 'ليست مصفوفة صالحة',
      });

      expect(await BodyProfileRepository().load(), isEmpty);
    });
  });

  group('NetworkPreferencesRepository', () {
    test('الاتصال التلقائي مُفعّل افتراضيًا ويُحفظ تغييره', () async {
      final NetworkPreferencesRepository repository =
          NetworkPreferencesRepository();
      expect(await repository.loadAutoConnect(), isTrue);

      expect(await repository.saveAutoConnect(false), isTrue);
      expect(
        await NetworkPreferencesRepository().loadAutoConnect(),
        isFalse,
      );
    });

    test('حفظ آخر نقطة اتصال ناجحة واسترجاعها', () async {
      final NetworkPreferencesRepository repository =
          NetworkPreferencesRepository();
      expect(await repository.loadLastEndpoint(), isNull);

      const LanCandidate candidate = LanCandidate(
        host: '192.168.8.1',
        port: 8765,
        latencyMs: 14,
        looksLikeRuView: true,
      );
      expect(await repository.saveLastEndpoint(candidate), isTrue);

      final LanCandidate? restored =
          await NetworkPreferencesRepository().loadLastEndpoint();
      expect(restored, isNotNull);
      expect(restored!.host, '192.168.8.1');
      expect(restored.port, 8765);
    });
  });
}
