// ================================================================
// GiftCouponService — client access to the scratch-card gift coupon
// system. See lib/models/gift_coupon_model.dart for the full lifecycle.
//
// SECURITY SHAPE: this client NEVER writes a customer-side coupon
// change. Minting (onServicePaidCreateCoupon), revealing
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
        .snapshots()
        .map((snap) {
      final coupons = snap.docs
          .map((d) => GiftCouponModel.fromFirestore(d.data(), d.id))
          .where((c) =>
              !c.isExpired &&
              c.status != GiftCouponStatus.redeemed &&
              c.status != GiftCouponStatus.claimed)
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

  /// Apply a scratched discount to an EXISTING service_requests bill
  /// (the Heroes flow) — the Cloud Function reads the bill's real
  /// amount itself and returns the new payable amount.
  Future<GiftCouponRedemption> redeemOnServiceRequest({
    required String couponId,
    required String requestId,
  }) {
    return _callRedeem({'couponId': couponId, 'requestId': requestId});
  }

  /// Apply a scratched discount to a NOT-YET-CREATED order (the Hotel
  /// checkout flow) — [orderAmount] is the live cart subtotal.
  Future<GiftCouponRedemption> redeemForNewOrder({
    required String couponId,
    required num orderAmount,
    required String requestType,
  }) {
    return _callRedeem({
      'couponId': couponId,
      'orderAmount': orderAmount,
      'requestType': requestType,
    });
  }

  Future<GiftCouponRedemption> _callRedeem(Map<String, dynamic> payload) async {
    try {
      final callable = _functions.httpsCallable('redeemGiftCoupon');
      final result = await callable.call<Map<String, dynamic>>(payload);
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
        .snapshots()
        .map((snap) {
      final coupons = snap.docs
          .map((d) => GiftCouponModel.fromFirestore(d.data(), d.id))
          .toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0)));
      return coupons;
    });
  }

  /// Admin decides what's inside a coupon and arms it. This is the
  /// 'awaiting_gift' -> 'ready' transition; after it, the customer can
  /// scratch as soon as [unlockAt] passes.
  ///
  /// Pass either [discountValue] (a ₹ amount usable on a future bill)
  /// or [giftLabel] (a gift collected in person) — never both.
  Future<void> setGift({
    required String couponId,
    num? discountValue,
    String? giftLabel,
    DateTime? unlockAt,
  }) {
    final isDiscount = discountValue != null && discountValue > 0;
    if (!isDiscount && (giftLabel == null || giftLabel.trim().isEmpty)) {
      throw ArgumentError('Provide either a discount value or a gift label.');
    }
    return _db.collection('gift_coupons').doc(couponId).update({
      'status': GiftCouponStatus.ready,
      'giftType': isDiscount ? GiftCouponType.discount : GiftCouponType.item,
      'value': isDiscount ? discountValue : 0,
      'giftLabel': isDiscount ? '' : giftLabel!.trim(),
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
