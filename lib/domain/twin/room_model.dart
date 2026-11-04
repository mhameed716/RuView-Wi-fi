import 'pbr_material.dart';

/// نوع القطعة المكتشفة عبر انعكاسات الإشارة الثابتة.
enum FurnitureKind {
  wall('جدار', 2.55),
  sofa('كنبة', 0.85),
  table('طاولة', 0.76),
  cabinet('خزانة', 1.85),
  bed('سرير', 0.55),
  door('باب', 2.05),
  plant('نبات', 1.05),
  unknown('قطعة غير مصنّفة', 0.8);

  const FurnitureKind(this.arabicLabel, this.heightM);

  final String arabicLabel;

  /// ارتفاع تقديري بالمتر (لرسم الحجم ثلاثي الأبعاد).
  final double heightM;
}

/// قطعة أثاث/معمار مستنتجة من البصمة الكتلية للانعكاسات.
class FurnitureObject {
  const FurnitureObject({
    required this.kind,
    required this.centerX,
    required this.centerZ,
    required this.widthM,
    required this.depthM,
    required this.confidence,
    required this.material,
  });

  final FurnitureKind kind;

  /// المركز على محور X (م).
  final double centerX;

  /// المركز على محور Z (م).
  final double centerZ;

  final double widthM;
  final double depthM;

  /// ثقة التصنيف (0..1).
  final double confidence;

  final PbrMaterial material;

  double get heightM => kind.heightM;

  double get areaM2 => widthM * depthM;

  /// وصف عربي جاهز للعرض: «كنبة — قماش كتان».
  String get label => '${kind.arabicLabel} — ${material.arabicName}';
}

/// خلية في شبكة الإشغال (Occupancy Grid).
class RoomCell {
  const RoomCell({
    required this.ix,
    required this.iz,
    required this.staticEnergy,
    required this.dynamicEnergy,
    required this.obstacle,
  });

  final int ix;
  final int iz;

  /// طاقة الانعكاس الثابت (0..1).
  final double staticEnergy;

  /// طاقة الحركة (0..1) — تدل على مساحة سالكة.
  final double dynamicEnergy;

  final bool obstacle;
}

/// خريطة الغرفة المستنتجة (RF-SLAM مبسّط): شبكة إشغال + قطع أثاث مصنّفة.
class RoomModel {
  const RoomModel({
    required this.cols,
    required this.rows,
    required this.cellM,
    required this.cells,
    required this.objects,
    required this.frames,
  });

  static const RoomModel empty = RoomModel(
    cols: 0,
    rows: 0,
    cellM: 0.25,
    cells: <RoomCell>[],
    objects: <FurnitureObject>[],
    frames: 0,
  );

  final int cols;
  final int rows;

  /// طول ضلع الخلية بالمتر.
  final double cellM;

  final List<RoomCell> cells;
  final List<FurnitureObject> objects;

  /// عدد الإطارات المستخدمة في المسح (0 = لا مسح بعد).
  final int frames;

  bool get hasData => frames > 0 && cells.isNotEmpty;

  double get widthM => cols * cellM;

  double get depthM => rows * cellM;

  RoomCell? cellAt(int ix, int iz) {
    if (ix < 0 || iz < 0 || ix >= cols || iz >= rows) return null;
    final int index = iz * cols + ix;
    if (index >= cells.length) return null;
    return cells[index];
  }

  int get obstacleCells =>
      cells.where((RoomCell cell) => cell.obstacle).length;

  double get obstacleAreaM2 => obstacleCells * cellM * cellM;

  double get freeAreaM2 => (cells.length - obstacleCells) * cellM * cellM;

  /// الخامات المستخدمة فعليًا في المشهد (بلا تكرار).
  List<PbrMaterial> get materials {
    final List<PbrMaterial> unique = <PbrMaterial>[];
    for (final FurnitureObject object in objects) {
      if (unique.any((PbrMaterial m) => m.id == object.material.id)) continue;
      unique.add(object.material);
    }
    return unique;
  }

  String get summary => hasData
      ? '${objects.length} قطعة مصنّفة · ${freeAreaM2.toStringAsFixed(1)} م² '
          'مساحة سالكة'
      : 'بانتظار انعكاسات ثابتة لبناء الخريطة';
}
