import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class HiveCache {
  HiveCache._();

  static const _boxName = 'allin1_cache';

  static const kUserProfile = 'user_profile';
  static const kWalletBalance = 'wallet_balance';
  static const kRideHistory = 'ride_history';
  static const kActiveRide = 'active_ride_state';

  static const ttlUserProfile = Duration(minutes: 30);
  static const ttlWalletBalance = Duration(minutes: 5);
  static const ttlRideHistory = Duration(hours: 24);
  static const ttlActiveRide = Duration(hours: 4);

  static Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return await Hive.openBox(_boxName);
  }

  static Future<void> put(
    String key,
    value, {
    Duration ttl = const Duration(minutes: 30),
  }) async {
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
      debugPrint(
        '[HiveCache] evict error: $e',
      ); // Added comment/print to fix empty catch
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

  static Future<void> clearAll() async {
    try {
      final box = await _box();
      await box.clear();
    } catch (e) {
      debugPrint(
        '[HiveCache] clearAll error: $e',
      ); // Added comment/print to fix empty catch
    }
  }
} // <--- கடைசியில கமா பிரச்சனை வராமல் இருக்க இந்த பிராக்கெட் போதுமானது
