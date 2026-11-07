import 'dart:math' as math;

import '../../core/utils/num_utils.dart';
import '../../data/models/sensing_frame.dart';
import 'pbr_material.dart';
import 'room_model.dart';

/// إعادة بناء الغرفة والأثاث من الانعكاسات الثابتة (RF-SLAM مبسّط).
///
/// الفكرة الفيزيائية:
///  • إشارة CSI = مكوّن متغيّر (حركة/تنفّس) + مكوّن ثابت (جدران وأثاث).
///  • `signal_field` من البوابة هو خريطة طاقة مكانية؛ نُراكمها بمرشّح
///    أُسّي لاستخراج المكوّن الثابت، ونقيس تباينها لفصل الساكن عن المتحرك.
///  • الخلايا عالية الطاقة الثابتة ومنخفضة التباين = عوائق (جدار/كنبة/خزانة).
///  • الخلايا التي دخلها شخص = مساحة سالكة.
///
/// ثم نُجمّع العوائق (flood fill) ونصنّف كل تجمّع حسب مساحته ونسبته
/// وموضعه، ونلبسه خامة PBR مناسبة — بدل ألوان عشوائية.
class RoomReconstructor {
  RoomReconstructor({
    this.cols = 24,
    this.rows = 24,
    this.cellM = 0.25,
    this.learningRate = 0.32,
    this.rebuildEvery = 4,
    this.minClusterCells = 3,
    this.staticThreshold = 0.55,
    this.motionThreshold = 0.42,
  }) {
    _static = List<double>.filled(cols * rows, 0);
    _dynamic = List<double>.filled(cols * rows, 0);
    _variance = List<double>.filled(cols * rows, 0);
  }

  final int cols;
  final int rows;

  /// طول ضلع الخلية (م).
  final double cellM;

  /// معدّل تعلّم المرشّح الأُسّي للمكوّن الثابت (0..1).
  final double learningRate;

  /// إعادة التصنيف كل كم إطار.
  final int rebuildEvery;

  /// أقل عدد خلايا لتكوين قطعة أثاث.
  final int minClusterCells;

  /// نسبة الطاقة الثابتة لاعتبار الخلية عائقًا.
  final double staticThreshold;

  /// أقصى طاقة حركة للخلية كي تُعدّ «ساكنة».
  final double motionThreshold;

  late final List<double> _static;
  late final List<double> _dynamic;
  late final List<double> _variance;

  int _frames = 0;
  List<FurnitureObject> _objects = const <FurnitureObject>[];
  RoomModel _model = RoomModel.empty;

  RoomModel get model => _model;

  int get frames => _frames;

  bool get hasData => _frames > 0;

  /// يُغذّى بإطار جديد ويُعيد الخريطة المحدّثة.
  RoomModel ingest(SensingFrame frame) {
    _frames++;
    _applySignalField(frame.signalField);
    _applyPersons(frame);

    if (_frames % math.max(1, rebuildEvery) == 0 || _objects.isEmpty) {
      _classify();
    }
    _model = _buildModel();
    return _model;
  }

  void reset() {
    _static.fillRange(0, _static.length, 0);
    _dynamic.fillRange(0, _dynamic.length, 0);
    _variance.fillRange(0, _variance.length, 0);
    _frames = 0;
    _objects = const <FurnitureObject>[];
    _model = RoomModel.empty;
  }

  void _applySignalField(SignalField field) {
    if (field.isEmpty) return;
    final int w = field.width;
    final int h = field.height;
    if (w <= 0 || h <= 0) return;

    final double peak = field.peak;
    if (peak <= 0) return;

    for (int iz = 0; iz < rows; iz++) {
      final int sy = ((iz / rows) * h).floor().clamp(0, h - 1);
      for (int ix = 0; ix < cols; ix++) {
        final int sx = ((ix / cols) * w).floor().clamp(0, w - 1);
        final int source = sy * w + sx;
        if (source >= field.values.length) continue;

        final double value = NumUtils.clamp01(field.values[source] / peak);
        final int index = iz * cols + ix;
        final double previous = _static[index];
        _static[index] = previous + (value - previous) * learningRate;
        final double deviation = (value - _static[index]).abs();
        _variance[index] = _variance[index] * 0.8 + deviation * 0.2;
      }
    }
  }

  void _applyPersons(SensingFrame frame) {
    for (final PersonDetection person in frame.persons) {
      if (person.position.length < 3) continue;
      final double x = person.position[0];
      final double z = person.position[2];
      if (!x.isFinite || !z.isFinite) continue;

      final int cx = (x / cellM).round();
      final int cz = (z / cellM).round();
      const int radius = 2;
      for (int dz = -radius; dz <= radius; dz++) {
        for (int dx = -radius; dx <= radius; dx++) {
          final int ix = cx + dx;
          final int iz = cz + dz;
          if (ix < 0 || iz < 0 || ix >= cols || iz >= rows) continue;
          final int index = iz * cols + ix;
          _dynamic[index] = NumUtils.clamp01(_dynamic[index] + 0.22);
        }
      }
    }
  }

