import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/twin/body_mesh.dart';
import '../../domain/twin/cloth_simulator.dart';
import '../../domain/twin/twin_state.dart';
import '../../domain/twin/vec3.dart';

/// مجسّم الجسم ثلاثي الأبعاد (SMPL) مرسوم بمحرّك إسقاط برمجي خفيف.
///
/// لماذا لا نستخدم مكتبة 3D؟ لأن التطبيق بلا أي حزمة خارجية؛ رسم الشبكة
/// يدويًا (rotation + perspective + depth sort + إضاءة) يعطي نتيجة مقنعة
/// ويكفي لهاتف متوسط. السطح نفسه ينتج من معاملات β عبر `BodyMeshBuilder`.
class BodyAvatarView extends StatelessWidget {
  const BodyAvatarView({
    super.key,
    required this.twin,
    this.height = 320,
    this.yaw = -0.42,
    this.showCloth = true,
    this.showSkeleton = true,
  });

  final TwinState twin;
  final double height;

  /// زاوية الدوران حول المحور Y (بالراديان).
  final double yaw;

  final bool showCloth;
  final bool showSkeleton;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _BodyPainter(
          twin: twin,
          yaw: yaw,
          showCloth: showCloth,
          showSkeleton: showSkeleton,
          textDirection: Directionality.of(context),
        ),
      ),
    );
  }
}

class _BodyPainter extends CustomPainter {
  _BodyPainter({
    required this.twin,
    required this.yaw,
    required this.showCloth,
    required this.showSkeleton,
    required this.textDirection,
  });

  final TwinState twin;
  final double yaw;
  final bool showCloth;
  final bool showSkeleton;
  final TextDirection textDirection;

  static const Vec3 _light = Vec3(-0.35, 0.78, 0.52);

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackdrop(canvas, size);

    final BodyMesh mesh = twin.mesh;
    if (mesh.isEmpty) {
      _paintPlaceholder(canvas, size);
      return;
    }

    final ({Vec3 min, Vec3 max}) bounds = mesh.bounds;
    final double bodyHeight = math.max(0.3, bounds.max.y - bounds.min.y);
    final double scale = (size.height * 0.8) / bodyHeight;
    final double cx = (bounds.min.x + bounds.max.x) / 2;
    final double baseY = size.height * 0.93;

    Vec3 rotate(Vec3 point) => MeshMath.yaw(point - Vec3(cx, 0, 0), yaw);

    Offset project(Vec3 point) {
      final double perspective = 1 / (1 + (point.z + 1.1) * 0.13);
      return Offset(
        size.width / 2 + point.x * scale * perspective,
        baseY - (point.y - bounds.min.y) * scale * perspective,
      );
    }

    final List<Vec3> rotated = mesh.vertices
        .map(rotate)
        .toList(growable: false);

    // ترتيب المثلثات من الأبعد إلى الأقرب (خوارزمية الرسّام).
    final int triangleCount = mesh.triangleCount;
    final List<int> order = List<int>.generate(triangleCount, (int i) => i);
    final List<double> depth = List<double>.filled(triangleCount, 0);
    for (int i = 0; i < triangleCount; i++) {
      final Vec3 a = rotated[mesh.triangles[i * 3]];
      final Vec3 b = rotated[mesh.triangles[i * 3 + 1]];
      final Vec3 c = rotated[mesh.triangles[i * 3 + 2]];
      depth[i] = (a.z + b.z + c.z) / 3;
    }
    order.sort((int a, int b) => depth[a].compareTo(depth[b]));

    final Paint fill = Paint()..style = PaintingStyle.fill;
    for (final int index in order) {
      final Vec3 a = rotated[mesh.triangles[index * 3]];
      final Vec3 b = rotated[mesh.triangles[index * 3 + 1]];
      final Vec3 c = rotated[mesh.triangles[index * 3 + 2]];

      final Vec3 normal = (b - a).cross(c - a).normalized();
      final double light = MeshMath.shade(
        normal: normal.z >= 0 ? normal : -normal,
        lightDirection: _light,
        roughness: 0.72,
      );

      final BodySurface surface = mesh.triangleSurfaces.length > index
          ? mesh.triangleSurfaces[index]
          : BodySurface.shirt;

      fill.color = _shaded(Color(surface.albedo), light);
      final Path path = Path()
        ..moveTo(project(a).dx, project(a).dy)
        ..lineTo(project(b).dx, project(b).dy)
        ..lineTo(project(c).dx, project(c).dy)
        ..close();
      canvas.drawPath(path, fill);
    }

    if (showCloth) {
      _paintCloth(canvas, size, project, rotate, cx: cx);
    }
    if (showSkeleton) {
      _paintSkeleton(canvas, project, rotate);
    }

