// lib/services/service_requests_listener.dart
//
// FIX (cross-screen listener consolidation): SuperAdminHomeScreen,
// AdminDashboardScreen, and AdminNewOrdersScreen each independently
// opened their own live Firestore listener against `service_requests`
// with overlapping filters (pending/admin_review, admin_review-only,
// admin_review-only+orderBy). Since AdminDashboardScreen and
// AdminNewOrdersScreen are both reached via Navigator.push FROM
// SuperAdminHomeScreen (which stays alive underneath, not replaced),
// all three listeners were open simultaneously for the whole time an
// admin navigates around — 3x the reads for what is, at the Firestore
// query-shape level, the exact same superset query.
//
// This singleton opens ONE real `.snapshots()` listener for the
// broadest shape (`status whereIn ['pending', 'admin_review']`,
// SuperAdminHomeScreen's original query — the other two screens' filters
// are each a strict subset of this one). Every screen that needs the
// pending/admin_review data now consumes THIS shared, cached, broadcast
// stream and — where they need a narrower subset (admin_review only) or
// a different sort (createdAt desc) — do that filtering/sorting
// client-side on the docs they receive, instead of opening another
// server-side listener.
import 'package:cloud_firestore/cloud_firestore.dart';

class ServiceRequestsListener {
  ServiceRequestsListener._();
  static final ServiceRequestsListener instance = ServiceRequestsListener._();

  Stream<QuerySnapshot<Map<String, dynamic>>>? _waitingAndReviewStream;

  /// Shared live listener for `service_requests` where
  /// `status` is `pending` or `admin_review`. Lazily created on first
  /// access, cached for the lifetime of the app, and broadcast so any
  /// number of screens/widgets can subscribe without opening a new
  /// server-side query each time.
  Stream<QuerySnapshot<Map<String, dynamic>>> get waitingAndReviewStream {
    return _waitingAndReviewStream ??= FirebaseFirestore.instance
        .collection('service_requests')
        .where('status', whereIn: ['pending', 'admin_review'])
        .snapshots()
        .asBroadcastStream();
  }
}
