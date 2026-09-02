// ================================================================
// usage_tracking_service.dart — Customer Usage Tracking (per Nizam's
// request, final pre-launch checking stage).
// ================================================================
// Lightweight, DB-read-efficient funnel counters: how many times the
// pre-login PWA landing page loaded, and how many times each app's
// APK download link was tapped. Both are single-document atomic
// increments (FieldValue.increment) — one write per event, never a
// read, and the admin-side viewer reads this ONE doc regardless of how
// many events have ever happened (no per-event documents, no growing
// collection to page through).
//
// The third funnel stage (signups) is deliberately NOT tracked here —
// it's already sitting in the `users` collection, and
// customer_usage_tracking_screen.dart reads its total via a single
// Firestore count() aggregation query (server-side count, one read
// regardless of collection size) rather than duplicating it into
// another counter that could drift out of sync.
//
// Errors are always swallowed silently (fire-and-forget) — a tracking
// failure must never block or visibly disrupt a real customer's
// download/visit.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import './firestore_usage_tracking.dart';

class UsageTrackingService {
  UsageTrackingService._();
  static final UsageTrackingService instance = UsageTrackingService._();

  DocumentReference<Map<String, dynamic>> get _doc => FirebaseFirestore
      .instance
      .collection('app_usage_stats')
      .doc('funnel');

  // Guards against double-counting a single page load (e.g. a hot
  // restart or a widget rebuild calling initState twice in debug mode).
  bool _landingVisitTrackedThisSession = false;

