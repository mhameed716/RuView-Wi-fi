import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/connection_settings.dart';

/// حفظ واسترجاع إعدادات الاتصال على الجهاز.
///
/// التصميم مقصود ليكون فاشلًا بأمان: أي خطأ في التخزين يعيد الإعدادات
/// الافتراضية بدل أن يمنع التطبيق من العمل.
class SettingsRepository {
  SettingsRepository({SharedPreferences? preferences}) : _preferences = preferences;

  static const String storageKey = 'ruview.connection.settings.v1';

  SharedPreferences? _preferences;
  ConnectionSettings? _cache;

  Future<SharedPreferences?> _prefs() async {
    if (_preferences != null) return _preferences;
    try {
      _preferences = await SharedPreferences.getInstance();
      return _preferences;
    } catch (_) {
      return null;
    }
  }

  Future<ConnectionSettings> load() async {
    final ConnectionSettings? cached = _cache;
    if (cached != null) return cached;

    final SharedPreferences? prefs = await _prefs();
    final String? raw = prefs?.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      final ConnectionSettings defaults = const ConnectionSettings();
      _cache = defaults;
      return defaults;
    }

    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final ConnectionSettings settings = ConnectionSettings.fromJson(decoded);
        _cache = settings.isValid ? settings : const ConnectionSettings();
        return _cache!;
      }
      if (decoded is Map) {
        final ConnectionSettings settings = ConnectionSettings.fromJson(
          decoded.map<String, dynamic>(
            (Object? key, Object? value) =>
                MapEntry<String, dynamic>('$key', value),
          ),
        );
        _cache = settings.isValid ? settings : const ConnectionSettings();
        return _cache!;
      }
    } catch (_) {
      // بيانات تالفة → تجاهل واستخدم الافتراضي.
    }

    final ConnectionSettings fallback = const ConnectionSettings();
    _cache = fallback;
    return fallback;
  }

  Future<bool> save(ConnectionSettings settings) async {
    _cache = settings;
    final SharedPreferences? prefs = await _prefs();
    if (prefs == null) return false;
    try {
      return await prefs.setString(storageKey, jsonEncode(settings.toJson()));
    } catch (_) {
      return false;
    }
  }

  Future<bool> clear() async {
    _cache = null;
    final SharedPreferences? prefs = await _prefs();
    if (prefs == null) return false;
    try {
      return await prefs.remove(storageKey);
    } catch (_) {
      return false;
    }
  }
}
