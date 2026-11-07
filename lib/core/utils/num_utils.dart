import 'dart:math' as math;

/// أدوات مساعدة رقمية/زمنية مشتركة (بدون أي تبعيات خارجية).
abstract final class NumUtils {
  static double clamp01(double value) {
    if (value.isNaN) return 0.0;
    if (value < 0) return 0.0;
    if (value > 1) return 1.0;
    return value;
  }

  static double clampRange(double value, double min, double max) {
    if (value.isNaN) return min;
    return value < min ? min : (value > max ? max : value);
  }

  /// تحويل قيمة من نطاق إلى آخر بأمان.
  static double mapRange(
    double value,
    double inMin,
    double inMax,
    double outMin,
    double outMax,
  ) {
    if (inMax == inMin) return outMin;
    final double t = clamp01((value - inMin) / (inMax - inMin));
    return outMin + (outMax - outMin) * t;
  }

  /// صياغة نسبة مئوية بالعربية (بدون كسور غير مفيدة).
  static String percent(double ratio) => '${(clamp01(ratio) * 100).round()}%';

  /// صياغة رقم بمنزلة عشرية واحدة مع تجنب القيم التالفة.
  static String oneDecimal(double value) {
    if (value.isNaN || value.isInfinite) return '—';
    return value.toStringAsFixed(1);
  }

  /// صياغة عدد صحيح مع تجنب القيم التالفة.
  static String integer(num? value) {
    if (value == null || value.isNaN || value.isInfinite) return '—';
    return value.round().toString();
  }
}

/// متوسط متحرك بسيط (EMA) لتنعيم القراءات المتذبذبة مثل معدل التنفس.
class ExponentialMovingAverage {
  ExponentialMovingAverage({this.alpha = 0.25, double? initial})
      : _value = initial;

  /// معامل التنعيم: كلما صغر، كان التنعيم أقوى.
  final double alpha;
  double? _value;

  double? get value => _value;

  bool get hasValue => _value != null;

  double add(double sample) {
    if (sample.isNaN || sample.isInfinite) {
      return _value ?? 0;
    }
    final double? previous = _value;
    final double next = previous == null
        ? sample
        : previous + (sample - previous) * alpha;
    _value = next;
    return next;
  }

  void reset() => _value = null;
}

/// حلقة أرقام ثابتة الحجم تُستخدم للرسوم المصغّرة (sparkline).
class SampleRing {
  SampleRing(this.capacity) : assert(capacity > 1);

  final int capacity;
  final List<double> _values = <double>[];

  List<double> get values => List<double>.unmodifiable(_values);

  bool get isEmpty => _values.isEmpty;

  int get length => _values.length;

  void add(double value) {
    if (value.isNaN || value.isInfinite) return;
    _values.add(value);
    if (_values.length > capacity) {
      _values.removeRange(0, _values.length - capacity);
    }
  }

  void clear() => _values.clear();

  double get maxValue =>
      _values.isEmpty ? 0 : _values.reduce((double a, double b) => math.max(a, b));

  double get minValue =>
      _values.isEmpty ? 0 : _values.reduce((double a, double b) => math.min(a, b));
}

/// مؤقّت لتقييد تكرار الأحداث في السجل (debounce زمني بسيط).
class CooldownGate {
  CooldownGate(this.cooldown);

  final Duration cooldown;
  DateTime? _lastPass;

  bool tryPass(DateTime now) {
    final DateTime? last = _lastPass;
    if (last != null && now.difference(last) < cooldown) {
      return false;
    }
    _lastPass = now;
    return true;
  }

  void reset() => _lastPass = null;
}