  void _classify() {
    double maxStatic = 0;
    for (final double value in _static) {
      maxStatic = math.max(maxStatic, value);
    }
    if (maxStatic <= 0) {
      _objects = const <FurnitureObject>[];
      return;
    }

    final List<bool> obstacle = List<bool>.filled(cols * rows, false);
    for (int i = 0; i < _static.length; i++) {
      final double normalized = _static[i] / maxStatic;
      obstacle[i] = normalized >= staticThreshold &&
          _variance[i] <= 0.34 &&
          _dynamic[i] <= motionThreshold;
    }

    final List<bool> visited = List<bool>.filled(cols * rows, false);
    final List<FurnitureObject> objects = <FurnitureObject>[];

    for (int start = 0; start < obstacle.length; start++) {
      if (!obstacle[start] || visited[start]) continue;

      final List<int> queue = <int>[start];
      visited[start] = true;
      int minX = cols;
      int maxX = 0;
      int minZ = rows;
      int maxZ = 0;
      int count = 0;
      double energy = 0;
      double variation = 0;

      while (queue.isNotEmpty) {
        final int index = queue.removeLast();
        final int ix = index % cols;
        final int iz = index ~/ cols;
        count++;
        energy += _static[index] / maxStatic;
        variation += _variance[index];
        minX = math.min(minX, ix);
        maxX = math.max(maxX, ix);
        minZ = math.min(minZ, iz);
        maxZ = math.max(maxZ, iz);

        const List<List<int>> neighbours = <List<int>>[
          <int>[1, 0],
          <int>[-1, 0],
          <int>[0, 1],
          <int>[0, -1],
        ];
        for (final List<int> offset in neighbours) {
          final int nx = ix + offset[0];
          final int nz = iz + offset[1];
          if (nx < 0 || nz < 0 || nx >= cols || nz >= rows) continue;
          final int next = nz * cols + nx;
          if (!obstacle[next] || visited[next]) continue;
          visited[next] = true;
          queue.add(next);
        }
      }

      if (count < minClusterCells) continue;

      final double widthM = (maxX - minX + 1) * cellM;
      final double depthM = (maxZ - minZ + 1) * cellM;
      final double meanEnergy = energy / count;
      final double meanVariation = variation / count;
      final double confidence = NumUtils.clamp01(
        0.35 + meanEnergy * 0.45 + (1 - NumUtils.clamp01(meanVariation * 3)) * 0.2,
      );

      final ({FurnitureKind kind, PbrMaterial material}) classification =
          classifyCluster(
            widthM: widthM,
            depthM: depthM,
            touchesBorder: minX == 0 ||
                minZ == 0 ||
                maxX == cols - 1 ||
                maxZ == rows - 1,
          );

      objects.add(
        FurnitureObject(
          kind: classification.kind,
          centerX: (minX + maxX + 1) / 2 * cellM,
          centerZ: (minZ + maxZ + 1) / 2 * cellM,
          widthM: widthM,
          depthM: depthM,
          confidence: confidence,
          material: classification.material,
        ),
      );
    }

    objects.sort(
      (FurnitureObject a, FurnitureObject b) => b.areaM2.compareTo(a.areaM2),
    );
    _objects = objects.take(24).toList(growable: false);
  }

  /// تصنيف تجمّع واحد + اختيار خامة PBR مطابقة.
  ///
  /// دالة نقية قابلة للاختبار مباشرة بمعزل عن الشبكة.
  static ({FurnitureKind kind, PbrMaterial material}) classifyCluster({
    required double widthM,
    required double depthM,
    required bool touchesBorder,
  }) {
    final double longSide = math.max(widthM, depthM);
    final double shortSide = math.max(0.1, math.min(widthM, depthM));
    final double aspect = longSide / shortSide;
    final double area = widthM * depthM;

    if (touchesBorder && aspect >= 2.0 && shortSide <= 0.75) {
      if (shortSide <= 0.35) {
        return (kind: FurnitureKind.door, material: MaterialLibrary.oak);
      }
      return (kind: FurnitureKind.wall, material: MaterialLibrary.stone);
    }
    if (touchesBorder && shortSide <= 0.5) {
      return (kind: FurnitureKind.wall, material: MaterialLibrary.stone);
    }
    if (area >= 1.4 && aspect >= 1.5) {
      return (kind: FurnitureKind.sofa, material: MaterialLibrary.fabric);
    }
    if (area >= 1.8) {
      return (kind: FurnitureKind.bed, material: MaterialLibrary.linen);
    }
    if (area <= 0.3) {
      return (kind: FurnitureKind.plant, material: MaterialLibrary.ceramic);
    }
    // قطعة عميقة/ضيقة بمساحة صغيرة = خزانة أو رف (خشب داكن).
    if (shortSide <= 0.55 && area <= 0.75) {
      return (kind: FurnitureKind.cabinet, material: MaterialLibrary.walnut);
    }
    if (area <= 1.1) {
      return (kind: FurnitureKind.table, material: MaterialLibrary.oak);
    }
    return (kind: FurnitureKind.unknown, material: MaterialLibrary.marble);
  }

  RoomModel _buildModel() {
    double maxStatic = 0;
    for (final double value in _static) {
      maxStatic = math.max(maxStatic, value);
    }

    final List<RoomCell> cells = <RoomCell>[];
    for (int iz = 0; iz < rows; iz++) {
      for (int ix = 0; ix < cols; ix++) {
        final int index = iz * cols + ix;
        final double normalized = maxStatic > 0 ? _static[index] / maxStatic : 0;
        cells.add(
          RoomCell(
            ix: ix,
            iz: iz,
            staticEnergy: NumUtils.clamp01(normalized),
            dynamicEnergy: NumUtils.clamp01(_dynamic[index]),
            obstacle: maxStatic > 0 &&
                normalized >= staticThreshold &&
                _variance[index] <= 0.34 &&
                _dynamic[index] <= motionThreshold,
          ),
        );
      }
    }

    return RoomModel(
      cols: cols,
      rows: rows,
      cellM: cellM,
      cells: cells,
      objects: _objects,
      frames: _frames,
    );
  }
}
