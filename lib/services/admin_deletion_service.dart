// ================================================================
// admin_deletion_service.dart — Test Data Cleanup System
// ================================================================
// NEW (Aug 11 2026, per Nizam): a single, shared place for admin to
// permanently delete test bookings/rides/orders created during
// development, so admin analytics reflect real customer demand.
//
// ── SCHEMA FACTS THIS FILE DEPENDS ON (audited before writing this) ──
//
// service_requests: the Firestore doc ID IS the requestId used
// everywhere in RTDB (service_request_service.dart's
// createServiceRequest() does `docRef.id` -> `requestId` field). So
// deleting service_requests/{id} also tells us the EXACT RTDB paths:
// active_service_requests/{id} always, and
// hero_service_pings/{assignedHeroId}/{id} IF the request has an
// assignedHeroId. There is no reverse index from requestId alone back
// to every hero who was ever pinged (hero_service_pings is keyed
// {heroId}/{requestId}, not the other way round) — per Nizam's
// explicit decision, cleanup is best-effort via the known
// assignedHeroId only. Unassigned/expired pings are left to their
// existing 90s self-expiry (service_request_service.dart's own
// broadcast-window cleanup already sweeps those in the normal case).
//
// rides: `_rideDocId` (the Firestore doc) and `_requestId` (the RTDB
// active_ride_requests key / hero_pings key) are TWO DIFFERENT IDs —
// ride_search_screen.dart mints them separately. The RTDB node stores
// `firestoreDocId` pointing back to the ride, but the ride doc stores
// NOTHING pointing forward to its RTDB requestId. There is therefore
// no direct-path way to find or delete that node from a rides doc
// alone. Per Nizam's explicit decision: skip it. active_ride_requests
// nodes are transient search-window state with the same short
// lifetime class as pings — by the time an admin deletes an old test
// ride, it is already gone.
//
// orders: legacy collection (cart_screen.dart). No RTDB involvement
// at all — confirmed by reading every field cart_screen.dart writes
// into it. Firestore-only delete.
//
// ── BATCH LIMITS ──
// Firestore WriteBatch caps at 500 operations. Chunked at 400 here for
// headroom (a service_requests bulk delete may also touch an RTDB
// path per item, and staying well under the ceiling avoids ever
// needing to reason about exact per-item operation counts).
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart' as rtdb;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// One item queued for deletion — carries just enough to clean up its
/// RTDB traces alongside the Firestore doc.
class DeletableRequest {
  const DeletableRequest({required this.id, this.assignedHeroId});
  final String id;
  final String? assignedHeroId;
}

class AdminDeletionService {
  AdminDeletionService._();
  static final AdminDeletionService instance = AdminDeletionService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const int _batchChunkSize = 400;

  // ================================================================
  // service_requests — Firestore doc + active_service_requests RTDB +
  // best-effort hero_service_pings via assignedHeroId.
  // ================================================================
  Future<void> deleteServiceRequest(DeletableRequest item) async {
    await _db.collection('service_requests').doc(item.id).delete();
    await _deleteRtdbPath('active_service_requests/${item.id}');
    if ((item.assignedHeroId ?? '').trim().isNotEmpty) {
      await _deleteRtdbPath(
        'hero_service_pings/${item.assignedHeroId}/${item.id}',
      );
    }
  }

  /// Chunked WriteBatch for the Firestore side + per-item RTDB cleanup.
  /// Returns the number of items actually deleted, so the caller can
  /// report a real count even if one item fails partway through.
  Future<int> bulkDeleteServiceRequests(List<DeletableRequest> items) async {
    var deleted = 0;
    for (final chunk in _chunk(items, _batchChunkSize)) {
      final batch = _db.batch();
      for (final item in chunk) {
        batch.delete(_db.collection('service_requests').doc(item.id));
      }
      await batch.commit();
      deleted += chunk.length;

      // RTDB has no batch-delete API here worth adding complexity for —
      // a multi-path update() with null values IS the batch primitive,
      // so build one per chunk instead of one round-trip per item.
      final rtdbUpdate = <String, Object?>{};
      for (final item in chunk) {
        rtdbUpdate['active_service_requests/${item.id}'] = null;
        if ((item.assignedHeroId ?? '').trim().isNotEmpty) {
          rtdbUpdate['hero_service_pings/${item.assignedHeroId}/${item.id}'] =
              null;
        }
      }
      await _updateRtdbMultiPath(rtdbUpdate);
    }
    return deleted;
  }

