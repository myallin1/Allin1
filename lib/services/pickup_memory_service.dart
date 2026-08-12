// ================================================================
// pickup_memory_service.dart — remembers the customer's last pickup
// ================================================================
// NEW (Aug 11 2026 — Instant-Seed architecture).
//
// WHY THIS EXISTS: the taxi screen used to have exactly one way to know
// where the customer was — ask the GPS and wait. On a Windows laptop or
// a desktop browser there is no GPS chip at all, so that meant slow
// WiFi/IP positioning, and if the customer had ever denied the
// permission, browsers never re-prompt, so it could never succeed at
// all. The customer sat on a spinner while their booking went nowhere.
//
// But we almost always already KNOW where they are: it's wherever they
// were picked up last time. Erode customers book from the same handful
// of places — home, shop, college, bus stand. Remembering the last
// confirmed pickup makes the second booking onward instant on EVERY
// platform, with zero network and zero permission involved.
//
// Deliberately its own tiny service rather than a private field in
// bike_booking_screen: the same seed is useful to any screen that needs
// a starting map centre, and keeping it here means one storage key and
// one shape instead of several screens inventing their own.
// ================================================================
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'hive_cache.dart';

/// A pickup point the customer explicitly confirmed.
class RememberedPickup {
  const RememberedPickup({
    required this.lat,
    required this.lng,
    required this.name,
  });

  final double lat;
  final double lng;
  final String name;

  LatLng get latLng => LatLng(lat, lng);
}

class PickupMemoryService {
  PickupMemoryService._();

  static final PickupMemoryService instance = PickupMemoryService._();

  /// Not per-uid on purpose. This is device-local convenience, not
  /// account data — a shared family phone booking from the same house
  /// benefits from the same seed, and there is nothing private in a
  /// map centre the customer picked themselves. It also means the seed
  /// survives a signed-out guest becoming a registered customer.
  static const String _key = 'last_confirmed_pickup';

  /// A pickup point is a stable fact about someone's life, not a cache
  /// entry — HiveCache's 30-minute default would defeat the entire
  /// purpose, so this is effectively permanent and simply overwritten
  /// by the next confirmed pickup.
  static const Duration _ttl = Duration(days: 365);

  Future<void> remember(LatLng point, {String name = 'Pinned location'}) async {
    try {
      await HiveCache.put(
        _key,
        <String, dynamic>{
          'lat': point.latitude,
          'lng': point.longitude,
          'name': name,
        },
        ttl: _ttl,
      );
    } catch (e) {
      // Never fatal: failing to remember only costs convenience.
      debugPrint('[PickupMemory] remember failed: $e');
    }
  }

  Future<RememberedPickup?> load() async {
    try {
      final raw = await HiveCache.get<dynamic>(_key);
      if (raw is! Map) return null;
      final map = Map<String, dynamic>.from(raw);
      final lat = (map['lat'] as num?)?.toDouble();
      final lng = (map['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return RememberedPickup(
        lat: lat,
        lng: lng,
        name: (map['name'] as String?)?.trim().isNotEmpty ?? false
            ? map['name'] as String
            : 'Pinned location',
      );
    } catch (e) {
      debugPrint('[PickupMemory] load failed: $e');
      return null;
    }
  }
}
