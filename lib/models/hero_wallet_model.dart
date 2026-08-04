// ================================================================
// HeroWalletModel — Prepaid Commission Wallet (Allin1 Super App)
// ================================================================
// NEW, separate system from `heroes/{uid}.walletBalance` /
// `wallet_transactions` (which track a hero's collected-fare earnings
// for payout bookkeeping — that stays completely untouched). This is
// the PREPAID side: heroes recharge real money into this balance, and
// the platform's commission is debited from it after every completed
// ride, per Nizam's "Revenue Master Plan" instruction. A hero whose
// balance drops below `lowBalanceThreshold` stops receiving new trip
// requests until they recharge again.
//
// Architecture constraint (explicit, from Nizam): NO Cloud Functions —
// the project is on Firebase's Spark (free) plan, which doesn't support
// them. Every balance mutation below is a client-side Firestore
// transaction, secured as tightly as Firestore Security Rules alone can
// manage (see firestore.rules — hero_wallets / hero_wallet_transactions
// / wallet_recharge_requests blocks).
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

class HeroWalletModel {
  final String heroId;
  final double balance;
  final double lifetimeRecharged;
  final double lifetimeCommissionPaid;
  final double lowBalanceThreshold;
  final bool isEligibleForRequests;
  final bool flaggedForReview;
  final DateTime? updatedAt;

  const HeroWalletModel({
    required this.heroId,
    this.balance = 0,
    this.lifetimeRecharged = 0,
    this.lifetimeCommissionPaid = 0,
    this.lowBalanceThreshold = 50,
    this.isEligibleForRequests = false,
    this.flaggedForReview = false,
    this.updatedAt,
  });

