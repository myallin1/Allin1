// ================================================================
// GiftCouponModel — "scratch card" gift coupon system.
//
// LIFECYCLE (per Nizam's design):
//   1. A customer completes ANY service in the app and pays for it.
//      A Cloud Function (functions/onServicePaidCreateCoupon.ts) fires
//      on that paymentStatus -> 'paid' write and auto-creates a coupon
//      in status 'awaiting_gift', with an `unlockAt` timer.
//   2. Admin opens the Gift Coupons section (Overview > Manage) and
//      sets what's actually inside: either a flat ₹ discount usable on
//      a future bill, or a free-text gift item collected offline.
//      Status becomes 'ready'.
//   3. Once `unlockAt` has passed, the customer can scratch the card
//      open in Rewards. Status becomes 'scratched' and the gift is
//      revealed. Both the timer and the scratch are enforced
//      server-side (scratchGiftCoupon) — never on client clock.
//   4. A 'discount' gift is then applied to a Hero task bill or Hotel
//      order (-> 'redeemed'). An 'item' gift is collected offline and
//      marked done by admin (-> 'claimed').
// ================================================================

import 'service_request_model.dart' show parseFlexibleTimestamp;

/// What's inside the card. Null until an admin has set it.
class GiftCouponType {
  static const String discount = 'discount';
  static const String item = 'item';
}

class GiftCouponStatus {
  /// Auto-created on payment; admin hasn't chosen the gift yet.
  static const String awaitingGift = 'awaiting_gift';

  /// Gift set by admin; scratchable once [GiftCouponModel.unlockAt] passes.
  static const String ready = 'ready';

  /// Customer scratched it open and has seen the gift.
  static const String scratched = 'scratched';

  /// A 'discount' gift that has been applied to a bill.
  static const String redeemed = 'redeemed';

  /// An 'item' gift that has been handed over offline.
  static const String claimed = 'claimed';
}

class GiftCouponModel {
  final String id;
  final String customerId;
  final String customerName;
  final String status;

  /// [GiftCouponType.discount] or [GiftCouponType.item]; null while the
  /// coupon is still in 'awaiting_gift'.
  final String? giftType;

  /// Rupee value for a `discount` gift.
  final num value;

  /// Human-readable gift for an `item` gift ("Free mobile cover").
  final String giftLabel;

  /// The paid service that earned this coupon.
  final String sourceRequestId;
  final String sourceRequestType;
  final String sourceSummary;

  /// Scratching is blocked until this moment (server-enforced).
  final DateTime? unlockAt;
  final DateTime? expiresAt;

  final String? giftSetBy;
  final DateTime? createdAt;
  final DateTime? giftSetAt;
  final DateTime? scratchedAt;
  final DateTime? redeemedAt;
  final String? redeemedOnRequestId;
  final String? redeemedOnRequestType;

  const GiftCouponModel({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.sourceRequestId,
    required this.sourceRequestType,
    this.status = GiftCouponStatus.awaitingGift,
    this.giftType,
    this.value = 0,
    this.giftLabel = '',
    this.sourceSummary = '',
    this.unlockAt,
    this.expiresAt,
    this.giftSetBy,
    this.createdAt,
    this.giftSetAt,
    this.scratchedAt,
    this.redeemedAt,
    this.redeemedOnRequestId,
    this.redeemedOnRequestType,
  });

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// The unlock timer has run out. Display-only — the server re-checks
  /// this on every scratch, so a customer with a fast device clock
  /// gains nothing.
  bool get isUnlocked =>
      unlockAt == null || !DateTime.now().isBefore(unlockAt!);

  /// Admin has set a gift and the timer has finished: the card is
  /// scratchable right now.
  bool get canScratch =>
      status == GiftCouponStatus.ready && isUnlocked && !isExpired;

  /// Gift set, but the timer is still counting down.
  bool get isCountingDown =>
      status == GiftCouponStatus.ready && !isUnlocked && !isExpired;

  /// Scratched open, and it's a ₹ discount still waiting to be spent.
  bool get isSpendableDiscount =>
      status == GiftCouponStatus.scratched &&
      giftType == GiftCouponType.discount &&
      value > 0 &&
      !isExpired;

  /// How long until the card unlocks (Duration.zero once unlocked).
  Duration get timeUntilUnlock {
    final unlock = unlockAt;
    if (unlock == null) return Duration.zero;
    final remaining = unlock.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// One-line description of the gift, for both the reveal UI and the
  /// admin list. Empty while the coupon is still 'awaiting_gift'.
  String get giftDescription {
    switch (giftType) {
      case GiftCouponType.discount:
        return '₹${value.toStringAsFixed(0)} OFF';
      case GiftCouponType.item:
        return giftLabel;
      default:
        return '';
    }
  }

  factory GiftCouponModel.fromFirestore(Map<String, dynamic> data, String id) {
    return GiftCouponModel(
      id: id,
      customerId: (data['customerId'] as String?) ?? '',
      customerName: (data['customerName'] as String?) ?? '',
      status: (data['status'] as String?) ?? GiftCouponStatus.awaitingGift,
      giftType: data['giftType'] as String?,
      value: (data['value'] as num?) ?? 0,
      giftLabel: (data['giftLabel'] as String?) ?? '',
      sourceRequestId: (data['sourceRequestId'] as String?) ?? '',
      sourceRequestType: (data['sourceRequestType'] as String?) ?? '',
      sourceSummary: (data['sourceSummary'] as String?) ?? '',
      unlockAt: parseFlexibleTimestamp(data['unlockAt']),
      expiresAt: parseFlexibleTimestamp(data['expiresAt']),
      giftSetBy: data['giftSetBy'] as String?,
      createdAt: parseFlexibleTimestamp(data['createdAt']),
      giftSetAt: parseFlexibleTimestamp(data['giftSetAt']),
      scratchedAt: parseFlexibleTimestamp(data['scratchedAt']),
      redeemedAt: parseFlexibleTimestamp(data['redeemedAt']),
      redeemedOnRequestId: data['redeemedOnRequestId'] as String?,
      redeemedOnRequestType: data['redeemedOnRequestType'] as String?,
    );
  }
}
