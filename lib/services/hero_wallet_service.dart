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
  // ================================================================
  // RATES (retuned Aug 17 2026 — Nizam)
  // ================================================================
  // Target, in Nizam's words: "oru small ride ku 2 rupee range ku
  // generate aganum, long rides ku five rupee aganum, but flat ah 2,5
  // rupees agakudathu... 1.85, 2.10, 3.60 nu rupees and paise la
  // generate aganum."
  //
  // So the requirement is not just a price level, it is that the price
  // must LOOK computed — a metered amount ending in paise, not a tariff.
  // That falls out naturally here because both inputs (km and billable
  // minutes) are continuous: no rounding to whole rupees anywhere, only
  // a final round to 2 decimal places.
  //
  // Worked examples with the constants below:
  //   3 km,  15 min  -> 0.90 + 0.66 + 0.30 = ₹1.86
  //   4 km,  18 min  -> 0.90 + 0.88 + 0.36 = ₹2.14
  //   8 km,  25 min  -> 0.90 + 1.76 + 0.50 = ₹3.16
  //  15 km,  45 min  -> 0.90 + 3.30 + 0.90 = ₹5.10
  // Small rides land around ₹2, long rides around ₹5, and no two rides
  // bill the same amount unless they were genuinely identical.
  //
  // IMPORTANT: ratePerActiveMinute is now applied to BILLABLE minutes
  // (time spent on an accepted job), not online minutes. A hero waiting
  // for work is billed nothing — see HeroUsageAccumulatorService's
  // startBillableWork/stopBillableWork.
  static const double ratePerActiveMinute = 0.02; // ₹ per minute ON A JOB
  // FIX (Dynamic Micro-Billing, Aug 11 2026, per Nizam — "switch to a
  // dynamic, fractional model based on the service scope"): this flat
  // rate now applies ONLY to completed activity with no distance
  // concept — service_requests (Hero Booking, Custom Order, Custom
  // Food Order, Grocery Order). Actual rides bill via
  // [ratePerRideBase]/[ratePerKm]/[maxFeePerRide] below instead — see
  // the per-ride loop in flushUsageCost(). Kept as the fallback for any
  // ride whose distance wasn't passed in, so nothing silently bills
  // ₹0.
  // Distance-less tasks (Hero Booking, Custom/Grocery/Food orders).
  // Lowered from a flat ₹2 so it is not the single most expensive line
  // on a hero's bill; the billable-minutes term now carries the "how
  // much work was this" signal instead, which is what makes these vary.
  static const double ratePerRideHandled = 1.20; // ₹ per completed task
  static const double ratePerRideBase = 0.90; // ₹ base fee per actual ride
  static const double ratePerKm = 0.22; // ₹ per km travelled
  // Raised from ₹3.00: the old cap sat BELOW the ₹5 long-ride target, so
  // every long ride would have flattened to exactly ₹3.00 — producing
  // precisely the "flat rate" outcome that was asked to be avoided. The
  // cap now only catches genuine outliers (a 40km+ trip).
  static const double maxFeePerRide = 6.50;

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
            'Your app usage so far is ₹${owed.toStringAsFixed(2)}. '
                'You can keep working as usual — please top up your wallet '
                'when convenient. We take 0% commission on your rides.',
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
    // FIX (Dynamic Micro-Billing, Aug 11 2026): distance (km) of each
    // ACTUAL ride included in [ridesHandled] since the last flush —
    // see HeroUsageAccumulatorService.consumeRideDistances(). Every
    // entry here bills at base+per-km (capped), instead of the flat
    // rate. `ridesHandled - rideDistancesKm.length` is the remaining
    // count with no distance (service_requests), which still bills at
    // the unchanged flat ratePerRideHandled. Purely additive — omit it
    // (default empty) and every ride in [ridesHandled] bills flat,
    // exactly as before this change.
    List<double> rideDistancesKm = const [],
    // FIX (Aug 11 2026 — Admin usage-fee ledger, Phase 2): optional,
    // denormalized onto the written transaction so the admin ledger
    // screen can render a hero name per row without an extra read per
    // hero — see HeroWalletTransactionModel.heroName for the full
    // rationale. Purely additive; every existing caller that doesn't
    // pass this keeps working exactly as before.
    String? heroName,
  }) async {
    if (activeMinutes <= 0 && ridesHandled <= 0) return;

    // Distance-based component: base fee + per-km, capped per ride —
    // e.g. a 5km ride bills ₹0.90 + (5 × ₹0.22) = ₹2.00 before the
    // billable-minutes term is added on top. The cap only bites on a
    // genuine outlier (~25km+), so ordinary long rides still land on a
    // computed paise amount rather than flattening to the cap.
    var rideComponent = 0.0;
    for (final km in rideDistancesKm) {
      final perRide = ratePerRideBase + (km * ratePerKm);
      rideComponent += perRide > maxFeePerRide ? maxFeePerRide : perRide;
    }
    // Whatever's left in ridesHandled after the distance-billed rides
    // are accounted for is flat-rate activity (service_requests, or a
    // ride whose distance genuinely wasn't available).
    final flatCount = ridesHandled - rideDistancesKm.length;
    final flatComponent =
        (flatCount > 0 ? flatCount : 0) * ratePerRideHandled;

    final rawCost =
        (activeMinutes * ratePerActiveMinute) + rideComponent + flatComponent;
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
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => WalletRechargeRequestModel.fromFirestore(
                d.data(), d.id,),)
            .toList(),);
  }
}