  factory HeroWalletModel.fromFirestore(Map<String, dynamic> data, String id) {
    final balance = (data['balance'] as num?)?.toDouble() ?? 0.0;
    final threshold = (data['lowBalanceThreshold'] as num?)?.toDouble() ?? 50.0;
    return HeroWalletModel(
      heroId: id,
      balance: balance,
      lifetimeRecharged: (data['lifetimeRecharged'] as num?)?.toDouble() ?? 0.0,
      lifetimeCommissionPaid:
          (data['lifetimeCommissionPaid'] as num?)?.toDouble() ?? 0.0,
      lowBalanceThreshold: threshold,
      // Recomputed defensively on read too, in case a doc was written by
      // an older code path — the source of truth is always "balance
      // versus threshold", never a stale stored flag alone.
      isEligibleForRequests:
          (data['isEligibleForRequests'] as bool?) ?? (balance >= threshold),
      flaggedForReview: data['flaggedForReview'] as bool? ?? false,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'balance': balance,
      'lifetimeRecharged': lifetimeRecharged,
      'lifetimeCommissionPaid': lifetimeCommissionPaid,
      'lowBalanceThreshold': lowBalanceThreshold,
      'isEligibleForRequests': isEligibleForRequests,
      'flaggedForReview': flaggedForReview,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  bool get isLowBalance => balance < lowBalanceThreshold;
}

// REPLACED (per Nizam's explicit instruction): the flat %
// RiderCommission-based cut is obsolete. `infraUsageFee` is the only
// debit type now -- a minimal, usage-proportional charge for server/DB
// maintenance (active-minutes-online + rides-handled), computed and
// batched client-side by HeroUsageAccumulatorService /
// HeroWalletService.flushUsageCost(). Zero activity produces zero
// entries of this type, by construction.
enum HeroWalletTxnType { recharge, infraUsageFee, clawback, adjustment }

extension HeroWalletTxnTypeX on HeroWalletTxnType {
  String get wireName {
    switch (this) {
      case HeroWalletTxnType.recharge:
        return 'recharge';
      case HeroWalletTxnType.infraUsageFee:
        return 'infra_usage_fee';
      case HeroWalletTxnType.clawback:
        return 'clawback';
      case HeroWalletTxnType.adjustment:
        return 'adjustment';
    }
  }

  static HeroWalletTxnType fromWire(String? value) {
    switch (value) {
      case 'recharge':
        return HeroWalletTxnType.recharge;
      case 'infra_usage_fee':
        return HeroWalletTxnType.infraUsageFee;
      case 'clawback':
        return HeroWalletTxnType.clawback;
      default:
        return HeroWalletTxnType.adjustment;
    }
  }
}

class HeroWalletTransactionModel {
  final String id;
  final String heroId;
  final HeroWalletTxnType type;
  final double amount; // positive = credit, negative = debit
  final double balanceAfter;
  final String? rideId;
  // Usage-fee breakdown (infra_usage_fee entries only) -- kept
  // transparent so a hero can see exactly what they were charged for,
  // per Nizam's "Transparent ... Earning Meter" requirement.
  final double? activeMinutes;
  final int? ridesHandled;
  final String? rechargeRequestId;
  final DateTime? createdAt;

  const HeroWalletTransactionModel({
    required this.id,
    required this.heroId,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.rideId,
    this.activeMinutes,
    this.ridesHandled,
    this.rechargeRequestId,
    this.createdAt,
  });

  factory HeroWalletTransactionModel.fromFirestore(
    Map<String, dynamic> data,
    String id,
  ) {
    return HeroWalletTransactionModel(
      id: id,
      heroId: data['heroId'] as String? ?? '',
      type: HeroWalletTxnTypeX.fromWire(data['type'] as String?),
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      balanceAfter: (data['balanceAfter'] as num?)?.toDouble() ?? 0.0,
      rideId: data['rideId'] as String?,
      activeMinutes: (data['activeMinutes'] as num?)?.toDouble(),
      ridesHandled: (data['ridesHandled'] as num?)?.toInt(),
      rechargeRequestId: data['rechargeRequestId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'heroId': heroId,
      'type': type.wireName,
      'amount': amount,
      'balanceAfter': balanceAfter,
      if (rideId != null) 'rideId': rideId,
      if (activeMinutes != null) 'activeMinutes': activeMinutes,
      if (ridesHandled != null) 'ridesHandled': ridesHandled,
      if (rechargeRequestId != null) 'rechargeRequestId': rechargeRequestId,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

enum WalletRechargeStatus { pending, approved, rejected }

extension WalletRechargeStatusX on WalletRechargeStatus {
  String get wireName => name;

  static WalletRechargeStatus fromWire(String? value) {
    switch (value) {
      case 'approved':
        return WalletRechargeStatus.approved;
      case 'rejected':
        return WalletRechargeStatus.rejected;
      default:
        return WalletRechargeStatus.pending;
    }
  }
}

class WalletRechargeRequestModel {
  final String id;
  final String heroId;
  final String? heroName;
  final double amount;
  final String upiRefNumber;
  final String screenshotUrl;
  final WalletRechargeStatus status;
  final DateTime? requestedAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? rejectionReason;

  const WalletRechargeRequestModel({
    required this.id,
    required this.heroId,
    this.heroName,
    required this.amount,
    required this.upiRefNumber,
    required this.screenshotUrl,
    this.status = WalletRechargeStatus.pending,
    this.requestedAt,
    this.reviewedAt,
    this.reviewedBy,
    this.rejectionReason,
  });

  factory WalletRechargeRequestModel.fromFirestore(
    Map<String, dynamic> data,
    String id,
  ) {
    return WalletRechargeRequestModel(
      id: id,
      heroId: data['heroId'] as String? ?? '',
      heroName: data['heroName'] as String?,
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      upiRefNumber: data['upiRefNumber'] as String? ?? '',
      screenshotUrl: data['screenshotUrl'] as String? ?? '',
      status: WalletRechargeStatusX.fromWire(data['status'] as String?),
      requestedAt: (data['requestedAt'] as Timestamp?)?.toDate(),
      reviewedAt: (data['reviewedAt'] as Timestamp?)?.toDate(),
      reviewedBy: data['reviewedBy'] as String?,
      rejectionReason: data['rejectionReason'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'heroId': heroId,
      if (heroName != null) 'heroName': heroName,
      'amount': amount,
      'upiRefNumber': upiRefNumber,
      'screenshotUrl': screenshotUrl,
      'status': status.wireName,
      'requestedAt': FieldValue.serverTimestamp(),
    };
  }
}
