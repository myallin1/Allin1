// lib/services/pinned_shortcuts_service.dart
// ================================================================
// Lets a customer long-press any home-screen service category to pin
// it as a personal shortcut — shown in a compact "My Shortcuts" row
// that jumps straight to that service, no digging through the rest of
// the app to find it again.
//
// NEW (Sep 22 2026 — Nizam: "ovvoru feature and option-um shortcut app
// mari veliya vaikka option venum, athu long-press pannuna Hive cache-la
// save aagi... user kum disturb irukkatha fully user customisable").
//
// Deliberately its OWN small Hive box, not HiveCache (that class is a
// TTL-expiring cache for server data — a pinned shortcut must never
// silently expire and vanish on its own). Deliberately per-device only:
// this is a personal, throwaway convenience list, not account data that
// needs to sync across devices or survive a reinstall — same trade-off
// a real phone's home-screen widget makes.
//
// Deliberately opt-in and empty by default: nothing is ever pre-pinned,
// and the "My Shortcuts" row renders nothing at all (not even a gap)
// until the customer actually long-presses something themselves — see
// dashboard_screen.dart's _MyShortcutsBar. "Disturb the user" was the
// one thing explicitly ruled out for this feature.
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class PinnedShortcutsService extends ChangeNotifier {
  PinnedShortcutsService._();
  static final PinnedShortcutsService instance = PinnedShortcutsService._();

  static const _boxName = 'pinned_shortcuts_v1';
  static const _idsKey = 'ids';

  /// A real home-screen widget has finite space too — capping here
  /// keeps "My Shortcuts" a quick glance, not a second cluttered
  /// version of the app it exists to shortcut past.
  static const maxPinned = 8;

  List<String> _ids = <String>[];
  bool _loaded = false;

  /// Newest pin last, oldest first — matches the eviction order below.
  List<String> get pinnedIds => List.unmodifiable(_ids);

  bool get isLoaded => _loaded;

  bool isPinned(String tapId) => _ids.contains(tapId);

  Future<Box<dynamic>> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box<dynamic>(_boxName);
    // Idempotent/safe even if some other entry point already called
    // this — same pattern HiveCache uses for the same reason.
    await Hive.initFlutter();
    return Hive.openBox<dynamic>(_boxName);
  }

  /// Loads the saved pin list. Safe to call more than once — a caller
  /// that isn't sure whether this already ran can just call it again;
  /// the read is local-only and effectively free. A failed load leaves
  /// the shortcuts bar simply empty rather than crashing the home
  /// screen — pins are a convenience, never something worth a hard
  /// failure over.
  Future<void> load() async {
    try {
      final box = await _box();
      final raw = box.get(_idsKey);
      if (raw is List) {
        _ids = raw.whereType<String>().toList(growable: true);
      }
    } catch (e) {
      debugPrint('[PinnedShortcutsService] load failed: $e');
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    try {
      final box = await _box();
      await box.put(_idsKey, _ids);
    } catch (e) {
      debugPrint('[PinnedShortcutsService] persist failed: $e');
    }
  }

  /// Pins [tapId] if it isn't already pinned, or unpins it if it is.
  /// Returns true when the result is "now pinned", false for "now
  /// unpinned" — lets the caller show the right confirmation message
  /// off this call's own result instead of a second isPinned() check
  /// racing the mutation above it.
  Future<bool> toggle(String tapId) async {
    final wasPinned = _ids.remove(tapId);
    if (!wasPinned) {
      // New pin past the cap: drop the oldest one first, same
      // "most-recently-used wins" rule a real home-screen widget slot
      // would apply rather than silently refusing the new pin.
      if (_ids.length >= maxPinned) {
        _ids.removeAt(0);
      }
      _ids.add(tapId);
    }
    notifyListeners();
    await _persist();
    return !wasPinned;
  }
}
