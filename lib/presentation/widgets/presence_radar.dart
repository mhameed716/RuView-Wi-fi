import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/l10n/ar_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/sensing_frame.dart';

/// رادار الحضور المكاني: حلقات متحدة المركز + مسح دوّار + نقط حياة
/// تمثّل الأشخاص المرصودين (من `persons[]` أو من تصنيف الحضور).
class PresenceRadar extends StatefulWidget {
  const PresenceRadar({
    super.key,
    required this.hasPresence,
    required this.personCount,
    required this.motionIntensity,
    required this.signalQuality,
    required this.persons,
    required this.hasData,
    required this.isStale,
    this.maxSize = 320,
  });

  final bool hasPresence;
  final int personCount;
  final double motionIntensity;
  final double signalQuality;
  final List<PersonDetection> persons;
  final bool hasData;
  final bool isStale;
  final double maxSize;

  @override
  State<PresenceRadar> createState() => _PresenceRadarState();
}

class _PresenceRadarState extends State<PresenceRadar>
    with TickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    _sweep.repeat();
    _pulse.repeat();
  }

  @override
  void dispose() {
    _sweep.dispose();
    _pulse.dispose();
    super.dispose();
  }

  List<_Blip> get _blips {
    final List<_Blip> blips = <_Blip>[];
    for (final PersonDetection person in widget.persons) {
      double nx = 0;
      double ny = 0;
      if (person.position.length >= 3) {
        // الخادم الرسمي يرسل [x, y, z] على مستوى الأرضية (y = 0).
        nx = person.position[0] / 6.0;
        ny = person.position[2] / 6.0;
      } else if (person.position.length >= 2) {
        nx = person.position[0] / 6.0;
        ny = person.position[1] / 6.0;
      }

      final bool hasGeometry = nx.abs() > 0.01 || ny.abs() > 0.01;
      if (!hasGeometry) {
        // موضع تقديري مستقر حول المركز عند غياب الإحداثيات.
        final double angle = 2.399963 * (person.id + 1);
        final double radius =
            0.42 + 0.2 * (1 - person.confidence.clamp(0.0, 1.0).toDouble());
        nx = math.cos(angle) * radius;
        ny = math.sin(angle) * radius;
      }

      final double length = math.sqrt(nx * nx + ny * ny);
      if (length > 0.9) {
        nx = nx / length * 0.9;
        ny = ny / length * 0.9;
      }

      blips.add(
        _Blip(
          dx: nx,
          dy: ny,
          strength: person.confidence.clamp(0.15, 1.0).toDouble(),
        ),
      );
    }

    if (blips.isEmpty && widget.hasPresence) {
      blips.add(const _Blip(dx: 0.16, dy: -0.22, strength: 0.6));
    }
    return blips;
  }

  @override
  Widget build(BuildContext context) {
    final bool active = widget.hasData && widget.hasPresence && !widget.isStale;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double side = math.min(
          constraints.maxWidth.isFinite ? constraints.maxWidth : widget.maxSize,
          widget.maxSize,
        );

        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[_sweep, _pulse]),
              builder: (BuildContext context, Widget? child) {
                return Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RadarPainter(
                          sweep: _sweep.value,
                          pulse: _pulse.value,
                          active: active,
                          hasData: widget.hasData,
                          blips: _blips,
                          motion: widget.motionIntensity,
                          signalQuality: widget.signalQuality,
                        ),
                      ),
                    ),
                    _RadarCaption(
                      hasData: widget.hasData,
                      hasPresence: widget.hasPresence,
                      personCount: widget.personCount,
                      isStale: widget.isStale,
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _RadarCaption extends StatelessWidget {
  const _RadarCaption({
    required this.hasData,
    required this.hasPresence,
    required this.personCount,
    required this.isStale,
  });

  final bool hasData;
  final bool hasPresence;
  final int personCount;
  final bool isStale;

  @override
  Widget build(BuildContext context) {
    if (!hasData) {
      return _pill(
        title: ArStrings.radarNoSignal,
        value: '—',
        color: AppColors.textMuted,
      );
    }

    if (!hasPresence) {
      return _pill(
        title: ArStrings.radarIdle,
        value: '0',
        color: AppColors.idle,
        caption: isStale ? ArStrings.dataStale : null,
      );
    }

    return _pill(
      title: ArStrings.radarActive,
      value: personCount > 0 ? '$personCount' : '1',
      color: isStale ? AppColors.warning : AppColors.emerald,
      caption: personCount > 1 ? 'أشخاص داخل النطاق' : 'شخص داخل النطاق',
    );
  }

  Widget _pill({
    required String title,
    required String value,
    required Color color,
    String? caption,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background.withAlpha(190),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withAlpha(90)),
        boxShadow: <BoxShadow>[
          BoxShadow(color: color.withAlpha(36), blurRadius: 22, spreadRadius: -6),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            value,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (caption != null)
            Text(
              caption,
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}

class _Blip {
  const _Blip({required this.dx, required this.dy, required this.strength});

  final double dx;
  final double dy;
  final double strength;
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.sweep,
    required this.pulse,
    required this.active,
    required this.hasData,
    required this.blips,
    required this.motion,
    required this.signalQuality,
  });

  final double sweep;
  final double pulse;
  final bool active;
  final bool hasData;
  final List<_Blip> blips;
  final double motion;
  final double signalQuality;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = math.min(size.width, size.height) / 2 - 4;
    if (radius <= 0) return;

    final Color accent = active ? AppColors.emerald : AppColors.cyan;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    // خلفية الرادار
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            accent.withAlpha(hasData ? 32 : 12),
            AppColors.background.withAlpha(0),
          ],
          stops: const <double>[0.0, 1.0],
        ).createShader(rect),
    );

    // حلقات متحدة المركز
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.cyan.withAlpha(38);
    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, radius * i / 4, ring);
    }

    // خطوط التقاطع
    final Paint cross = Paint()
      ..strokeWidth = 1
      ..color = AppColors.cyan.withAlpha(22);
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      cross,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      cross,
    );

    // مسح دوّار
    if (hasData) {
      final double angle = sweep * 2 * math.pi;
      final double sweepWidth = 0.9 + motion * 0.35;
      canvas.save();
      canvas.clipPath(Path()..addOval(rect));
      final Paint sweepPaint = Paint()
        ..shader = SweepGradient(
          startAngle: angle - sweepWidth,
          endAngle: angle,
          colors: <Color>[
            accent.withAlpha(0),
            accent.withAlpha(20),
            accent.withAlpha(68),
          ],
          stops: const <double>[0.0, 0.65, 1.0],
        ).createShader(rect);
      canvas.drawCircle(center, radius, sweepPaint);
      canvas.restore();

      final Offset leading = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas.drawLine(
        center,
        leading,
        Paint()
          ..color = accent.withAlpha(170)
          ..strokeWidth = 1.4,
      );
    }

    // هوائي المركز
    canvas.drawCircle(
      center,
      7,
      Paint()
        ..color = accent.withAlpha(hasData ? 90 : 40)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(center, 3.4, Paint()..color = accent);

    // نقط الأشخاص
    final double ringPulse = 0.35 + 0.65 * pulse;
    for (final _Blip blip in blips) {
      final Offset position = Offset(
        center.dx + blip.dx * radius,
        center.dy + blip.dy * radius,
      );
      final Color blipColor = active ? AppColors.emerald : AppColors.cyan;
      final double coreRadius = 3.2 + blip.strength * 2.6;

      canvas.drawCircle(
        position,
        coreRadius * 2.6,
        Paint()
          ..color = blipColor.withAlpha(70)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawCircle(position, coreRadius, Paint()..color = blipColor);

      canvas.drawCircle(
        position,
        coreRadius + 6 + ringPulse * 16 * blip.strength,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = blipColor.withAlpha(
            ((1 - pulse) * 150).round().clamp(0, 255).toInt(),
          ),
      );
    }

    // حلقة خارجية تتنفس مع جودة الإشارة
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = accent.withAlpha(60 + (signalQuality * 120).round()),
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) => true;
}
