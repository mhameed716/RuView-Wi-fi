import 'dart:math' as math;

import '../../core/utils/num_utils.dart';
import 'body_shape.dart';
import 'vec3.dart';

/// محاكاة قماش/ملابس خفيفة (Verlet + قيود مسافة) تُلبَس على المجسّم.
///
/// الغرض: أن تتحرك الملابس مع حركة الجسم الحقيقية — تتأرجح عند المشي،
/// وتنضغط عند الجلوس — بدل سطح صلب «بلاستيكي».
///
/// الحساب كله في الفضاء المتري (متر/ثانية) وبلا Flutter، لذا يمكن اختبار
/// استقراره عدديًا.
class ClothSimulator {
  ClothSimulator({
    this.cols = defaultCols,
    this.rows = defaultRows,
    this.spacing = 0.058,
    this.iterations = 3,
    this.damping = 0.984,
    this.gravity = 6.4,
    this.maxOffset = 0.9,
  });

  /// أبعاد شبكة القماش الافتراضية (تُستخدم في الرسم أيضًا).
  static const int defaultCols = 7;
  static const int defaultRows = 5;

  final int cols;
  final int rows;

  /// المسافة بين جزيئين متجاورين (م).
  final double spacing;

  /// عدد تكرارات حلّ القيود في كل خطوة.
  final int iterations;

  /// تخميد السرعة (0..1) — يمنع الطنين.
  final double damping;

  /// تسارع الجذب (م/ث²) — أخف من الحقيقي ليبدو القماش خفيفًا.
  final double gravity;

  /// أقصى إزاحة مسموحة عن نقطة الارتساء (م) — حماية من الانفجار الرقمي.
  final double maxOffset;

  final List<Vec3> _points = <Vec3>[];
  final List<Vec3> _previous = <Vec3>[];
  final Set<int> _pinned = <int>{};
  List<int> _links = const <int>[];

  double _time = 0;

  bool get isReady => _points.length == cols * rows && _pinned.isNotEmpty;

  int get particleCount => _points.length;

  int get pinnedCount => _pinned.length;

  /// مواضع الجزيئات (صفًا صفًا) للرسم.
  List<Vec3> get particles => List<Vec3>.unmodifiable(_points);

  /// ارتساء القماش على الكتفين والصدر حسب شكل الجسم.
  void reset({required Map<String, Vec3> joints, required BodyShape shape}) {
    _points.clear();
    _previous.clear();
    _pinned.clear();
    _time = 0;

    final Vec3 left =
        joints['left_shoulder'] ?? Vec3(shape.shoulderM / 2, shape.heightM * 0.8, 0);
    final Vec3 right =
        joints['right_shoulder'] ?? Vec3(-shape.shoulderM / 2, shape.heightM * 0.8, 0);
    final Vec3 chest = joints['pelvis'] != null && joints['neck'] != null
        ? (joints['pelvis']! + joints['neck']!) * 0.5
        : Vec3(0, shape.heightM * 0.66, 0);

    final Vec3 across = (left - right);
    final Vec3 acrossUnit = across.normalized();
    final double width = math.max(0.2, across.length);

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final double t = cols == 1 ? 0.5 : c / (cols - 1);
        final Vec3 anchor = right + acrossUnit * (width * t);
        final double drop = r * spacing;
        final double depth = 0.045 + r * 0.012;
        final Vec3 point = Vec3(
          anchor.x * (1 - r * 0.05) + chest.x * r * 0.05,
          anchor.y - drop,
          anchor.z + depth,
        );
        _points.add(point);
        _previous.add(point);
        if (r == 0) _pinned.add(r * cols + c);
      }
    }

    final List<int> links = <int>[];
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final int index = r * cols + c;
        if (c + 1 < cols) links.addAll(<int>[index, index + 1]);
        if (r + 1 < rows) links.addAll(<int>[index, index + cols]);
      }
    }
    _links = links;
  }

  /// خطوة زمنية واحدة.
  ///
  /// [motion] شدّة حركة الشخص (0..1) وتُترجم إلى رياح خفيفة على القماش،
  /// و[dt] الفارق الزمني بالثواني.
  void step(double dt, {double motion = 0, Vec3 wind = Vec3.zero}) {
    if (!isReady) return;
    final double step = NumUtils.clampRange(dt, 0.001, 0.05);
    _time += step;

    final double drag = NumUtils.clamp01(motion) * 1.9;
    final double gust = math.sin(_time * 3.1) * 0.35 + 0.65;

    for (int i = 0; i < _points.length; i++) {
      if (_pinned.contains(i)) {
        _previous[i] = _points[i];
        continue;
      }
      final Vec3 current = _points[i];
      final Vec3 velocity = (current - _previous[i]) * damping;
      final Vec3 acceleration = Vec3(
        wind.x * drag + drag * 0.12 * gust,
        -gravity,
        wind.z * drag + drag * 0.18 * gust,
      );

      _previous[i] = current;
      _points[i] = current + velocity + acceleration * (step * step);
    }

    for (int iter = 0; iter < iterations; iter++) {
      _solveLinks();
      _clampBounds();
    }
  }

  /// إعادة القماش إلى الارتساء (عند تغيّر الوضعية أو ضياع الشخص).
  void settle() {
    for (int i = 0; i < _points.length; i++) {
      _previous[i] = _points[i];
    }
  }

  /// متوسط إزاحة الجزيئات الحرة عن مواضع ارتسائها — مؤشر «رفرفة» للعرض.
  double get flutter {
    if (!isReady) return 0;
    double total = 0;
    int count = 0;
    for (int i = 0; i < _points.length; i++) {
      if (_pinned.contains(i)) continue;
      total += (_points[i] - _previous[i]).length;
      count++;
    }
    return count == 0 ? 0 : total / count;
  }

  void _solveLinks() {
    for (int i = 0; i < _links.length; i += 2) {
      final int a = _links[i];
      final int b = _links[i + 1];
      final Vec3 pa = _points[a];
      final Vec3 pb = _points[b];
      final Vec3 delta = pb - pa;
      final double distance = delta.length;
      if (distance <= 1e-6) continue;

      final double difference = (distance - spacing) / distance;
      final Vec3 correction = delta * (difference * 0.5);

      final bool aPinned = _pinned.contains(a);
      final bool bPinned = _pinned.contains(b);
      if (aPinned && bPinned) continue;
      if (aPinned) {
        _points[b] = pb - correction * 2;
      } else if (bPinned) {
        _points[a] = pa + correction * 2;
      } else {
        _points[a] = pa + correction;
        _points[b] = pb - correction;
      }
    }
  }

  void _clampBounds() {
    for (int i = 0; i < _points.length; i++) {
      final Vec3 point = _points[i];
      if (!point.isFinite) {
        _points[i] = _previous[i];
        continue;
      }
      _points[i] = Vec3(
        NumUtils.clampRange(point.x, -maxOffset, maxOffset),
        math.max(0.02, NumUtils.clampRange(point.y, -maxOffset, 2.2)),
        NumUtils.clampRange(point.z, -maxOffset, maxOffset),
      );
    }
  }
}
