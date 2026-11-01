import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/emergency_dialer.dart';
import '../viewmodels/sensing_view_model.dart';
import 'neon_button.dart';

/// حوار تعديل رقم الطوارئ. يعيد الرقم الجديد أو `null` عند الإلغاء.
Future<String?> showEmergencyNumberDialog(
  BuildContext context,
  String current,
) {
  final TextEditingController controller =
      TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Row(
          children: <Widget>[
            Icon(Icons.call_rounded, size: 18, color: AppColors.cyan),
            SizedBox(width: 8),
            Text(
              'رقم الطوارئ',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'الرقم الافتراضي 997 (الهلال الأحمر السعودي). يمكنك تغييره إلى '
              'رقم محلي آخر مثل 999 أو 911.',
              style: TextStyle(
                fontSize: 11,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: AppTheme.inputDecoration(
                labelText: 'رقم الطوارئ',
                hintText: '997',
                prefixIcon: Icons.dialpad_rounded,
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        actions: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: NeonButton(
                  label: 'إلغاء',
                  height: 42,
                  variant: NeonButtonVariant.outlined,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: NeonButton(
                  label: 'حفظ',
                  height: 42,
                  icon: Icons.check_rounded,
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(controller.text.trim()),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}

/// حوار تسجيل بصمة مشية (اسم الشخص).
Future<String?> showGaitEnrollDialog(BuildContext context) {
  final TextEditingController controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Row(
          children: <Widget>[
            Icon(Icons.fingerprint_rounded, size: 18, color: AppColors.cyan),
            SizedBox(width: 8),
            Text(
              'تسجيل بصمة مشية',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'اكتب اسمًا لتمييز البصمة. ستُحفظ ميزات إيقاع المشي فقط — '
              'لا صور ولا تسجيل صوتي ولا بيانات بيومترية خام.',
              style: TextStyle(
                fontSize: 11,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: AppTheme.inputDecoration(
                labelText: 'اسم الشخص',
                hintText: 'مثال: أحمد',
                prefixIcon: Icons.person_outline_rounded,
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        actions: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: NeonButton(
                  label: 'إلغاء',
                  height: 42,
                  variant: NeonButtonVariant.outlined,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: NeonButton(
                  label: 'تسجيل',
                  height: 42,
                  icon: Icons.check_rounded,
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(controller.text.trim()),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}

/// شريط سفلي قصير لإبلاغ نتيجة إجراء.
void showMonitorSnack(BuildContext context, String message) {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 11.5, color: AppColors.textPrimary),
        ),
        backgroundColor: AppColors.surfaceHigh,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
}

/// تعديل رقم الطوارئ مع حفظه في التخزين المحلي.
Future<void> editEmergencyNumber(
  BuildContext context,
  SensingViewModel sensing,
) async {
  final String? value =
      await showEmergencyNumberDialog(context, sensing.emergencyNumber);
  if (value == null || value.isEmpty || !context.mounted) return;
  final bool saved = await sensing.setEmergencyNumber(value);
  if (!context.mounted) return;
  showMonitorSnack(
    context,
    saved
        ? 'تم تحديث رقم الطوارئ إلى ${sensing.emergencyNumber}'
        : 'رقم غير صالح — لم يتم الحفظ',
  );
}

/// فتح لوحة الاتصال على رقم الطوارئ (بلا اتصال تلقائي).
Future<void> callEmergency(
  BuildContext context,
  SensingViewModel sensing,
) async {
  final DialOutcome outcome = await sensing.callEmergency();
  if (!context.mounted) return;
  showMonitorSnack(
    context,
    switch (outcome) {
      DialOutcome.dialerOpened => 'فُتح تطبيق الهاتف على الرقم — أكمل الاتصال',
      DialOutcome.copiedToClipboard =>
        'تعذّر فتح تطبيق الهاتف — تم نسخ الرقم ${sensing.emergencyNumber}',
      DialOutcome.invalidNumber => 'رقم الطوارئ غير صالح، عدّله من الزر المجاور',
    },
  );
}
