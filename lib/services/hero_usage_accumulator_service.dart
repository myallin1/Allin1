// ================================================================
// HeroUsageAccumulatorService — Allin1 Super App
// ================================================================
// Per Nizam's "App Infra Cost Recovery" architecture (replacing the
// flat % commission model entirely): heroes are charged a minimal,
// usage-proportional fee for server/database maintenance instead of a
// cut of their earnings. This class is the CLIENT-SIDE ACCUMULATOR half
// of that design — it tracks a hero's "active usage" (minutes spent
// Online, rides handled) purely in memory, with ZERO Firestore writes
// per minute. HeroWalletService.flushUsageCost() is what actually
// writes the accumulated cost to the wallet, and only gets called at
// two points: a ride completing, or the hero going Offline (see
// hero_ride_screen.dart / hero_home_screen.dart) — i.e. batched,
// exactly as instructed, so our own write costs never scale with
// elapsed time, only with genuine hero activity.
//
// Zero usage = zero cost falls out of this naturally: if a hero never
// opens the app, startSession() is never called, consumeActiveMinutes()
// returns 0, and flushUsageCost() early-returns without writing
// anything at all -- no daily recurring fee, no background job, no
// charge for time the hero was never in the app.
// ================================================================

class HeroUsageAccumulatorService {
  HeroUsageAccumulatorService._internal();
  static final HeroUsageAccumulatorService _instance =
      HeroUsageAccumulatorService._internal();
  factory HeroUsageAccumulatorService() => _instance;

  DateTime? _sessionStartedAt;
  int _ridesHandledSinceFlush = 0;

  /// Call when the hero flips Online (or the app resumes an already-Online
  /// session). Idempotent -- calling it again while a session is already
  /// running does NOT reset the clock, so a lifecycle-resume re-confirming
  /// "still online" never loses already-accrued minutes.
  void startSession() {
    _sessionStartedAt ??= DateTime.now();
  }

  /// Call once per ride the hero actually completes. Contributes the
  /// per-ride component of the token formula in HeroWalletService.
  void recordRideHandled() {
    _ridesHandledSinceFlush++;
  }

  /// Returns the active minutes accrued since the last flush (or since
  /// startSession(), whichever is more recent), and restarts the clock
  /// from now -- so a mid-session flush (a ride completing) never
  /// double-counts the same minutes on the next flush when the hero
  /// eventually goes Offline.
  double consumeActiveMinutes() {
    final startedAt = _sessionStartedAt;
    if (startedAt == null) return 0;
    final now = DateTime.now();
    final minutes = now.difference(startedAt).inSeconds / 60.0;
    _sessionStartedAt = now;
    return minutes < 0 ? 0 : minutes;
  }

  /// Returns the rides handled since the last flush and resets the
  /// counter.
  int consumeRidesHandled() {
    final count = _ridesHandledSinceFlush;
    _ridesHandledSinceFlush = 0;
    return count;
  }

  /// Call when the hero flips Offline (after a final flush has already
  /// been sent for the remaining minutes) -- fully stops the clock so no
  /// further minutes accrue while the hero isn't in an active session.
  void endSession() {
    _sessionStartedAt = null;
  }

  bool get hasActiveSession => _sessionStartedAt != null;
}
