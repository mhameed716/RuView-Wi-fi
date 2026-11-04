import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/app.dart';
import 'package:ruview_wifi/data/repositories/sensing_repository.dart';
import 'package:ruview_wifi/data/services/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// تدفّق «الوضع التجريبي»: من زر في الواجهة إلى بيانات حقيقية تمرّ عبر
/// النقل ← المستودع ← ViewModels ← الشاشة، مع إعلان صريح أنها محاكاة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4200);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      RuViewApp(
        settingsRepository: SettingsRepository(),
        sensingRepository: SensingRepository(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// إيقاف المحاكاة قبل إغلاق الشجرة حتى لا يبقى مؤقّت دوري معلّق.
  Future<void> stopSimulator(WidgetTester tester) async {
    final Finder stop = find.text('إيقاف المحاكاة');
    if (stop.evaluate().isEmpty) return;
    await tester.ensureVisible(stop.first);
    await tester.pump();
    await tester.tap(stop.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('زر الوضع التجريبي يملأ الواجهة ويعلن أنها محاكاة',
      (WidgetTester tester) async {
    await pumpApp(tester);

    final Finder start = find.text('تشغيل الوضع التجريبي (محاكاة)');
    expect(start, findsWidgets);

    await tester.ensureVisible(start.first);
    await tester.pump();
    await tester.tap(start.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // الإعلان الصريح عن المحاكاة ظاهر.
    expect(find.text('محاكاة نشطة'), findsWidgets);

    // بيانات فعلية وصلت: الحضور ظاهر في الملخص.
    expect(find.text('شخص مرصود'), findsWidgets);

    await stopSimulator(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('لوحة الرصد تعرض بيانات المحاكاة مع شريط تحذيري',
      (WidgetTester tester) async {
    await pumpApp(tester);

    final Finder start = find.text('تشغيل الوضع التجريبي (محاكاة)');
    await tester.ensureVisible(start.first);
    await tester.pump();
    await tester.tap(start.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final Finder cta = find.text('الانتقال إلى لوحة الرصد');
    await tester.ensureVisible(cta);
    await tester.pump();
    await tester.tap(cta);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('رادار الحضور المكاني'), findsOneWidget);
    expect(
      find.text('البيانات المعروضة مولّدة داخل التطبيق وليست استشعارًا حقيقيًا.'),
      findsWidgets,
    );

    await stopSimulator(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
