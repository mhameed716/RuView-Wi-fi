import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'lan_scanner.dart';

/// حفظ تفضيلات الشبكة: الاتصال التلقائي + آخر نقطة اتصال ناجحة.
///
/// فاشل بأمان: أي خطأ يعيد الافتراضي (الاتصال التلقائي مُفعّل).
class NetworkPreferencesRepository {
  NetworkPreferencesRepository({SharedPreferences? preferences})
      : _preferences = preferences;

  static const String autoConnectKey = 'ruview.network.autoconnect.v1';
  static const String lastEndpointKey = 'ruview.network.lastEndpoint.v1';

  SharedPreferences? _preferences;
  bool? _autoCache;
  LanCandidate? _endpointCache;

  Future<SharedPreferences?> _prefs() async {
    if (_preferences != null) return _preferences;
    try {
      _preferences = await SharedPreferences.getInstance();
      return _preferences;
    } catch (_) {
      return null;
    }
  }

  Future<bool> loadAutoConnect() async {
    final bool? cached = _autoCache;
    if (cached != null) return cached;
    final SharedPreferences? prefs = await _prefs();
    final bool value = prefs?.getBool(autoConnectKey) ?? true;
    _autoCache = value;
    return value;
  }

  Future<bool> saveAutoConnect(bool value) async {
    _autoCache = value;
    final SharedPreferences? prefs = await _prefs();
    if (prefs == null) return false;
    try {
      return await prefs.setBool(autoConnectKey, value);
    } catch (_) {
      return false;
    }
  }

  Future<LanCandidate?> loadLastEndpoint() async {
    final LanCandidate? cached = _endpointCache;
    if (cached != null) return cached;
    final SharedPreferences? prefs = await _prefs();
    final String? raw = prefs?.getString(lastEndpointKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      final LanCandidate candidate = LanCandidate.fromJson(decoded);
      if (candidate.host.isEmpty || candidate.port <= 0) return null;
      _endpointCache = candidate;
      return candidate;
    } catch (_) {
      return null;
    }
  }

  Future<bool> saveLastEndpoint(LanCandidate candidate) async {
    _endpointCache = candidate;
    final SharedPreferences? prefs = await _prefs();
    if (prefs == null) return false;
    try {
      return await prefs.setString(
        lastEndpointKey,
        jsonEncode(candidate.toJson()),
      );
    } catch (_) {
      return false;
    }
  }
}
