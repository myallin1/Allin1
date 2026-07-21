// ================================================================
// service_request_service.dart — Broadcast Order System
// Data layer for the 4 service-request categories (Hero Booking,
// Custom Order, Custom Food Order, Grocery Order). Isolated from the
// `orders` collection per CTO decision. Mirrors the ride-hailing
// broadcast/atomic-accept pattern in ride_search_screen.dart and
// hero_home_screen.dart, but broadcasts to ALL eligible heroes
// simultaneously instead of pinging sequentially.
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart' as rtdb;
import 'package:flutter/foundation.dart' show debugPrint;

/// Canonical status enum — the single source of truth for lifecycle state.
/// UI label sets (task-type vs goods-type) are presentation-only mappings
/// on top of these exact string values; never introduce a second enum.
const List<String> kServiceRequestStatuses = [
  'pending',
  'hero_assigned',
  'in_progress',
  'nearing_completion',
  'completed',
  'admin_review',
];

const int kServiceRequestPingExpirySeconds = 90;

/// Status-advance order for the hero/admin 3-button control — a
/// deliberate subset of kServiceRequestStatuses (excludes 'pending'
/// and 'admin_review', which aren't reachable once a hero is
/// assigned). Single source of truth shared by hero_home_screen.dart
/// and admin_new_orders_screen.dart — do not redefine locally.
const List<String> kServiceRequestAdvanceOrder = [
  'hero_assigned',
  'in_progress',
  'nearing_completion',
  'completed',
];

class ServiceRequestService {
  /// Reserves a document ID without writing anything — used when a
  /// caller needs the future request's ID before creating the doc
  /// (e.g. to build a Storage upload path keyed by requestId).
  String reserveRequestId() =>
      FirebaseFirestore.instance.collection('service_requests').doc().id;

