import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/app.dart';
import 'package:ruview_wifi/data/repositories/sensing_repository.dart';
import 'package:ruview_wifi/data/services/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
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

  testWidgets('لوحة التحكم تعرض النصوص العربية وإعدادات الاتصال', (WidgetTester tester) async {
    await pumpApp(tester);

    expect(find.text('RuView Wi-Fi'), findsOneWidget);
    expect(find.text('إعدادات الاتصال'), findsOneWidget);
    expect(find.text('عنوان IP للخادم'), findsOneWidget);
    expect(find.text('المنفذ'), findsOneWidget);
    expect(find.text('ملخص سريع'), findsOneWidget);
    expect(find.text('وضع الحراسة الأمنية'), findsOneWidget);
    expect(find.text('اتصال (997)'), findsOneWidget);
    expect(find.text('العقد النشطة'), findsOneWidget);
    expect(find.text('جودة الإشارة'), findsOneWidget);
    expect(find.text('الانتقال إلى لوحة الرصد'), findsOneWidget);
    expect(find.text('اتصال'), findsWidgets);

    // اتجاه RTL مفروض على الشاشة.
    final BuildContext context = tester.element(find.byType(Scaffold).first);
    expect(Directionality.of(context), TextDirection.rtl);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('التحقق من صحة العنوان يمنع الاتصال ويعرض الخطأ', (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.enterText(find.byType(TextFormField).first, '');
    await tester.pump();

    await tester.tap(find.text('اتصال').last);
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('أدخل عنوان IP أو اسم مضيف صالحًا'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('الانتقال إلى لوحة الرصد يعرض الرادار والعلامات الحيوية', (WidgetTester tester) async {
    await pumpApp(tester);

    final Finder cta = find.text('الانتقال إلى لوحة الرصد');
    await tester.ensureVisible(cta);
    await tester.pump();
    await tester.tap(cta);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('لوحة الرصد'), findsWidgets);
    expect(find.text('رادار الحضور المكاني'), findsOneWidget);
    expect(find.text('العلامات الحيوية'), findsOneWidget);
    expect(find.text('سجل الأنشطة والتنبيهات'), findsOneWidget);
    expect(find.text('الحالة الحالية'), findsOneWidget);
    expect(find.text('النوم والعلامات الحيوية'), findsOneWidget);
    expect(find.text('معدل التنفس'), findsWidgets);
    expect(find.text('شدة الحركة'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