  // ================================================================
  // rides — Firestore doc ONLY. See the file-level comment: there is
  // no reliable way to locate the matching active_ride_requests /
  // hero_pings node from a rides doc alone, and Nizam confirmed
  // skipping it rather than adding an unindexed RTDB scan.
  // ================================================================
  Future<void> deleteRide(String rideId) async {
    await _db.collection('rides').doc(rideId).delete();
  }

  Future<int> bulkDeleteRides(List<String> rideIds) async {
    var deleted = 0;
    for (final chunk in _chunk(rideIds, _batchChunkSize)) {
      final batch = _db.batch();
      for (final id in chunk) {
        batch.delete(_db.collection('rides').doc(id));
      }
      await batch.commit();
      deleted += chunk.length;
    }
    return deleted;
  }

  // ================================================================
  // orders — legacy cart_screen.dart collection. Firestore-only; this
  // collection never touches RTDB (verified against every field
  // cart_screen.dart writes).
  // ================================================================
  Future<void> deleteOrder(String orderId) async {
    await _db.collection('orders').doc(orderId).delete();
  }

  Future<int> bulkDeleteOrders(List<String> orderIds) async {
    var deleted = 0;
    for (final chunk in _chunk(orderIds, _batchChunkSize)) {
      final batch = _db.batch();
      for (final id in chunk) {
        batch.delete(_db.collection('orders').doc(id));
      }
      await batch.commit();
      deleted += chunk.length;
    }
    return deleted;
  }

  // ── helpers ──────────────────────────────────────────────────────
  Future<void> _deleteRtdbPath(String path) async {
    try {
      await rtdb.FirebaseDatabase.instance.ref(path).remove();
    } catch (e) {
      // Non-fatal: the Firestore doc — the record admin actually sees
      // and cares about — is already gone by the time this runs. A
      // stray RTDB node left behind self-expires anyway.
      debugPrint('[AdminDeletionService] RTDB cleanup failed for $path: $e');
    }
  }

  Future<void> _updateRtdbMultiPath(Map<String, Object?> paths) async {
    if (paths.isEmpty) return;
    try {
      await rtdb.FirebaseDatabase.instance.ref().update(paths);
    } catch (e) {
      debugPrint('[AdminDeletionService] RTDB multi-path cleanup failed: $e');
    }
  }

  Iterable<List<T>> _chunk<T>(List<T> items, int size) sync* {
    for (var i = 0; i < items.length; i += size) {
      yield items.sublist(i, i + size > items.length ? items.length : i + size);
    }
  }
}

// ================================================================
// Shared confirmation dialogs — same wording contract for every
// screen, so "delete" always means the same thing to an admin no
// matter which list they're looking at.
// ================================================================

/// Single-item delete confirmation. [subject] is what's being deleted,
/// e.g. "Test Request", "Test Ride", "Test Order".
Future<bool> confirmSingleDelete(
  BuildContext context, {
  required String subject,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF12121E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Delete $subject?',
        style: const TextStyle(
          color: Color(0xFFEEEEF5),
          fontWeight: FontWeight.w700,
        ),
      ),
      content: const Text(
        'This will permanently remove this record from Firestore and RTDB. '
        'This action cannot be undone.',
        style: TextStyle(color: Color(0xFF7777A0)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete', style: TextStyle(color: Color(0xFFFF5252))),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Bulk delete confirmation — states the exact count so an admin never
/// commits to a number they didn't mean to select.
Future<bool> confirmBulkDelete(
  BuildContext context, {
  required int count,
  required String subjectPlural,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF12121E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Delete $count $subjectPlural?',
        style: const TextStyle(
          color: Color(0xFFEEEEF5),
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Text(
        'This will permanently remove all $count selected records from '
        'Firestore and RTDB. This action cannot be undone.',
        style: const TextStyle(color: Color(0xFF7777A0)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'Delete $count',
            style: const TextStyle(color: Color(0xFFFF5252)),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
