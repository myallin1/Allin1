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
  factory HeroUsageAccumulatorService() => _instance;
  HeroUsageAccumulatorService._internal();
  static final HeroUsageAccumulatorService _instance =
      HeroUsageAccumulatorService._internal();

  DateTime? _sessionStartedAt;
  // FIX (Hero Earnings & Online Time Monitor, Aug 11 2026, per Nizam):
  // _sessionStartedAt above gets reset on every consumeActiveMinutes()
  // call (mid-session ride-completion flushes), so it can never answer
  // "when did this online period actually begin" by the time the hero
  // goes offline. This second timestamp is set once per online toggle
  // (same idempotent ??= as startSession()) and is ONLY ever cleared
  // by endSession() — never touched by consumeActiveMinutes() — so it
  // survives the whole online period intact for logging one
  // hero_sessions doc (see hero_home_screen.dart's offline-toggle
  // flow).
  DateTime? _trueSessionStartedAt;
  int _ridesHandledSinceFlush = 0;
  // FIX (Dynamic Micro-Billing, Aug 11 2026, per Nizam): rides now bill
  // their infra-fee component by distance instead of a flat rate — see
  // HeroWalletService.flushUsageCost(). Only ACTUAL rides push a value
  // here (hero_ride_screen.dart passes the same billedDistanceKm the
  // customer's fare was computed from); service_requests still call
  // recordRideHandled() with no distance, so they fall through to the
  // unchanged flat per-task rate. This list and _ridesHandledSinceFlush
  // are deliberately kept in sync: every distance pushed here also
  // increments the count, so `ridesHandled - distances.length` in
  // flushUsageCost() correctly isolates the flat-rate (task) portion.
  final List<double> _rideDistancesSinceFlush = [];

  /// Call when the hero flips Online (or the app resumes an already-Online
  /// session). Idempotent -- calling it again while a session is already
  /// running does NOT reset the clock, so a lifecycle-resume re-confirming
  /// "still online" never loses already-accrued minutes.
  void startSession() {
    // NOTE: this starts the ONLINE-TIME clock (used for the hero's own
    // "online time" stat and the hero_sessions log). It no longer starts
    // a BILLING clock — see _workStartedAt below.
    _sessionStartedAt ??= DateTime.now();
    _trueSessionStartedAt ??= DateTime.now();
  }

  // ================================================================
  // BILLABLE WORK CLOCK (Aug 17 2026)
  // ================================================================
  // Nizam: "heros namma app kulla summa iruntha avanagaluku bill
  // agakudathu... hero ride and yenna service yeduthu follow pandraro
  // apo mattum".
  //
  // Before this, billable minutes were the SAME clock as online minutes:
  // a hero who flipped Online and then waited two hours for a booking
  // was billed for two hours of doing nothing. That is indefensible to
  // the hero and it punishes exactly the behaviour we want (staying
  // online and available).
  //
  // Now a separate clock that runs ONLY between accepting a job and
  // finishing it. Waiting is free; working is metered.
  //
  // Kept as its own field rather than reusing _sessionStartedAt because
  // the online-time stat still needs the full online period — the hero's
  // earnings screen shows "online time", and that number should not
  // shrink just because we stopped billing for idle time.
  DateTime? _workStartedAt;
  double _billableMinutesSinceFlush = 0;

  /// Call when the hero ACCEPTS a ride or service request.
  /// Idempotent — a re-confirm while already working does not restart
  /// the clock and so cannot lose accrued time.
  void startBillableWork() {
    _workStartedAt ??= DateTime.now();
  }

  /// Call when the ride/task ends (completed, cancelled or released).
  /// Banks the elapsed time and stops the clock, so nothing accrues
  /// while the hero waits for the next job.
  void stopBillableWork() {
    final startedAt = _workStartedAt;
    if (startedAt == null) return;
    final mins = DateTime.now().difference(startedAt).inSeconds / 60.0;
    if (mins > 0) _billableMinutesSinceFlush += mins;
    _workStartedAt = null;
  }

  /// Billable minutes accrued since the last flush. Includes any time
  /// still running on an open job, so a flush mid-job is accurate.
  double consumeBillableMinutes() {
    // Bank whatever is currently running, then restart that clock from
    // now — same no-double-count discipline as consumeActiveMinutes().
    final startedAt = _workStartedAt;
    if (startedAt != null) {
      final mins = DateTime.now().difference(startedAt).inSeconds / 60.0;
      if (mins > 0) _billableMinutesSinceFlush += mins;
      _workStartedAt = DateTime.now();
    }
    final out = _billableMinutesSinceFlush;
    _billableMinutesSinceFlush = 0;
    return out < 0 ? 0 : out;
  }

  /// When this online period truly began — unlike [_sessionStartedAt],
  /// never reset by a mid-session flush. Null if not currently online.
  DateTime? get trueSessionStartedAt => _trueSessionStartedAt;

  /// Call once per ride/task the hero actually completes. Contributes
  /// the per-ride/per-task component of the token formula in
  /// HeroWalletService.
  ///
  /// [distanceKm] — pass the ride's billed distance for actual rides
  /// (hero_ride_screen.dart already computes this for the customer's
  /// fare — reuse the same number). Leave it null/omitted for
  /// service_requests (Hero Booking, Custom Order, etc.), which have no
  /// distance concept and should keep billing at the flat per-task
  /// rate.
  void recordRideHandled({double? distanceKm}) {
    _ridesHandledSinceFlush++;
    if (distanceKm != null) {
      _rideDistancesSinceFlush.add(distanceKm < 0 ? 0 : distanceKm);
    }
  }

  /// Returns the active minutes accrued since the last flush (or since
  /// startSession(), whichever is more recent), and restarts the clock
  /// from now -- so a mid-session flush (a ride completing) never
  /// double-counts the same minutes on the next flush when the hero
  /// eventually goes Offline.
  /// NO LONGER USED FOR BILLING (Aug 17 2026).
  ///
  /// This returns ONLINE minutes — the whole period the hero was
  /// available, including waiting. Billing now uses
  /// [consumeBillableMinutes] instead, which only counts time spent on
  /// an accepted job (Nizam: "summa iruntha bill agakudathu").
  ///
  /// Kept, not deleted, because "how long was this hero online" is still
  /// a real question — but do NOT wire it back into flushUsageCost() or
  /// idle time starts being charged again. The hero_sessions online-time
  /// log deliberately computes its own duration from
  /// [trueSessionStartedAt] rather than calling this, so it is unaffected
  /// by the billing change.
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

  /// Returns the billed distance (km) of every actual ride handled
  /// since the last flush, and clears the list. Does NOT include
  /// service_requests — those never call recordRideHandled() with a
  /// distance in the first place.
  List<double> consumeRideDistances() {
    final list = List<double>.from(_rideDistancesSinceFlush);
    _rideDistancesSinceFlush.clear();
    return list;
  }

  /// Call when the hero flips Offline (after a final flush has already
  /// been sent for the remaining minutes) -- fully stops the clock so no
  /// further minutes accrue while the hero isn't in an active session.
  void endSession() {
    _sessionStartedAt = null;
    _trueSessionStartedAt = null;
  }

  bool get hasActiveSession => _sessionStartedAt != null;
}
