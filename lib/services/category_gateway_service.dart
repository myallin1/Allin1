// ================================================================
// Category Gateway Service — Allin1 Super App
// Lazy-load category data with cache-first strategy
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'cache_service.dart';
import 'food_db_service.dart';

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
  // Taxi rides stay on the MAIN project (shared with hero/admin ride
  // handling — never touches the second "myallin1-food" project).
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // FIX (Nizam's cost-cutting plan): sellers/menu_items (every seller
  // vertical — food, grocery, tech, pharmacy) now live on the SECOND,
  // dedicated "myallin1-food" Firebase project, not the main database.
  FirebaseFirestore get _sellersDb => FoodDbService().firestore;

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

  bool _isSellerCategory(Category category) =>
      _getCategoryCollection(category) == 'sellers';

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
      final db = _isSellerCategory(category) ? _sellersDb : _firestore;
      final snapshot = await db
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
      await _cache.cacheSellers(categoryKey, sellers);

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
      final snapshot = await _sellersDb
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

      await _cache.cacheProducts(sellerId, products);

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
