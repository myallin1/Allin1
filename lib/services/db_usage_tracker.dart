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

  void recordRead([int count = 1]) {
    if (!_initialized) return;
    _pendingReads += count;
  }

  void recordWrite([int count = 1]) {
    if (!_initialized) return;
    _pendingWrites += count;
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
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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
