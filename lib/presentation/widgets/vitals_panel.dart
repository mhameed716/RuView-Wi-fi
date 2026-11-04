import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/l10n/ar_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/num_utils.dart';
import '../../data/models/sensing_frame.dart';
import '../../data/models/vital_signs.dart';
import 'neon_card.dart';
import 'sparkline.dart';
import 'status_pill.dart';

/// لوحة العلامات الحيوية: عدّاد تنفس دائري + شدة الحركة + الرسم المصغّر.
class VitalsPanel extends StatelessWidget {
  const VitalsPanel({
    super.key,
    required this.breathingRate,
    required this.breathingStatus,
    required this.breathingRatio,
    required this.motionIntensity,
    required this.motionLevel,
    required this.confidence,
    required this.breathingHistory,
    required this.hasData,
    this.heartRate,
  });

  final double? breathingRate;
  final BreathingStatus breathingStatus;
  final double breathingRatio;
  final double motionIntensity;
  final MotionLevel motionLevel;
  final double confidence;
  final List<double> breathingHistory;
  final bool hasData;
  final double? heartRate;

  Color get _breathingColor => switch (breathingStatus) {
        BreathingStatus.normal => AppColors.emerald,
        BreathingStatus.fast => AppColors.warning,
        BreathingStatus.slow => AppColors.cyan,
        BreathingStatus.unknown => AppColors.idle,
      };

  @override
  Widget build(BuildContext context) {
    return NeonCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: ArStrings.vitalsPanel,
            subtitle: 'قياسات لاتلامسية من تشويش موجات الواي فاي',
            icon: Icons.monitor_heart_outlined,
            trailing: StatusPill(
              label: breathingStatus.arabicLabel,
              color: _breathingColor,
              compact: true,
              pulsing: breathingStatus == BreathingStatus.normal && hasData,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 132,
                height: 132,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: breathingRatio),
                  duration: const Duration(milliseconds: 550),
                  curve: Curves.easeOutCubic,
                  builder: (BuildContext context, double value, Widget? child) {
                    return CustomPaint(
                      painter: _GaugePainter(value: value, color: _breathingColor),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              Formatters.decimal(breathingRate),
                              style: TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w800,
                                color: _breathingColor,
                                height: 1.05,
                              ),
                            ),
                            const Text(
                              ArStrings.breathsPerMinute,
                              style: TextStyle(
                                fontSize: 9.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      ArStrings.breathingRate,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        _LegendDot(color: _breathingColor),
                        const SizedBox(width: 6),
                        Text(
                          breathingStatus.arabicLabel,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: _breathingColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Sparkline(
                      values: breathingHistory,
                      color: _breathingColor,
                      minValue: 6,
                      maxValue: 30,
                      height: 40,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _Metric(
                            label: ArStrings.confidence,
                            value: NumUtils.percent(confidence),
                          ),
                        ),
                        if (heartRate != null)
                          Expanded(
                            child: _Metric(
                              label: 'النبض',
                              value: '${Formatters.decimal(heartRate, digits: 0)}',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const NeonDivider(height: 22),
          Row(
            children: <Widget>[
              const Icon(
                Icons.directions_run_rounded,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 7),
              const Text(
                ArStrings.motionIntensity,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                NumUtils.percent(motionIntensity),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.cyan,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                motionLevel.arabicLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: motionLevel.isMoving
                      ? AppColors.cyan
                      : AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          _MotionBar(value: motionIntensity),
        ],
      ),
    );
  }
}

class _MotionBar extends StatelessWidget {
  const _MotionBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0).toDouble()),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double animated, Widget? child) {
        return Container(
          height: 10,
          decoration: BoxDecoration(
            color: AppColors.backgroundElevated,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: animated <= 0.001 ? 0.001 : animated,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: <Color>[AppColors.cyan, AppColors.emerald],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.cyan.withAlpha(90),
                        blurRadius: 10,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[BoxShadow(color: color.withAlpha(120), blurRadius: 6)],
      ),
    );
  }
}

/// عدّاد قوسي (270°) بمؤشر متدرّج.
class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.value, required this.color});

  final double value;
  final Color color;

  static const double _startAngle = math.pi * 0.75;
  static const double _sweepAngle = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = math.min(size.width, size.height) / 2 - 9;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = AppColors.border;
    canvas.drawArc(rect, _startAngle, _sweepAngle, false, track);

    final double clamped = value.clamp(0.0, 1.0).toDouble();
    if (clamped > 0.002) {
      final Paint progress = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: _startAngle,
          endAngle: _startAngle + _sweepAngle,
          colors: <Color>[color.withAlpha(120), color],
        ).createShader(rect);
      canvas.drawArc(rect, _startAngle, _sweepAngle * clamped, false, progress);

      final double angle = _startAngle + _sweepAngle * clamped;
      final Offset knob = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas.drawCircle(
        knob,
        4.5,
        Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(knob, 2.6, Paint()..color = Colors.white);
    }

    // علامات المقياس
    final Paint tick = Paint()
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = AppColors.border;
    for (int i = 0; i <= 6; i++) {
      final double angle = _startAngle + _sweepAngle * (i / 6);
      final Offset outer = Offset(
        center.dx + math.cos(angle) * (radius - 9),
        center.dy + math.sin(angle) * (radius - 9),
      );
      final Offset inner = Offset(
        center.dx + math.cos(angle) * (radius - 13),
        center.dy + math.sin(angle) * (radius - 13),
      );
      canvas.drawLine(inner, outer, tick);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color;
}
