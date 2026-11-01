import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// أسلوب الزر.
enum NeonButtonVariant { filled, outlined, danger }

/// زر نيون رئيسي/ثانوي مع حالة تحميل ومؤشر تدرّج.
class NeonButton extends StatelessWidget {
  const NeonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.variant = NeonButtonVariant.filled,
    this.expand = true,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final NeonButtonVariant variant;
  final bool expand;
  final double height;

  bool get _enabled => onPressed != null && !loading;

  Color get _accent => switch (variant) {
        NeonButtonVariant.filled => AppColors.cyan,
        NeonButtonVariant.outlined => AppColors.textSecondary,
        NeonButtonVariant.danger => AppColors.danger,
      };

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(AppTheme.radiusMedium);

    final Widget content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (loading)
          SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                variant == NeonButtonVariant.filled
                    ? const Color(0xFF00131A)
                    : AppColors.cyan,
              ),
            ),
          )
        else if (icon != null)
          Icon(
            icon,
            size: 19,
            color: variant == NeonButtonVariant.filled
                ? const Color(0xFF00131A)
                : _accent,
          ),
        if (icon != null || loading) const SizedBox(width: 9),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: variant == NeonButtonVariant.filled
                  ? const Color(0xFF00131A)
                  : _accent,
            ),
          ),
        ),
      ],
    );

    return Opacity(
      opacity: _enabled ? 1 : 0.55,
      child: SizedBox(
        height: height,
        width: expand ? double.infinity : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: variant == NeonButtonVariant.filled
                ? AppColors.primaryGradient
                : null,
            color: variant == NeonButtonVariant.filled
                ? null
                : AppColors.surface,
            border: variant == NeonButtonVariant.filled
                ? null
                : Border.all(color: _accent.withAlpha(110)),
            boxShadow: variant == NeonButtonVariant.filled && _enabled
                ? <BoxShadow>[
                    BoxShadow(
                      color: AppColors.cyan.withAlpha(60),
                      blurRadius: 22,
                      spreadRadius: -4,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: _enabled ? onPressed : null,
              borderRadius: radius,
              splashColor: Colors.white.withAlpha(40),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// زر أيقونة صغير بخلفية داكنة (مثل زر الرجوع أو مسح السجل).
class NeonIconButton extends StatelessWidget {
  const NeonIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.size = 42,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color tone = color ?? AppColors.textSecondary;
    final Widget button = Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, size: 19, color: onPressed == null ? AppColors.textMuted : tone),
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
