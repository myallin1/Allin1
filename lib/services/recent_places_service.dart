import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Genuine, on-device history of the customer's own confirmed pickup and
/// drop selections.
///
/// This is deliberately separate from the static Erode landmark list in
/// bike_booking_screen.dart (`_defaultSearchLocations`). HANDOFF.md
/// documents why an earlier "recent places" list was ripped out: it was
/// four hardcoded, invented addresses that booked real rides to places
/// the customer had never been to. Every entry this service returns was
/// a real tap by this customer -- nothing here is invented.
///
/// No Hive adapter/codegen needed: entries are plain
/// Map<String, dynamic> of primitives (String/num), which Hive stores
/// natively without a @HiveType model.
class RecentPlacesService {
  RecentPlacesService._();
  static final RecentPlacesService instance = RecentPlacesService._();
  factory RecentPlacesService() => instance;

  static const _boxName = 'recent_places';
  static const _itemsKey = 'items';

  /// Most recent entries kept; oldest falls off the end.
  static const maxItems = 6;

  /// Two selections within this radius are treated as "the same place"
  /// for de-duplication (GPS/geocoder jitter is usually a few metres).
  static const _dedupeRadiusKm = 0.05;

  static Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    // Same lazy self-init as HiveCache: only main_customer.dart calls
    // Hive.initFlutter() at startup, and initFlutter() is safe/idempotent
    // to call again from here so this stays usable from any entrypoint.
    await Hive.initFlutter();
    return Hive.openBox(_boxName);
  }

  Future<List<Map<String, dynamic>>> getRecentPlaces() async {
    try {
      final box = await _box();
      final raw = box.get(_itemsKey);
      if (raw is! List) {
        return const <Map<String, dynamic>>[];
      }
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      debugPrint('[RecentPlacesService] read error: $e');
      return const <Map<String, dynamic>>[];
    }
  }

  /// Records [location] (a pickup or drop the customer actually
  /// confirmed) as the newest recent place, de-duplicating against any
  /// existing entry with the same name or within [_dedupeRadiusKm].
  Future<void> recordPlace(Map<String, dynamic> location) async {
    final lat = (location['lat'] as num?)?.toDouble();
    final lng = (location['lng'] as num?)?.toDouble();
    final name = (location['name'] as String? ?? '').trim();
    if (lat == null || lng == null || name.isEmpty) {
      return;
    }
    try {
      final box = await _box();
      final existing = await getRecentPlaces();
      existing.removeWhere((p) {
        if ((p['name'] as String?)?.trim() == name) {
          return true;
        }
        final pLat = (p['lat'] as num?)?.toDouble();
        final pLng = (p['lng'] as num?)?.toDouble();
        if (pLat == null || pLng == null) {
          return false;
        }
        return _haversineKm(lat, lng, pLat, pLng) < _dedupeRadiusKm;
      });
      final entry = <String, dynamic>{
        'name': name,
        'full': location['full'] as String? ?? name,
        'lat': lat,
        'lng': lng,
        'source': 'recent',
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      };
      final updated = <Map<String, dynamic>>[entry, ...existing];
      if (updated.length > maxItems) {
        updated.removeRange(maxItems, updated.length);
      }
      await box.put(_itemsKey, updated);
    } catch (e) {
      debugPrint('[RecentPlacesService] write error: $e');
    }
  }

  static double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * (pi / 180);
    final dLon = (lon2 - lon1) * (pi / 180);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}
