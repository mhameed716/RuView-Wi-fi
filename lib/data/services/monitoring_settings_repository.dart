import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/gait_profile.dart';

/// حفظ إعدادات الرصد المتقدم: وضع الحراسة، رقم الطوارئ، بصمات المشية.
///
/// كل عملية فاشلة تعيد قيمة افتراضية آمنة بدل تعطيل التطبيق.
class MonitoringSettingsRepository {
  MonitoringSettingsRepository({SharedPreferences? preferences})
      : _preferences = preferences;

  static const String intrusionKey = 'ruview.monitoring.intrusion.v1';
  static const String emergencyNumberKey = 'ruview.monitoring.emergency.v1';
  static const String gaitProfilesKey = 'ruview.monitoring.gait.v1';

  /// رقم طوارئ افتراضي (الهلال الأحمر السعودي). قابل للتعديل من الواجهة.
  static const String defaultEmergencyNumber = '997';

  SharedPreferences? _preferences;
  bool? _intrusionCache;
  String? _emergencyCache;
  List<GaitProfile>? _gaitCache;

  Future<SharedPreferences?> _prefs() async {
    if (_preferences != null) return _preferences;
    try {
      _preferences = await SharedPreferences.getInstance();
      return _preferences;
    } catch (_) {
      return null;
    }
  }

  Future<bool> loadIntrusionArmed() async {
    final bool? cached = _intrusionCache;
    if (cached != null) return cached;
    final SharedPreferences? prefs = await _prefs();
    final bool value = prefs?.getBool(intrusionKey) ?? false;
    _intrusionCache = value;
    return value;
  }

  Future<bool> saveIntrusionArmed(bool value) async {
    _intrusionCache = value;
    final SharedPreferences? prefs = await _prefs();
    if (prefs == null) return false;
    try {
      return await prefs.setBool(intrusionKey, value);
    } catch (_) {
      return false;
    }
  }

  Future<String> loadEmergencyNumber() async {
    final String? cached = _emergencyCache;
    if (cached != null) return cached;
    final SharedPreferences? prefs = await _prefs();
    final String raw = (prefs?.getString(emergencyNumberKey) ?? '').trim();
    final String value = raw.isEmpty ? defaultEmergencyNumber : raw;
    _emergencyCache = value;
    return value;
  }

  Future<bool> saveEmergencyNumber(String number) async {
    final String cleaned = number.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) return false;
    _emergencyCache = cleaned;
    final SharedPreferences? prefs = await _prefs();
    if (prefs == null) return false;
    try {
      return await prefs.setString(emergencyNumberKey, cleaned);
    } catch (_) {
      return false;
    }
  }

  Future<List<GaitProfile>> loadGaitProfiles() async {
    final List<GaitProfile>? cached = _gaitCache;
    if (cached != null) return cached;

    final SharedPreferences? prefs = await _prefs();
    final String? raw = prefs?.getString(gaitProfilesKey);
    if (raw == null || raw.isEmpty) {
      _gaitCache = const <GaitProfile>[];
      return _gaitCache!;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        final List<GaitProfile> profiles = decoded
            .whereType<Map<Object?, Object?>>()
            .map(
              (Map<Object?, Object?> entry) => GaitProfile.fromJson(
                entry.map<String, dynamic>(
                  (Object? key, Object? value) =>
                      MapEntry<String, dynamic>('$key', value),
                ),
              ),
            )
            .toList(growable: false);
        _gaitCache = profiles;
        return profiles;
      }
    } catch (_) {
      // بيانات تالفة → ابدأ بقائمة فارغة.
    }
    _gaitCache = const <GaitProfile>[];
    return _gaitCache!;
  }

  Future<bool> saveGaitProfiles(List<GaitProfile> profiles) async {
    _gaitCache = profiles;
    final SharedPreferences? prefs = await _prefs();
    if (prefs == null) return false;
    try {
      final String encoded = jsonEncode(
        profiles.map((GaitProfile profile) => profile.toJson()).toList(),
      );
      return await prefs.setString(gaitProfilesKey, encoded);
    } catch (_) {
      return false;
    }
  }
}
