// ================================================================
// Category Gateway Service — Allin1 Super App
// Lazy-load category data with cache-first strategy
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'cache_service.dart';

enum Category {
  bikeTaxi,
  food,
  grocery,
  tech,
  pharmacy,
  carTaxi,
}

class CategoryGatewayService {
  static final CategoryGatewayService _instance =
      CategoryGatewayService._internal();
  factory CategoryGatewayService() => _instance;
  CategoryGatewayService._internal();

  final CacheService _cache = CacheService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── Category to Firestore Collection Mapping ───────────────
  String _getCategoryCollection(Category category) {
    switch (category) {
      case Category.bikeTaxi:
        return 'rides';
      case Category.food:
        return 'sellers';
      case Category.grocery:
        return 'sellers';
      case Category.tech:
        return 'sellers';
      case Category.pharmacy:
        return 'sellers';
      case Category.carTaxi:
        return 'rides';
    }
  }

  String _getCategoryFilter(Category category) {
    switch (category) {
      case Category.bikeTaxi:
        return 'bike_taxi';
      case Category.food:
        return 'food';
      case Category.grocery:
        return 'grocery';
      case Category.tech:
        return 'tech';
      case Category.pharmacy:
        return 'pharmacy';
      case Category.carTaxi:
        return 'car_taxi';
    }
  }

  // ── Load Category Data (Cache-First Strategy) ───────────────
  Future<List<Map<String, dynamic>>> loadCategoryData(Category category) async {
    try {
      final categoryKey = _getCategoryFilter(category);

      // STEP 1: Check cache first
      final cachedSellers = _cache.getSellers(categoryKey);
      if (cachedSellers != null && cachedSellers.isNotEmpty) {
        return cachedSellers;
      }

      // STEP 2: Cache miss — fetch from Firestore
      //
      // FIX (same root cause as loadSellerProducts below, and the
      // usage_billing_service.dart index issue fixed earlier this
      // session): combining two equality .where() clauses with
      // .orderBy() on a THIRD field (rating) requires a deployed
      // Firestore composite index. No firestore.indexes.json exists in
      // this repo, so that index isn't guaranteed to exist on the live
      // project — if it's missing, Firestore throws
      // failed-precondition: requires an index, and the old
      // catch (e) { return []; } below silently swallowed it. Every
      // correctly-registered seller (hotel/menu created fine on the
      // seller side) would render as an empty hotel list on the
      // customer's food category browse screen, with zero visible
      // error — exactly the reported "seller creates hotel, customer
      // can't see/order from it" symptom. Removed orderBy and sort
      // client-side instead (capped at 50 results, cheap to sort).
      final snapshot = await _firestore
          .collection(_getCategoryCollection(category))
          .where('category', isEqualTo: _getCategoryFilter(category))
          .where('status', isEqualTo: 'active')
          .limit(50)
          .get();

      final sellers = snapshot.docs
          .map(
            (doc) => {
              'id': doc.id,
              ...doc.data(),
            },
          )
          .toList()
        ..sort((a, b) => ((b['rating'] as num?) ?? 0).compareTo((a['rating'] as num?) ?? 0));

      // STEP 3: Update cache
      //
      // Same Timestamp trap as loadSellerProducts below, and the same
      // two-part fix — see the long comment there. This is the one that
      // broke the SELLER LIST: seller docs carry createdAt/updatedAt as
      // Firestore Timestamps (SellerModel.toJson writes them), Hive
      // cannot serialise those, and the throw propagated out of a
      // successful read. Sanitise, and never let a cache write take down
      // a fetch that already succeeded.
      try {
        await _cache.cacheSellers(categoryKey, _hiveSafe(sellers));
      } catch (e) {
        debugPrint('[CategoryGateway] seller cache write skipped: $e');
      }

      return sellers;
    } catch (e) {
      // FIX: rethrow instead of silently returning [] -- same reasoning
      // as loadSellerProducts' fix below. A genuinely-empty category
      // (no sellers yet) and a crashed query (missing index,
      // permission-denied, offline) used to render as the exact same
      // "no sellers" empty state, making this bug invisible without
      // direct Firestore Console access. Callers should catch this and
      // show a real "Failed to load" + Retry state, matching
      // seller_detail_screen.dart's existing pattern for
      // loadSellerProducts.
      rethrow;
    }
  }

  // ── Load Seller Products (Cache-First Strategy) ─────────────
  /// Deep-converts Firestore-only types into Hive/JSON-safe primitives.
  ///
  /// Hive has no adapter for Firestore's `Timestamp`, `GeoPoint` or
  /// `DocumentReference`, and throws
  /// `HiveError: Cannot write, unknown type: ...` on any of them. Under
  /// dart2js the type name is minified ('minified:iC'), which is why the
  /// error message alone did not name Timestamp.
  ///
  /// Timestamps become ISO-8601 strings — the same representation
  /// ServiceRequestModel.toJson uses for its Hive round-trip, so a
  /// cached value reads back through the same flexible parsers already
  /// in this codebase.
  ///
  /// Recurses into nested maps/lists: a menu item's `variants` list
  /// holds maps, and a future field could nest deeper still.
  static dynamic _hiveSafeValue(dynamic v) {
    if (v is Timestamp) return v.toDate().toIso8601String();
    if (v is DateTime) return v.toIso8601String();
    if (v is GeoPoint) return {'lat': v.latitude, 'lng': v.longitude};
    if (v is DocumentReference) return v.path;
    if (v is Map) {
      return v.map<String, dynamic>(
          (k, val) => MapEntry(k.toString(), _hiveSafeValue(val)));
    }
    if (v is List) return v.map(_hiveSafeValue).toList();
    return v;
  }

