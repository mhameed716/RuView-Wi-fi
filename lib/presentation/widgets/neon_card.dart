import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// بطاقة بخلفية زجاجية داكنة، حواف دائرية وهالة نيون خفيفة.
class NeonCard extends StatelessWidget {
  const NeonCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.glowColor,
    this.borderColor,
    this.onTap,
    this.margin = EdgeInsets.zero,
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? glowColor;
  final Color? borderColor;
  final VoidCallback? onTap;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final Color glow = glowColor ?? AppColors.cyan;
    final double radius = borderRadius ?? AppTheme.radiusLarge;

    final Widget content = Padding(padding: padding, child: child);

    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: <Color>[Color(0xFF111B2B), Color(0xFF0B1220)],
          ),
          border: Border.all(color: borderColor ?? AppColors.border),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: glow.withAlpha(26),
              blurRadius: 28,
              spreadRadius: -8,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: onTap == null
            ? content
            : Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(radius),
                  splashColor: glow.withAlpha(30),
                  highlightColor: glow.withAlpha(16),
                  child: content,
                ),
              ),
      ),
    );
  }
}

/// عنوان قسم داخل الشاشة.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.cyan.withAlpha(24),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.cyan.withAlpha(60)),
              ),
              child: Icon(icon, size: 16, color: AppColors.cyan),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// فاصل رأسي رقيق.
class NeonDivider extends StatelessWidget {
  const NeonDivider({super.key, this.height = 18});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: height / 2),
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              AppColors.border.withAlpha(0),
              AppColors.border,
              AppColors.border.withAlpha(0),
            ],
          ),
        ),
      ),
    );
  }
}
