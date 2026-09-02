// ================================================================
// master_catalog_service.dart — admin CRUD + seller-facing read for
// the shared universal product catalog (see master_catalog_model.dart).
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/master_catalog_model.dart';
import 'firestore_usage_tracking.dart';
import 'hive_cache.dart';

class MasterCatalogService {
  MasterCatalogService._();
  static final MasterCatalogService instance = MasterCatalogService._();

  final CollectionReference<Map<String, dynamic>> _ref =
      FirebaseFirestore.instance.collection('master_catalog');

  // Catalog items change rarely (admin adds a new SKU maybe weekly) but
  // are read by every seller who opens "My Products" — a long TTL keeps
  // this a near-zero-cost read on the common path, matching this app's
  // existing catalog-cache philosophy (see HiveCache's own header
  // comment on kSellersList/kProductsList).
  static const Duration _kCatalogTtl = Duration(hours: 6);
  static String _cacheKey(String department) => 'master_catalog_$department';

  // ── Admin: full CRUD ─────────────────────────────────────────────
  Future<void> upsertItem(MasterCatalogItemModel item) async {
    await _ref.doc(item.id).set(item.toFirestore(), SetOptions(merge: true));
    // Invalidate — an admin edit must be visible to the next seller who
    // opens their products screen, not hidden behind a 6-hour cache.
    await HiveCache.evict(_cacheKey(item.department));
  }

  Future<void> deleteItem(String itemId, String department) async {
    await _ref.doc(itemId).delete();
    await HiveCache.evict(_cacheKey(department));
  }

  /// Admin's own management screen wants EVERY item (active or
  /// retired), unfiltered and always fresh — this is a low-frequency
  /// admin-only screen, not a customer/seller hot path, so no cache.
  Future<List<MasterCatalogItemModel>> listAllForAdmin(String department) async {
    final snap = await _ref
        .where('department', isEqualTo: department)
        .limit(500)
        .trackedGet();
    final items = snap.docs
        .map((d) => MasterCatalogItemModel.fromFirestore(d.data(), d.id))
        .toList()
      ..sort((a, b) => a.category.compareTo(b.category));
    return items;
  }

  // ── Seller: cached, active-only read ─────────────────────────────
  /// What seller_grocery_products_screen.dart browses to build its
  /// toggle list. Cache-first — mirrors CategoryGatewayService's own
  /// cache-first pattern exactly, just with a longer TTL since this
  /// content is centrally curated and changes far less often than a
  /// per-seller product list.
  Future<List<MasterCatalogItemModel>> listActiveForSeller(String department) async {
    try {
      final cached = await HiveCache.get<List>(_cacheKey(department));
      if (cached != null && cached.isNotEmpty) {
        return cached.map((e) {
          final map = Map<String, dynamic>.from(e as Map);
          return MasterCatalogItemModel.fromFirestore(map, map['id'] as String);
        }).toList();
      }
    } catch (e) {
      debugPrint('[MasterCatalogService] cache read failed (non-fatal): $e');
    }

    final snap = await _ref
        .where('department', isEqualTo: department)
        .where('isActive', isEqualTo: true)
        .limit(500)
        .trackedGet();
    final items = snap.docs
        .map((d) => MasterCatalogItemModel.fromFirestore(d.data(), d.id))
        .toList()
      ..sort((a, b) => a.category.compareTo(b.category));

    // FIX (same Hive-vs-Timestamp trap CategoryGatewayService's own
    // comments document at length): createdAt/updatedAt are Firestore
    // Timestamps, which Hive cannot serialise. Caching the raw map here
    // would throw and silently degrade every seller's catalog browse to
    // "always hits Firestore" — converting to ISO-8601 strings first
    // (read back fine, since fromFirestore only ever needs id/name/
    // department/category/unit/imageUrl/isActive for the seller-facing
    // path — createdAt/updatedAt aren't shown there) avoids that.
    try {
      final safeDocs = snap.docs
          .map((d) => {
                'id': d.id,
                'name': d.data()['name'],
                'department': d.data()['department'],
                'category': d.data()['category'],
                'unit': d.data()['unit'],
                'imageUrl': d.data()['imageUrl'],
                'isActive': d.data()['isActive'],
              })
          .toList();
      await HiveCache.put(_cacheKey(department), safeDocs, ttl: _kCatalogTtl);
    } catch (e) {
      debugPrint('[MasterCatalogService] cache write skipped (non-fatal): $e');
    }

    return items;
  }
}
