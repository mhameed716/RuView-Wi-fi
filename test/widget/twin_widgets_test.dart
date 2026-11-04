import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/core/theme/app_theme.dart';
import 'package:ruview_wifi/data/repositories/sensing_repository.dart';
import 'package:ruview_wifi/data/services/settings_repository.dart';
import 'package:ruview_wifi/domain/twin/body_profile.dart';
import 'package:ruview_wifi/domain/twin/room_model.dart';
import 'package:ruview_wifi/domain/twin/twin_state.dart';
import 'package:ruview_wifi/presentation/viewmodels/connection_view_model.dart';
import 'package:ruview_wifi/presentation/widgets/auto_connect_card.dart';
import 'package:ruview_wifi/presentation/widgets/rf_twin_card.dart';
import 'package:ruview_wifi/presentation/widgets/room_reconstruction_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpCard(WidgetTester tester, Widget card) async {
    tester.view.physicalSize = const Size(1200, 3200);
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
              child: card,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('بطاقة التوأم الراديوي تعرض المجسّم والقياسات', (WidgetTester tester) async {
    await pumpCard(
      tester,
      RfTwinCard(
        twin: TwinState.empty,
        identityLabel: 'هوية غير مسجّلة',
        profiles: const <BodyProfile>[],
        onEnroll: () {},
        onRemoveProfile: (String id) {},
      ),
    );

    expect(find.text(RfTwinCard.title), findsOneWidget);
    expect(find.text('القياسات الجسدية'), findsOneWidget);
    expect(find.text('الطول'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('twin-enroll-button')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('لوحة الغرفة تعرض عنوانها وزر إعادة المسح', (WidgetTester tester) async {
    await pumpCard(
      tester,
      RoomReconstructionPanel(
        room: RoomModel.empty,
        onRescan: () {},
      ),
    );

    expect(find.text(RoomReconstructionPanel.title), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('room-rescan-button')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('بطاقة الاتصال التلقائي تعرض الشبكة والمرشّحين', (WidgetTester tester) async {
    final SensingRepository sensing = SensingRepository();
    final ConnectionViewModel viewModel = ConnectionViewModel(
      repository: sensing,
      settingsRepository: SettingsRepository(),
      enableAutoDiscovery: false,
    );
    addTearDown(() {
      viewModel.dispose();
      unawaited(sensing.dispose());
    });

    await viewModel.initialize();
    await pumpCard(tester, AutoConnectCard(viewModel: viewModel));

    expect(find.text(AutoConnectCard.title), findsOneWidget);
    expect(find.text('الشبكة الحالية'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('auto-connect-toggle')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('rescan-button')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
