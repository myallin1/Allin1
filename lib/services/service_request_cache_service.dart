// ================================================================
// service_request_cache_service.dart
//
// Local, permanent (no-TTL) on-device store of the customer's own
// COMPLETED service_requests documents (electronics_service today —
// same shape works for hero_booking/custom_order/etc if reused
// later). Distinct from HiveCache (TTL-based, general-purpose) and
// RecentPlacesService (recent locations) — this one exists so a
// completed request's full details never need a Firestore round-trip
// again: once a request reaches 'completed', its full doc snapshot is
// written here at the same moment the app observes the completion,
// and every later read of that specific request comes from here
// instead of re-querying/re-listening to Firestore.
//
// Requests that are NOT yet completed are never written here — their
// status can still change, so they must stay on a live Firestore
// listener until they finish. See _buildMyEnquiries /
// _buildEnquiriesStatusTab in nj_tech_store_screen.dart for how the
// two sources (this cache + a live snapshot listener) are merged into
// one list.
// ================================================================
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ServiceRequestCacheService {
  factory ServiceRequestCacheService() => instance;
  ServiceRequestCacheService._();
  static final ServiceRequestCacheService instance =
      ServiceRequestCacheService._();

  static const _boxName = 'completed_service_requests';

  static Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    // Same lazy self-init pattern as HiveCache/RecentPlacesService —
    // safe to call from any entrypoint, not just main_customer.dart.
    await Hive.initFlutter();
    return Hive.openBox(_boxName);
  }

  /// Persists a completed request's full data locally, keyed by its
  /// Firestore document id. Call this the moment the app observes
  /// status == 'completed' for a request — the same client action
  /// that "notices" completion is what writes it here, so there's
  /// never a separate later trip back to Firestore just to re-read
  /// something already fully known.
  Future<void> cacheCompletedRequest(
    String requestId,
    Map<String, dynamic> data,
  ) async {
    try {
      final box = await _box();
      // Store plain, JSON-safe primitives only — Firestore Timestamps
      // don't survive Hive's binary format, so convert to epoch millis.
      final safeData = _sanitizeForHive(data);
      await box.put(requestId, safeData);
    } catch (e) {
      debugPrint('[ServiceRequestCacheService] cache write error: $e');
    }
  }

  /// Returns the cached data for one request, or null if it isn't
  /// cached (i.e. wasn't completed yet, or this device never saw it
  /// complete).
  Future<Map<String, dynamic>?> getCachedRequest(String requestId) async {
    try {
      final box = await _box();
      final raw = box.get(requestId);
      if (raw is! Map) return null;
      return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint('[ServiceRequestCacheService] read error: $e');
      return null;
    }
  }

  /// All cached completed requests, newest first, optionally filtered
  /// to one requestType (e.g. 'electronics_service').
  Future<List<Map<String, dynamic>>> getAllCachedRequests({
    String? requestType,
  }) async {
    try {
      final box = await _box();
      final entries = box.values
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .where((e) =>
              requestType == null || e['requestType'] == requestType,)
          .toList();
      entries.sort((a, b) {
        final aTime = (a['createdAtMs'] as int?) ?? 0;
        final bTime = (b['createdAtMs'] as int?) ?? 0;
        return bTime.compareTo(aTime);
      });
      return entries;
    } catch (e) {
      debugPrint('[ServiceRequestCacheService] list read error: $e');
      return const [];
    }
  }

  /// True if this requestId already has a cached (completed) copy —
  /// callers use this to decide whether a Firestore listener is even
  /// needed for that specific request.
  Future<bool> isCached(String requestId) async {
    try {
      final box = await _box();
      return box.containsKey(requestId);
    } catch (e) {
      return false;
    }
  }

  /// Strips Firestore-specific types (Timestamp) down to plain
  /// primitives Hive can store, and records the doc id + a plain-int
  /// createdAt so getAllCachedRequests() can sort without touching
  /// Firestore types again.
  Map<String, dynamic> _sanitizeForHive(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    data.forEach((key, value) {
      result[key] = _sanitizeValue(value);
    });
    // Firestore Timestamp objects can't be stored directly — the
    // caller (nj_tech_store_screen.dart) is expected to have already
    // converted 'createdAt'/'updatedAt' to 'createdAtMs'/'updatedAtMs'
    // before calling cacheCompletedRequest(); this is just a safety
    // net so a raw Timestamp never crashes the Hive write.
    return result;
  }

  dynamic _sanitizeValue(value) {
    if (value is Map) {
      final map = <String, dynamic>{};
      value.forEach((k, v) {
        map[k.toString()] = _sanitizeValue(v);
      });
      return map;
    }
    if (value is List) {
      return value.map(_sanitizeValue).toList();
    }
    // Firestore Timestamp has toDate(); anything with that shape gets
    // converted to epoch millis rather than stored as an opaque object
    // Hive doesn't know how to serialize.
    try {
      final dynamic maybeTimestamp = value;
      if (maybeTimestamp != null &&
          maybeTimestamp.runtimeType.toString() == 'Timestamp') {
        return (maybeTimestamp.toDate() as DateTime).millisecondsSinceEpoch;
      }
    } catch (_) {
      // Not a Timestamp — fall through and store as-is.
    }
    return value;
  }
}
