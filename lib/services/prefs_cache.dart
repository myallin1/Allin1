import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PrefsCache {
  PrefsCache._();

  static const _kUserName  = 'pref_user_name';
  static const _kUserRole  = 'pref_user_role';
  static const _kLastTab   = 'pref_last_tab';
  static const _kOnboarded = 'pref_onboarded';
  static const _kThemeKey  = 'pref_theme_key';
  static const _kLangCode  = 'pref_lang_code';

  // Deep-screen breadcrumb (Aug 19 2026 — cold-start-after-kill UX
  // mitigation). Records the last *named* route pushed, plus its
  // JSON-serializable arguments and a timestamp, so a cold start can
  // optionally jump straight back to it after landing on the restored
  // tab instead of stranding the customer on the dashboard. Deliberately
  // separate keys from _kLastTab: the tab restore must never be blocked
  // or altered by breadcrumb failures.
  static const _kBreadcrumbRoute = 'pref_breadcrumb_route';
  static const _kBreadcrumbArgs  = 'pref_breadcrumb_args';
  static const _kBreadcrumbTs    = 'pref_breadcrumb_ts';

  static Future<void> saveBreadcrumb({
    required String route,
    Map<String, dynamic>? args,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBreadcrumbRoute, route);
    await p.setString(_kBreadcrumbArgs, args == null ? '' : jsonEncode(args));
    await p.setInt(_kBreadcrumbTs, DateTime.now().millisecondsSinceEpoch);
  }

  /// Returns null if there is no breadcrumb, or if it's older than
  /// [maxAge] (default 2 hours) — an old breadcrumb is more likely to
  /// point at stale/expired data than to be a helpful restore.
  static Future<({String route, Map<String, dynamic>? args})?> loadBreadcrumb({
    Duration maxAge = const Duration(hours: 2),
  }) async {
    final p = await SharedPreferences.getInstance();
    final route = p.getString(_kBreadcrumbRoute);
    if (route == null || route.isEmpty) return null;
    final ts = p.getInt(_kBreadcrumbTs);
    if (ts == null) return null;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    if (age > maxAge.inMilliseconds) return null;
    final rawArgs = p.getString(_kBreadcrumbArgs);
    Map<String, dynamic>? args;
    if (rawArgs != null && rawArgs.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawArgs);
        if (decoded is Map<String, dynamic>) args = decoded;
      } catch (_) {
        // Corrupt/incompatible payload — treat as no-args restore.
        args = null;
      }
    }
    return (route: route, args: args);
  }

  static Future<void> clearBreadcrumb() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kBreadcrumbRoute);
    await p.remove(_kBreadcrumbArgs);
    await p.remove(_kBreadcrumbTs);
  }

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
