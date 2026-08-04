// ================================================================
// HeroWalletService — App Infra Cost Recovery Wallet (Allin1 Super App)
// ================================================================
// REPLACED per Nizam's explicit instruction: this is NOT a percentage
// commission on hero earnings anymore. We provide a free earning
// portal and charge only a minimal, usage-proportional fee for
// server/database maintenance -- computed from a hero's own real
// activity (minutes spent Online, rides handled), never a cut of what
// they earn. Heroes recharge a prepaid balance (auto-credited
// immediately on submission, verified by admin afterward -- "Auto-
// Credit + Post-Verify / Claw-back"), and infra usage fees are debited
// from that same balance. A hero whose balance drops below
// [HeroWalletModel.lowBalanceThreshold] stops receiving new trip
// requests until they recharge again.
//
// "Zero Usage = Zero Cost" is structural, not a special case: if a hero
// never opens the app / never goes Online, HeroUsageAccumulatorService
// never starts a session, flushUsageCost() is simply never called, and
// no infra_usage_fee entries are ever written for that hero. There is
// no recurring daily fee anywhere in this design.
//
// "Batched Background Deductions" (cost optimization, per Nizam):
// this method is intentionally NOT called every minute. It is called
// exactly twice per ride lifecycle at most -- once when a ride
// completes, once when the hero goes Offline -- with the accumulated
// minutes/rides handed in by the caller (see
// HeroUsageAccumulatorService.consumeActiveMinutes() /
// consumeRidesHandled()). This keeps OUR OWN Firestore write costs
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

import '../models/hero_wallet_model.dart';

class HeroWalletService {
  factory HeroWalletService() => _instance;
  HeroWalletService._internal();
  static final HeroWalletService _instance = HeroWalletService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
    return _walletRef(heroId).snapshots().map((snap) {
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
        .snapshots()
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
        WalletRechargeRequestModel(
          id: requestRef.id,
          heroId: heroId,
          heroName: heroName,
          amount: amount,
          upiRefNumber: upiRefNumber,
          screenshotUrl: screenshotUrl,
        ).toFirestore(),
      );

      tx.set(
        walletRef,
        {
          'balance': newBalance,
          'lifetimeRecharged': currentRecharged + amount,
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
          type: HeroWalletTxnType.recharge,
          amount: amount,
          balanceAfter: newBalance,
          rechargeRequestId: requestRef.id,
        ).toFirestore(),
      );
    });
  }

  // Token formula (per Nizam's "App Infra Cost Recovery" architecture):
  // a minimal charge per minute the hero was actually Online (server
  // presence writes, RTDB radar listeners, ping subscriptions -- all
  // genuine infra load), plus a minimal charge per ride actually
  // handled (dispatch + status-update + payment-settlement reads/
  // writes). Both terms are strictly activity-driven, so zero activity
  // produces exactly zero cost. Tune these two constants to match real
  // observed Firestore/RTDB cost per hero -- they are the entire
  // pricing model now, replacing RiderCommission for heroes.
  static const double ratePerActiveMinute = 0.05; // ₹ per online minute
  static const double ratePerRideHandled = 2; // ₹ per completed ride

  /// Called by the Hero App at two batched points ONLY -- a ride
  /// completing, or the hero going Offline (see
  /// hero_ride_screen.dart / hero_home_screen.dart) -- with the minutes/
  /// rides accumulated in memory since the last flush (see
  /// HeroUsageAccumulatorService). This is intentionally NOT called
  /// every minute in real time, per Nizam's explicit cost-optimization
  /// instruction: batching keeps OUR OWN Firestore write costs bounded
  /// by hero activity rather than by elapsed wall-clock time.
  ///
  /// "Zero Usage = Zero Cost": if both [activeMinutes] and
  /// [ridesHandled] are (approximately) zero, this returns immediately
  /// without writing anything at all -- no entry, no wallet touch.
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
    required double activeMinutes,
    required int ridesHandled,
  }) async {
    if (activeMinutes <= 0 && ridesHandled <= 0) return;

    final rawCost =
        (activeMinutes * ratePerActiveMinute) + (ridesHandled * ratePerRideHandled);
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
          // continuity with the (now-obsolete) commission model this
          // replaced -- semantically it's lifetime infra usage fees
          // paid. Renaming would just be churn for a single number.
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
          activeMinutes: activeMinutes,
          ridesHandled: ridesHandled,
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
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => WalletRechargeRequestModel.fromFirestore(
                d.data(), d.id,),)
            .toList(),);
  }
}
