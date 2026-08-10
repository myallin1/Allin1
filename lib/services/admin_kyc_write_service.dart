// ================================================================
// AdminKycWriteService — the ONLY place the Admin AI Co-Pilot feature
// is allowed to write to a real operational record (heroes / sellers /
// sos_kyc_requests).
// ================================================================
// NEW (CTO mandate — "Final Write Execution"). Every method here is a
// byte-for-byte mirror of the existing, human-reviewed write logic
// already shipping in the real approval screens:
//   - approveHero/rejectHero        <- hero_approvals_screen.dart
//                                       (_approveHero/_rejectHero,
//                                       ~lines 463-620)
//   - approveSeller/rejectSeller    <- admin_seller_approval_screen.dart
//                                       (~lines 304-412)
//   - approveSosKyc/rejectSosKyc    <- admin_sos_kyc_approvals_screen.dart
//                                       (_approve/_reject, ~lines 341-414)
// Deliberately copied rather than refactored to share code with those
// screens — this keeps the human-driven UI path and the AI-driven path
// each independently readable/auditable, and means a future change to
// one can never silently change the other's behavior.
//
// SAFETY MODEL — read before calling any method here:
//   - This file has NO knowledge of the Yes/No confirmation gate. It
//     trusts its caller completely. The ONLY caller is
//     admin_quick_task_service.dart's _executePendingAdminAction, and
//     it only calls in here after: (1) the CTO's explicit "Yes,
//     proceed", AND (2) a verified `uid` that came from a real
//     Firestore document AdminAiAuditTools actually read (never a
//     free-text guess) — see that file's "No Blind Writes" comment.
//   - No seller-code generation is implemented here. The CTO's mandate
//     mentioned it as an example ("...generating a seller code if
//     needed, etc.") but no such field/concept exists anywhere else in
//     this codebase (verified — no sellerCode/seller_code references
//     anywhere in lib/). Inventing one here would create a field
//     nothing else reads, so this mirrors the real approve flow
//     exactly (status -> 'active') instead of fabricating new schema.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class AdminKycWriteResult {
  const AdminKycWriteResult({required this.success, this.error});
  final bool success;
  final String? error;
}

class AdminKycWriteService {
  AdminKycWriteService._();

  // TASK 3 (Aug 8 2026) — KYC & Selfie Guard, AI co-pilot path.
  // Byte-for-byte mirror of hero_approvals_screen.dart's
  // _missingKycItems() — MUST be kept in sync with that check. Unlike
  // the human screen (which already has the hero's data map in hand
  // from its list StreamBuilder), this path only receives a uid, so it
  // fetches the doc itself before deciding.
  static List<String> _missingKycItems(Map<String, dynamic> data) {
    bool empty(String key) {
      final v = data[key];
      return v == null || (v is String && v.trim().isEmpty);
    }

    final missing = <String>[];
    if (empty('selfieUrl')) missing.add('Selfie photo');
    if (empty('aadhaarDocUrl')) missing.add('Aadhaar document');
    if (empty('panDocUrl')) missing.add('PAN document');
    if (empty('licenseDocUrl')) missing.add('License document');
    if (empty('name')) missing.add('Name');
    if (empty('phone')) missing.add('Phone number');
    return missing;
  }

