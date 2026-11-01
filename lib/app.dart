import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/l10n/ar_strings.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/sensing_repository.dart';
import 'data/services/settings_repository.dart';
import 'presentation/app_scope.dart';
import 'presentation/screens/dashboard_screen.dart';
import 'presentation/viewmodels/connection_view_model.dart';
import 'presentation/viewmodels/sensing_view_model.dart';

/// جذر التطبيق: ينشئ طبقة البيانات والـ ViewModels ويمرّرها عبر [AppScope].
class RuViewApp extends StatefulWidget {
  const RuViewApp({super.key, this.settingsRepository, this.sensingRepository});

  /// حقن بدائل للاختبار.
  final SettingsRepository? settingsRepository;
  final SensingRepository? sensingRepository;

  @override
  State<RuViewApp> createState() => _RuViewAppState();
}

class _RuViewAppState extends State<RuViewApp> {
  late final SettingsRepository _settingsRepository;
  late final SensingRepository _sensingRepository;
  late final ConnectionViewModel _connectionViewModel;
  late final SensingViewModel _sensingViewModel;

  @override
  void initState() {
    super.initState();
    _settingsRepository = widget.settingsRepository ?? SettingsRepository();
    _sensingRepository = widget.sensingRepository ?? SensingRepository();
    _connectionViewModel = ConnectionViewModel(
      repository: _sensingRepository,
      settingsRepository: _settingsRepository,
    );
    _sensingViewModel = SensingViewModel(repository: _sensingRepository);
    unawaited(_connectionViewModel.initialize());
  }

  @override
  void dispose() {
    _connectionViewModel.dispose();
    _sensingViewModel.dispose();
    unawaited(_sensingRepository.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      connectionViewModel: _connectionViewModel,
      sensingViewModel: _sensingViewModel,
      sensingRepository: _sensingRepository,
      settingsRepository: _settingsRepository,
      child: MaterialApp(
        title: ArStrings.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        locale: const Locale('ar'),
        supportedLocales: const <Locale>[Locale('ar')],
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // ضمان اتجاه RTL بالكامل حتى خارج نطاق الترجمة.
        builder: (BuildContext context, Widget? child) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const DashboardScreen(),
      ),
    );
  }
}
