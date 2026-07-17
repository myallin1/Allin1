// ================================================================
// Category Gateway Service — Allin1 Super App
// Lazy-load category data with cache-first strategy
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
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
      final snapshot = await _firestore
          .collection(_getCategoryCollection(category))
          .where('category', isEqualTo: _getCategoryFilter(category))
          .where('status', isEqualTo: 'active')
          .orderBy('rating', descending: true)
          .limit(50)
          .get();

      final sellers = snapshot.docs
          .map(
            (doc) => {
              'id': doc.id,
              ...doc.data(),
            },
          )
          .toList();

      // STEP 3: Update cache
      await _cache.cacheSellers(categoryKey, sellers);

      return sellers;
    } catch (e) {
      return [];
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

      final snapshot = await _firestore
          .collection('sellers')
          .doc(sellerId)
          .collection('products')
          .where('isAvailable', isEqualTo: true)
          .orderBy('name')
          .limit(100)
          .get();

      final products = snapshot.docs
          .map(
            (doc) => {
              'id': doc.id,
              ...doc.data(),
            },
          )
          .toList();

      await _cache.cacheProducts(sellerId, products);

      return products;
    } catch (e) {
      return [];
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
      final cachedFares = _cache.getRideFares();
      if (cachedFares != null) {
        return cachedFares;
      }

      final doc =
          await _firestore.collection('settings').doc('ride_fares').get();

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
    Category category,
  ) async {
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
    };
  }
}
