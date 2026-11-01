import 'package:flutter/material.dart';

import '../../presentation/screens/monitor_screen.dart';

/// انتقالات الشاشات (انسيابية وبسيطة بدون حزم إضافية).
abstract final class AppRoutes {
  static const Duration duration = Duration(milliseconds: 420);

  /// الانتقال إلى لوحة الرصد.
  static Route<void> monitor() {
    return PageRouteBuilder<void>(
      transitionDuration: duration,
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (BuildContext context, Animation<double> animation,
              Animation<double> secondaryAnimation) =>
          const MonitorScreen(),
      transitionsBuilder: (BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) {
        final Animation<double> curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.05),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /// فتح لوحة الرصد من أي مكان.
  static Future<void> openMonitor(BuildContext context) {
    return Navigator.of(context).push(monitor());
  }

  /// رجوع آمن.
  static void pop(BuildContext context) {
    final NavigatorState navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }
}
