/// أدوات تحويل آمنة للقيم القادمة من JSON.
///
/// البوابات المختلفة (الخادم الرسمي، ESP32، بوابات جهات أخرى) تُرسل أحيانًا
/// أرقامًا كنصوص، أو `null`، أو حقولًا ناقصة. هذه الأدوات تمنع انهيار التحليل
/// وتحافظ على قيم افتراضية معقولة.
abstract final class JsonRead {
  static double asDouble(Object? value, [double fallback = 0.0]) {
    if (value is num) {
      final double v = value.toDouble();
      return v.isFinite ? v : fallback;
    }
    if (value is String) {
      final double? parsed = double.tryParse(value);
      if (parsed != null && parsed.isFinite) return parsed;
    }
    return fallback;
  }

  static double? asOptionalDouble(Object? value) {
    if (value == null) return null;
    if (value is num) {
      final double v = value.toDouble();
      return v.isFinite ? v : null;
    }
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int asInt(Object? value, [int fallback = 0]) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static int? asOptionalInt(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static bool asBool(Object? value, [bool fallback = false]) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final String v = value.toLowerCase().trim();
      if (v == 'true' || v == '1' || v == 'yes') return true;
      if (v == 'false' || v == '0' || v == 'no') return false;
    }
    return fallback;
  }

  static String asString(Object? value, [String fallback = '']) {
    if (value == null) return fallback;
    if (value is String) return value;
    return value.toString();
  }

  static Map<String, dynamic> asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map<String, dynamic>(
        (Object? key, Object? val) =>
            MapEntry<String, dynamic>(key.toString(), val),
      );
    }
    return const <String, dynamic>{};
  }

  static List<Map<String, dynamic>> asMapList(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .map(JsonRead.asMap)
        .where((Map<String, dynamic> map) => map.isNotEmpty)
        .toList(growable: false);
  }

  static List<double> asDoubleList(Object? value) {
    if (value is! List) return const <double>[];
    return value
        .map((Object? item) => asDouble(item))
        .where((double v) => v.isFinite)
        .toList(growable: false);
  }
}