  /// Creates a new service_requests doc, mirrors it to
  /// active_service_requests in RTDB, and broadcasts a ping to every
  /// online + available hero simultaneously.
  Future<String> createServiceRequest({
    required String requestType,
    required String customerId,
    required String customerName,
    required String customerPhone,
    required Map<String, dynamic> details,
    String? preGeneratedRequestId,
  }) async {
    // Allow callers that need the ID before the doc exists (e.g. grocery
    // orders that upload an image to a Storage path keyed by requestId)
    // to reserve the ID up front via `reserveRequestId()`.
    final docRef = preGeneratedRequestId != null
        ? FirebaseFirestore.instance.collection('service_requests').doc(preGeneratedRequestId)
        : FirebaseFirestore.instance.collection('service_requests').doc();
    final requestId = docRef.id;

    await docRef.set({
      'requestId': requestId,
      'requestType': requestType,
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'details': details,
      'status': 'pending',
      'assignedHeroId': null,
      'assignedHeroName': null,
      'assignedHeroPhone': null,
      'assignmentMethod': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final pingExpiresAt = DateTime.now().toUtc().millisecondsSinceEpoch +
        kServiceRequestPingExpirySeconds * 1000;

    await rtdb.FirebaseDatabase.instance
        .ref('active_service_requests/$requestId')
        .set({
      'requestId': requestId,
      'requestType': requestType,
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'details': details,
      'status': 'pinging',
      'currentPingHeroId': '',
      'acceptedHeroId': '',
      'pingExpiresAt': pingExpiresAt,
      'createdAt': rtdb.ServerValue.timestamp,
    });

    await _broadcastToEligibleHeroes(
      requestId: requestId,
      requestType: requestType,
      customerName: customerName,
      customerPhone: customerPhone,
      details: details,
      pingExpiresAt: pingExpiresAt,
    );

    return requestId;
  }

  /// Broadcasts a ping to every hero currently online AND available.
  /// Reuses the existing bike-taxi/parcel hero pool — no category
  /// filtering, since this is not a new hero recruitment.
  Future<void> _broadcastToEligibleHeroes({
    required String requestId,
    required String requestType,
    required String customerName,
    required String customerPhone,
    required Map<String, dynamic> details,
    required int pingExpiresAt,
  }) async {
    final snap =
        await rtdb.FirebaseDatabase.instance.ref('online_heroes').get();
    if (!snap.exists || snap.value is! Map) return;

    final heroes = Map<dynamic, dynamic>.from(snap.value as Map);
    final futures = <Future<void>>[];

    heroes.forEach((heroId, heroDataRaw) {
      if (heroDataRaw is! Map) return;
      final heroData = Map<String, dynamic>.from(heroDataRaw);
      final isAvailable = (heroData['isAvailable'] as bool?) ?? false;
      if (!isAvailable) return;

      futures.add(
        rtdb.FirebaseDatabase.instance
            .ref('hero_service_pings/$heroId/$requestId')
            .set({
          'requestId': requestId,
          'requestType': requestType,
          'customerName': customerName,
          'customerPhone': customerPhone,
          'details': details,
          'pingExpiresAt': pingExpiresAt,
          'status': 'pinging',
        }),
      );
    });

    await Future.wait(futures);
  }

  /// Atomic accept — mirrors hero_home_screen.dart's `_acceptRide` exactly.
  /// Only one hero can win the race; the RTDB transaction is the single
  /// source of truth for "who got it first."
  Future<bool> acceptServiceRequest({
    required String requestId,
    required String heroId,
    required String heroName,
    required String heroPhone,
  }) async {
    final requestRef = rtdb.FirebaseDatabase.instance
        .ref('active_service_requests/$requestId');

    final transResult = await requestRef.runTransaction((Object? currentData) {
      if (currentData == null) {
        // Optimistic local cache run. NEVER abort here — the server
        // will re-run this against the real data.
        return rtdb.Transaction.success({
          'status': 'accepted',
          'acceptedHeroId': heroId,
          'acceptedHeroName': heroName,
          'acceptedHeroPhone': heroPhone,
        });
      }

      final data = Map<String, dynamic>.from(currentData as Map);
      final status = data['status'] as String? ?? '';

      if (status == 'accepted' || status == 'cancelled' || status == 'timeout') {
        return rtdb.Transaction.abort();
      }

      data['status'] = 'accepted';
      data['acceptedHeroId'] = heroId;
      data['acceptedHeroName'] = heroName;
      data['acceptedHeroPhone'] = heroPhone;
      return rtdb.Transaction.success(data);
    });

    if (!transResult.committed) {
      // Another hero won the race — clean up our own ping, no error shown.
      await rtdb.FirebaseDatabase.instance
          .ref('hero_service_pings/$heroId/$requestId')
          .remove();
      return false;
    }

    await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .update({
      'status': 'hero_assigned',
      'assignedHeroId': heroId,
      'assignedHeroName': heroName,
      'assignedHeroPhone': heroPhone,
      'assignmentMethod': 'broadcast',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Winner's own ping is always removed (was already the case).
    await rtdb.FirebaseDatabase.instance
        .ref('hero_service_pings/$heroId/$requestId')
        .remove();

    // Bug fix: previously only the WINNING hero's own ping node was
    // ever removed — every other hero who was also broadcast this
    // requestId kept their ping node (and, if their dialog was already
    // open, kept showing "New Service Request" indefinitely) with
    // nothing telling them it was already taken. Sweep-clear every
    // other online hero's ping node for this requestId too, same
    // hero pool _broadcastToEligibleHeroes() used to create them.
    // Best-effort: a hero who went offline between broadcast and
    // accept won't be in this snapshot, but their stale ping node
    // self-expires via the client-side pingExpiresAt check in
    // hero_home_screen.dart's _listenForServicePings() regardless.
    try {
      final onlineSnap =
          await rtdb.FirebaseDatabase.instance.ref('online_heroes').get();
      if (onlineSnap.exists && onlineSnap.value is Map) {
        final heroes = Map<dynamic, dynamic>.from(onlineSnap.value as Map);
        final sweepFutures = <Future<void>>[];
        for (final otherHeroId in heroes.keys) {
          if (otherHeroId == heroId) continue; // already removed above
          sweepFutures.add(
            rtdb.FirebaseDatabase.instance
                .ref('hero_service_pings/$otherHeroId/$requestId')
                .remove(),
          );
        }
        await Future.wait(sweepFutures);
      }
    } catch (e) {
      debugPrint('[ServiceRequestService] Ping sweep-clear failed: $e');
    }

    return true;
  }

  /// Hero or admin status-advance. Both paths write the exact same field
  /// on the exact same document — the customer tracking screen cannot
  /// tell (and does not need to know) which side triggered the update.
  Future<void> advanceStatus(String requestId, String newStatus) async {
    assert(kServiceRequestStatuses.contains(newStatus));
    await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .update({
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Unified Hero Task System: money fields ──────────────────────
  // Generic 'estimatedAmount'/'finalAmount' fields (not fare-specific
  // names) since these apply across all 4 non-ride request types
  // (hero_booking, custom_order, custom_food_order, grocery_order),
  // none of which share a measurable basis (distance/weight/etc.) for
  // automatic calculation the way ride fares do — manual entry only,
  // by design (confirmed decision: a calculated-formula system is a
  // possible future per-category enhancement, not in scope now).

  /// Sets the estimated amount for a service request. Called by the
  /// hero right before they advance to 'in_progress' (gates the
  /// "Start" action — see _ServiceRequestStatusCard in
  /// hero_home_screen.dart), or optionally pre-filled by an admin at
  /// manual-assignment time. Does not itself change `status`.
  Future<void> setEstimatedAmount(String requestId, double amount) async {
    await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .update({
      'estimatedAmount': amount,
      // Reset to null (not-yet-responded) on every write — covers both
      // the hero's first entry and a re-entry after the customer
      // rejects (see rejectEstimate()), so a revised estimate always
      // needs a fresh approval rather than inheriting a stale decision.
      'estimateApprovedByCustomer': null,
      'estimateRespondedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Customer-side: approves the hero's entered estimate. This is what
  /// unblocks the hero's "Start" action — see
  /// _ServiceRequestStatusCard._advanceTo() in hero_home_screen.dart,
  /// which waits on `estimateApprovedByCustomer == true` before it will
  /// call advanceStatus('in_progress').
  Future<void> approveEstimate(String requestId) async {
    await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .update({
      'estimateApprovedByCustomer': true,
      'estimateRespondedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Customer-side: rejects the hero's entered estimate. Deliberately
  /// does NOT touch `status` (no admin_review routing, no
  /// cancellation) — clears `estimatedAmount` back to null so the
  /// hero's UI drops back into "enter an estimate" mode and can submit
  /// a revised number, which re-triggers the same approval wait via
  /// setEstimatedAmount()'s reset above. A simple negotiate loop, no
  /// cap on rejection count (can be added later if repeated rejection
  /// turns out to be a real problem in practice).
  Future<void> rejectEstimate(String requestId) async {
    await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .update({
      'estimatedAmount': null,
      'estimateApprovedByCustomer': null,
      'estimateRespondedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Completes a service request with a final bill amount in one
  /// write — mirrors the ride flow's finalFare/actualFare pattern,
  /// generalized to a single generic field since these categories
  /// have no tip/base-fare split concept. Hero enters this at "Mark
  /// Complete", pre-filled with the estimate but adjustable.
  ///
  /// Also sets paymentStatus: 'pending_collection' — mirrors the ride
  /// flow's completed-but-unpaid state (rides collection's same
  /// field/value), so the customer's payment screen and the hero's
  /// "mark payment received" action both have a status to key off.
  Future<void> completeWithFinalAmount(
    String requestId,
    double finalAmount,
  ) async {
    await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .update({
      'finalAmount': finalAmount,
      'status': 'completed',
      'paymentStatus': 'pending_collection',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Customer-side: marks a completed service request as paid. This is
  /// intentionally NOT a real payment-gateway integration — same scope
  /// boundary as the rest of the Unified Hero Task System v1 (manual
  /// amount entry, no automatic calculation). Records which method the
  /// customer selected for the hero's own records.
  Future<void> markServiceRequestPaid(
    String requestId, {
    required String method,
  }) async {
    await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .update({
      'paymentStatus': 'paid',
      'paymentMethod': method,
      'paidAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Hero-side: the final "close the task" action — acknowledges the
  /// hero has physically received payment (relevant for cash; for
  /// markServiceRequestPaid's UPI/wallet path this is effectively
  /// already true, but the hero still gets an explicit closing action
  /// to parallel the ride flow's "Collect Payment" → ride-complete
  /// step). Does not change `status` (already 'completed') — only
  /// paymentStatus.
  Future<void> markServiceRequestPaymentReceived(String requestId) async {
    await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .update({
      'paymentStatus': 'paid',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Admin manually assigns a hero after confirming by phone — no
  /// broadcast ping needed since the admin already coordinated directly.
  Future<void> adminAssignHero({
    required String requestId,
    required String heroId,
    required String heroName,
    required String heroPhone,
  }) async {
    await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .update({
      'status': 'hero_assigned',
      'assignedHeroId': heroId,
      'assignedHeroName': heroName,
      'assignedHeroPhone': heroPhone,
      'assignmentMethod': 'admin_manual',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Also close out the RTDB broadcast state so a hero whose ping
    // hasn't expired yet can't win a concurrent atomic-accept race
    // against this manual assignment — acceptServiceRequest's
    // transaction aborts on status == 'accepted'.
    await rtdb.FirebaseDatabase.instance
        .ref('active_service_requests/$requestId')
        .update({
      'status': 'accepted',
      'acceptedHeroId': heroId,
      'acceptedHeroName': heroName,
      'acceptedHeroPhone': heroPhone,
    });
  }

  /// Cancels a service request — customer- or admin-initiated. Per
  /// product decision, cancelled requests are FULLY DELETED from
  /// Firestore (not soft-deleted with a 'cancelled' status) to
  /// guarantee zero stale-data risk in hero/admin views. Eligibility
  /// (which statuses may be cancelled, by whom) is enforced by the
  /// CALLER — this method does not re-check status, since the
  /// customer-side and admin-side allowed-stage sets differ.
  ///
  /// Before deleting, best-effort marks the RTDB
  /// active_service_requests/{id} node's status as 'cancelled'. This
  /// matters because acceptServiceRequest()'s transaction already has
  /// a dormant guard — `if (status == 'accepted' || status ==
  /// 'cancelled' || status == 'timeout') return Transaction.abort()`
  /// — that aborts a hero's in-flight accept attempt when it sees
  /// this status. Deleting that RTDB node instead (rather than
  /// updating its status) would make the transaction's `currentData
  /// == null` branch treat it as a fresh "optimistic success" write,
  /// which could let a hero accidentally revive a task that was just
  /// cancelled. Updating first closes that race; the delete below
  /// only removes the Firestore source-of-truth document.
  Future<void> cancelServiceRequest(String requestId) async {
    try {
      await rtdb.FirebaseDatabase.instance
          .ref('active_service_requests/$requestId')
          .update({'status': 'cancelled'});
    } catch (e) {
      // Best-effort — the RTDB node may already be gone (hero accepted
      // and it was cleaned up, or it timed out) — proceed to delete
      // the Firestore doc regardless.
      debugPrint('[ServiceRequestService] RTDB cancel-mark failed (non-fatal): $e');
    }

    await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .delete();
  }

  /// Hero-side "give this back" action for a task they accepted but no
  /// longer want to do — deliberately NOT the same thing as
  /// cancelServiceRequest() (which is customer/admin-initiated and
  /// deletes the doc entirely). A released task still needs doing, so
  /// it routes to 'admin_review' — the exact same status/query
  /// markTimeoutIfStillPending() uses — so it surfaces on
  /// admin_new_orders_screen.dart's "AWAITING ASSIGNMENT" section (and
  /// the admin_review-count badges) for a human to re-assign or call
  /// the customer, rather than silently re-entering the broadcast pool.
  /// Only sensible before the hero has actually started (see the
  /// 'Release Task' button's hero_assigned-only gating in
  /// hero_home_screen.dart) — clears the assignment and any
  /// not-yet-approved estimate so the request looks freshly
  /// admin-manageable again.
  Future<void> releaseServiceRequest(String requestId) async {
    try {
      // Same reasoning as cancelServiceRequest()'s RTDB update: mark
      // rather than delete, reusing 'timeout' (already one of
      // acceptServiceRequest()'s transaction abort-guard values) so a
      // stray in-flight accept from the releasing hero's own old ping
      // can't race back in and revive an assignment that's being
      // handed back.
      await rtdb.FirebaseDatabase.instance
          .ref('active_service_requests/$requestId')
          .update({'status': 'timeout'});
    } catch (e) {
      debugPrint('[ServiceRequestService] RTDB release-mark failed (non-fatal): $e');
    }

    await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .update({
      'status': 'admin_review',
      'assignedHeroId': null,
      'assignedHeroName': null,
      'assignedHeroPhone': null,
      'assignmentMethod': null,
      'estimatedAmount': null,
      'estimateApprovedByCustomer': null,
      'estimateRespondedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Called by the requesting screen ~90s after broadcast. If the
  /// request is still 'pending' (no hero accepted), routes it to the
  /// admin "New Orders" tab for manual follow-up.
  Future<void> markTimeoutIfStillPending(String requestId) async {
    final docRef =
        FirebaseFirestore.instance.collection('service_requests').doc(requestId);
    final doc = await docRef.get();
    if (!doc.exists) return;

    final status = doc.data()?['status'] as String? ?? '';
    if (status != 'pending') return; // Already progressed — nothing to do.

    await docRef.update({
      'status': 'admin_review',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await rtdb.FirebaseDatabase.instance
        .ref('active_service_requests/$requestId')
        .update({'status': 'timeout'});
  }
}
