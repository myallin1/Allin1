// ================================================================
// HeroWalletService — Usage Fee Wallet (Allin1 Super App)
// ================================================================
// REPLACED AGAIN (Sep 22 2026, per Nizam's explicit instruction) — this
// file previously recorded an Aug 11 2026 decision that this was NOT a
// percentage commission, deliberately computed from a hero's own real
// activity (minutes Online, rides handled) instead of a cut of their
// earnings. Nizam has now explicitly reversed that: the fee is 3.3% of
// each order/ride's amount, with a ₹2 floor per order (see
// [usageFeeRate]/[usageFeeMinimum] on flushUsageCost() below) — a real
// commission on hero earnings, chosen because a flat/activity-based fee
// put a hard ceiling on revenue from large orders regardless of their
// value, which works against the business scaling.
//
// Heroes recharge a prepaid balance (auto-credited immediately on
// submission, verified by admin afterward -- "Auto-Credit + Post-Verify
// / Claw-back"), and usage fees are debited from that same balance. A
// hero whose balance drops below [HeroWalletModel.lowBalanceThreshold]
// stops receiving new trip requests until they recharge again.
//
// "Zero Usage = Zero Cost" is structural, not a special case: if a hero
// never completes an order, flushUsageCost() is simply never called
// with anything to bill, and no infra_usage_fee entries are ever
// written for that hero. There is no recurring daily fee anywhere in
// this design.
//
// "Batched Background Deductions" (cost optimization, per Nizam):
// this method is intentionally NOT called every minute. It is called
// exactly twice per ride lifecycle at most -- once when a ride/order
// completes, once when the hero goes Offline -- with the completed
// orders' amounts accumulated by the caller (see
// HeroUsageAccumulatorService.recordRideHandled(orderAmount: ...) /
// consumeOrderAmounts()). This keeps OUR OWN Firestore write costs
// bounded by hero activity, not by wall-clock time.
//
// STRICT constraint (explicit, from Nizam): NO Cloud Functions — Spark
// (free) Firebase plan doesn't support them. Every mutation here is a
// plain client-side `FirebaseFirestore.runTransaction`, which is the
// strongest consistency guarantee available without server code: it
// re-reads the balance at commit time and retries automatically if
// another write raced it, so two concurrent transactions on the same
// hero's wallet can never silently clobber each other.
//
// What plain Firestore rules genuinely CANNOT stop, since there is no
// trusted server to independently recompute "the correct usage cost" or
// "did this UPI payment really happen": a modified client could, in
// theory, call these methods with fabricated numbers. This is the
// accepted trade-off of the no-Cloud-Functions constraint, mitigated by
// the post-verify claw-back flow for recharges.
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/hero_wallet_model.dart';
import './firestore_usage_tracking.dart';

class HeroWalletService {
  factory HeroWalletService() => _instance;
  HeroWalletService._internal() : _firestore = FirebaseFirestore.instance;
  static final HeroWalletService _instance = HeroWalletService._internal();

