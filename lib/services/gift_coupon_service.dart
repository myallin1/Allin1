// ================================================================
// GiftCouponService — client access to the scratch-card gift coupon
// system. See lib/models/gift_coupon_model.dart for the full lifecycle.
//
// SECURITY SHAPE: this client NEVER writes a customer-side coupon
// change. Minting (onServiceRequestUpdated), revealing
// (scratchGiftCoupon) and spending (redeemGiftCoupon) are all Cloud
// Functions, and firestore.rules denies clients every write to
// gift_coupons. The customer methods here are therefore reads plus
// callable invocations only. The admin methods DO write directly —
// that's an admin-authenticated write the rules allow.
//
// QUERY SHAPE: every query below filters on a SINGLE equality field
// and sorts in Dart rather than with orderBy. That's deliberate — an
// equality + orderBy on a different field needs a composite index, and
// a missing/rebuilding index throws failed-precondition at runtime
// (the exact trap documented in task_service.dart). Coupon counts are
// small (one per paid service), so sorting client-side is free.
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/gift_coupon_model.dart';
import './firestore_usage_tracking.dart';

/// What was under the foil, as returned by scratchGiftCoupon.
class GiftCouponReveal {
  final String giftType;
  final num value;
  final String giftLabel;
  final String giftDescription;

  const GiftCouponReveal({
    required this.giftType,
    required this.value,
    required this.giftLabel,
    required this.giftDescription,
  });

  bool get isDiscount => giftType == GiftCouponType.discount;
}

/// Result of applying a discount coupon to a bill or a new order.
class GiftCouponRedemption {
  final num discount;
  final num payableAmount;
  const GiftCouponRedemption({required this.discount, required this.payableAmount});
}

