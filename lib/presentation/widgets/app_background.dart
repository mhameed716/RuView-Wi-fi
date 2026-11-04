import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// خلفية الشاشة: تدرّج داكن + هالتان نيون خفيفتان أعلى الشاشة.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child, this.accent});

  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final Color glow = accent ?? AppColors.cyan;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.screenGradient),
        ),
        Positioned(
          top: -140,
          right: -80,
          child: IgnorePointer(
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[glow.withAlpha(46), glow.withAlpha(0)],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 40,
          left: -120,
          child: IgnorePointer(
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    AppColors.emerald.withAlpha(30),
                    AppColors.emerald.withAlpha(0),
                  ],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// رأس شاشة بسيط: شعار + اسم + وصف + إجراء اختياري.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.trailing, this.subtitle});

  final Widget? trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: AppColors.primaryGradient,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.cyan.withAlpha(70),
                blurRadius: 18,
                spreadRadius: -4,
              ),
            ],
          ),
          child: const Icon(
            Icons.wifi_tethering_rounded,
            color: Color(0xFF00131A),
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'RuView Wi-Fi',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: 0.2,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle ?? 'استشعار مكاني عبر الواي فاي — بدون كاميرات',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
