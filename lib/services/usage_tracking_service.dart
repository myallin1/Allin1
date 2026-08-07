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

  Future<void> trackLandingPageVisit() async {
    if (_landingVisitTrackedThisSession) return;
    _landingVisitTrackedThisSession = true;
    try {
      await _doc.set(<String, dynamic>{
        'landingPageVisits': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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
      await _doc.set(<String, dynamic>{
        field: FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[UsageTracking] trackApkDownload($appVariant) failed: $e');
    }
  }
}
