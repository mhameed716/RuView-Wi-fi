import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/sleep_summary.dart';
import '../../data/models/vital_signs.dart';
import 'neon_card.dart';
import 'sparkline.dart';
import 'status_pill.dart';

/// لوحة النوم والعلامات الحيوية أثناء النوم.
///
/// تعرض: جودة النوم، معدل التنفس مع تصنيفه (طبيعي/بطيء/سريع)، تقلّب التنفس،
/// وعدد اضطرابات التنفس (احتمال انقطاع النفس) — إضافة إلى رسم مصغّر للتنفس.
class SleepVitalsPanel extends StatelessWidget {
  const SleepVitalsPanel({
    super.key,
    required this.summary,
    required this.breathingHistory,
    required this.hasData,
  });

  final SleepSummary summary;
  final List<double> breathingHistory;
  final bool hasData;

  static Color colorFor(SleepState state) => switch (state) {
        SleepState.absent => AppColors.idle,
        SleepState.awake => AppColors.cyan,
        SleepState.light => AppColors.cyanDim,
        SleepState.deep => AppColors.emerald,
        SleepState.disturbed => AppColors.warning,
      };

  Color get _tone => colorFor(summary.state);

  @override
  Widget build(BuildContext context) {
    final double? breathing = summary.averageBreathing;
    final _BreathingClass breathingClass = _BreathingClass.of(breathing);

    return NeonCard(
      glowColor: _tone,
      borderColor: _tone.withAlpha(52),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            title: 'النوم والعلامات الحيوية',
            subtitle: 'تنفس أثناء النوم • جودة النوم • انقطاع النفس',
            icon: Icons.bedtime_rounded,
            trailing: StatusPill(
              label: summary.isMonitoring
                  ? summary.state.arabicLabel
                  : 'بانتظار الاستلقاء',
              color: _tone,
              compact: true,
              pulsing: summary.isMonitoring,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              _QualityRing(
                score: summary.qualityScore,
                ratio: summary.qualityRatio,
                tone: _tone,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _StatRow(
                      label: 'معدل التنفس',
                      value: breathing == null
                          ? '—'
                          : '${Formatters.decimal(breathing)} مرة/دقيقة',
                      tone: breathingClass.tone,
                      trailing: breathingClass.label,
                    ),
                    const SizedBox(height: 7),
                    _StatRow(
                      label: 'تقلّب التنفس',
                      value: summary.samples < 3
                          ? '—'
                          : '± ${Formatters.decimal(summary.breathingVariability)}',
                      tone: AppColors.textSecondary,
                    ),
                    const SizedBox(height: 7),
                    _StatRow(
                      label: 'اضطرابات التنفس',
                      value: '${summary.apneaEvents}',
                      tone: summary.apneaEvents == 0
                          ? AppColors.emerald
                          : AppColors.warning,
                    ),
                    const SizedBox(height: 7),
                    _StatRow(
                      label: 'مدة الجلسة',
                      value: Formatters.duration(summary.session),
                      tone: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              const Text(
                'معدل التنفس',
                style: TextStyle(fontSize: 10, color: AppColors.textMuted),
              ),
              const Spacer(),
              Text(
                summary.qualityLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _tone,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Sparkline(
            values: breathingHistory,
            color: _tone,
            height: 52,
            minValue: 6,
            maxValue: 26,
          ),
          if (summary.apneaEvents > 0) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.warning.withAlpha(20),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(color: AppColors.warning.withAlpha(84)),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.monitor_heart_outlined,
                    size: 15,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تم رصد ${summary.apneaEvents} اضطراب تنفس '
                      '(غياب إشارة التنفس > 25 ثانية). راقب النائم أو راجع '
                      'طبيبًا إن تكرّر.',
                      style: const TextStyle(
                        fontSize: 10,
                        height: 1.6,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 9),
          Text(
            hasData
                ? 'تقدير استرشادي من CSI وليس جهازًا طبيًا — لا يُعتمد للتشخيص.'
                : 'استلقِ على السرير وابقَ ساكنًا لبضع دقائق لبدء الجلسة.',
            style: TextStyle(
              fontSize: 9.5,
              height: 1.55,
              color: AppColors.textMuted.withAlpha(220),
            ),
          ),
        ],
      ),
    );
  }
}

class _QualityRing extends StatelessWidget {
  const _QualityRing({
    required this.score,
    required this.ratio,
    required this.tone,
  });

  final int score;
  final double ratio;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      height: 86,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          SizedBox(
            width: 86,
            height: 86,
            child: CircularProgressIndicator(
              value: ratio,
              strokeWidth: 7,
              backgroundColor: AppColors.surfaceHigh,
              valueColor: AlwaysStoppedAnimation<Color>(tone),
              strokeCap: StrokeCap.round,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '$score',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: tone,
                ),
              ),
              const Text(
                'جودة النوم',
                style: TextStyle(
                  fontSize: 8.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    required this.tone,
    this.trailing,
  });

  final String label;
  final String value;
  final Color tone;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
        ),
        if (trailing != null) ...<Widget>[
          Text(
            trailing!,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: tone,
            ),
          ),
          const SizedBox(width: 6),
        ],
        Text(
          value,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: tone,
          ),
        ),
      ],
    );
  }
}

/// تصنيف معدل التنفس مقابل النطاق الطبيعي.
class _BreathingClass {
  const _BreathingClass(this.label, this.tone);

  final String label;
  final Color tone;

  static _BreathingClass of(double? bpm) {
    if (bpm == null || bpm <= 0) {
      return const _BreathingClass('—', AppColors.textMuted);
    }
    if (bpm < VitalSigns.normalMinBpm) {
      return const _BreathingClass('بطيء', AppColors.cyan);
    }
    if (bpm > VitalSigns.normalMaxBpm) {
      return const _BreathingClass('سريع', AppColors.warning);
    }
    return const _BreathingClass('طبيعي', AppColors.emerald);
  }
}
