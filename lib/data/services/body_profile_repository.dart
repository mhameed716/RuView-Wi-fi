import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/twin/body_profile.dart';

/// حفظ/استرجاع «التوائم المسبقة» (بصمات القياسات الجسدية).
///
/// فاشل بأمان: بيانات تالفة → قائمة فارغة بدل تعطيل التطبيق.
class BodyProfileRepository {
  BodyProfileRepository({SharedPreferences? preferences})
      : _preferences = preferences;

  static const String storageKey = 'ruview.twin.bodyProfiles.v1';

  SharedPreferences? _preferences;
  List<BodyProfile>? _cache;

  Future<SharedPreferences?> _prefs() async {
    if (_preferences != null) return _preferences;
    try {
      _preferences = await SharedPreferences.getInstance();
      return _preferences;
    } catch (_) {
      return null;
    }
  }

  Future<List<BodyProfile>> load() async {
    final List<BodyProfile>? cached = _cache;
    if (cached != null) return cached;

    final SharedPreferences? prefs = await _prefs();
    final String? raw = prefs?.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      _cache = const <BodyProfile>[];
      return _cache!;
    }

    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        final List<BodyProfile> profiles = <BodyProfile>[];
        for (final Object? entry in decoded) {
          try {
            profiles.add(BodyProfile.fromJson(entry));
          } catch (_) {
            // تخطَّ السجلّ التالف واستمر.
          }
        }
        _cache = List<BodyProfile>.unmodifiable(profiles);
        return _cache!;
      }
    } catch (_) {
      // بيانات تالفة → ابدأ بقائمة فارغة.
    }

    _cache = const <BodyProfile>[];
    return _cache!;
  }

  Future<bool> save(List<BodyProfile> profiles) async {
    _cache = List<BodyProfile>.unmodifiable(profiles);
    final SharedPreferences? prefs = await _prefs();
    if (prefs == null) return false;
    try {
      final String encoded = jsonEncode(
        profiles.map((BodyProfile profile) => profile.toJson()).toList(),
      );
      return await prefs.setString(storageKey, encoded);
    } catch (_) {
      return false;
    }
  }
}