    _paintScale(canvas, size, bounds: bounds);
    _paintCaption(canvas, size);
  }

  void _paintBackdrop(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF0A1420), Color(0xFF070D16)],
        ).createShader(rect),
    );

    // شبكة أرضية بمنظور.
    final Paint grid = Paint()
      ..color = AppColors.cyan.withAlpha(18)
      ..strokeWidth = 1;
    for (int i = 1; i <= 4; i++) {
      final double y = size.height * (0.62 + i * 0.075);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.93),
        width: size.width * 0.52,
        height: size.height * 0.09,
      ),
      Paint()..color = AppColors.cyan.withAlpha(22),
    );
  }

  void _paintCloth(
    Canvas canvas,
    Size size,
    Offset Function(Vec3) project,
    Vec3 Function(Vec3) rotate, {
    required double cx,
  }) {
    final List<Vec3> cloth = twin.cloth;
    const int cols = ClothSimulator.defaultCols;
    const int rows = ClothSimulator.defaultRows;
    if (cloth.length != cols * rows) return;

    final List<Vec3> rotated = cloth
        .map((Vec3 point) => rotate(Vec3(point.x - cx, point.y, point.z)))
        .toList(growable: false);

    final Paint fill = Paint()
      ..color = const Color(0xFF2F7E93).withAlpha(150)
      ..style = PaintingStyle.fill;
    final Paint edge = Paint()
      ..color = AppColors.cyan.withAlpha(70)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (int r = 0; r < rows - 1; r++) {
      for (int c = 0; c < cols - 1; c++) {
        final Vec3 p0 = rotated[r * cols + c];
        final Vec3 p1 = rotated[r * cols + c + 1];
        final Vec3 p2 = rotated[(r + 1) * cols + c + 1];
        final Vec3 p3 = rotated[(r + 1) * cols + c];

        final Path path = Path()
          ..moveTo(project(p0).dx, project(p0).dy)
          ..lineTo(project(p1).dx, project(p1).dy)
          ..lineTo(project(p2).dx, project(p2).dy)
          ..lineTo(project(p3).dx, project(p3).dy)
          ..close();
        canvas.drawPath(path, fill);
        canvas.drawPath(path, edge);
      }
    }
  }

  void _paintSkeleton(
    Canvas canvas,
    Offset Function(Vec3) project,
    Vec3 Function(Vec3) rotate,
  ) {
    const List<List<String>> bones = <List<String>>[
      <String>['nose', 'neck'],
      <String>['neck', 'left_shoulder'],
      <String>['neck', 'right_shoulder'],
      <String>['left_shoulder', 'left_elbow'],
      <String>['left_elbow', 'left_wrist'],
      <String>['right_shoulder', 'right_elbow'],
      <String>['right_elbow', 'right_wrist'],
      <String>['left_shoulder', 'left_hip'],
      <String>['right_shoulder', 'right_hip'],
      <String>['left_hip', 'right_hip'],
      <String>['left_hip', 'left_knee'],
      <String>['left_knee', 'left_ankle'],
      <String>['right_hip', 'right_knee'],
      <String>['right_knee', 'right_ankle'],
    ];

    final Paint bone = Paint()
      ..color = AppColors.cyan.withAlpha(150)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final Paint dot = Paint()..color = AppColors.emerald.withAlpha(210);

    for (final List<String> pair in bones) {
      final Vec3? a = twin.joints[pair[0]];
      final Vec3? b = twin.joints[pair[1]];
      if (a == null || b == null) continue;
      canvas.drawLine(project(rotate(a)), project(rotate(b)), bone);
    }
    for (final MapEntry<String, Vec3> joint in twin.joints.entries) {
      if (!joint.key.contains('shoulder') &&
          !joint.key.contains('hip') &&
          joint.key != 'nose' &&
          joint.key != 'neck') {
        continue;
      }
      canvas.drawCircle(project(rotate(joint.value)), 2.4, dot);
    }
  }

  void _paintScale(
    Canvas canvas,
    Size size, {
    required ({Vec3 min, Vec3 max}) bounds,
  }) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: '${((bounds.max.y - bounds.min.y) * 100).round()} سم',
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: textDirection,
    )..layout();

    final Paint tick = Paint()
      ..color = AppColors.cyan.withAlpha(90)
      ..strokeWidth = 1;
    final double x = size.width - 12;
    final double top = size.height * 0.13;
    final double bottom = size.height * 0.93;
    canvas.drawLine(Offset(x, top), Offset(x, bottom), tick);
    for (int i = 0; i <= 4; i++) {
      final double y = top + (bottom - top) * i / 4;
      canvas.drawLine(Offset(x - 5, y), Offset(x, y), tick);
    }
    painter.paint(canvas, Offset(x - painter.width - 8, top - 4));
  }

  void _paintCaption(Canvas canvas, Size size) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: 'SMPL-X ',
            style: const TextStyle(
              color: AppColors.cyan,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(
            text: twin.shape.betaLabel,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
      textDirection: textDirection,
    )..layout(maxWidth: size.width - 24);
    painter.paint(canvas, const Offset(12, 10));
  }

  void _paintPlaceholder(Canvas canvas, Size size) {
    final TextPainter painter = TextPainter(
      text: const TextSpan(
        text: 'بانتظار رصد جسم لبناء المجسّم',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: textDirection,
    )..layout(maxWidth: size.width);
    painter.paint(
      canvas,
      Offset((size.width - painter.width) / 2, size.height / 2 - 8),
    );
  }

  Color _shaded(Color base, double light) {
    final double factor = 0.32 + 0.98 * light;
    return Color.fromARGB(
      255,
      (base.red * factor).round().clamp(0, 255),
      (base.green * factor).round().clamp(0, 255),
      (base.blue * factor).round().clamp(0, 255),
    );
  }

  @override
  bool shouldRepaint(covariant _BodyPainter oldDelegate) {
    return oldDelegate.twin != twin ||
        oldDelegate.yaw != yaw ||
        oldDelegate.showCloth != showCloth;
  }
}
