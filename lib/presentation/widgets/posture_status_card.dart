import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/gait_profile.dart';
import '../../data/models/posture.dart';
import '../../data/models/sensing_frame.dart';
import '../../domain/monitoring/safety_state.dart';
import 'neon_button.dart';
import 'neon_card.dart';
import 'skeleton_view.dart';
import 'status_pill.dart';

/// بطاقة «الحالة الحالية»: وضعية الجسم + هيلكل تقديري + بصمة المشية.
///
/// كل القيم تأتي من [SensingViewModel]، والبطاقة عرضية فقط (Stateless) لذلك
/// تبقى سهلة الاختبار ولا تحتفظ بحالة.
class PostureStatusCard extends StatelessWidget {
  const PostureStatusCard({
    super.key,
    required this.posture,
    required this.source,
    required this.confidence,
    required this.keypoints,
    required this.hasSkeleton,
    required this.hasData,
    required this.gaitMatch,
    required this.gaitProfiles,
    required this.gaitCollecting,
    this.onEnroll,
    this.onRemoveProfile,
  });

  final PostureKind posture;
  final PostureSource source;
  final double confidence;
  final List<PoseKeypoint> keypoints;
  final bool hasSkeleton;
  final bool hasData;
  final GaitMatch? gaitMatch;
  final List<GaitProfile> gaitProfiles;
  final bool gaitCollecting;
  final VoidCallback? onEnroll;
  final void Function(GaitProfile profile)? onRemoveProfile;

  static Color colorFor(PostureKind kind) => switch (kind) {
        PostureKind.standing || PostureKind.walking => AppColors.emerald,
        PostureKind.sitting => AppColors.cyan,
        PostureKind.lying => AppColors.cyanDim,
        PostureKind.bending => AppColors.warning,
        PostureKind.fallen => AppColors.danger,
        PostureKind.unknown => AppColors.idle,
      };

  static IconData iconFor(PostureKind kind) => switch (kind) {
        PostureKind.standing => Icons.accessibility_new_rounded,
        PostureKind.sitting => Icons.event_seat_rounded,
        PostureKind.lying => Icons.airline_seat_flat_rounded,
        PostureKind.walking => Icons.directions_walk_rounded,
        PostureKind.bending => Icons.accessibility_rounded,
        PostureKind.fallen => Icons.personal_injury_rounded,
        PostureKind.unknown => Icons.help_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final Color tone = colorFor(posture);
    final String label = hasData ? posture.arabicLabel : 'بانتظار البيانات';

    return NeonCard(
      glowColor: tone,
      borderColor: tone.withAlpha(64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            title: 'الحالة الحالية',
            subtitle: 'تصنيف النشاط (HAR) من انعكاسات Wi-Fi',
            icon: Icons.accessibility_new_rounded,
            trailing: StatusPill(
              label: label,
              color: tone,
              icon: iconFor(posture),
              compact: true,
            ),
          ),
          Row(
            children: <Widget>[
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (Widget child, Animation<double> anim) {
                  return FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.82, end: 1).animate(anim),
                      child: child,
                    ),
                  );
                },
                child: _PostureGlyph(
                  key: ValueKey<PostureKind>(posture),
                  icon: iconFor(posture),
                  tone: tone,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'الحالة الحالية:',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      child: Text(
                        label,
                        key: ValueKey<String>(label),
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                          color: tone,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasData
                          ? 'المصدر: ${source.arabicLabel}'
                              ' • الثقة ${(confidence * 100).round()}%'
                          : 'ابدأ الاتصال ليقوم التطبيق بتقدير الوضعية',
                      style: const TextStyle(
                        fontSize: 10.5,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          if (hasSkeleton)
            SkeletonView(keypoints: keypoints, accent: tone)
          else
            _SkeletonPlaceholder(tone: tone),
          const NeonDivider(height: 20),
          _GaitSection(
            hasData: hasData,
            tone: tone,
            gaitMatch: gaitMatch,
            profiles: gaitProfiles,
            collecting: gaitCollecting,
            onEnroll: onEnroll,
            onRemoveProfile: onRemoveProfile,
          ),
        ],
      ),
    );
  }
}