class GiftCouponService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // ── CUSTOMER ────────────────────────────────────────────────────

  /// Every coupon of the signed-in customer that still matters to them:
  /// locked ones counting down, scratchable ones, and scratched
  /// discounts not yet spent. Fully-spent ones drop out.
  Stream<List<GiftCouponModel>> streamMyCoupons() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(const []);
    return _db
        .collection('gift_coupons')
        .where('customerId', isEqualTo: uid)
        // CTO audit (Weakness 5): bound the read. A customer realistically
        // holds 5–20 live coupons in a 60-day window, so this never
        // truncates in practice — it just stops one pathological account
        // from re-reading an unbounded set on every Rewards open.
        .limit(50)
        .trackedSnapshots()
        .map((snap) {
      final coupons = snap.docs
          .map((d) => GiftCouponModel.fromFirestore(d.data(), d.id))
          .where((c) =>
              !c.isExpired &&
              c.status != GiftCouponStatus.redeemed &&
              c.status != GiftCouponStatus.claimed &&
              c.status != GiftCouponStatus.cancelled)
          .toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0)));
      return coupons;
    });
  }

  /// Only the coupons that can actually be applied to a bill right now
  /// — scratched-open ₹ discounts. Feeds both redemption pickers.
  Stream<List<GiftCouponModel>> streamSpendableDiscounts() {
    return streamMyCoupons().map(
      (coupons) => coupons.where((c) => c.isSpendableDiscount).toList(),
    );
  }

  /// Scratch [couponId] open. The gift is revealed by the SERVER only
  /// after it re-checks the unlock timer against its own clock — the
  /// app genuinely does not know what's inside until this returns.
  Future<GiftCouponReveal> scratch(String couponId) async {
    try {
      final callable = _functions.httpsCallable('scratchGiftCoupon');
      final result = await callable.call<Map<String, dynamic>>({'couponId': couponId});
      final data = result.data;
      return GiftCouponReveal(
        giftType: (data['giftType'] as String?) ?? '',
        value: (data['value'] as num?) ?? 0,
        giftLabel: (data['giftLabel'] as String?) ?? '',
        giftDescription: (data['giftDescription'] as String?) ?? '',
      );
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Could not open this card.');
    }
  }

  /// Apply a scratched ₹ discount to an EXISTING service_requests doc.
  /// Used by BOTH redemption points — the Heroes task bill and the
  /// Hotel checkout (which now creates its order first and redeems
  /// against it, see custom_hotel_view_screen.dart).
  ///
  /// The Cloud Function reads the real bill amount off Firestore; no
  /// amount is ever sent from here.
  Future<GiftCouponRedemption> redeemOnServiceRequest({
    required String couponId,
    required String requestId,
  }) async {
    try {
      final callable = _functions.httpsCallable('redeemGiftCoupon');
      final result = await callable.call<Map<String, dynamic>>({
        'couponId': couponId,
        'requestId': requestId,
      });
      final data = result.data;
      return GiftCouponRedemption(
        discount: (data['discount'] as num?) ?? 0,
        payableAmount: (data['payableAmount'] as num?) ?? 0,
      );
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Could not redeem this coupon.');
    }
  }

  // ── ADMIN ───────────────────────────────────────────────────────

  /// Every coupon in [status], newest first — one tab of the admin
  /// Gift Coupons screen.
  Stream<List<GiftCouponModel>> streamCouponsByStatus(String status) {
    return _db
        .collection('gift_coupons')
        .where('status', isEqualTo: status)
        .trackedSnapshots()
        .map((snap) {
      final coupons = snap.docs
          .map((d) => GiftCouponModel.fromFirestore(d.data(), d.id))
          .toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0)));
      return coupons;
    });
  }

  /// Every armed coupon's sealed gift, keyed by coupon id. Admin-only
  /// (see the `gift_coupon_gifts` rule) — this is what the customer
  /// deliberately cannot read.
  ///
  /// ONE stream for the whole screen, joined in memory against the
  /// coupon list, rather than a read per rendered card — the same
  /// "no per-card reads" rule the rest of the admin app follows.
  Stream<Map<String, GiftCouponReveal>> streamSealedGifts() {
    return _db.collection('gift_coupon_gifts').trackedSnapshots().map((snap) {
      final map = <String, GiftCouponReveal>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final giftType = (data['giftType'] as String?) ?? '';
        final value = (data['value'] as num?) ?? 0;
        final giftLabel = (data['giftLabel'] as String?) ?? '';
        map[doc.id] = GiftCouponReveal(
          giftType: giftType,
          value: value,
          giftLabel: giftLabel,
          giftDescription: giftType == GiftCouponType.discount
              ? '₹${value.toStringAsFixed(0)} OFF'
              : giftLabel,
        );
      }
      return map;
    });
  }

  /// Admin decides what's inside a coupon and arms it. This is the
  /// 'awaiting_gift' -> 'ready' transition; after it, the customer can
  /// scratch as soon as [unlockAt] passes.
  ///
  /// Pass either [discountValue] (a ₹ amount usable on a future bill)
  /// or [giftLabel] (a gift collected in person) — never both.
  ///
  /// THE GIFT ITSELF GOES TO `gift_coupon_gifts`, NOT ONTO THE COUPON.
  /// The customer can read their own gift_coupons doc (that's how the
  /// countdown renders), so putting the prize there would let a patched
  /// client read it before scratching. scratchGiftCoupon copies it
  /// across at the moment of the reveal. The coupon doc gets only the
  /// status change and the timer.
  Future<void> setGift({
    required String couponId,
    num? discountValue,
    String? giftLabel,
    DateTime? unlockAt,
  }) async {
    final isDiscount = discountValue != null && discountValue > 0;
    if (!isDiscount && (giftLabel == null || giftLabel.trim().isEmpty)) {
      throw ArgumentError('Provide either a discount value or a gift label.');
    }

    // Seal the envelope FIRST. If this succeeds but the coupon update
    // below fails, the coupon simply stays in 'awaiting_gift' and the
    // admin retries — no half-armed card the customer can scratch into
    // an empty envelope.
    await _db.collection('gift_coupon_gifts').doc(couponId).set({
      'giftType': isDiscount ? GiftCouponType.discount : GiftCouponType.item,
      'value': isDiscount ? discountValue : 0,
      'giftLabel': isDiscount ? '' : giftLabel!.trim(),
      'setBy': FirebaseAuth.instance.currentUser?.uid,
      'setAt': FieldValue.serverTimestamp(),
    });

    await _db.collection('gift_coupons').doc(couponId).update({
      'status': GiftCouponStatus.ready,
      if (unlockAt != null) 'unlockAt': Timestamp.fromDate(unlockAt),
      'giftSetBy': FirebaseAuth.instance.currentUser?.uid,
      'giftSetAt': FieldValue.serverTimestamp(),
    });
  }

  /// Admin marks an 'item' gift as physically handed over.
  Future<void> markItemClaimed(String couponId) {
    return _db.collection('gift_coupons').doc(couponId).update({
      'status': GiftCouponStatus.claimed,
      'redeemedAt': FieldValue.serverTimestamp(),
    });
  }
}
