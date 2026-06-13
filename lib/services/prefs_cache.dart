import 'package:shared_preferences/shared_preferences.dart';

class PrefsCache {
  PrefsCache._();

  static const _kUserName  = 'pref_user_name';
  static const _kUserRole  = 'pref_user_role';
  static const _kLastTab   = 'pref_last_tab';
  static const _kOnboarded = 'pref_onboarded';
  static const _kThemeKey  = 'pref_theme_key';
  static const _kLangCode  = 'pref_lang_code';

  static Future<void> saveUserMeta({required String name, required String role}) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUserName, name);
    await p.setString(_kUserRole, role);
  }

  static Future<({String name, String role})> loadUserMeta() async {
    final p = await SharedPreferences.getInstance();
    return (name: p.getString(_kUserName) ?? '', role: p.getString(_kUserRole) ?? 'customer');
  }

  static Future<void> saveLastTab(int index) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kLastTab, index);
  }

  static Future<int> loadLastTab() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kLastTab) ?? 0;
  }

  static Future<void> setOnboarded() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOnboarded, true);
  }

  static Future<bool> isOnboarded() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kOnboarded) ?? false;
  }

  static Future<void> saveThemeKey(String key) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kThemeKey, key);
  }

  static Future<String?> loadThemeKey() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kThemeKey);
  }

  static Future<void> saveLangCode(String code) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLangCode, code);
  }

  static Future<String?> loadLangCode() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kLangCode);
  }

  static Future<void> clearAll() async {
    final p = await SharedPreferences.getInstance();
    await p.clear();
  }
}
