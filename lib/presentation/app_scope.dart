import 'package:flutter/widgets.dart';

import '../data/repositories/sensing_repository.dart';
import '../data/services/settings_repository.dart';
import 'viewmodels/connection_view_model.dart';
import 'viewmodels/sensing_view_model.dart';

/// حاوية اعتماديات بسيطة (بدون مكتبات إدارة حالة خارجية).
///
/// توفّر الـ ViewModels والمستودعات لشجرة الواجهات، وتبقى ملكية دورة الحياة
/// في `RuViewApp` (يُنشئها ويحرّرها).
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.connectionViewModel,
    required this.sensingViewModel,
    required this.sensingRepository,
    required this.settingsRepository,
    required super.child,
  });

  final ConnectionViewModel connectionViewModel;
  final SensingViewModel sensingViewModel;
  final SensingRepository sensingRepository;
  final SettingsRepository settingsRepository;

  static AppScope of(BuildContext context) {
    final AppScope? scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope غير موجود في شجرة الواجهات');
    return scope!;
  }

  @override
  bool updateShouldNotify(covariant AppScope oldWidget) {
    return oldWidget.connectionViewModel != connectionViewModel ||
        oldWidget.sensingViewModel != sensingViewModel;
  }
}
