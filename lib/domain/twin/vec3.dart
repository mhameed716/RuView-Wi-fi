import 'dart:math' as math;

/// متجه/نقطة ثلاثية الأبعاد — أساس كل هندسة «التوأم الراديوي».
///
/// بلا أي اعتماد على Flutter، ليصبح كل الحساب الهندسي قابلًا للاختبار مباشرة.
class Vec3 {
  const Vec3(this.x, this.y, this.z);

  factory Vec3.fromJson(Object? json) {
    if (json is Map) {
      return Vec3(
        _toDouble(json['x']),
        _toDouble(json['y']),
        _toDouble(json['z']),
      );
    }
    if (json is List && json.length >= 3) {
      return Vec3(_toDouble(json[0]), _toDouble(json[1]), _toDouble(json[2]));
    }
    return zero;
  }

  static const Vec3 zero = Vec3(0, 0, 0);

  static const Vec3 up = Vec3(0, 1, 0);

  static const Vec3 forward = Vec3(0, 0, 1);

  final double x;
  final double y;
  final double z;

  Vec3 operator +(Vec3 other) => Vec3(x + other.x, y + other.y, z + other.z);

  Vec3 operator -(Vec3 other) => Vec3(x - other.x, y - other.y, z - other.z);

  Vec3 operator *(double scale) => Vec3(x * scale, y * scale, z * scale);

  Vec3 operator -() => Vec3(-x, -y, -z);

  double get length => math.sqrt(x * x + y * y + z * z);

  bool get isFinite => x.isFinite && y.isFinite && z.isFinite;

  double dot(Vec3 other) => x * other.x + y * other.y + z * other.z;

  Vec3 cross(Vec3 other) => Vec3(
        y * other.z - z * other.y,
        z * other.x - x * other.z,
        x * other.y - y * other.x,
      );

  Vec3 normalized() {
    final double len = length;
    if (len <= 1e-9) return zero;
    return Vec3(x / len, y / len, z / len);
  }

  double distanceTo(Vec3 other) => (this - other).length;

  Vec3 lerp(Vec3 other, double t) => Vec3(
        x + (other.x - x) * t,
        y + (other.y - y) * t,
        z + (other.z - z) * t,
      );

  /// امتداد شعاعي: يُستخدم لتوليد حلقات المجسّم حول محور العضو.
  Vec3 offset(Vec3 u, Vec3 v, double du, double dv) =>
      Vec3(x + u.x * du + v.x * dv, y + u.y * du + v.y * dv, z + u.z * du + v.z * dv);

  Map<String, dynamic> toJson() => <String, dynamic>{'x': x, 'y': y, 'z': z};

  List<double> toList() => <double>[x, y, z];

  @override
  bool operator ==(Object other) =>
      other is Vec3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() =>
      'Vec3(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}, ${z.toStringAsFixed(2)})';

  static double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}