  static List<Map<String, dynamic>> _hiveSafe(
    List<Map<String, dynamic>> rows,
  ) =>
      rows
          .map((r) => Map<String, dynamic>.from(
              _hiveSafeValue(r) as Map<String, dynamic>))
          .toList();

  Future<List<Map<String, dynamic>>> loadSellerProducts(
    String sellerId,
    Category category,
  ) async {
    try {
      final cachedProducts = _cache.getProducts(sellerId);
      if (cachedProducts != null && cachedProducts.isNotEmpty) {
        return cachedProducts;
      }

      // Standardized on 'menu_items' — that's the subcollection name
      // FoodSellerService actually writes to (see addMenuItem /
      // batchUpsertMenuItems in food_seller_service.dart). This used
      // to read 'products' instead, so a seller's menu always loaded
      // empty even after they'd added items.
      //
      // FIX (root cause of "seller shows only their name, no menu
      // items" for already-onboarded sellers): this combined an
      // equality filter (isAvailable) with .orderBy() on a DIFFERENT
      // field (name) — the exact same composite-index requirement
      // already root-caused and fixed once this session in
      // usage_billing_service.dart. Without that index deployed, this
      // query threw `failed-precondition: requires an index`, and the
      // catch (e) { return []; } below silently swallowed it — every
      // seller's menu resolved to an empty list even when menu_items
      // had real, correctly-written documents in it. Removed the
      // orderBy and sort client-side instead (menu lists are small —
      // capped at 100 here, effectively far fewer per seller).
      final snapshot = await _firestore
          .collection('sellers')
          .doc(sellerId)
          .collection('menu_items')
          .where('isAvailable', isEqualTo: true)
          .limit(100)
          .get();

      final products = snapshot.docs
          .map(
            (doc) => {
              'id': doc.id,
              ...doc.data(),
            },
          )
          .toList()
        ..sort((a, b) => ((a['name'] as String?) ?? '').compareTo((b['name'] as String?) ?? ''));

      // ================================================================
      // ROOT CAUSE FIX (Aug 17 2026) — "Failed to load products"
      // HiveError: Cannot write, unknown type: minified:iC
      // ================================================================
      // 'minified:iC' is Firestore's `Timestamp` after dart2js minifies
      // it. menu_items docs carry createdAt/updatedAt as Timestamps
      // (MenuItemModel.toJson writes them, and updateMenuItem stamps
      // updatedAt with FieldValue.serverTimestamp()), and Hive cannot
      // serialise a Timestamp without a registered adapter.
      //
      // So the Firestore READ succeeded and the products were in hand —
      // then the CACHE WRITE threw, the exception propagated out of this
      // method, and the customer saw "Failed to load products" for a
      // seller whose menu had loaded perfectly. A caching optimisation
      // took down the feature it was meant to speed up.
      //
      // Two independent fixes, because either alone leaves a trap:
      //
      //   1. SANITISE — convert Timestamps to ISO-8601 strings before
      //      caching. This is the same Hive-safe discipline
      //      ServiceRequestModel.toJson already follows for the same
      //      reason. Now the cache actually works instead of throwing.
      //
      //   2. NEVER LET THE CACHE BREAK THE READ — wrap the write so any
      //      future unserialisable field (a GeoPoint, a DocumentReference,
      //      a nested map someone adds next year) degrades to "no cache"
      //      rather than "no menu". The products are already fetched and
      //      correct at this point; failing to remember them is a
      //      performance loss, not a functional one.
      try {
        await _cache.cacheProducts(sellerId, _hiveSafe(products));
      } catch (e) {
        debugPrint('[CategoryGateway] product cache write skipped: $e');
      }

      return products;
    } catch (e) {
      // FIX: this used to swallow every failure and return [] here,
      // which made a genuinely-empty menu (0 docs, no error) and a
      // crashed query (permission-denied, missing index, offline,
      // etc.) render as the EXACT same "No products available" screen
      // to the customer — impossible to tell apart without direct
      // Firestore Console access. seller_detail_screen.dart's caller
      // already has a proper try/catch that shows a real "Failed to
      // load products" + Retry state when this rethrows, so real
      // errors are no longer silently indistinguishable from a seller
      // who simply hasn't added a dish yet.
      rethrow;
    }
  }