  // Sep 6 2026 — test-only seam so the recharge/claw-back transaction
  // logic can be verified against a fake in-memory Firestore, without
  // touching how the real singleton behaves anywhere in the app: every
  // existing `HeroWalletService()` call site is completely unaffected —
  // `_internal()` above still always wires the real
  // `FirebaseFirestore.instance`, exactly as before this change.
  @visibleForTesting
  HeroWalletService.test(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _walletRef(String heroId) =>
      _firestore.collection('hero_wallets').doc(heroId);

  CollectionReference<Map<String, dynamic>> _txnRef(String heroId) =>
      _walletRef(heroId).collection('transactions');

  CollectionReference<Map<String, dynamic>> get _rechargeRequestsRef =>
      _firestore.collection('wallet_recharge_requests');

  /// Live wallet balance/eligibility for a hero. Screens should build off
  /// this rather than a one-shot `get()` — balance changes on every ride
  /// completion, and the low-balance banner needs to react instantly.
  Stream<HeroWalletModel> watchWallet(String heroId) {
    return _walletRef(heroId).trackedSnapshots().map((snap) {
      if (!snap.exists || snap.data() == null) {
        return HeroWalletModel(heroId: heroId);
      }
      return HeroWalletModel.fromFirestore(snap.data()!, heroId);
    });
  }

  Stream<List<HeroWalletTransactionModel>> watchTransactions(
    String heroId, {
    int limit = 50,
  }) {
    return _txnRef(heroId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .trackedSnapshots()
        .map((snap) => snap.docs
            .map((d) => HeroWalletTransactionModel.fromFirestore(d.data(), d.id))
            .toList(),);
  }

  /// Submits a recharge request AND immediately credits the hero's
  /// wallet in the SAME transaction ("Auto-Credit"). The request stays
  /// `pending` for admin's post-verify pass; if it's later rejected, the
  /// admin approval screen writes a matching `clawback` debit (see
  /// [rejectRechargeRequest] below) that exactly reverses this credit.
  Future<void> submitRechargeRequest({
    required String heroId,
    required double amount, required String upiRefNumber, required String screenshotUrl, String? heroName,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Recharge amount must be positive');
    }
    final requestRef = _rechargeRequestsRef.doc();
    final walletRef = _walletRef(heroId);
    final txnRef = _txnRef(heroId).doc();

    await _firestore.runTransaction((tx) async {
      final walletSnap = await tx.get(walletRef);
      final currentBalance =
          (walletSnap.data()?['balance'] as num?)?.toDouble() ?? 0.0;
      final currentRecharged =
          (walletSnap.data()?['lifetimeRecharged'] as num?)?.toDouble() ?? 0.0;
      final threshold =
          (walletSnap.data()?['lowBalanceThreshold'] as num?)?.toDouble() ??
              50.0;
      final newBalance = currentBalance + amount;

      tx.set(
        requestRef,
        {
          ...WalletRechargeRequestModel(
            id: requestRef.id,
            heroId: heroId,
            heroName: heroName,
            amount: amount,
            upiRefNumber: upiRefNumber,
            screenshotUrl: screenshotUrl,
          ).toFirestore(),
          // SECURITY (Sep 6 2026, round 2): a one-way flip required by
          // firestore.rules' _heroWalletDeltaIsBacked — marks this
          // specific request as "already spent" on wallet credit, so a
          // hero can't point lastRechargeRequestId at the SAME
          // still-pending request more than once to double (or n-tuple)
          // credit themselves before an admin reviews it.
          'creditedToWallet': true,
        },
      );

      tx.set(
        walletRef,
        {
          'balance': newBalance,
          'lifetimeRecharged': currentRecharged + amount,
          'lowBalanceThreshold': threshold,
          'isEligibleForRequests': newBalance >= threshold,
          'updatedAt': FieldValue.serverTimestamp(),
          // SECURITY (Sep 6 2026): required by firestore.rules'
          // _heroWalletDeltaIsBacked — a balance increase is only
          // accepted when it points at a matching, freshly-created
          // `pending` recharge request for the exact same amount. Every
          // legitimate recharge already creates exactly this request
          // (see requestRef.set(...) above, same transaction), so this
          // is purely a pointer to work that was already happening —
          // nothing here changes what a real recharge does.
          'lastRechargeRequestId': requestRef.id,
        },
        SetOptions(merge: true),
      );

      tx.set(
        txnRef,
        HeroWalletTransactionModel(
          id: txnRef.id,
          heroId: heroId,
          type: HeroWalletTxnType.recharge,
          amount: amount,
          balanceAfter: newBalance,
          rechargeRequestId: requestRef.id,
        ).toFirestore(),
      );
    });
  }

  // REPLACED (Sep 22 2026, per Nizam's explicit instruction — reversing
  // the Aug 11 2026 "NOT a percentage commission" decision recorded
  // above). The old activity-based model (minutes online + per-ride
  // distance, capped at ₹6.50/ride) put a hard ceiling on revenue from
  // large orders regardless of their value — a ₹1000 courier job billed
  // the same ₹6.50 as a middling ride. Nizam's growth goal ("namma than
  // king ah irukanum") needs revenue that scales WITH the business, not
  // a fee that's capped independent of it. New model: 3.3% of the
  // order/ride amount, with a ₹2 floor so even a tiny order still
  // covers real infra cost.
  //   ₹40 order  -> max(1.32, 2.00)  = ₹2.00 (floor applies)
  //   ₹100 order -> max(3.30, 2.00)  = ₹3.30
  //   ₹250 order -> max(8.25, 2.00)  = ₹8.25
  //   ₹1000 order -> max(33.00, 2.00) = ₹33.00 (no cap — see above)
  static const double usageFeeRate = 0.033; // 3.3% of the order amount
  static const double usageFeeMinimum = 2; // ₹ floor per order

  // ================================================================
  // TOP-UP REMINDER FAN-OUT (Aug 17 2026)
  // ================================================================
  // Nizam: "namma hero ku namma use pandrathunala ivlo use pannirukeenga
  // so unga wallet ah topup pannnikonganu yella hero kum push messege
  // anupiklam."
  //
  // No Cloud Functions on the Spark plan, so the fan-out is written from
  // the ADMIN app: one notifications/{id} doc per hero, which the hero
  // app's existing notifications screen already renders. Nothing new to
  // build on the hero side.
  //
  // COST AND SAFETY:
  //  * Writes only to heroes ACTUALLY IN MINUS beyond [minOwed], not the
  //    whole fleet. A hero who owes nothing should never be nagged —
  //    that is how a reminder becomes spam and gets ignored by the
  //    people who do owe.
  //  * Batched (500/commit, Firestore's limit) rather than one write at
  //    a time.
  //  * The message carries the hero's OWN numbers, because "you owe
  //    ₹47.20" is actionable and "please top up" is not.
  //
  // Returns how many heroes were notified.
  Future<int> sendTopUpReminders({
    required String sentByAdminUid,
    double minOwed = 1.0,
  }) async {
    final snap = await _firestore.collection('hero_wallets').limit(500).get();

    final targets = <String, double>{};
    for (final d in snap.docs) {
      final bal = (d.data()['balance'] as num?)?.toDouble() ?? 0.0;
      if (bal < 0 && bal.abs() >= minOwed) targets[d.id] = bal.abs();
    }
    if (targets.isEmpty) return 0;

    final batch = _firestore.batch();
    targets.forEach((heroId, owed) {
      batch.set(_firestore.collection('notifications').doc(), {
        'userId': heroId,
        'title': 'Wallet top-up reminder',
        'message':
            'Your app usage fee so far is ₹${owed.toStringAsFixed(2)}. '
                'You can keep working as usual — please top up your wallet '
                'when convenient.',
        'type': 'wallet_topup',
        'amountOwed': owed,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        'sentBy': sentByAdminUid,
      });
    });
    await batch.commit();
    return targets.length;
  }

  /// Called by the Hero App at two batched points ONLY -- a ride/order
  /// completing, or the hero going Offline (see hero_ride_screen.dart /
  /// hero_home_screen.dart / service_request_service.dart) -- with the
  /// completed orders' amounts accumulated in memory since the last
  /// flush (see HeroUsageAccumulatorService.consumeOrderAmounts()).
  /// This is intentionally NOT called every minute in real time, per
  /// Nizam's explicit cost-optimization instruction: batching keeps OUR
  /// OWN Firestore write costs bounded by hero activity rather than by
  /// elapsed wall-clock time.
  ///
  /// "Zero Usage = Zero Cost": if [orderAmounts] is empty, this returns
  /// immediately without writing anything at all -- no entry, no wallet
  /// touch.
  ///
  /// This is intentionally SEPARATE from `heroes/{uid}.walletBalance` /
  /// `wallet_transactions` (the hero's own collected-cash earnings
  /// ledger) — that flow is unrelated and untouched by this method.
  ///
  /// Non-fatal by design at the call site: a failure here should never
  /// block the hero from completing/closing out a ride they already
  /// collected cash for, or from going Offline. Callers should wrap
  /// this in try/catch and just log on failure.
  Future<void> flushUsageCost({
    required String heroId,
    // One entry per completed order/ride since the last flush (see
    // HeroUsageAccumulatorService.recordRideHandled(orderAmount: ...)).
    // Each order bills independently at max(amount * usageFeeRate,
    // usageFeeMinimum) so a mix of a ₹40 order and a ₹500 order in the
    // same flush charges correctly for each, not an average of both.
    required List<double> orderAmounts,
    // FIX (Aug 11 2026 — Admin usage-fee ledger, Phase 2): optional,
    // denormalized onto the written transaction so the admin ledger
    // screen can render a hero name per row without an extra read per
    // hero — see HeroWalletTransactionModel.heroName for the full
    // rationale. Purely additive; every existing caller that doesn't
    // pass this keeps working exactly as before.
    String? heroName,
  }) async {
    if (orderAmounts.isEmpty) return;

    var rawCost = 0.0;
    for (final amount in orderAmounts) {
      // FIX (Sep 22 2026 reaudit): an order with no real amount (0, or
      // negative from a bad read) must contribute NOTHING, not the ₹2
      // floor — the floor exists to cover infra cost for a genuine
      // small order, not to charge a hero for an order this service
      // never actually saw a value for (e.g. service_request_service.
      // dart's finalAmount/estimatedAmount fallback chain landing on
      // its final `?? 0.0`). Charging ₹2 for phantom data would violate
      // this file's own "Zero Usage = Zero Cost" principle.
      if (amount <= 0) continue;
      final perOrder = amount * usageFeeRate;
      rawCost += perOrder > usageFeeMinimum ? perOrder : usageFeeMinimum;
    }
    // Round to paise -- avoids writing values like 0.0500000001 forever.
    final usageCost = (rawCost * 100).roundToDouble() / 100;
    if (usageCost <= 0) return;

    final walletRef = _walletRef(heroId);
    final txnRef = _txnRef(heroId).doc();

    await _firestore.runTransaction((tx) async {
      final walletSnap = await tx.get(walletRef);
      final currentBalance =
          (walletSnap.data()?['balance'] as num?)?.toDouble() ?? 0.0;
      final currentPaid =
          (walletSnap.data()?['lifetimeCommissionPaid'] as num?)
                  ?.toDouble() ??
              0.0;
      final threshold =
          (walletSnap.data()?['lowBalanceThreshold'] as num?)?.toDouble() ??
              50.0;
      // Balance is allowed to go negative here on purpose -- a hero
      // should never be blocked from CLOSING a ride they already
      // collected cash for, or from going Offline, just because their
      // prepaid balance was thin. Going negative simply makes
      // isEligibleForRequests false, which is exactly the enforcement
      // mechanism: they stop receiving NEW requests until they recharge
      // back above the threshold.
      final newBalance = currentBalance - usageCost;

      tx.set(
        walletRef,
        {
          'balance': newBalance,
          // Field name kept as lifetimeCommissionPaid for storage
          // continuity -- it is now, literally, lifetime commission
          // paid again (3.3% of order value), so the name that once
          // needed a "kept for continuity" excuse now just describes
          // the field correctly.
          'lifetimeCommissionPaid': currentPaid + usageCost,
          'lowBalanceThreshold': threshold,
          'isEligibleForRequests': newBalance >= threshold,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      tx.set(
        txnRef,
        HeroWalletTransactionModel(
          id: txnRef.id,
          heroId: heroId,
          type: HeroWalletTxnType.infraUsageFee,
          amount: -usageCost,
          balanceAfter: newBalance,
          ridesHandled: orderAmounts.length,
          heroName: heroName,
        ).toFirestore(),
      );
    });
  }

  // FIX (Hero Earnings & Online Time Monitor, Aug 11 2026, per Nizam —
  // "when they tap Fetch/Refresh, deduct a minimal micro-fee in paise
  // for the server read cost"): a hero's own Earnings/Online-Time
  // monitor is fetch-on-demand (no live listener — see
  // hero_earnings_screen.dart), but every tap still costs real
  // Firestore reads on OUR side. This is the same "activity = cost"
  // philosophy as flushUsageCost() above, just gated on a manual tap
  // instead of online-minutes/rides. Deliberately a tiny fixed amount
  // (10 paise), not a formula — this is a read-cost recovery fee, not
  // a service fee, so it doesn't need to scale with anything.
  static const double monitorRefreshFee = 0.10; // ₹0.10 per manual Fetch tap

  /// Charges the flat monitor-refresh micro-fee. Non-fatal by design —
  /// callers should NOT block the fetch itself on this; a failed
  /// micro-fee charge should never stop a hero from seeing their own
  /// earnings.
  Future<void> chargeMonitorRefreshFee(String heroId, {String? heroName}) async {
    const fee = monitorRefreshFee;
    final walletRef = _walletRef(heroId);
    final txnRef = _txnRef(heroId).doc();

    await _firestore.runTransaction((tx) async {
      final walletSnap = await tx.get(walletRef);
      final currentBalance =
          (walletSnap.data()?['balance'] as num?)?.toDouble() ?? 0.0;
      final currentPaid =
          (walletSnap.data()?['lifetimeCommissionPaid'] as num?)
                  ?.toDouble() ??
              0.0;
      final threshold =
          (walletSnap.data()?['lowBalanceThreshold'] as num?)?.toDouble() ??
              50.0;
      final newBalance = currentBalance - fee;

      tx.set(
        walletRef,
        {
          'balance': newBalance,
          'lifetimeCommissionPaid': currentPaid + fee,
          'lowBalanceThreshold': threshold,
          'isEligibleForRequests': newBalance >= threshold,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      tx.set(
        txnRef,
        HeroWalletTransactionModel(
          id: txnRef.id,
          heroId: heroId,
          type: HeroWalletTxnType.infraUsageFee,
          amount: -fee,
          balanceAfter: newBalance,
          heroName: heroName,
        ).toFirestore(),
      );
    });
  }

  /// Admin-only: approves a pending recharge request. The balance was
  /// already credited at submission time (auto-credit) -- approval just
  /// marks the request verified, no further balance change.
  Future<void> approveRechargeRequest({
    required String requestId,
    required String adminId,
  }) async {
    await _rechargeRequestsRef.doc(requestId).update({
      'status': WalletRechargeStatus.approved.wireName,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': adminId,
    });
  }

  /// Admin-only: rejects a pending recharge request and claws back the
  /// exact amount that was auto-credited at submission, in one
  /// transaction. Also flags the hero's wallet for review so the pattern
  /// is visible to admins reviewing that hero's history later.
  Future<void> rejectRechargeRequest({
    required String requestId,
    required String adminId,
    String? reason,
  }) async {
    final requestRef = _rechargeRequestsRef.doc(requestId);

    await _firestore.runTransaction((tx) async {
      final requestSnap = await tx.get(requestRef);
      if (!requestSnap.exists) {
        throw StateError('Recharge request $requestId not found');
      }
      final data = requestSnap.data()!;
      if (data['status'] != WalletRechargeStatus.pending.wireName) {
        // Already reviewed -- avoid double claw-back if an admin
        // double-taps Reject.
        return;
      }
      final heroId = data['heroId'] as String;
      final amount = (data['amount'] as num).toDouble();

      final walletRef = _walletRef(heroId);
      final walletSnap = await tx.get(walletRef);
      final currentBalance =
          (walletSnap.data()?['balance'] as num?)?.toDouble() ?? 0.0;
      final currentRecharged =
          (walletSnap.data()?['lifetimeRecharged'] as num?)?.toDouble() ?? 0.0;
      final threshold =
          (walletSnap.data()?['lowBalanceThreshold'] as num?)?.toDouble() ??
              50.0;
      final newBalance = currentBalance - amount;

      tx.update(requestRef, {
        'status': WalletRechargeStatus.rejected.wireName,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': adminId,
        if (reason != null) 'rejectionReason': reason,
      });

      tx.set(
        walletRef,
        {
          'balance': newBalance,
          'lifetimeRecharged':
              (currentRecharged - amount).clamp(0, double.infinity),
          'lowBalanceThreshold': threshold,
          'isEligibleForRequests': newBalance >= threshold,
          'flaggedForReview': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      final txnRef = _txnRef(heroId).doc();
      tx.set(
        txnRef,
        HeroWalletTransactionModel(
          id: txnRef.id,
          heroId: heroId,
          type: HeroWalletTxnType.clawback,
          amount: -amount,
          balanceAfter: newBalance,
          rechargeRequestId: requestId,
        ).toFirestore(),
      );
    });
  }

  Stream<List<WalletRechargeRequestModel>> watchPendingRechargeRequests() {
    return _rechargeRequestsRef
        .where('status', isEqualTo: WalletRechargeStatus.pending.wireName)
        .orderBy('requestedAt', descending: true)
        .trackedSnapshots()
        .map((snap) => snap.docs
            .map((d) => WalletRechargeRequestModel.fromFirestore(
                d.data(), d.id,),)
            .toList(),);
  }
}
