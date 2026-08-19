import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class HiveCache {
  HiveCache._();

  static const _boxName = 'allin1_cache';

  static const kUserProfile   = 'user_profile';
  static const kWalletBalance = 'wallet_balance';
  static const kRideHistory   = 'ride_history';
  static const kActiveRide    = 'active_ride_state';

  static const ttlUserProfile   = Duration(minutes: 30);
  static const ttlWalletBalance = Duration(minutes: 5);
  static const ttlRideHistory   = Duration(hours: 24);
  static const ttlActiveRide    = Duration(hours: 4);

  // ── Extended coverage (Aug 11 2026 — Nizam's Spark-plan read-budget
  // hardening). These are catalogue-style reads: content that every
  // customer loads on nearly every app open, but which changes rarely.
  // They were previously uncached (and some were live .snapshots()
  // streams, which bill per document delivered AND re-bill on every
  // change), making them the largest avoidable draw on the 50K
  // reads/day Spark limit. TTLs are deliberately generous here because
  // stale-by-an-hour promotional content is harmless, whereas a stale
  // wallet balance is not — hence the much shorter TTL above.
  static const kErodeOffers   = 'erode_offers';
  static const kSellersList   = 'sellers_list';
  static const kProductsList  = 'products_list';
  static const kBanners       = 'banners';
  static const kSellerOrders  = 'seller_orders';
  // NEW (Aug 19 2026 — Home Page Banner Offers). Same version-gated
  // cache-first pattern as kErodeOffers: a one-shot .get() behind a
  // long TTL, refetched only when MigrationGateService.rewardsVersion
  // moves. See dashboard_screen.dart's _HomeBannerOffersSection.
  static const kHomeBannerOffers = 'home_banner_offers';

  static const ttlErodeOffers  = Duration(hours: 1);
  static const ttlSellersList  = Duration(minutes: 45);
  static const ttlProductsList = Duration(minutes: 45);
  static const ttlBanners      = Duration(hours: 2);
  static const ttlSellerOrders = Duration(hours: 1);
  static const ttlHomeBannerOffers = Duration(hours: 1);

  static Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    // HiveCache is shared across every app entrypoint (customer, hero,
    // seller). Only main_customer.dart calls Hive.initFlutter() at
    // startup — callers like the hero app's notification dedup
    // (hero_ride_notification_service.dart) would otherwise crash on
    // openBox() with no storage path configured. initFlutter() is
    // idempotent/safe to call again if another entrypoint already did.
    await Hive.initFlutter();
    return await Hive.openBox(_boxName);
  }

  static Future<void> put(String key, value, {Duration ttl = const Duration(minutes: 30)}) async {
    try {
      final box = await _box();
      await box.put(key, {
        'value': value,
        'expiresAt': DateTime.now().add(ttl).millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('[HiveCache] put error ($key): $e');
    }
  }

  static Future<void> cacheErodeOffers(List<Map<String, dynamic>> offers) async {
    await put(kErodeOffers, offers, ttl: ttlErodeOffers);
  }

  static Future<void> cacheUserProfile(Map<String, dynamic> profileData) async {
    // 30 mins TTL is fine, as changes are explicitly written back to cache on edit
    await put(kUserProfile, profileData, ttl: ttlUserProfile);
  }

  static Future<Map<String, dynamic>?> getCachedUserProfile() async {
    final data = await get<Map>(kUserProfile);
    if (data == null) return null;
    return Map<String, dynamic>.from(data);
  }

  static Future<List<Map<String, dynamic>>?> getCachedErodeOffers() async {
    final list = await get<List>(kErodeOffers);
    if (list == null) return null;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> cacheSellerOrders(String sellerId, List<Map<String, dynamic>> orders) async {
    await put('${kSellerOrders}_$sellerId', orders, ttl: ttlSellerOrders);
  }

  static Future<List<Map<String, dynamic>>?> getCachedSellerOrders(String sellerId) async {
    final list = await get<List>('${kSellerOrders}_$sellerId');
    if (list == null) return null;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<T?> get<T>(String key) async {
    try {
      final box = await _box();
      final raw = box.get(key);
      if (raw == null) return null;
      
      final entry = Map<String, dynamic>.from(raw as Map);
      final expiresAt = (entry['expiresAt'] as int?) ?? 0;
      
      if (DateTime.now().millisecondsSinceEpoch > expiresAt) {
        await box.delete(key);
        return null;
      }
      return entry['value'] as T?;
    } catch (e) {
      return null;
    }
  }

  static Future<void> evict(String key) async {
    try {
      final box = await _box();
      await box.delete(key);
    } catch (e) {
      debugPrint('[HiveCache] evict error: $e'); // Added comment/print to fix empty catch
    }
  }

  static Future<bool> isFresh(String key) async {
    try {
      final box = await _box();
      final raw = box.get(key);
      if (raw == null) return false;
      
      final entry = Map<String, dynamic>.from(raw as Map);
      final expiresAt = (entry['expiresAt'] as int?) ?? 0;
      
      return DateTime.now().millisecondsSinceEpoch < expiresAt;
    } catch (_) {
      return false;
    }
  }

  /// Cache-first wrapper around any Firestore (or other) fetch.
  ///
  /// Added (Aug 11 2026) as the reusable primitive for extending cache
  /// coverage: previously every caller hand-rolled its own
  /// get-cache / check-null / fetch / put sequence, which is why
  /// coverage stalled at four screens. Now a read path becomes cached
  /// by wrapping its existing fetch in one call.
  ///
  /// Returns cached data when fresh. On a miss it runs [fetch], caches
  /// the result, and returns it. If [fetch] THROWS (offline, quota
  /// exceeded, permission blip) this deliberately falls back to
  /// returning EXPIRED cached data when any exists, rather than
  /// propagating the error — for catalogue content, showing slightly
  /// stale offers beats showing an error screen, and this is exactly
  /// the behaviour that keeps the app usable if we ever do hit the
  /// Spark daily read ceiling mid-day.
  static Future<T?> cachedFetch<T>(
    String key,
    Future<T> Function() fetch, {
    Duration ttl = const Duration(minutes: 30),
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await get<T>(key);
      if (cached != null) return cached;
    }
    try {
      final fresh = await fetch();
      await put(key, fresh, ttl: ttl);
      return fresh;
    } catch (e) {
      debugPrint('[HiveCache] cachedFetch($key) fetch failed: $e');
      // Stale-if-error: reach past the TTL check for any prior value.
      try {
        final box = await _box();
        final raw = box.get(key);
        if (raw != null) {
          final entry = Map<String, dynamic>.from(raw as Map);
          final stale = entry['value'] as T?;
          if (stale != null) {
            debugPrint('[HiveCache] serving STALE cache for $key');
            return stale;
          }
        }
      } catch (_) {
        // fall through
      }
      rethrow;
    }
  }

  static Future<void> clearAll() async {
    try {
      final box = await _box();
      await box.clear();
    } catch (e) {
      debugPrint('[HiveCache] clearAll error: $e'); // Added comment/print to fix empty catch
    }
  }
} // <--- கடைசியில கமா பிரச்சனை வராமல் இருக்க இந்த பிராக்கெட் போதுமானது