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
  // Split into two phases so app-open is not held hostage by boxes the
  // first screen never touches.
  //
  //   initCritical()  -> awaited BEFORE runApp(). Only the boxes the
  //                      home screen actually reads on first paint.
  //   initDeferred()  -> run unawaited AFTER runApp(). Ads / ride-fares
  //                      are read by screens the customer reaches later.
  //
  // Both open their boxes in PARALLEL (Future.wait) instead of one after
  // another — each Hive.openBox() is a local storage I/O round-trip
  // (IndexedDB on web), so awaiting them in sequence was paying the full
  // cost N times over for no reason.
  bool _criticalReady = false;
  bool _deferredReady = false;

  /// True once ads/ride-fares boxes are open. Callers that touch those
  /// boxes early should check this and fall back to a network fetch.
  bool get isDeferredReady => _deferredReady;

  Future<void> initCritical() async {
    if (_criticalReady) return;
    // Hive.initFlutter() is already called by main() before this runs.
    // It used to be repeated here, which was a redundant second await.
    final boxes = await Future.wait<Box<dynamic>>([
      Hive.openBox('sellers_cache'),
      Hive.openBox('products_cache'),
      Hive.openBox('settings_cache'),
    ]);
    _sellersBox = boxes[0];
    _productsBox = boxes[1];
    _settingsBox = boxes[2];
    _criticalReady = true;
  }

  Future<void> initDeferred() async {
    if (_deferredReady) return;
    final boxes = await Future.wait<Box<dynamic>>([
      Hive.openBox('ads_cache'),
      Hive.openBox('ride_fares_cache'),
    ]);
    _adsBox = boxes[0];
    _rideFaresBox = boxes[1];
    _deferredReady = true;
  }

  /// Legacy entry point — kept so existing callers keep compiling.
  /// Opens everything, same as before.
  Future<void> init() async {
    await initCritical();
    await initDeferred();
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
  // _adsBox / _rideFaresBox now open AFTER runApp(), so every entry
  // point here either awaits initDeferred() (async paths) or bails out
  // to null (sync getters) instead of hitting a LateInitializationError.
  // A null from a getter already means "no usable cache" to callers, so
  // they fall through to their normal network fetch — same as a miss.
  Future<void> cacheAds(List<Map<String, dynamic>> ads) async {
    await initDeferred();
    await _cacheData(_adsBox, 'local_ads', ads, _adsTTL);
  }

  List<Map<String, dynamic>>? getAds() {
    if (!_deferredReady) return null;
    final data = _getCachedData(_adsBox, 'local_ads');
    if (data == null) return null;
    return List<dynamic>.from(data as Iterable? ?? [])
        .cast<Map<String, dynamic>>();
  }

  Future<void> clearAdsCache() async {
    await initDeferred();
    await _clearCache(_adsBox, 'local_ads');
  }

  // ── Ride Fares Cache ────────────────────────────────────────
  Future<void> cacheRideFares(Map<String, dynamic> fares) async {
    await initDeferred();
    await _cacheData(_rideFaresBox, 'ride_fares', fares, _rideFaresTTL);
  }

  Map<String, dynamic>? getRideFares() {
    if (!_deferredReady) return null;
    final data = _getCachedData(_rideFaresBox, 'ride_fares');
    if (data == null) return null;
    return Map<String, dynamic>.from(data as Map? ?? {});
  }

  Future<void> clearRideFaresCache() async {
    await initDeferred();
    await _clearCache(_rideFaresBox, 'ride_fares');
  }

  // ── Clear All Cache ─────────────────────────────────────────
  Future<void> clearAllCache() async {
    await initCritical();
    await initDeferred();
    await _sellersBox.clear();
    await _productsBox.clear();
    await _settingsBox.clear();
    await _adsBox.clear();
    await _rideFaresBox.clear();
  }

  // ── Close Hive Boxes ────────────────────────────────────────
  Future<void> dispose() async {
    if (_criticalReady) {
      await _sellersBox.close();
      await _productsBox.close();
      await _settingsBox.close();
      _criticalReady = false;
    }
    if (_deferredReady) {
      await _adsBox.close();
      await _rideFaresBox.close();
      _deferredReady = false;
    }
  }
}
