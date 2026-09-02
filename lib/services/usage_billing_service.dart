// ================================================================
// UsageBillingService — Monthly usage counts for seller/hero billing
// ================================================================
// DECISION (confirmed with Nizam): "usage" for billing purposes means
// completed orders (sellers) / completed rides+tasks (heroes) per
// month — not raw database-read tracking. This is simple, honest, and
// hard to game, and needs zero new tracking infrastructure since it's
// computed from data the app already writes.
//
// Scope note: today only 'catalog_food_order' service_requests carry a
// real sellerId (Hotel / Home Kitchen menu orders) — per Nizam's
// separate confirmed decision, Grocery and Electronics stay
// broadcast-only with no seller linkage, so they have no seller-level
// usage to count yet. If that changes later, extend
// getSellerCompletedOrderCount's requestType filter.
//
// Deliberately NOT a live listener — this is a periodic/monthly report,
// so each call is a one-time query, run on demand from the admin
// screen rather than continuously, to avoid adding to the read-cost
// problems fixed elsewhere this session.
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import './firestore_usage_tracking.dart';

class UsageBillingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Returns {sellerId: completedOrderCount} for all catalog_food_order
  /// sellers with at least one completed order in between monthStart and monthEnd (end exclusive).
  /// Single query (requestType + status equality, no composite index
  /// needed beyond what already exists), grouped client-side.
  Future<Map<String, int>> getSellerCompletedOrderCounts({
    required DateTime monthStart,
    required DateTime monthEnd,
  }) async {
    final snapshot = await _firestore
        .collection('service_requests')
        .where('requestType', isEqualTo: 'catalog_food_order')
        .where('status', isEqualTo: 'completed')
        .trackedGet();

    final counts = <String, int>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final updatedAt = (data['updatedAt'] as Timestamp?)?.toDate();
      if (updatedAt == null ||
          updatedAt.isBefore(monthStart) ||
          !updatedAt.isBefore(monthEnd)) {
        continue;
      }
      final details = data['details'] as Map<String, dynamic>?;
      final sellerId = details?['sellerId'] as String?;
      if (sellerId == null || sellerId.isEmpty) continue;
      counts[sellerId] = (counts[sellerId] ?? 0) + 1;
    }
    return counts;
  }

  /// Returns {heroId: completedCount} combining completed bike-taxi
  /// rides AND completed broadcast service_requests (hero_booking /
  /// custom_order / custom_food_order / grocery_order /
  /// catalog_food_order — any assignedHeroId) for between monthStart and monthEnd (end exclusive).
  //
  // FIX: this used to chain .where('status', isEqualTo: ...) with
  // .orderBy(<a DIFFERENT field>) on both queries below — that combo
  // (equality filter + orderBy on a field other than the one being
  // filtered) DOES require a Firestore composite index, unlike this
  // file's old comment claimed. Neither index existed, so every single
  // "Generate" tap failed with
  // [cloud_firestore/failed-precondition] The query requires an index.
  // The orderBy was never actually needed — results are only ever
  // grouped into counts client-side below, order doesn't matter for
  // correctness — so it's simply removed instead of creating 2 new
  // composite indexes for a report that runs once per admin click.
  Future<Map<String, int>> getHeroCompletedTaskCounts({
    required DateTime monthStart,
    required DateTime monthEnd,
  }) async {
    final counts = <String, int>{};

    final ridesSnapshot = await _firestore
        .collection('rides')
        .where('status', isEqualTo: 'completed')
        .trackedGet();
    for (final doc in ridesSnapshot.docs) {
      final data = doc.data();
      final completedAt = (data['completedAt'] as Timestamp?)?.toDate();
      if (completedAt == null ||
          completedAt.isBefore(monthStart) ||
          !completedAt.isBefore(monthEnd)) {
        continue;
      }
      final heroId = data['heroId'] as String?;
      if (heroId == null || heroId.isEmpty) continue;
      counts[heroId] = (counts[heroId] ?? 0) + 1;
    }

    final requestsSnapshot = await _firestore
        .collection('service_requests')
        .where('status', isEqualTo: 'completed')
        .trackedGet();
    for (final doc in requestsSnapshot.docs) {
      final data = doc.data();
      final updatedAt = (data['updatedAt'] as Timestamp?)?.toDate();
      if (updatedAt == null ||
          updatedAt.isBefore(monthStart) ||
          !updatedAt.isBefore(monthEnd)) {
        continue;
      }
      final heroId = data['assignedHeroId'] as String?;
      if (heroId == null || heroId.isEmpty) continue;
      counts[heroId] = (counts[heroId] ?? 0) + 1;
    }

    return counts;
  }
}
