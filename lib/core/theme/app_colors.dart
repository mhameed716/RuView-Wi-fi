import 'package:flutter/material.dart';

/// لوحة ألوان RuView Wi-Fi — وضع داكن افتراضي مع لمسات نيون عالية التباين.
///
/// الألوان مقصودة لتطابق هوية لوحة RuView الرسمية (خلفية داكنة + سماوي/زمردي)
/// مع تحسين التباين لشاشات الهواتف في ظروف إضاءة مختلفة.
abstract final class AppColors {
  // الخلفيات
  static const Color background = Color(0xFF05070D);
  static const Color backgroundElevated = Color(0xFF0A1018);
  static const Color surface = Color(0xFF101827);
  static const Color surfaceHigh = Color(0xFF16223A);
  static const Color border = Color(0xFF1E2B3D);

  // لمسات النيون
  static const Color cyan = Color(0xFF00E5FF);
  static const Color cyanDim = Color(0xFF00A8BF);
  static const Color emerald = Color(0xFF00F5A0);
  static const Color emeraldDim = Color(0xFF00A86E);

  // الحالات
  static const Color danger = Color(0xFFFF4D6D);
  static const Color warning = Color(0xFFFFB347);
  static const Color idle = Color(0xFF6B7C93);

  // النصوص
  static const Color textPrimary = Color(0xFFEAF2F9);
  static const Color textSecondary = Color(0xFF93A7BC);
  static const Color textMuted = Color(0xFF5F7288);

  /// تدرّج زر الاتصال الرئيسي.
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[cyan, emerald],
  );

  /// تدرّج خلفية الشاشة (هالة علوية خفيفة).
  static const LinearGradient screenGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0xFF08131F), background],
    stops: <double>[0.0, 0.55],
  );

  static Color statusColor(StatusTone tone) => switch (tone) {
        StatusTone.ok => emerald,
        StatusTone.active => cyan,
        StatusTone.warning => warning,
        StatusTone.danger => danger,
        StatusTone.idle => idle,
      };
}

/// نغمة دلالية تُستخدم لتلوين المؤشرات والشرائح.
enum StatusTone { ok, active, warning, danger, idle }