  // ---- Hero -----------------------------------------------------
  static Future<AdminKycWriteResult> approveHero(String uid) async {
    try {
      final firestore = FirebaseFirestore.instance;

      // TASK 3: hard block, same as the human approvals screen — the
      // AI co-pilot must never be able to approve an incomplete hero
      // just because it wasn't told to check.
      final heroSnap = await firestore.collection('heroes').doc(uid).get();
      final heroData = heroSnap.data() ?? <String, dynamic>{};
      Map<String, dynamic> pendingData = <String, dynamic>{};
      final pendingSnap =
          await firestore.collection('heroes_pending').doc(uid).get();
      if (pendingSnap.exists) pendingData = pendingSnap.data() ?? {};
      // A field may live on either doc depending on registration path —
      // check whichever one actually has it.
      final merged = <String, dynamic>{...pendingData, ...heroData};
      final missing = _missingKycItems(merged);
      if (missing.isNotEmpty) {
        return AdminKycWriteResult(
          success: false,
          error: 'Cannot approve — hero is missing: ${missing.join(', ')}.',
        );
      }

      final batch = firestore.batch();
      final heroRef = firestore.collection('heroes').doc(uid);
      final pendingRef = firestore.collection('heroes_pending').doc(uid);
      final updateData = {
        'approvalStatus': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      };
      batch.set(heroRef, updateData, SetOptions(merge: true));
      if ((await pendingRef.get()).exists) {
        batch.set(pendingRef, updateData, SetOptions(merge: true));
      }
      await batch.commit();

      // Best-effort RTDB mirror, exact same pattern as
      // hero_approvals_screen.dart's _approveHero — failure here must
      // not roll back or fail the Firestore approval itself.
      try {
        await FirebaseDatabase.instance.ref('hero_status_updates/$uid').set({
          'type': 'approval',
          'timestamp': ServerValue.timestamp,
        });
      } catch (e) {
        debugPrint('[AdminKycWriteService] hero_status_updates write failed: $e');
      }
      return const AdminKycWriteResult(success: true);
    } catch (e) {
      debugPrint('[AdminKycWriteService] approveHero failed: $e');
      return AdminKycWriteResult(success: false, error: e.toString());
    }
  }

  static Future<AdminKycWriteResult> rejectHero(String uid, String reason) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();
      final heroRef = firestore.collection('heroes').doc(uid);
      final pendingRef = firestore.collection('heroes_pending').doc(uid);
      final updateData = {
        'approvalStatus': 'rejected',
        'rejectionReason': reason,
        'rejectedAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      };
      batch.set(heroRef, updateData, SetOptions(merge: true));
      if ((await pendingRef.get()).exists) {
        batch.set(pendingRef, updateData, SetOptions(merge: true));
      }
      await batch.commit();
      return const AdminKycWriteResult(success: true);
    } catch (e) {
      debugPrint('[AdminKycWriteService] rejectHero failed: $e');
      return AdminKycWriteResult(success: false, error: e.toString());
    }
  }

  // ---- Seller -----------------------------------------------------
  static Future<AdminKycWriteResult> approveSeller(String uid) async {
    try {
      await FirebaseFirestore.instance.collection('sellers').doc(uid).set(
        {
          'status': 'active',
          'approvedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return const AdminKycWriteResult(success: true);
    } catch (e) {
      debugPrint('[AdminKycWriteService] approveSeller failed: $e');
      return AdminKycWriteResult(success: false, error: e.toString());
    }
  }

  static Future<AdminKycWriteResult> rejectSeller(String uid, String reason) async {
    try {
      await FirebaseFirestore.instance.collection('sellers').doc(uid).set(
        {
          'status': 'rejected',
          'rejectionReason': reason,
          'rejectedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return const AdminKycWriteResult(success: true);
    } catch (e) {
      debugPrint('[AdminKycWriteService] rejectSeller failed: $e');
      return AdminKycWriteResult(success: false, error: e.toString());
    }
  }

  // ---- SOS KYC ------------------------------------------------------
  static Future<AdminKycWriteResult> approveSosKyc(String uid) async {
    try {
      await FirebaseFirestore.instance.collection('sos_kyc_requests').doc(uid).update({
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
      });
      return const AdminKycWriteResult(success: true);
    } catch (e) {
      debugPrint('[AdminKycWriteService] approveSosKyc failed: $e');
      return AdminKycWriteResult(success: false, error: e.toString());
    }
  }

  static Future<AdminKycWriteResult> rejectSosKyc(String uid, String reason) async {
    try {
      await FirebaseFirestore.instance.collection('sos_kyc_requests').doc(uid).update({
        'status': 'rejected',
        'rejectionReason': reason,
        'rejectedAt': FieldValue.serverTimestamp(),
      });
      return const AdminKycWriteResult(success: true);
    } catch (e) {
      debugPrint('[AdminKycWriteService] rejectSosKyc failed: $e');
      return AdminKycWriteResult(success: false, error: e.toString());
    }
  }
}
