import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/twin/body_profile.dart';
import '../../domain/twin/body_shape.dart';
import '../../domain/twin/twin_state.dart';
import 'body_avatar_view.dart';
import 'neon_button.dart';
import 'neon_card.dart';

/// بطاقة «التوأم الراديوي»: مجسّم SMPL ثلاثي الأبعاد + القياسات الجسدية +
/// بصمة الشخص (توأم مسبق) — كلها على شاشة الرصد دون شاشة جديدة.
class RfTwinCard extends StatelessWidget {
  const RfTwinCard({
    super.key,
    required this.twin,
    required this.identityLabel,
    required this.profiles,
    required this.onEnroll,
    required this.onRemoveProfile,
  });

  final TwinState twin;
  final String identityLabel;
  final List<BodyProfile> profiles;
  final VoidCallback onEnroll;
  final void Function(String id) onRemoveProfile;

  static const String title = 'التوأم الراديوي (SMPL)';
  static const String subtitle =
      'مجسّم ثلاثي الأبعاد يتشكّل من الانعكاسات + إكمال تنبئي + قماش حيّ';

  @override
  Widget build(BuildContext context) {
    final BodyShape shape = twin.shape;
    final List<BodyMeasurement> measurements = shape.measurements;

    return NeonCard(
      glowColor: AppColors.cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.cyan.withAlpha(24),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cyan.withAlpha(70)),
                ),
                child: const Icon(
                  Icons.accessibility_new_rounded,
                  size: 17,
                  color: AppColors.cyan,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF08111B),
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              ),
              child: BodyAvatarView(
                twin: twin,
                height: 300,
                yaw: -0.42,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _CompletionBar(
            value: twin.completionScore,
            label: twin.hasMesh
                ? 'إكمال الشكل: ${(twin.completionScore * 100).round()}% · '
                    '${twin.mesh.vertexCount} رأس شبكة'
                : 'بانتظار رصد جسم',
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              const Icon(
                Icons.fingerprint_rounded,
                size: 14,
                color: AppColors.emerald,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'الهوية: $identityLabel',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                '${(shape.confidence * 100).round()}% ثقة',
                style: const TextStyle(
                  fontSize: 9.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'القياسات الجسدية',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              const double spacing = 8;
              final double width = (constraints.maxWidth - spacing) / 2;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: <Widget>[
                  for (final BodyMeasurement item in measurements)
                    SizedBox(
                      width: width,
                      child: _MeasurementTile(item: item),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          NeonButton(
            key: const ValueKey<String>('twin-enroll-button'),
            label: 'تسجيل توأم لهذا الشخص',
            icon: Icons.person_add_alt_1_rounded,
            height: 46,
            expand: true,
            variant: twin.hasBody
                ? NeonButtonVariant.filled
                : NeonButtonVariant.outlined,
            onPressed: twin.hasBody ? onEnroll : null,
          ),
          if (profiles.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const Text(
              'التوائم المحفوظة',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            for (final BodyProfile profile in profiles.take(4))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.badge_outlined,
                      size: 13,
                      color: AppColors.cyan,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${profile.label} · '
                        '${(profile.shape.heightM * 100).round()} سم · '
                        '${profile.shape.buildLabel}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onRemoveProfile(profile.id),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CompletionBar extends StatelessWidget {
  const _CompletionBar({required this.value, required this.label});

  final double value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final double clamped = value.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: clamped,
            minHeight: 6,
            backgroundColor: AppColors.surface,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.cyan),
          ),
        ),
      ],
    );
  }
}

class _MeasurementTile extends StatelessWidget {
  const _MeasurementTile({required this.item});

  final BodyMeasurement item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withAlpha(130),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            item.label,
            style: const TextStyle(
              fontSize: 9,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
