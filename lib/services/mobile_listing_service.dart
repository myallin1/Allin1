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
    final page = await fetchListingsPage(condition: condition, limit: limit);
    return page.items;
  }

  /// Default page size. Twenty is roughly two screens of the grid on a
  /// phone — enough that the customer never sees the loader on a normal
  /// scroll, small enough that opening the tab costs 20 reads, not 120.
  static const int kPageSize = 20;

  /// One page of listings plus the cursor needed to ask for the next.
  ///
  /// PAGINATION SHAPE (Aug 19 2026, CTO audit — "Data Scaling").
  /// The audit framed the old single fetch as a performance risk; the
  /// sharper problem was correctness. It capped at 120 documents with
  /// no way to reach document 121, so once Erode's shops list past that
  /// point, real stock would simply have been invisible — silently, with
  /// no empty state and no error.
  ///
  /// Deliberately cursor-based (startAfterDocument), not offset-based:
  /// Firestore bills an offset as if it read every skipped document, so
  /// offset paging gets more expensive the further a customer scrolls.
  /// A cursor costs the same on page 10 as on page 1.
  ///
  /// Still an equality filter with NO orderBy, so this needs no
  /// composite index — Firestore falls back to ordering by document
  /// name, which is stable and therefore a safe cursor. The trade-off:
  /// "newest first" can only be applied WITHIN a page (see the sort
  /// below), not across the whole result set. Accepted on purpose —
  /// true global newest-first would require an orderBy('createdAt')
  /// composite index on a collection group, and the audit's own
  /// zero-breakage principle says not to add index requirements to a
  /// live query without a deploy to match.
  Future<MobileListingsPage> fetchListingsPage({
    required String condition,
    int limit = kPageSize,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    var query = _db
        .collectionGroup(kSubcollection)
        .where('condition', isEqualTo: condition)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snap = await query.get();

    DbUsageTracker.instance.recordRead(
      snap.docs.length,
      'mobile_hub',
      condition == MobileCondition.used ? 'browse_used' : 'browse_new',
    );

    final items = snap.docs
        .map((d) => MobileListing.fromJson(d.data(), docId: d.id))
        .where((l) => l.inStock)
        .toList();

    // Newest first within this page. Note this runs AFTER the inStock
    // filter, so a page can legitimately return fewer items than
    // `limit` while more pages still exist — which is exactly why
    // hasMore below is derived from the RAW doc count, not items.length.
    items.sort((a, b) {
      final at = a.createdAt;
      final bt = b.createdAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });

    return MobileListingsPage(
      items: items,
      lastDoc: snap.docs.isEmpty ? null : snap.docs.last,
      // A short page means Firestore had nothing more to give. Using the
      // raw doc count (not the filtered list) prevents a page made
      // entirely of out-of-stock phones from being read as "the end".
      hasMore: snap.docs.length == limit,
    );
  }
}

/// A page of browse results plus everything needed to request the next.
class MobileListingsPage {
  final List<MobileListing> items;

  /// Cursor for the next call. Null when the page came back empty.
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;

  /// False once Firestore returns a short page — the caller should stop
  /// asking rather than firing an endless tail of empty reads.
  final bool hasMore;

  const MobileListingsPage({
    required this.items,
    required this.lastDoc,
    required this.hasMore,
  });
}
