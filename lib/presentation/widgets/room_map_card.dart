import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/twin/pbr_material.dart';
import '../../domain/twin/room_model.dart';

/// رسم إسقاطي (isometric) لخريطة الغرفة المستنتجة من الانعكاسات الثابتة.
///
/// كل خلية عائق تُرسم صندوقًا ثلاثي الأوجه بلون خامتها، فتظهر الكنبة قماشية
/// والخزانة خشبية والجدار حجريًا — لا ألوان عشوائية.
class RoomMapView extends StatelessWidget {
  const RoomMapView({super.key, required this.room, this.height = 260});

  final RoomModel room;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _RoomPainter(
          room: room,
          textDirection: Directionality.of(context),
        ),
      ),
    );
  }
}

class _RoomBox {
  _RoomBox({
    required this.x,
    required this.z,
    required this.size,
    required this.heightM,
    required this.material,
  });

  final double x;
  final double z;
  final double size;
  final double heightM;
  final PbrMaterial material;
}

class _RoomPainter extends CustomPainter {
  _RoomPainter({required this.room, required this.textDirection});

  final RoomModel room;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF08111B), Color(0xFF060A12)],
        ).createShader(rect),
    );

    if (!room.hasData) {
      _text(
        canvas,
        'لم تُبنَ خريطة الغرفة بعد — تحتاج انعكاسات ثابتة (Static CSI)',
        Offset(size.width / 2, size.height / 2),
        color: AppColors.textSecondary,
        center: true,
      );
      return;
    }

    final double span = math.max(
      room.widthM,
      room.depthM,
    );
    if (span <= 0) return;

    final double scale = (size.height * 0.62) / span;
    final double kx = math.cos(math.pi / 6) * scale;
    final double ky = math.sin(math.pi / 6) * scale;
    final double ox = size.width / 2;
    final double oy = size.height * 0.34;

    Offset iso(double x, double y, double z) => Offset(
          ox + (x - z) * kx,
          oy + (x + z) * ky - y * scale,
        );

    // الأرضية.
    final Path floor = Path()
      ..moveTo(iso(0, 0, 0).dx, iso(0, 0, 0).dy)
      ..lineTo(iso(room.widthM, 0, 0).dx, iso(room.widthM, 0, 0).dy)
      ..lineTo(iso(room.widthM, 0, room.depthM).dx,
          iso(room.widthM, 0, room.depthM).dy)
      ..lineTo(iso(0, 0, room.depthM).dx, iso(0, 0, room.depthM).dy)
      ..close();
    canvas.drawPath(floor, Paint()..color = const Color(0xFF0C1724));

    final Paint grid = Paint()
      ..color = AppColors.cyan.withAlpha(16)
      ..strokeWidth = 0.8;
    final int steps = 6;
    for (int i = 1; i < steps; i++) {
      final double t = i / steps;
      canvas.drawLine(
        iso(room.widthM * t, 0, 0),
        iso(room.widthM * t, 0, room.depthM),
        grid,
      );
      canvas.drawLine(
        iso(0, 0, room.depthM * t),
        iso(room.widthM, 0, room.depthM * t),
        grid,
      );
    }

    // صناديق العوائق.
    final List<_RoomBox> boxes = <_RoomBox>[];
    for (final RoomCell cell in room.cells) {
      if (!cell.obstacle) continue;
      final double x = cell.ix * room.cellM;
      final double z = cell.iz * room.cellM;
      final FurnitureObject? object = _objectAt(x, z);
      boxes.add(
        _RoomBox(
          x: x,
          z: z,
          size: room.cellM,
          heightM: object != null
              ? math.min(object.heightM, 2.6)
              : 0.55,
          material: object?.material ?? MaterialLibrary.stone,
        ),
      );
    }
    boxes.sort((_RoomBox a, _RoomBox b) => (a.x + a.z).compareTo(b.x + b.z));

    for (final _RoomBox box in boxes) {
      _paintBox(canvas, box, iso);
    }

    _paintLabels(canvas, size, iso);
    _paintLegend(canvas, size);
  }

  FurnitureObject? _objectAt(double x, double z) {
    for (final FurnitureObject object in room.objects) {
      if ((x - object.centerX).abs() <= object.widthM / 2 + room.cellM &&
          (z - object.centerZ).abs() <= object.depthM / 2 + room.cellM) {
        return object;
      }
    }
    return null;
  }

  void _paintBox(
    Canvas canvas,
    _RoomBox box,
    Offset Function(double x, double y, double z) iso,
  ) {
    final double x0 = box.x;
    final double z0 = box.z;
    final double x1 = box.x + box.size * 0.94;
    final double z1 = box.z + box.size * 0.94;
    final double h = box.heightM;

    final Color base = Color(box.material.albedo);
    final Paint top = Paint()..color = _lighten(base, 1.18);
    final Paint left = Paint()..color = _lighten(base, 0.82);
    final Paint right = Paint()..color = _lighten(base, 0.6);

    final Path topFace = Path()
      ..moveTo(iso(x0, h, z0).dx, iso(x0, h, z0).dy)
      ..lineTo(iso(x1, h, z0).dx, iso(x1, h, z0).dy)
      ..lineTo(iso(x1, h, z1).dx, iso(x1, h, z1).dy)
      ..lineTo(iso(x0, h, z1).dx, iso(x0, h, z1).dy)
      ..close();
    canvas.drawPath(topFace, top);

    final Path leftFace = Path()
      ..moveTo(iso(x0, 0, z1).dx, iso(x0, 0, z1).dy)
      ..lineTo(iso(x0, h, z1).dx, iso(x0, h, z1).dy)
      ..lineTo(iso(x0, h, z0).dx, iso(x0, h, z0).dy)
      ..lineTo(iso(x0, 0, z0).dx, iso(x0, 0, z0).dy)
      ..close();
    canvas.drawPath(leftFace, left);

    final Path rightFace = Path()
      ..moveTo(iso(x0, 0, z0).dx, iso(x0, 0, z0).dy)
      ..lineTo(iso(x0, h, z0).dx, iso(x0, h, z0).dy)
      ..lineTo(iso(x1, h, z0).dx, iso(x1, h, z0).dy)
      ..lineTo(iso(x1, 0, z0).dx, iso(x1, 0, z0).dy)
      ..close();
    canvas.drawPath(rightFace, right);

    final Paint edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.black.withAlpha(90);
    canvas
      ..drawPath(topFace, edge)
      ..drawPath(leftFace, edge)
      ..drawPath(rightFace, edge);
  }

  void _paintLabels(
    Canvas canvas,
    Size size,
    Offset Function(double x, double y, double z) iso,
  ) {
    int drawn = 0;
    for (final FurnitureObject object in room.objects) {
      if (drawn >= 5) break;
      if (object.kind == FurnitureKind.wall && object.confidence < 0.75) continue;
      final Offset anchor = iso(
        object.centerX,
        object.heightM + 0.12,
        object.centerZ,
      );
      if (anchor.dx < 0 || anchor.dx > size.width || anchor.dy < 0) continue;

      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: object.kind.arabicLabel,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: textDirection,
      )..layout();

      final Rect box = Rect.fromCenter(
        center: anchor,
        width: painter.width + 12,
        height: painter.height + 6,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(6)),
        Paint()..color = const Color(0xFF0B1622).withAlpha(220),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(6)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = Color(object.material.albedo).withAlpha(180),
      );
      painter.paint(
        canvas,
        Offset(box.center.dx - painter.width / 2, box.center.dy - painter.height / 2),
      );
      drawn++;
    }
  }

  void _paintLegend(Canvas canvas, Size size) {
    final List<PbrMaterial> materials = room.materials;
    if (materials.isEmpty) return;

    double x = 12;
    double y = size.height - 18;
    for (final PbrMaterial material in materials.take(4)) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, 8, 8),
          const Radius.circular(2),
        ),
        Paint()..color = Color(material.albedo),
      );
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: material.arabicName,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 9,
          ),
        ),
        textDirection: textDirection,
      )..layout();
      painter.paint(canvas, Offset(x + 12, y - 1));
      x += painter.width + 26;
      if (x > size.width - 70) {
        x = 12;
        y -= 14;
      }
    }
  }

  Color _lighten(Color base, double factor) => Color.fromARGB(
        255,
        (base.red * factor).round().clamp(0, 255),
        (base.green * factor).round().clamp(0, 255),
        (base.blue * factor).round().clamp(0, 255),
      );

  void _text(
    Canvas canvas,
    String value,
    Offset center, {
    required Color color,
    bool center = false,
  }) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(color: color, fontSize: 11, height: 1.5),
      ),
      textAlign: center ? TextAlign.center : TextAlign.start,
      textDirection: textDirection,
    )..layout(maxWidth: 240);
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _RoomPainter oldDelegate) =>
      oldDelegate.room != room;
}
