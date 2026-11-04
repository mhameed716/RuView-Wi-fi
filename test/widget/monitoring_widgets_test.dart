import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/core/theme/app_theme.dart';
import 'package:ruview_wifi/data/models/gait_profile.dart';
import 'package:ruview_wifi/data/models/posture.dart';
import 'package:ruview_wifi/data/models/sensing_frame.dart';
import 'package:ruview_wifi/data/models/sleep_summary.dart';
import 'package:ruview_wifi/domain/monitoring/safety_state.dart';
import 'package:ruview_wifi/presentation/widgets/emergency_banner.dart';
import 'package:ruview_wifi/presentation/widgets/posture_status_card.dart';
import 'package:ruview_wifi/presentation/widgets/security_mode_card.dart';
import 'package:ruview_wifi/presentation/widgets/sleep_vitals_panel.dart';

/// غلاف اختبار: RTL + الثيم الداكن + مساحة كافية للبطاقات الطويلة.
Future<void> pumpCard(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1100, 2600);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PostureStatusCard', () {
    testWidgets('يعرض الوضعية الحالية وملاحظة غياب المفاصل', (WidgetTester tester) async {
      await pumpCard(
        tester,
        PostureStatusCard(
          posture: PostureKind.sitting,
          source: PostureSource.server,
          confidence: 0.82,
          keypoints: const <PoseKeypoint>[],
          hasSkeleton: false,
          hasData: true,
          gaitMatch: null,
          gaitProfiles: const <GaitProfile>[],
          gaitCollecting: false,
          onEnroll: () {},
        ),
      );

      expect(find.text('الحالة الحالية'), findsOneWidget);
      expect(find.text('الحالة الحالية:'), findsOneWidget);
      expect(find.text('جالس'), findsWidgets);
      expect(find.textContaining('المصدر: الخادم'), findsOneWidget);
      expect(find.textContaining('لا يرسل الخادم نقاط المفاصل'), findsOneWidget);
      expect(find.text('بصمة المشية'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('يعرض بصمات المشية ونتيجة التعرّف', (WidgetTester tester) async {
      final GaitProfile profile = GaitProfile(
        id: 'gait_1',
        name: 'سارة',
        vector: const GaitFeatureVector(
          motionMean: 0.5,
          motionStd: 0.1,
          dominantHz: 1.6,
          changeRate: 0.08,
          variance: 2,
          samples: 20,
        ),
        enrolledAt: DateTime(2026, 1, 1),
      );

      await pumpCard(
        tester,
        PostureStatusCard(
          posture: PostureKind.walking,
          source: PostureSource.keypoints,
          confidence: 0.55,
          keypoints: const <PoseKeypoint>[],
          hasSkeleton: false,
          hasData: true,
          gaitMatch: GaitMatch(
            profile: profile,
            similarity: 0.91,
            matchedAt: DateTime(2026, 1, 1),
          ),
          gaitProfiles: <GaitProfile>[profile],
          gaitCollecting: true,
          onEnroll: () {},
          onRemoveProfile: (GaitProfile _) {},
        ),
      );

      expect(find.text('يمشي'), findsWidgets);
      expect(find.text('تم التعرّف: سارة'), findsOneWidget);
      expect(find.text('91%'), findsOneWidget);
      expect(find.text('سارة'), findsOneWidget);
      expect(find.text('تسجيل بصمة مشية الآن'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('SleepVitalsPanel', () {
    testWidgets('يعرض معدل التنفس وتصنيفه واضطرابات التنفس',
        (WidgetTester tester) async {
      await pumpCard(
        tester,
        SleepVitalsPanel(
          summary: const SleepSummary(
            state: SleepState.deep,
            session: Duration(minutes: 42),
            averageBreathing: 16,
            breathingVariability: 0.4,
            apneaEvents: 2,
            qualityScore: 78,
            isMonitoring: true,
            samples: 120,
          ),
          breathingHistory: const <double>[15, 16, 16.5, 16, 15.8],
          hasData: true,
        ),
      );

      expect(find.text('النوم والعلامات الحيوية'), findsOneWidget);
      expect(find.text('معدل التنفس'), findsWidgets);
      expect(find.text('16.0 مرة/دقيقة'), findsOneWidget);
      expect(find.text('طبيعي'), findsOneWidget);
      expect(find.text('اضطرابات التنفس'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('78'), findsOneWidget);
      expect(find.textContaining('اضطراب تنفس'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('SecurityModeCard', () {
    testWidgets('يبدّل وضع الحراسة ويعرض رقم الطوارئ', (WidgetTester tester) async {
      bool armed = false;
      await pumpCard(
        tester,
        SecurityModeCard(
          armed: false,
          lastIntrusionAt: null,
          incidentCount: 0,
          emergencyNumber: '997',
          onArmedChanged: (bool value) => armed = value,
          onEditNumber: () {},
          onCallEmergency: () {},
        ),
      );

      expect(find.text('وضع الحراسة الأمنية'), findsOneWidget);
      expect(find.text('اتصال (997)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('security-toggle')));
      await tester.pump();
      expect(armed, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('يعرض شريط التسلل عند وجود تنبيه', (WidgetTester tester) async {
      await pumpCard(
        tester,
        SecurityModeCard(
          armed: true,
          lastIntrusionAt: DateTime(2026, 1, 1, 23),
          incidentCount: 3,
          emergencyNumber: '997',
          intrusionAlert: IntrusionAlert(
            detectedAt: DateTime(2026, 1, 1, 23),
            motionIntensity: 0.72,
            confidence: 0.88,
            zone: 'zone_1',
          ),
          onDismissAlert: () {},
          onArmedChanged: (bool _) {},
          onEditNumber: () {},
          onCallEmergency: () {},
        ),
      );

      expect(find.textContaining('حركة مرصودة في وضع الحراسة'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('EmergencyBanner', () {
    testWidgets('يعرض نص الطوارئ ويستدعي الإجراءين', (WidgetTester tester) async {
      bool dismissed = false;
      bool called = false;

      await pumpCard(
        tester,
        EmergencyBanner(
          alert: FallAlert(
            detectedAt: DateTime(2026, 1, 1, 20),
            confidence: 0.92,
            posture: PostureKind.fallen,
            reason: 'انتقال سريع من واقف إلى سقوط',
          ),
          emergencyNumber: '997',
          onDismiss: () => dismissed = true,
          onCall: () => called = true,
        ),
      );

      expect(
        find.text('⚠️ تنبيه طارئ: تم رصد حالة سقوط في الغرفة!'),
        findsOneWidget,
      );
      expect(find.text('اتصال بالطوارئ (997)'), findsOneWidget);

      await tester.tap(find.text('إلغاء الإنذار'));
      await tester.pump();
      expect(dismissed, isTrue);

      await tester.tap(find.text('اتصال بالطوارئ (997)'));
      await tester.pump();
      expect(called, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
