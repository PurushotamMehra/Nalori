import 'package:shared_preferences/shared_preferences.dart';

class MetadataEnhancementPreferences {
  static const _enhanceBookDetailsOnlineKey =
      'setting_enhanceBookDetailsOnline';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _cachedPrefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<bool> loadEnhanceBookDetailsOnline() async {
    final prefs = await _cachedPrefs;
    return prefs.getBool(_enhanceBookDetailsOnlineKey) ?? false;
  }

  Future<void> setEnhanceBookDetailsOnline(bool value) async {
    final prefs = await _cachedPrefs;
    await prefs.setBool(_enhanceBookDetailsOnlineKey, value);
  }
}
