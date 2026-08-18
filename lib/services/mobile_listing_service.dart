// ================================================================
// MobileListingService — Allin1 Mobile Hub (Aug 18 2026)
// ================================================================
// Firestore access for phones that sellers are actually selling.
//
// STORAGE SHAPE
//   sellers/{sellerId}/mobile_listings/{listingId}
//
// Chosen to mirror the proven sellers/{id}/menu_items pattern so the
// security rules are a copy of a rule block that's already live and
// battle-tested (read: any authed user, write: owning seller or admin),
// and so a seller's listings are automatically scoped to them with no
// extra ownership field to police.
//
// READ COST — the reason browse uses collectionGroup
//   A customer browsing "all new mobiles in Erode" needs listings
//   across EVERY seller. The naive version is: read all mobile sellers,
//   then one subcollection query per seller — an N+1 that grows with
//   every shop that joins. `collectionGroup('mobile_listings')` answers
//   it in ONE query regardless of seller count.
//
//   Verified safe before choosing it: `mobile_listings` appears nowhere
//   else in the codebase, so the collection-group name is unique and
//   can't accidentally sweep in unrelated documents — the exact risk
//   that made cloudinary_orphan_scanner.dart avoid collectionGroup for
//   the generic name 'items'.
//
// WRITE COST
//   Listings are written only when a seller adds/edits a phone — a
//   handful of writes per shop per week, not per customer view.
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/mobile_models.dart';
import 'db_usage_tracker.dart';

class MobileListingService {
  MobileListingService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Sub-collection name. Must stay unique app-wide — see the
  /// collectionGroup note in this file's header before renaming or
  /// reusing this string anywhere else.
  static const String kSubcollection = 'mobile_listings';

  /// Hard cap per seller. Keeps one shop from flooding the browse grid
  /// (and keeps any single seller's read/write footprint bounded).
  static const int kMaxListingsPerSeller = 60;

  CollectionReference<Map<String, dynamic>> _refFor(String sellerId) =>
      _db.collection('sellers').doc(sellerId).collection(kSubcollection);

  // ── Seller side ────────────────────────────────────────────────

  /// Live list of one seller's own listings, for their dashboard.
  /// Scoped to a single seller's subcollection, so this is cheap.
  Stream<List<MobileListing>> streamSellerListings(String sellerId) {
    return _refFor(sellerId).snapshots().map((snap) {
      DbUsageTracker.instance
          .recordRead(snap.docs.length, 'seller_mobile_dashboard', 'my_listings');
      final items = snap.docs
          .map((d) => MobileListing.fromJson(d.data(), docId: d.id))
          .toList();
      // Sorted client-side (no orderBy) so no composite index is
      // needed — same convention as streamCustomerRequests.
      items.sort((a, b) {
        final at = a.createdAt;
        final bt = b.createdAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
      return items;
    });
  }

  Future<int> countSellerListings(String sellerId) async {
    final snap = await _refFor(sellerId).get();
    DbUsageTracker.instance
        .recordRead(snap.docs.length, 'seller_mobile_dashboard', 'count');
    return snap.docs.length;
  }

  /// Creates a listing. Returns the new doc id.
  ///
  /// Throws [StateError] when the seller is at [kMaxListingsPerSeller]
  /// so the UI can show a clear message instead of silently growing.
  Future<String> addListing(MobileListing listing) async {
    final existing = await countSellerListings(listing.sellerId);
    if (existing >= kMaxListingsPerSeller) {
      throw StateError(
        'You have reached the maximum of $kMaxListingsPerSeller listings. '
        'Please remove one before adding another.',
      );
    }
    final doc = _refFor(listing.sellerId).doc();
    await doc.set(<String, dynamic>{
      ...listing.toJson(),
      'id': doc.id,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> updateListing(MobileListing listing) async {
    await _refFor(listing.sellerId).doc(listing.id).update(<String, dynamic>{
      ...listing.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stock toggle only — a single tiny field write, which is what a
  /// seller does most often ("sold out" / "back in stock").
  Future<void> setInStock(String sellerId, String listingId, bool inStock) {
    return _refFor(sellerId).doc(listingId).update(<String, dynamic>{
      'inStock': inStock,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteListing(String sellerId, String listingId) {
    return _refFor(sellerId).doc(listingId).delete();
  }

  // ── Customer side ──────────────────────────────────────────────

  /// Every seller's listings of one condition ('new' or 'used'), in a
  /// single query.
  ///
  /// Deliberately a one-shot `.get()` rather than `.snapshots()`:
  /// a phone catalog does not need to update live on a customer's
  /// screen, and a standing listener across every seller would re-read
  /// on any shop's edit, for every customer with the tab open. The UI
  /// pairs this with pull-to-refresh.
  ///
  /// Equality filter only (`condition`), no orderBy — no composite
  /// index required. Sorting happens client-side.
  Future<List<MobileListing>> fetchListings({
    required String condition,
    int limit = 120,
  }) async {
    final snap = await _db
        .collectionGroup(kSubcollection)
        .where('condition', isEqualTo: condition)
        .limit(limit)
        .get();

    DbUsageTracker.instance.recordRead(
      snap.docs.length,
      'mobile_hub',
      condition == MobileCondition.used ? 'browse_used' : 'browse_new',
    );

    final items = snap.docs
        .map((d) => MobileListing.fromJson(d.data(), docId: d.id))
        .where((l) => l.inStock)
        .toList();

    // In-stock first is already handled by the filter above; sort by
    // newest so freshly added stock surfaces to the top.
    items.sort((a, b) {
      final at = a.createdAt;
      final bt = b.createdAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return items;
  }
}
