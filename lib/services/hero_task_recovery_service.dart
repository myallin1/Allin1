// ================================================================
// hero_task_recovery_service.dart — Hero Recovery System (rides half)
// ================================================================
// NEW (Aug 11 2026, per Nizam — combined stuck-hero bug fix + Customer
// Service Management & Recovery System). service_requests already had
// a hero-side "give this back" escape hatch (releaseServiceRequest() in
// service_request_service.dart) — this file adds the equivalent for
// `rides`, which had none.
//
// ── WHY FIRESTORE-ONLY (no RTDB write here) ──
// Audited during the earlier Test Data Cleanup work (see
// admin_deletion_service.dart's file-level comment): a rides Firestore
// doc (`_rideDocId`) and its RTDB `active_ride_requests`/`hero_pings`
// keys (`_requestId`) are two different IDs with no reverse link stored
// on the ride doc. There is no reliable way to find the matching RTDB
// node from a rides doc alone. By the time a ride is old/stuck enough
// for a hero to need this screen, its RTDB search-window state has
// already self-expired (same short-lived-node lifetime class as pings)
// — Nizam explicitly confirmed skipping RTDB cleanup for rides in that
// earlier task, and the same reasoning applies to releasing a ride here.
//
// ── STATUS VALUE ──
// Reuses 'admin_review' (Nizam's explicit choice) — the exact same
// status service_requests already use for the identical purpose, so
// admin only needs one status value to look for across both
// collections instead of two.
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';

class HeroTaskRecoveryService {
  HeroTaskRecoveryService._();
  static final HeroTaskRecoveryService instance = HeroTaskRecoveryService._();

  /// Hero-initiated "give this ride back" — used by the Incomplete /
  /// Stuck Tasks hub. Clears the hero's claim and hands the ride to
  /// admin for follow-up (call the customer, re-dispatch, or delete if
  /// it was test data). firestore.rules already permits this: the
  /// rides update rule only pins the CURRENT heroId, not the incoming
  /// one, so a hero clearing their own claim was already an open door —
  /// this just adds the UI/service method that uses it.
  Future<void> releaseRide(String rideId) async {
    await FirebaseFirestore.instance.collection('rides').doc(rideId).update({
      'status': 'admin_review',
      'heroId': null,
      'heroName': null,
      'heroPhone': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