class _PostureGlyph extends StatelessWidget {
  const _PostureGlyph({super.key, required this.icon, required this.tone});

  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: <Color>[tone.withAlpha(46), tone.withAlpha(12)],
        ),
        border: Border.all(color: tone.withAlpha(96)),
        boxShadow: <BoxShadow>[
          BoxShadow(color: tone.withAlpha(38), blurRadius: 20, spreadRadius: -6),
        ],
      ),
      child: Icon(icon, size: 30, color: tone),
    );
  }
}

class _SkeletonPlaceholder extends StatelessWidget {
  const _SkeletonPlaceholder({required this.tone});

  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.backgroundElevated,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.polyline_rounded, size: 18, color: tone.withAlpha(160)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'لا يرسل الخادم نقاط المفاصل حاليًا — يُعتمد على تصنيف الوضعية '
              'المرسل من البوابة.',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.6,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GaitSection extends StatelessWidget {
  const _GaitSection({
    required this.hasData,
    required this.tone,
    required this.gaitMatch,
    required this.profiles,
    required this.collecting,
    this.onEnroll,
    this.onRemoveProfile,
  });

  final bool hasData;
  final Color tone;
  final GaitMatch? gaitMatch;
  final List<GaitProfile> profiles;
  final bool collecting;
  final VoidCallback? onEnroll;
  final void Function(GaitProfile profile)? onRemoveProfile;

  @override
  Widget build(BuildContext context) {
    final GaitMatch? match = gaitMatch;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(
              Icons.fingerprint_rounded,
              size: 16,
              color: AppColors.cyan,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'بصمة المشية',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            StatusPill(
              label: collecting ? 'جاهز للتسجيل' : 'جمع العينات…',
              color: collecting ? AppColors.emerald : AppColors.idle,
              compact: true,
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'تعرّف على الشخص من إيقاع مشيه وانعكاسات CSI — بدون كاميرا وبدون وجه.',
          style: TextStyle(
            fontSize: 10.5,
            height: 1.55,
            color: AppColors.textMuted,
          ),
        ),
        if (match != null) ...<Widget>[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: tone.withAlpha(24),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              border: Border.all(color: tone.withAlpha(80)),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.verified_user_rounded, size: 15, color: tone),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تم التعرّف: ${match.profile.name}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: tone,
                    ),
                  ),
                ),
                Text(
                  match.similarityLabel,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (profiles.isNotEmpty) ...<Widget>[
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: <Widget>[
              for (final GaitProfile profile in profiles)
                _ProfileChip(
                  profile: profile,
                  onRemove: onRemoveProfile == null
                      ? null
                      : () => onRemoveProfile!(profile),
                ),
            ],
          ),
        ],
        const SizedBox(height: 11),
        NeonButton(
          label: collecting
              ? 'تسجيل بصمة مشية الآن'
              : (hasData
                  ? 'يحتاج مشيًا متواصلًا ~12 ثانية'
                  : 'بانتظار بيانات الحركة'),
          icon: Icons.add_a_photo_outlined,
          height: 44,
          variant: NeonButtonVariant.outlined,
          onPressed: collecting ? onEnroll : null,
        ),
      ],
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({required this.profile, this.onRemove});

  final GaitProfile profile;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 5, 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.directions_walk_rounded,
            size: 12,
            color: AppColors.cyanDim,
          ),
          const SizedBox(width: 5),
          Text(
            profile.name,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.textSecondary,
            ),
          ),
          if (onRemove != null) ...<Widget>[
            const SizedBox(width: 3),
            GestureDetector(
              onTap: onRemove,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(3),
                child: Icon(
                  Icons.close_rounded,
                  size: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
