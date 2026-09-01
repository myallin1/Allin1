// ================================================================
// sos_dispatch_service.dart — claim / resolve / escalate a customer
// SOS alert
// ================================================================
// NEW (Aug 29 2026 — Nizam's full spec, in his own words):
// "customer navigate pandra location and phone number um nearbyla 5kms
// kulla irukka yella emergency responder kum poganum... apo heros sos
// requst kuduththa customer call panni ketparu 'ungaluku yethum
// problema' nu, avanga onnilla sollita heros no problem-nu andha
// request close panniruvanga, suppose customer phone yedukalaina
// pakkathula irukka yella hero-vும் antha place-ku poi customer-ku
// yenna problem-nu paathu kappathuvanga."
//
// That is a 4-state lifecycle on top of the existing `sos_alerts`
// collection (sos_screen.dart already writes the initial doc — this
// file adds everything that happens to it afterward):
//
//   active    — broadcasting to every Emergency Responder hero within
//               5km (see hero_home_screen.dart's SOS overlay, which
//               already does the 5km distance filter client-side; this
//               service only needs to gate WHO is allowed to claim).
//   claimed   — exactly one hero has it, is calling the customer.
//   escalated — that hero couldn't reach the customer by phone. Back to
//               every nearby responder, same as active but visibly
//               flagged so a hero can see this is a SECOND attempt, not
//               a fresh alert.
//   resolved  — either the customer confirmed they're fine, or (out of
//               scope for this file) admin manually closes it.
//
// WHY A FIRESTORE TRANSACTION FOR THE CLAIM
// Multiple Emergency Responder heroes can be looking at the same alert
// at the same moment — that is the whole point of broadcasting to all
// of them. Without a transaction, two heroes tapping "I'm Responding"
// within the same second could both believe they own it, and the
// customer gets two different heroes turning up (or worse, both
// heroes assume the OTHER one is handling it and neither calls). A
// transaction makes "first tap wins" atomic, mirroring the exact
// pattern service_request_service.dart's acceptServiceRequest and
// hero_home_screen.dart's ride-accept already use for the identical
// race.
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

/// Alert lifecycle values for `sos_alerts/{id}.status`. 'active' is
/// unchanged from the pre-existing sos_screen.dart writer — the three
/// new values are additive, so a client that has never heard of this
/// file (there wasn't one before today) still sees exactly the
/// 'active'/non-'active' distinction it always has.
class SosAlertStatus {
  SosAlertStatus._();
  static const String active = 'active';
  static const String claimed = 'claimed';
  static const String escalated = 'escalated';
  static const String resolved = 'resolved';
}

/// Why a resolved alert was closed. Only one reason exists today
/// ('no_problem') but this is a String, not a bool, so a future admin
/// manual-close path has somewhere to record its own reason without a
/// schema change.
class SosResolution {
  SosResolution._();
  static const String noProblem = 'no_problem';
}

class SosDispatchService {
  SosDispatchService._();
  static final SosDispatchService instance = SosDispatchService._();

  CollectionReference<Map<String, dynamic>> get _alerts =>
      FirebaseFirestore.instance.collection('sos_alerts');

  /// A hero taps "I'm Responding". Succeeds only if nobody else has
  /// already claimed (or re-claimed after an escalation) this exact
  /// alert — see the file header for why this must be a transaction.
  ///
  /// Returns true if THIS hero now owns the alert, false if someone else
  /// won the race (or the alert is already resolved) — the caller uses
  /// this to decide whether to show the call/resolve UI or step back.
  Future<bool> claim({
    required String alertId,
    required String heroId,
    required String heroName,
    required String heroPhone,
  }) async {
    final ref = _alerts.doc(alertId);
    try {
      return await FirebaseFirestore.instance.runTransaction<bool>((txn) async {
        final snap = await txn.get(ref);
        if (!snap.exists) return false;
        final data = snap.data()!;
        final status = data['status'] as String? ?? SosAlertStatus.active;

        // Claimable from 'active' (first responder) or 'escalated' (the
        // previous responder's call went unanswered — anyone nearby,
        // including that same hero, may claim it again). NOT claimable
        // from 'claimed' (someone else already has it) or 'resolved'
        // (already handled).
        if (status != SosAlertStatus.active &&
            status != SosAlertStatus.escalated) {
          return false;
        }

        txn.update(ref, {
          'status': SosAlertStatus.claimed,
          'claimedByHeroId': heroId,
          'claimedByHeroName': heroName,
          'claimedByHeroPhone': heroPhone,
          'claimedAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
    } catch (_) {
      // A transaction abort/permission hiccup reads as "didn't win the
      // claim" rather than a crash — the calling hero just sees the
      // overlay step back to "someone else is handling this", which is
      // the safe default when we can't be sure.
      return false;
    }
  }

  /// The claiming hero called the customer and the customer said
  /// they're fine. Closes the alert for good — no further escalation.
  Future<void> resolveNoProblem({
    required String alertId,
    required String heroId,
  }) {
    return _alerts.doc(alertId).update({
      'status': SosAlertStatus.resolved,
      'resolvedReason': SosResolution.noProblem,
      'resolvedByHeroId': heroId,
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }

  /// The claiming hero called and got no answer. Releases the claim and
  /// flips status to 'escalated' so EVERY Emergency Responder within 5km
  /// — including the one who just tried — sees it again, per Nizam's
  /// "pakkathula irukka yella hero-vும் antha place-ku poi paathu
  /// kappathuvanga": if a phone call can't confirm the customer is safe,
  /// the fallback is heroes physically going to check.
  ///
  /// escalatedCount is incremented (not just a boolean) so the overlay
  /// can eventually say "3rd attempt" if this keeps happening, rather
  /// than looking identical to the first broadcast forever.
  Future<void> escalateNoAnswer({
    required String alertId,
  }) {
    return _alerts.doc(alertId).update({
      'status': SosAlertStatus.escalated,
      'claimedByHeroId': null,
      'claimedByHeroName': null,
      'claimedByHeroPhone': null,
      'escalatedCount': FieldValue.increment(1),
      'lastEscalatedAt': FieldValue.serverTimestamp(),
    });
  }
}
