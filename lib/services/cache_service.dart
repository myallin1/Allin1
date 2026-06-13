// ================================================================
// Cache Service — Allin1 Super App
// Hive-based caching with TTL (Time-To-Live) for cost optimization
// ================================================================

import 'package:hive_flutter/hive_flutter.dart';

class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  // ── Hive Boxes ──────────────────────────────────────────────
  late Box<dynamic> _sellersBox;
  late Box<dynamic> _productsBox;
  late Box<dynamic> _settingsBox;
  late Box<dynamic> _adsBox;
  late Box<dynamic> _rideFaresBox;

  // ── TTL Configuration ───────────────────────────────────────
  static const Duration _sellersTTL = Duration(hours: 4);
  static const Duration _productsTTL = Duration(hours: 2);
  static const Duration _settingsTTL = Duration(hours: 1);
  static const Duration _adsTTL = Duration(minutes: 30);
  static const Duration _rideFaresTTL = Duration(hours: 1);

  // ── Initialize Hive Boxes ───────────────────────────────────
  Future<void> init() async {
    try {
      await Hive.initFlutter();

      _sellersBox = await Hive.openBox('sellers_cache');
      _productsBox = await Hive.openBox('products_cache');
      _settingsBox = await Hive.openBox('settings_cache');
      _adsBox = await Hive.openBox('ads_cache');
      _rideFaresBox = await Hive.openBox('ride_fares_cache');
    } catch (e) {
      rethrow;
    }
  }

  // ── Generic Cache Methods ───────────────────────────────────
  Future<void> _cacheData(
    Box<dynamic> box,
    String key,
    data,
    Duration ttl,
  ) async {
    await box.put(key, data);
    await box.put('${key}_cachedAt', DateTime.now());
    await box.put('${key}_ttl', ttl.inMilliseconds);
  }

  dynamic _getCachedData(Box<dynamic> box, String key) {
    try {
      if (!isCacheValid(box, key)) {
        return null;
      }
      return box.get(key);
    } catch (e) {
      return null;
    }
  }

  bool isCacheValid(Box<dynamic> box, String key) {
    try {
      final cachedAt = box.get('${key}_cachedAt') as DateTime?;
      final ttlMillis = box.get('${key}_ttl') as int?;

      if (cachedAt == null || ttlMillis == null) {
        return false;
      }

      final age = DateTime.now().difference(cachedAt);
      final ttl = Duration(milliseconds: ttlMillis);

      return age < ttl;
    } catch (e) {
      return false;
    }
  }

  Future<void> _clearCache(Box<dynamic> box, String key) async {
    await box.delete(key);
    await box.delete('${key}_cachedAt');
    await box.delete('${key}_ttl');
  }

  // ── Sellers Cache ───────────────────────────────────────────
  Future<void> cacheSellers(
    String category,
    List<Map<String, dynamic>> sellers,
  ) async {
    await _cacheData(_sellersBox, category, sellers, _sellersTTL);
  }

  List<Map<String, dynamic>>? getSellers(String category) {
    final data = _getCachedData(_sellersBox, category);
    if (data == null) return null;
    return List<dynamic>.from(data as Iterable? ?? [])
        .cast<Map<String, dynamic>>();
  }

  Future<void> clearSellersCache(String category) async {
    await _clearCache(_sellersBox, category);
  }

  // ── Products Cache ──────────────────────────────────────────
  Future<void> cacheProducts(
    String sellerId,
    List<Map<String, dynamic>> products,
  ) async {
    await _cacheData(_productsBox, sellerId, products, _productsTTL);
  }

  List<Map<String, dynamic>>? getProducts(String sellerId) {
    final data = _getCachedData(_productsBox, sellerId);
    if (data == null) return null;
    return List<dynamic>.from(data as Iterable? ?? [])
        .cast<Map<String, dynamic>>();
  }

  Future<void> clearProductsCache(String sellerId) async {
    await _clearCache(_productsBox, sellerId);
  }

  // ── Platform Settings Cache ─────────────────────────────────
  Future<void> cacheSettings(Map<String, dynamic> settings) async {
    await _cacheData(_settingsBox, 'platform_settings', settings, _settingsTTL);
  }

  Map<String, dynamic>? getSettings() {
    final data = _getCachedData(_settingsBox, 'platform_settings');
    if (data == null) return null;
    return Map<String, dynamic>.from(data as Map? ?? {});
  }

  Future<void> clearSettingsCache() async {
    await _clearCache(_settingsBox, 'platform_settings');
  }

  // ── Local Ads Cache ─────────────────────────────────────────
  Future<void> cacheAds(List<Map<String, dynamic>> ads) async {
    await _cacheData(_adsBox, 'local_ads', ads, _adsTTL);
  }

  List<Map<String, dynamic>>? getAds() {
    final data = _getCachedData(_adsBox, 'local_ads');
    if (data == null) return null;
    return List<dynamic>.from(data as Iterable? ?? [])
        .cast<Map<String, dynamic>>();
  }

  Future<void> clearAdsCache() async {
    await _clearCache(_adsBox, 'local_ads');
  }

  // ── Ride Fares Cache ────────────────────────────────────────
  Future<void> cacheRideFares(Map<String, dynamic> fares) async {
    await _cacheData(_rideFaresBox, 'ride_fares', fares, _rideFaresTTL);
  }

  Map<String, dynamic>? getRideFares() {
    final data = _getCachedData(_rideFaresBox, 'ride_fares');
    if (data == null) return null;
    return Map<String, dynamic>.from(data as Map? ?? {});
  }

  Future<void> clearRideFaresCache() async {
    await _clearCache(_rideFaresBox, 'ride_fares');
  }

  // ── Clear All Cache ─────────────────────────────────────────
  Future<void> clearAllCache() async {
    await _sellersBox.clear();
    await _productsBox.clear();
    await _settingsBox.clear();
    await _adsBox.clear();
    await _rideFaresBox.clear();
  }

  // ── Close Hive Boxes ────────────────────────────────────────
  Future<void> dispose() async {
    await _sellersBox.close();
    await _productsBox.close();
    await _settingsBox.close();
    await _adsBox.close();
    await _rideFaresBox.close();
  }
}
