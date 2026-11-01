import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// رسم بياني مصغّر لسلسلة قراءات (بدون مكتبات خارجية).
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 42,
    this.minValue,
    this.maxValue,
    this.strokeWidth = 1.8,
    this.fill = true,
  });

  final List<double> values;
  final Color color;
  final double height;
  final double? minValue;
  final double? maxValue;
  final double strokeWidth;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          color: color,
          minValue: minValue,
          maxValue: maxValue,
          strokeWidth: strokeWidth,
          fill: fill,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.color,
    required this.minValue,
    required this.maxValue,
    required this.strokeWidth,
    required this.fill,
  });

  final List<double> values;
  final Color color;
  final double? minValue;
  final double? maxValue;
  final double strokeWidth;
  final bool fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final Paint gridPaint = Paint()
      ..color = AppColors.border.withAlpha(120)
      ..strokeWidth = 1;
    final double midY = size.height / 2;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), gridPaint);

    if (values.length < 2) {
      return;
    }

    double lo = minValue ?? values.reduce(math.min);
    double hi = maxValue ?? values.reduce(math.max);
    if (hi - lo < 0.0001) {
      hi = lo + 1;
    }

    final double dx = size.width / (values.length - 1);
    final Path path = Path();
    for (int i = 0; i < values.length; i++) {
      final double normalized =
          ((values[i] - lo) / (hi - lo)).clamp(0.0, 1.0).toDouble();
      final double x = dx * i;
      final double y = size.height - 3 - normalized * (size.height - 6);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    if (fill) {
      final Path fillPath = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        fillPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[color.withAlpha(70), color.withAlpha(0)],
          ).createShader(Offset.zero & size),
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6),
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.color != color ||
        oldDelegate.minValue != minValue ||
        oldDelegate.maxValue != maxValue;
  }
}
