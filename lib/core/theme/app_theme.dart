import 'package:flutter/material.dart';

import 'app_colors.dart';

/// ثيم التطبيق: داكن افتراضيًا + زوايا دائرية + تباين عالٍ.
abstract final class AppTheme {
  /// عائلة الخط الافتراضية. عند إضافة خط عربي مخصص (Cairo/Tajawal) في
  /// `pubspec.yaml` استبدل القيمة بـ 'Cairo'.
  static const String fontFamily = 'Roboto';

  static const List<String> fontFallback = <String>[
    'Noto Naskh Arabic',
    'Noto Sans Arabic',
    'Droid Arabic Naskh',
    'Tajawal',
    'Cairo',
    'Roboto',
  ];

  static const double radiusSmall = 12;
  static const double radiusMedium = 18;
  static const double radiusLarge = 26;

  /// زخرفة موحّدة لحقول الإدخال (بدل الاعتماد على `ThemeData.inputDecorationTheme`
  /// لتوافق أوسع مع إصدارات Flutter المختلفة).
  static InputDecoration inputDecoration({
    required String labelText,
    String? hintText,
    IconData? prefixIcon,
    String? errorText,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSmall),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      errorText: errorText,
      filled: true,
      fillColor: AppColors.backgroundElevated,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
      labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      floatingLabelStyle: const TextStyle(color: AppColors.cyan, fontSize: 13),
      prefixIcon: prefixIcon == null
          ? null
          : Icon(prefixIcon, size: 19, color: AppColors.textMuted),
      errorStyle: const TextStyle(color: AppColors.danger, fontSize: 11),
      enabledBorder: border(AppColors.border),
      focusedBorder: border(AppColors.cyan, 1.6),
      errorBorder: border(AppColors.danger),
      focusedErrorBorder: border(AppColors.danger, 1.6),
    );
  }

  static ThemeData dark() {
    const ColorScheme scheme = ColorScheme.dark(
      primary: AppColors.cyan,
      onPrimary: Color(0xFF00131A),
      secondary: AppColors.emerald,
      onSecondary: Color(0xFF00130C),
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
      onError: Colors.white,
    );

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 22),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.cyan,
        linearTrackColor: AppColors.border,
      ),
    );
  }
}
