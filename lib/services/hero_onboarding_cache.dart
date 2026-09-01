// ================================================================
// hero_onboarding_cache.dart — local-only onboarding-status cache
// ================================================================
// NEW (Aug 12 2026 — Nizam: "user'oda onboarding status ah every app
// boot la query pannama, local cache vachu route pannanum... zero
// latency, zero DB read cost"): a thin SharedPreferences wrapper so
// main_hero.dart's boot gate, hero_register_screen.dart, and
// hero_pending_screen.dart all read/write the exact same key instead
// of each hardcoding their own string.
//
// This is explicitly an OPTIMIZATION, not the source of truth —
// Firestore's heroes/{uid}.approvalStatus remains the real state.
// Nothing here is ever trusted for security-sensitive decisions (the
// dashboard, dispatch, etc. all still gate on Firestore/claims); it
// only decides which screen to paint FIRST on boot, saving a read in
// the common case where nothing has changed since last launch. If the
// cache is ever wrong or missing, every call site here falls back to
// the existing Firestore-based gate, so it can never strand a hero.
import 'package:shared_preferences/shared_preferences.dart';

class HeroOnboardingCache {
  HeroOnboardingCache._();

  static const String _kKey = 'hero_onboarding_status';

  /// 'pending' | 'approved' | null (no cached status yet, or cleared).
  static Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kKey);
  }

  static Future<void> setPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, 'pending');
  }

  static Future<void> setApproved() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, 'approved');
  }

  /// Clears the cache — called on rejection/block (so a re-registration
  /// isn't blocked by a stale flag) and on sign-out.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }
}
