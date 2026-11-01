import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../domain/monitoring/safety_state.dart';
import 'emergency_banner.dart';
import 'neon_button.dart';
import 'neon_card.dart';
import 'status_pill.dart';

/// بطاقة «وضع الحراسة الأمنية» في لوحة التحكم.
///
/// عند التفعيل يعرض المحرّك أي حركة كتنبيه تسلل بعد مهلة تسليح، ويسجّلها في
/// سجل الأنشطة الأمنية ويرسل إشعارًا فوريًا.
class SecurityModeCard extends StatelessWidget {
  const SecurityModeCard({
    super.key,
    required this.armed,
    required this.lastIntrusionAt,
    required this.incidentCount,
    required this.emergencyNumber,
    required this.onArmedChanged,
    required this.onEditNumber,
    required this.onCallEmergency,
    this.intrusionAlert,
    this.onDismissAlert,
  });

  final bool armed;
  final DateTime? lastIntrusionAt;
  final int incidentCount;
  final String emergencyNumber;
  final ValueChanged<bool> onArmedChanged;
  final VoidCallback onEditNumber;
  final VoidCallback onCallEmergency;
  final IntrusionAlert? intrusionAlert;
  final VoidCallback? onDismissAlert;

  @override
  Widget build(BuildContext context) {
    final Color tone = armed ? AppColors.warning : AppColors.cyan;
    final IntrusionAlert? alert = intrusionAlert;

    return NeonCard(
      glowColor: tone,
      borderColor: tone.withAlpha(armed ? 96 : 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            title: 'وضع الحراسة الأمنية',
            subtitle: armed
                ? 'مفعّل — أي حركة تُسجَّل وتُرسل كإشعار'
                : 'معطّل — لن تُسجَّل الأنشطة الأمنية',
            icon: Icons.shield_rounded,
            trailing: _NeonToggle(
              key: const ValueKey<String>('security-toggle'),
              value: armed,
              onChanged: onArmedChanged,
              activeColor: AppColors.warning,
            ),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: _SecurityStat(
                  icon: Icons.history_rounded,
                  label: 'آخر تنبيه',
                  value: lastIntrusionAt == null
                      ? 'لا يوجد'
                      : Formatters.timeAgo(lastIntrusionAt!),
                  tone: lastIntrusionAt == null
                      ? AppColors.textSecondary
                      : AppColors.warning,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _SecurityStat(
                  icon: Icons.notifications_active_rounded,
                  label: 'عدد التنبيهات',
                  value: '$incidentCount',
                  tone: incidentCount == 0
                      ? AppColors.textSecondary
                      : AppColors.danger,
                ),
              ),
            ],
          ),
          if (alert != null) ...<Widget>[
            const SizedBox(height: 10),
            IntrusionStrip(
              alert: alert,
              onDismiss: onDismissAlert ?? () {},
            ),
          ],
          const SizedBox(height: 11),
          Row(
            children: <Widget>[
              Expanded(
                child: NeonButton(
                  label: 'تعديل رقم الطوارئ',
                  icon: Icons.edit_rounded,
                  height: 42,
                  variant: NeonButtonVariant.outlined,
                  onPressed: onEditNumber,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: NeonButton(
                  label: 'اتصال ($emergencyNumber)',
                  icon: Icons.call_rounded,
                  height: 42,
                  onPressed: onCallEmergency,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            'تُحوَّل الحركة إلى تنبيه بعد 20 ثانية من التفعيل (لتجنّب تنبيه خروجك)، '
            'وبحد أقصى تنبيه واحد كل 30 ثانية. الاتصال يفتح لوحة الهاتف فقط '
            'ولا يتصل تلقائيًا.',
            style: TextStyle(
              fontSize: 9.5,
              height: 1.6,
              color: AppColors.textMuted.withAlpha(220),
            ),
          ),
        ],
      ),
    );
  }
}

/// مفتاح تشغيل نيون مخصّص (يتفادى اختلافات واجهة Switch بين إصدارات Flutter).
class _NeonToggle extends StatelessWidget {
  const _NeonToggle({
    super.key,
    required this.value,
    required this.onChanged,
    required this.activeColor,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final Color tone = value ? activeColor : AppColors.idle;

    return Semantics(
      toggled: value,
      label: 'تفعيل وضع الحراسة الأمنية',
      child: GestureDetector(
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 56,
          height: 30,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: value ? tone.withAlpha(56) : AppColors.surfaceHigh,
            border: Border.all(color: tone.withAlpha(value ? 150 : 70)),
            boxShadow: value
                ? <BoxShadow>[
                    BoxShadow(color: tone.withAlpha(70), blurRadius: 14),
                  ]
                : const <BoxShadow>[],
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerLeft : Alignment.centerRight,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? tone : AppColors.textMuted,
                boxShadow: <BoxShadow>[
                  BoxShadow(color: tone.withAlpha(120), blurRadius: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecurityStat extends StatelessWidget {
  const _SecurityStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.backgroundElevated,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 14, color: tone),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: tone,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// شريحة صغيرة تعرض وضع الحراسة في رأس الشاشة.
class ArmStatusPill extends StatelessWidget {
  const ArmStatusPill({super.key, required this.armed});

  final bool armed;

  @override
  Widget build(BuildContext context) {
    return StatusPill(
      label: armed ? 'الحراسة مفعّلة' : 'الحراسة متوقفة',
      color: armed ? AppColors.warning : AppColors.idle,
      icon: armed ? Icons.shield_rounded : Icons.shield_outlined,
      compact: true,
    );
  }
}
