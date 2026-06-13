// ================================================================
// UserBalanceModel — Local-First edge cache model
// Allin1 Super App — Wallet / NJ Coins balance snapshot
// Backed by Hive (works on Android, iOS & PWA Web)
// ================================================================

import 'package:hive_flutter/hive_flutter.dart';

part 'user_balance_model.g.dart';

@HiveType(typeId: 12)
class UserBalanceModel extends HiveObject {
  @HiveField(0)
  final String userId;

  @HiveField(1)
  final int pendingCoins;

  @HiveField(2)
  final int verifiedCoins;

  /// Rupee wallet balance (for future fiat wallet feature)
  @HiveField(3)
  final double walletRupees;

  /// Total lifetime coins earned
  @HiveField(4)
  final int lifetimeCoins;

  /// Number of completed tasks
  @HiveField(5)
  final int completedTaskCount;

  /// When TrailBase/Firebase last updated this balance
  @HiveField(6)
  final String updatedAt; // ISO-8601

  /// When we last cached this locally
  @HiveField(7)
  final DateTime lastSynced;

  UserBalanceModel({
    required this.userId,
    required this.updatedAt,
    required this.lastSynced,
    this.pendingCoins = 0,
    this.verifiedCoins = 0,
    this.walletRupees = 0.0,
    this.lifetimeCoins = 0,
    this.completedTaskCount = 0,
  });

  /// Total coins (pending + verified)
  int get totalCoins => pendingCoins + verifiedCoins;

  /// Verified coins converted to rupees (1000 coins = ₹10)
  double get rupeeValue => verifiedCoins * (10.0 / 1000.0);

  bool get canWithdraw => verifiedCoins >= 5000;

  /// Create an empty/default balance for a new user
  factory UserBalanceModel.empty(String userId) => UserBalanceModel(
        userId: userId,
        updatedAt: DateTime.now().toIso8601String(),
        lastSynced: DateTime.now(),
      );

  factory UserBalanceModel.fromJson(Map<String, dynamic> json) =>
      UserBalanceModel(
        userId: json['user_id'] as String,
        pendingCoins: (json['pending_coins'] as num?)?.toInt() ?? 0,
        verifiedCoins: (json['verified_coins'] as num?)?.toInt() ?? 0,
        walletRupees: (json['wallet_rupees'] as num?)?.toDouble() ?? 0.0,
        lifetimeCoins: (json['lifetime_coins'] as num?)?.toInt() ?? 0,
        completedTaskCount:
            (json['completed_task_count'] as num?)?.toInt() ?? 0,
        updatedAt:
            (json['updated_at'] as String?) ?? DateTime.now().toIso8601String(),
        lastSynced: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'pending_coins': pendingCoins,
        'verified_coins': verifiedCoins,
        'wallet_rupees': walletRupees,
        'lifetime_coins': lifetimeCoins,
        'completed_task_count': completedTaskCount,
        'updated_at': updatedAt,
      };
}
