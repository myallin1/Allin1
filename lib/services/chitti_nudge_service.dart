// ================================================================
// ChittiNudgeService — the ONE gate every proactive Chitti message
// must pass through, Aug 25 2026 ("Priority 2: Proactive Nudges")
// ================================================================
// Nizam's brief: Chitti should speak up unprompted sometimes ("your
// ride is 2 mins away", "should I reorder your usual?") — but every
// unprompted-AI feature has the same failure mode if nobody puts a
// ceiling on it: it starts useful and drifts into spam within a week,
// because each new trigger gets added independently with no memory of
// what every OTHER trigger already fired today.
//
// The fix is structural, not a discipline problem: no trigger site
// (dashboard cold-load, ride tracking, wherever the next one gets
// added) is allowed to call ChittiOverlayService directly. Every one
// of them calls tryFire() first, and only shows anything if it
// returns true. That means the anti-spam rules live in exactly one
// place and can never be silently bypassed by a new feature that
// forgot to check.
//
// FOUR RULES, ALL ENFORCED HERE:
//   1. Daily cap — kMaxNudgesPerDay total, no matter how many
//      different trigger conditions fire.
//   2. Global cooldown — kGlobalCooldown minimum gap between ANY two
//      nudges, even of different types, so two triggers can't stack
//      into a burst.
//   3. Per-type cooldown — each nudgeId gets its own minimum gap
//      (passed in by the caller, since "reorder your usual" and "ride
//      ETA" have very different natural repeat rates).
//   4. Delivery is always passive — this service only decides WHETHER
//      to speak; the caller is responsible for using
//      ChittiOverlayService.setCaption() (an ambient bubble) and
//      NEVER a dialog/snackbar/auto-opened chat panel. See that
//      method's own doc for why.
//
// WHY SharedPreferences AND NOT HIVE
// This is a handful of scalar values (a few timestamps + a counter),
// exactly the shape SharedPreferences is for — the "each service picks
// the store that matches its data" split HiveCache/ChittiOrderMemoryService
// already established: Hive for structured/growing data, prefs for a
// few flags. Also matches AuthPromptService's existing
// "last shown at" pattern for the same reason (see auth_prompt_service.dart).
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChittiNudgeService {
  ChittiNudgeService._();
  static final ChittiNudgeService instance = ChittiNudgeService._();

  static const int kMaxNudgesPerDay = 6;
  static const Duration kGlobalCooldown = Duration(minutes: 3);

  static const String _kGlobalLastAt = 'chitti_nudge_global_last_at';
  static const String _kDailyCountDate = 'chitti_nudge_daily_count_date';
  static const String _kDailyCount = 'chitti_nudge_daily_count';
  static const String _kMuted = 'chitti_nudge_muted';
  static const String _kPerTypePrefix = 'chitti_nudge_last_at_';

  /// Customer-facing kill switch — wire to a Settings toggle later if
  /// wanted. Muted by default changes nothing about the READ-ONLY tools
  /// or normal chat; it only stops UNPROMPTED messages.
  Future<bool> isMuted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kMuted) ?? false;
  }

  Future<void> setMuted(bool muted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMuted, muted);
  }

  /// The one gate. [nudgeId] is a short stable key ('reorder_usual',
  /// 'ride_eta_near') — [perTypeCooldown] is how long THIS specific
  /// nudge type must wait before it's allowed to repeat. Returns true
  /// only when every rule passes, and as a side effect records that a
  /// nudge is about to be shown — so callers should call this
  /// immediately before showing the caption, not speculatively earlier.
  Future<bool> tryFire(
    String nudgeId, {
    required Duration perTypeCooldown,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (prefs.getBool(_kMuted) ?? false) return false;

      final now = DateTime.now();

      // Rule 1: daily cap. The counter is keyed to a stored date string
      // so it resets naturally on the first nudge of a new day, with no
      // scheduled job needed.
      final todayKey = '${now.year}-${now.month}-${now.day}';
      final storedDate = prefs.getString(_kDailyCountDate);
      var todayCount = (storedDate == todayKey) ? (prefs.getInt(_kDailyCount) ?? 0) : 0;
      if (todayCount >= kMaxNudgesPerDay) return false;

      // Rule 2: global cooldown since ANY last nudge, any type.
      final globalLastMs = prefs.getInt(_kGlobalLastAt);
      if (globalLastMs != null) {
        final since = now.difference(DateTime.fromMillisecondsSinceEpoch(globalLastMs));
        if (since < kGlobalCooldown) return false;
      }

      // Rule 3: this nudgeId's own cooldown.
      final perTypeKey = '$_kPerTypePrefix$nudgeId';
      final perTypeLastMs = prefs.getInt(perTypeKey);
      if (perTypeLastMs != null) {
        final since = now.difference(DateTime.fromMillisecondsSinceEpoch(perTypeLastMs));
        if (since < perTypeCooldown) return false;
      }

      // Every rule passed — record and allow.
      todayCount += 1;
      await prefs.setString(_kDailyCountDate, todayKey);
      await prefs.setInt(_kDailyCount, todayCount);
      await prefs.setInt(_kGlobalLastAt, now.millisecondsSinceEpoch);
      await prefs.setInt(perTypeKey, now.millisecondsSinceEpoch);
      return true;
    } catch (e) {
      // Fail CLOSED, not open — a prefs read/write hiccup should mean
      // "stay quiet this time", never "nudge with no record of it",
      // which would defeat every rule above on the very next call.
      debugPrint('[ChittiNudgeService] tryFire failed, staying quiet: $e');
      return false;
    }
  }
}
