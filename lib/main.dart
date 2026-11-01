import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';

/// نقطة الدخول: تثبيت الاتجاه الرأسي، وتنسيق شريط الحالة مع الوضع الداكن.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFF05070D),
      systemNavigationBarDividerColor: Color(0xFF05070D),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const RuViewApp());
}
