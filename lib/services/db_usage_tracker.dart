// ================================================================
// DbUsageTracker — lightweight per-app Firestore read/write counter
// ================================================================
// FIX: Nizam reported ~1k Firestore reads/hr in the Firebase Usage
// tab and wanted to know WHICH app (customer/hero/admin/seller) is
// responsible, to find the actual root cause of the read volume.
//
// Firebase's own Usage tab only shows PROJECT-WIDE totals — it has
// no per-app breakdown. True per-query attribution needs Cloud
// Functions + BigQuery export, which are unavailable on the Spark
// (free) plan this project runs on. This is a client-side
// approximation instead:
//
//   - Each app calls DbUsageTracker.instance.init('hero') (etc) once
//     at startup, tagging every count with that app's name.
//   - Call DbUsageTracker.instance.recordRead(n) / recordWrite(n) at
//     known hotspot call sites (heavy StreamBuilder listeners, big
//     .get() queries) — NOT a full interception layer, since the
//     Firestore SDK has no global read/write hook to attach to.
//   - Counts accumulate in memory and flush every 3 minutes (and on
//     app dispose) as a SINGLE batched FieldValue.increment() write
//     to db_usage_stats/{app}_{yyyy-mm-dd}_{HH} — one write per flush
//     interval per app, not one write per read, so the monitor
//     itself adds negligible cost.
//
// UPDATE (per Nizam's request for finer time ranges — "last 60
// minutes", "last 24 hours", pick-a-day — instead of only 1/7/30-day
// buckets): the doc key was widened from a per-DAY bucket to a
// per-HOUR bucket. This does NOT increase write cost — it's still
// exactly one write per 3-minute flush per app, just addressed to a
// different document key depending on the current hour. Each doc also
// stores a sortable `dateHour` string ("yyyy-MM-dd-HH") so the admin
// DB Monitor screen can run a single range query (one inequality
// filter, no composite index needed) instead of fetching the whole
// collection and filtering client-side — keeping the monitor itself
// cheap even as history accumulates over months.
//
// This is intentionally approximate (it only counts what's been
// instrumented, not literally every SDK call) — good enough to see
// which app's usage is trending up, which is what Nizam asked for.
// ================================================================
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class DbUsageTracker {
  DbUsageTracker._();
  static final DbUsageTracker instance = DbUsageTracker._();

  String? _appName;
  Timer? _flushTimer;
  int _pendingReads = 0;
  int _pendingWrites = 0;
  bool _initialized = false;

  static const Duration _flushInterval = Duration(minutes: 3);

  /// Call once at app startup, e.g. DbUsageTracker.instance.init('hero').
  /// appName should be one of: 'customer', 'hero', 'admin', 'seller'.
  void init(String appName) {
    if (_initialized) return;
    _initialized = true;
    _appName = appName;
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flush());
  }

  // NEW (Aug 11 2026 — Nizam: "yentha app la yentha screen database read
  // write ah unwanted ah use pannuthu-nu oru detailed report kidacha
  // database usage ah innum optimise pannalam").
  //
  // The tracker knew WHICH APP was spending reads but never WHICH SCREEN,
  // so a report could tell you "customer used 4,000 reads today" without
  // telling you where to go fix it. These per-screen buckets are
  // accumulated in memory alongside the existing totals and flushed in
  // the SAME single document write — so attribution costs zero extra
  // writes and cannot make the monitor itself expensive.
  final Map<String, int> _pendingScreenReads = <String, int>{};
  final Map<String, int> _pendingScreenWrites = <String, int>{};

  // NEW (Aug 12 2026 — Nizam: "high read/write volumes but cannot
  // pinpoint exactly which specific queries or actions are causing
  // them"): a `screen` name alone answers "which screen" but not
  // "which query on that screen" — a screen with 3 different listeners
  // all showed up as one indistinguishable number. [action] is an
  // optional free-text label for the specific query/listener (e.g.
  // 'listen_active_ping', 'fetch_ride_history') layered onto the SAME
  // screen bucket via a flat composite key ('screen::action') rather
  // than a second nested map — this keeps the existing screenReads/
  // screenWrites schema and FieldValue.increment() shape completely
  // unchanged (still one flat map, still one write per flush), and
  // matches the 'app · screen' string-join convention the Admin DB
  // Monitor screen already parses, so that screen only needs one more
  // split, not a new data shape.
  //
  // Fully backward compatible: every one of the ~16 existing call
  // sites that only pass `screen` keeps landing on a plain 'screen' key
  // exactly as before (no '::' suffix) — only NEW/updated call sites
  // that pass `action` get the richer key. Both key shapes coexist in
  // the same map and the UI (admin_db_usage_screen.dart) treats an
  // absent action as "generic"/unspecified.
  static String _key(String? screen, String? action) {
    final s = (screen == null || screen.trim().isEmpty) ? 'unattributed' : screen.trim();
    final a = action?.trim();
    return (a == null || a.isEmpty) ? s : '$s::$a';
  }

  /// Optional [screen] attributes this read to a named screen (e.g.
  /// 'dashboard', 'ride_search'). Existing callers that omit it keep
  /// working exactly as before and simply land in the 'unattributed'
  /// bucket — which is itself useful, since a large unattributed number
  /// tells you how much of the app still needs instrumenting.
  ///
  /// Optional [action]/query-type (e.g. 'listen_active_ping',
  /// 'fetch_ride_history') narrows the attribution further, down to the
  /// specific query/listener on that screen — see [_key] above.
  void recordRead([int count = 1, String? screen, String? action]) {
    if (!_initialized) return;
    _pendingReads += count;
    final key = _key(screen, action);
    _pendingScreenReads[key] = (_pendingScreenReads[key] ?? 0) + count;
  }

  void recordWrite([int count = 1, String? screen, String? action]) {
    if (!_initialized) return;
    _pendingWrites += count;
    final key = _key(screen, action);
    _pendingScreenWrites[key] = (_pendingScreenWrites[key] ?? 0) + count;
  }

  /// yyyy-MM-dd — used for the human-readable `date` field.
  String get _dateStr {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// yyyy-MM-dd-HH — sortable hour bucket key, used both as the doc ID
  /// suffix and stored as a field for range queries.
  String get _dateHourStr {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    return '${_dateStr}_$h';
  }

  Future<void> _flush() async {
    if (_appName == null) return;
    final reads = _pendingReads;
    final writes = _pendingWrites;
    if (reads == 0 && writes == 0) return;

    // Reset immediately (optimistic) so a slow/failed write doesn't
    // double-count on the next interval — worst case a flush is lost
    // on rare network failure, which is fine for an approximate monitor.
    _pendingReads = 0;
    _pendingWrites = 0;
    // Snapshot + clear the per-screen buckets under the same optimistic
    // reset as the totals above, so the two can never drift apart.
    final screenReads = Map<String, int>.from(_pendingScreenReads);
    final screenWrites = Map<String, int>.from(_pendingScreenWrites);
    _pendingScreenReads.clear();
    _pendingScreenWrites.clear();

    final dateHour = _dateHourStr;
    try {
      await FirebaseFirestore.instance
          .collection('db_usage_stats')
          .doc('${_appName}_$dateHour')
          .set({
        'app': _appName,
        'date': _dateStr,
        'hour': DateTime.now().hour,
        'dateHour': dateHour,
        'reads': FieldValue.increment(reads),
        'writes': FieldValue.increment(writes),
        // Nested per-screen maps, merged into the SAME document — still
        // exactly one write per flush regardless of how many screens
        // were active.
        if (screenReads.isNotEmpty)
          'screenReads':
              screenReads.map((k, v) => MapEntry(k, FieldValue.increment(v))),
        if (screenWrites.isNotEmpty)
          'screenWrites':
              screenWrites.map((k, v) => MapEntry(k, FieldValue.increment(v))),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true),);
    } catch (e) {
      // Swallow — this is a best-effort monitor, must never crash or
      // block the app it's instrumenting.
      if (kDebugMode) {
        debugPrint('DbUsageTracker flush failed: $e');
      }
    }
  }

  /// Optional: force an immediate flush (e.g. on app dispose).
  Future<void> flushNow() => _flush();

  void dispose() {
    _flushTimer?.cancel();
  }
}