  /// `yyyy-MM-dd` bucket key for per-day counters.
  ///
  /// FIX (Aug 11 2026 — Nizam's request for "datewise, month wise filter
  /// option ... with real sync data" on Customer Usage Tracking): the
  /// funnel counters were LIFETIME TOTALS with no time dimension at all,
  /// so date/month filtering was literally impossible to compute from
  /// them — there was nothing to filter on. Each event now ALSO
  /// increments a per-day bucket under `daily.<yyyy-MM-dd>.<field>`,
  /// which is what makes real date/month ranges possible.
  ///
  /// Cost is unchanged in practice: both the lifetime field and the daily
  /// bucket are updated in the SAME single set(merge:true) call — still
  /// one write per event, still one document read to render everything.
  static String _dayKey([DateTime? when]) {
    final d = when ?? DateTime.now();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  Future<void> _bumpFunnel(String field) async {
    await _doc.set(<String, dynamic>{
      field: FieldValue.increment(1),
      'daily': <String, dynamic>{
        _dayKey(): <String, dynamic>{field: FieldValue.increment(1)},
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> trackLandingPageVisit() async {
    if (_landingVisitTrackedThisSession) return;
    _landingVisitTrackedThisSession = true;
    try {
      await _bumpFunnel('landingPageVisits');
    } catch (e) {
      debugPrint('[UsageTracking] trackLandingPageVisit failed: $e');
    }
  }

  /// [appVariant] must be one of 'customer' | 'hero' | 'admin' | 'seller'
  /// — matches every other appVariant convention in the codebase
  /// (UpdateService.fallbackApkUrl, DownloadAppBanner, etc.).
  Future<void> trackApkDownload(String appVariant) async {
    final field = switch (appVariant) {
      'hero' => 'download_hero',
      'admin' => 'download_admin',
      'seller' => 'download_seller',
      _ => 'download_customer',
    };
    try {
      await _bumpFunnel(field);
    } catch (e) {
      debugPrint('[UsageTracking] trackApkDownload($appVariant) failed: $e');
    }
  }

  // ================================================================
  // CUSTOMER DEMAND TRACKING (Aug 11 2026 — Nizam's request: "customer
  // athigama search panni pora place, athigama order podura hotel
  // names, athigama use pandra transport vehicles" — so we can point
  // the business at what customers actually want).
  // ================================================================
  // COST DESIGN (this is the whole reason it's shaped this way): every
  // counter lives as a nested map field inside ONE document,
  // app_usage_stats/customer_demand. Each tracked event is a single
  // atomic FieldValue.increment write with NO read, and the admin
  // screen reads exactly ONE document to render every chart — no
  // per-event documents, no growing collection to page through, and
  // crucially no cost growth as volume increases. On the Spark plan,
  // where 20K writes/day is a real ceiling, a naive
  // "one document per search event" design would have burned the
  // entire daily quota by itself.
  //
  // CARDINALITY GUARD: a Firestore document is capped at 1MB, so an
  // unbounded set of distinct keys could theoretically overflow it.
  // Keys are aggressively normalized below (lowercased, trimmed,
  // punctuation stripped, length-capped) to collapse "Surampatti ",
  // "surampatti" and "SURAMPATTI." into one bucket. For a single-city
  // launch this keeps the realistic key count in the hundreds — orders
  // of magnitude below the limit.
  DocumentReference<Map<String, dynamic>> get _demandDoc => FirebaseFirestore
      .instance
      .collection('app_usage_stats')
      .doc('customer_demand');

  /// Normalizes a free-text label into a stable, safe map key.
  /// Firestore map keys can't be empty and shouldn't carry punctuation
  /// that complicates later field-path access, so this strips it.
  static String? _normalizeKey(String? raw) {
    if (raw == null) return null;
    final cleaned = raw
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return null;
    // Cap length so one pathological input can't bloat the doc.
    return cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned;
  }

  Future<void> _incrementDemand(String category, String? rawKey) async {
    final key = _normalizeKey(rawKey);
    if (key == null) return;
    try {
      // Nested-map merge (rather than dot-notation field paths) so a key
      // containing unexpected characters can never be misread as a path
      // separator.
      await _demandDoc.set(<String, dynamic>{
        category: <String, dynamic>{key: FieldValue.increment(1)},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[UsageTracking] _incrementDemand($category/$key) failed: $e');
    }
  }

  /// Customer searched for / selected a pickup or drop location.
  Future<void> trackPlaceSearched(String? placeName) =>
      _incrementDemand('places', placeName);

  /// Customer placed an order with a specific hotel/restaurant/store.
  Future<void> trackHotelOrdered(String? hotelName) =>
      _incrementDemand('hotels', hotelName);

  /// Customer booked a specific transport category (bike/auto/car/etc).
  Future<void> trackVehicleBooked(String? vehicleType) =>
      _incrementDemand('vehicles', vehicleType);

  /// Customer opened a service category (food/grocery/taxi/hero booking).
  Future<void> trackServiceUsed(String? serviceName) =>
      _incrementDemand('services', serviceName);

  // ================================================================
  // ONE-TIME HISTORICAL BACKFILL (Nizam's chosen option, Aug 11 2026)
  // ================================================================
  // The incremental counters above only start from the first booking
  // after this build ships — which is why the Customer Demand screen
  // showed empty even though real ride/order history already exists.
  // This scans that history ONCE and seeds the counters, after which the
  // forward-only increments keep everything current.
  //
  // COST: this is the ONE genuinely read-heavy operation in the whole
  // analytics system — it reads every historical ride + service_request
  // (bounded by [limit] below). That's why it is admin-triggered and
  // explicitly one-shot rather than something that runs on app start or
  // on every screen open. After it runs once, viewing demand costs a
  // single document read forever.
  //
  // IDEMPOTENCE: writes a `backfilledAt` marker and refuses to run again
  // unless [force] is set. Without this guard, a second run would DOUBLE
  // every historical count (the increments are additive), silently
  // corrupting the numbers with no way to tell from the UI.
  Future<BackfillResult> backfillFromHistory({
    bool force = false,
    int limit = 3000,
  }) async {
    final existing = await _demandDoc.get();
    if (!force && (existing.data()?['backfilledAt'] != null)) {
      return const BackfillResult(
        skipped: true,
        message: 'Already backfilled. Use Force to run again '
            '(this will double existing historical counts).',
      );
    }

    // Accumulate everything in memory first, then write ONE document.
    // Writing per-event would cost thousands of writes and blow the
    // 20K/day Spark write budget on a single button tap.
    final places = <String, int>{};
    final hotels = <String, int>{};
    final vehicles = <String, int>{};
    final services = <String, int>{};

    void bump(Map<String, int> target, String? raw) {
      final key = _normalizeKey(raw);
      if (key == null) return;
      target[key] = (target[key] ?? 0) + 1;
    }

    var ridesScanned = 0;
    var requestsScanned = 0;

    final ridesSnap = await FirebaseFirestore.instance
        .collection('rides')
        .limit(limit)
        .trackedGet();
    for (final doc in ridesSnap.docs) {
      final d = doc.data();
      ridesScanned++;
      bump(places, d['pickupAddress'] as String?);
      bump(places, d['dropAddress'] as String?);
      bump(vehicles, d['vehicleType'] as String?);
      bump(services, 'taxi');
    }

    final reqSnap = await FirebaseFirestore.instance
        .collection('service_requests')
        .limit(limit)
        .trackedGet();
    for (final doc in reqSnap.docs) {
      final d = doc.data();
      requestsScanned++;
      bump(services, d['requestType'] as String?);
      final details = d['details'];
      if (details is Map) {
        bump(
            hotels,
            (details['hotelName'] ??
                details['sellerName'] ??
                details['storeName'] ??
                details['shopName'] ??
                details['restaurantName']) as String?,);
        bump(places, (details['pickupAddress'] ?? details['pickup']) as String?);
        bump(places, (details['dropAddress'] ?? details['drop']) as String?);
      }
    }

    // Merge additively so any counts already accumulated by the live
    // increments since deploy are preserved rather than overwritten.
    await _demandDoc.set(<String, dynamic>{
      'places': places.map((k, v) => MapEntry(k, FieldValue.increment(v))),
      'hotels': hotels.map((k, v) => MapEntry(k, FieldValue.increment(v))),
      'vehicles': vehicles.map((k, v) => MapEntry(k, FieldValue.increment(v))),
      'services': services.map((k, v) => MapEntry(k, FieldValue.increment(v))),
      'backfilledAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return BackfillResult(
      skipped: false,
      message: 'Backfilled $ridesScanned rides + $requestsScanned requests '
          '(${places.length} places, ${hotels.length} vendors, '
          '${vehicles.length} vehicles).',
    );
  }
}

class BackfillResult {
  const BackfillResult({required this.skipped, required this.message});
  final bool skipped;
  final String message;
}
