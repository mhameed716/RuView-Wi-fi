import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/sensing_frame.dart';

/// رسم هيكل عظمي مبسّط من مفاصل الخادم (17 نقطة COCO).
///
/// يُستخدم داخل بطاقة الوضعية لتوضيح «تقدير الوضعية» بصريًا. كل شيء محلي:
/// لا مكتبات رسم خارجية ولا صور — فقط [CustomPainter].
///
/// إحداثيات المفاصل تُطبَّع تلقائيًا إلى مساحة اللوحة حتى لو أرسل الخادم
/// إحداثيات مطلقة.
class SkeletonView extends StatelessWidget {
  const SkeletonView({
    super.key,
    required this.keypoints,
    this.height = 152,
    this.accent,
    this.flipY = false,
  });

  final List<PoseKeypoint> keypoints;
  final double height;
  final Color? accent;

  /// اعكس المحور الرأسي إن أرسل الخادم إحداثيات بنمط رياضي (y للأعلى).
  final bool flipY;

  @override
  Widget build(BuildContext context) {
    final Color color = accent ?? AppColors.cyan;
    final BorderRadius radius = BorderRadius.circular(AppTheme.radiusMedium);

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF0B1622), Color(0xFF070C14)],
        ),
        border: Border.all(color: color.withAlpha(48)),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: CustomPaint(
          painter: _SkeletonPainter(
            keypoints: keypoints,
            color: color,
            flipY: flipY,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// أزواج المفاصل المرسومة (ترتيب COCO: 0 أنف، 5/6 كتفان، 11/12 وركان…).
const List<List<int>> _bonePairs = <List<int>>[
  <int>[0, 1],
  <int>[0, 2],
  <int>[1, 3],
  <int>[2, 4],
  <int>[5, 6],
  <int>[5, 7],
  <int>[7, 9],
  <int>[6, 8],
  <int>[8, 10],
  <int>[5, 11],
  <int>[6, 12],
  <int>[11, 12],
  <int>[11, 13],
  <int>[13, 15],
  <int>[12, 14],
  <int>[14, 16],
];

class _SkeletonPainter extends CustomPainter {
  _SkeletonPainter({
    required this.keypoints,
    required this.color,
    required this.flipY,
  });

  final List<PoseKeypoint> keypoints;
  final Color color;
  final bool flipY;

  static const double _minConfidence = 0.2;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);
    if (keypoints.isEmpty || size.width <= 0 || size.height <= 0) return;

    final List<PoseKeypoint> points =
        keypoints.length > 17 ? keypoints.sublist(0, 17) : keypoints;
    final List<bool> visible = <bool>[
      for (final PoseKeypoint point in points)
        point.confidence >= _minConfidence && point.x.isFinite && point.y.isFinite,
    ];

    double minX = double.infinity;
    double maxX = double.negativeInfinity;
    double minY = double.infinity;
    double maxY = double.negativeInfinity;
    for (int i = 0; i < points.length; i++) {
      if (!visible[i]) continue;
      minX = math.min(minX, points[i].x);
      maxX = math.max(maxX, points[i].x);
      minY = math.min(minY, points[i].y);
      maxY = math.max(maxY, points[i].y);
    }
    if (!minX.isFinite || !minY.isFinite) return;

    const double padding = 16;
    final double spanX = math.max(maxX - minX, 0.05);
    final double spanY = math.max(maxY - minY, 0.05);
    final double scale = math.min(
      (size.width - padding * 2) / spanX,
      (size.height - padding * 2) / spanY,
    );
    final double offsetX = (size.width - spanX * scale) / 2 - minX * scale;
    final double offsetY = (size.height - spanY * scale) / 2 - minY * scale;

    Offset project(PoseKeypoint point) {
      final double y = flipY ? (minY + maxY - point.y) : point.y;
      return Offset(offsetX + point.x * scale, offsetY + y * scale);
    }

    final Paint glowPaint = Paint()
      ..color = color.withAlpha(40)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final Paint bonePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[color, color.withAlpha(150)],
      ).createShader(Offset.zero & size)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // رسم العظام.
    for (final List<int> pair in _bonePairs) {
      final int a = pair[0];
      final int b = pair[1];
      if (a >= points.length || b >= points.length) continue;
      if (!visible[a] || !visible[b]) continue;
      final Offset start = project(points[a]);
      final Offset end = project(points[b]);
      canvas.drawLine(start, end, glowPaint);
      canvas.drawLine(start, end, bonePaint);
    }

    // رسم المفاصل.
    final Paint jointPaint = Paint()..color = color;
    final Paint haloPaint = Paint()..color = color.withAlpha(45);
    for (int i = 0; i < points.length; i++) {
      if (!visible[i]) continue;
      final Offset center = project(points[i]);
      final bool isHead = i == 0;
      final double radius = isHead ? 5.6 : 3.2;
      canvas.drawCircle(center, radius + 4.5, haloPaint);
      canvas.drawCircle(center, radius, jointPaint);
      if (isHead) {
        canvas.drawCircle(
          center,
          radius + 2,
          Paint()
            ..color = color.withAlpha(200)
            ..strokeWidth = 1.4
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = Colors.white.withAlpha(8)
      ..strokeWidth = 1;
    for (double y = size.height / 4; y < size.height; y += size.height / 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    final Paint center = Paint()
      ..color = color.withAlpha(16)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      center,
    );
  }

  @override
  bool shouldRepaint(covariant _SkeletonPainter oldDelegate) =>
      oldDelegate.keypoints != keypoints ||
      oldDelegate.color != color ||
      oldDelegate.flipY != flipY;
}