  // ── Load Platform Settings (Cache-First Strategy) ───────────
  Future<Map<String, dynamic>> loadPlatformSettings() async {
    try {
      final cachedSettings = _cache.getSettings();
      if (cachedSettings != null) {
        return cachedSettings;
      }

      final doc =
          await _firestore.collection('platformSettings').doc('global').get();

      if (!doc.exists) {
        return _getDefaultSettings();
      }

      final settings = doc.data() ?? _getDefaultSettings();
      await _cache.cacheSettings(settings);

      return settings;
    } catch (e) {
      return _getDefaultSettings();
    }
  }

  // ── Load Ride Fares (Cache-First Strategy) ───────────────────
  // NOT used for fare math anymore. Per Nizam's MVP decision, every
  // fare calculation reads from the hardcoded lib/config/fare_rates
  // .dart (FareRates) instead of this Firestore-backed
  // settings/ride_fares document, to avoid paying a DB read on every
  // fare estimate. bike_booking_screen.dart's old _loadFareConfig()
  // caller was removed for that reason. This method (and
  // _getDefaultRideFares() below) are left in place unremoved only in
  // case something non-fare-related still depends on them later —
  // as of this change nothing in lib/ calls loadRideFares() or
  // forceRefreshRideFares().
  Future<Map<String, dynamic>> loadRideFares() async {
    try {
      // ride_fares_cache now opens after runApp(). Without this await, a
      // very early call would see an empty cache and go straight to
      // Firestore — a database read we already paid for once. Idempotent
      // and instant once the box is open.
      await _cache.initDeferred();
      final cachedFares = _cache.getRideFares();
      if (cachedFares != null) {
        return cachedFares;
      }

      final doc = await _firestore.collection('settings').doc('ride_fares').get();

      if (!doc.exists) {
        return _getDefaultRideFares();
      }

      final fares = doc.data() ?? _getDefaultRideFares();
      await _cache.cacheRideFares(fares);

      return fares;
    } catch (e) {
      return _getDefaultRideFares();
    }
  }

  // ── Load Local Ads (Cache-First Strategy) ───────────────────
  Future<List<Map<String, dynamic>>> loadLocalAds() async {
    try {
      // Same reason as loadRideFares() — make sure ads_cache is open
      // before deciding the cache is empty and hitting Firestore.
      await _cache.initDeferred();
      final cachedAds = _cache.getAds();
      if (cachedAds != null && cachedAds.isNotEmpty) {
        return cachedAds;
      }

      final snapshot = await _firestore
          .collection('ads')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();

      final ads = snapshot.docs
          .map(
            (doc) => {
              'id': doc.id,
              ...doc.data(),
            },
          )
          .toList();

      await _cache.cacheAds(ads);

      return ads;
    } catch (e) {
      return [];
    }
  }

  // ── Force Refresh (Clear Cache + Fetch Fresh) ───────────────
  Future<List<Map<String, dynamic>>> forceRefreshCategory(
      Category category,) async {
    final categoryKey = _getCategoryFilter(category);
    await _cache.clearSellersCache(categoryKey);
    return loadCategoryData(category);
  }

  Future<List<Map<String, dynamic>>> forceRefreshProducts(
    String sellerId,
    Category category,
  ) async {
    await _cache.clearProductsCache(sellerId);
    return loadSellerProducts(sellerId, category);
  }

  Future<Map<String, dynamic>> forceRefreshSettings() async {
    await _cache.clearSettingsCache();
    return loadPlatformSettings();
  }

  Future<List<Map<String, dynamic>>> forceRefreshAds() async {
    await _cache.clearAdsCache();
    return loadLocalAds();
  }

  Future<Map<String, dynamic>> forceRefreshRideFares() async {
    await _cache.clearRideFaresCache();
    return loadRideFares();
  }

  // ── Default Settings (Fallback) ─────────────────────────────
  Map<String, dynamic> _getDefaultSettings() {
    return {
      'bikeTaxiBaseFare': 25.0,
      'bikeTaxiPerKm': 12.0,
      'coinValue': 100,
      'riderCommission': 15.0,
      'sellerCommission': 18.0,
      'platformFee': 2.0,
      'upiZeroFee': true,
      'deliveryBaseFee': 30.0,
      'deliveryPerKm': 5.0,
    };
  }

  // ── Default Ride Fares (Fallback) ────────────────────────────
  Map<String, dynamic> _getDefaultRideFares() {
    return {
      'bike': {
        'baseFare': 25.0,
        'perKm': 10.0,
        'baseDistance': 2.0,
      },
      'auto': {
        'baseFare': 30.0,
        'perKm': 12.0,
        'baseDistance': 2.0,
      },
      'cab': {
        'baseFare': 50.0,
        'perKm': 15.0,
        'baseDistance': 2.0,
      },
      'parcel': {
        'baseFare': 40.0,
        'perKm': 10.0,
        'baseDistance': 2.0,
      },
      'mini_truck': {
        'baseFare': 60.0,
        'perKm': 16.0,
        'baseDistance': 2.0,
      },
      'lorry': {
        'baseFare': 100.0,
        'perKm': 22.0,
        'baseDistance': 2.0,
      },
    };
  }
}
