// ================================================================
// UserWalletModel — Allin1 Super App
// NJ Coins Wallet Tracking - Phase 1 (Dummy Data Ready)
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'task_model.dart';

class UserWalletModel {
  final String userId;

  // NJ Coins Balance
  final int njCoinsBalance; // Current spendable balance
  final int njCoinsExpiring; // Coins expiring in 7 days
  final int njCoinsPending; // Coins pending validation

  // Streak Tracking
  final int currentStreak; // Consecutive days with task completion
  final int longestStreak; // Lifetime best streak
  final DateTime? lastTaskDate; // Last date user completed a task
  final int dailyEarnedCoins; // Coins earned today

  // Tier System
  final int userLevel; // 1=Bronze, 2=Silver, 3=Gold, 4=Platinum
  final int levelProgress; // ₹ earned toward next level
  final int levelGoal; // ₹ needed for next level

  // Lifetime Stats
  final int lifetimeEarned; // Total NJ Coins ever earned
  final int lifetimeSpent; // Total NJ Coins spent
  final int tasksCompleted; // Total tasks completed

  // Fraud Prevention
  final String? deviceId;
  final String? aadharHash; // SHA256 hash (null = not verified)
  final bool flaggedForReview;

  // Daily Coin Usage Tracking (CEO Security Guardrail)
  final int dailyCoinsUsed; // Coins used today (resets at midnight)
  final DateTime? lastCoinUseDate; // Last date coins were used
  final int
      maxDailyCoinLimit; // Max coins user can spend per day (default: 500)

  const UserWalletModel({
    required this.userId,
    this.njCoinsBalance = 0,
    this.njCoinsExpiring = 0,
    this.njCoinsPending = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.lastTaskDate,
    this.dailyEarnedCoins = 0,
    this.userLevel = 1,
    this.levelProgress = 0,
    this.levelGoal = 500,
    this.lifetimeEarned = 0,
    this.lifetimeSpent = 0,
    this.tasksCompleted = 0,
    this.deviceId,
    this.aadharHash,
    this.flaggedForReview = false,
    this.dailyCoinsUsed = 0,
    this.lastCoinUseDate,
    this.maxDailyCoinLimit = 500,
  });

  // Factory from Firestore (Phase 2)
  factory UserWalletModel.fromFirestore(Map<String, dynamic> data, String id) {
    return UserWalletModel(
      userId: id,
      njCoinsBalance: data['njCoinsBalance'] as int? ?? 0,
      njCoinsExpiring: data['njCoinsExpiring'] as int? ?? 0,
      njCoinsPending: data['njCoinsPending'] as int? ?? 0,
      currentStreak: data['currentStreak'] as int? ?? 0,
      longestStreak: data['longestStreak'] as int? ?? 0,
      lastTaskDate: data['lastTaskDate'] != null
          ? (data['lastTaskDate'] as Timestamp).toDate()
          : null,
      dailyEarnedCoins: data['dailyEarnedCoins'] as int? ?? 0,
      userLevel: data['userLevel'] as int? ?? 1,
      levelProgress: data['levelProgress'] as int? ?? 0,
      levelGoal: data['levelGoal'] as int? ?? 500,
      lifetimeEarned: data['lifetimeEarned'] as int? ?? 0,
      lifetimeSpent: data['lifetimeSpent'] as int? ?? 0,
      tasksCompleted: data['tasksCompleted'] as int? ?? 0,
      deviceId: data['deviceId'] as String?,
      aadharHash: data['aadharHash'] as String?,
      flaggedForReview: data['flaggedForReview'] as bool? ?? false,
      dailyCoinsUsed: data['dailyCoinsUsed'] as int? ?? 0,
      lastCoinUseDate: data['lastCoinUseDate'] != null
          ? (data['lastCoinUseDate'] as Timestamp).toDate()
          : null,
      maxDailyCoinLimit: data['maxDailyCoinLimit'] as int? ?? 500,
    );
  }

  // Convert to Firestore (Phase 2)
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'njCoinsBalance': njCoinsBalance,
      'njCoinsExpiring': njCoinsExpiring,
      'njCoinsPending': njCoinsPending,
      'currentStreak': currentStreak,
      'longestStreak': longestStreak,
      'lastTaskDate':
          lastTaskDate != null ? Timestamp.fromDate(lastTaskDate!) : null,
      'dailyEarnedCoins': dailyEarnedCoins,
      'userLevel': userLevel,
      'levelProgress': levelProgress,
      'levelGoal': levelGoal,
      'lifetimeEarned': lifetimeEarned,
      'lifetimeSpent': lifetimeSpent,
      'tasksCompleted': tasksCompleted,
      'deviceId': deviceId,
      'aadharHash': aadharHash,
      'flaggedForReview': flaggedForReview,
      'dailyCoinsUsed': dailyCoinsUsed,
      'lastCoinUseDate':
          lastCoinUseDate != null ? Timestamp.fromDate(lastCoinUseDate!) : null,
      'maxDailyCoinLimit': maxDailyCoinLimit,
    };
  }

  // Check if user is on streak
  bool isOnStreak() {
    if (lastTaskDate == null) {
      return false;
    }
    final now = DateTime.now();
    final last = lastTaskDate!;
    final diff = now.difference(last).inDays;
    return diff <= 1; // Within 24 hours
  }

  // Get streak bonus multiplier
  double getStreakMultiplier() {
    if (currentStreak >= 30) {
      return 2; // Platinum: 2x
    }
    if (currentStreak >= 14) {
      return 1.5; // Gold: 1.5x
    }
    if (currentStreak >= 7) {
      return 1.25; // Silver: 1.25x
    }
    if (currentStreak >= 3) {
      return 1.1; // Bronze: 1.1x
    }
    return 1;
  }

  // Get tier name
  String getTierName() {
    switch (userLevel) {
      case 4:
        return 'Platinum';
      case 3:
        return 'Gold';
      case 2:
        return 'Silver';
      default:
        return 'Bronze';
    }
  }

  // Get tier color
  int getTierColor() {
    switch (userLevel) {
      case 4:
        return 0xFFE5E4E2; // Platinum (silver-white)
      case 3:
        return 0xFFFFD700; // Gold
      case 2:
        return 0xFFC0C0C0; // Silver
      default:
        return 0xFFCD7F32; // Bronze
    }
  }

  // Progress to next level
  double getLevelProgressPercent() {
    if (levelGoal <= 0) {
      return 100;
    }
    return (levelProgress / levelGoal * 100).clamp(0.0, 100.0);
  }

  // Check if user can complete task (maxPerUser check)
  bool canCompleteTask(TaskModel task, int userCompletions) {
    return userCompletions < task.maxPerUser;
  }
}

// ================================================================
// DUMMY DATA FOR PHASE 1 TESTING
// ================================================================

abstract final class DummyUserWallet {
  static UserWalletModel getSampleWallet(String userId) {
    return UserWalletModel(
      userId: userId,
      njCoinsBalance: 340,
      njCoinsExpiring: 120,
      njCoinsPending: 50,
      currentStreak: 7,
      longestStreak: 21,
      lastTaskDate: DateTime.now().subtract(const Duration(hours: 5)),
      dailyEarnedCoins: 45,
      userLevel: 2, // Silver
      levelProgress: 340,
      lifetimeEarned: 2450,
      lifetimeSpent: 2110,
      tasksCompleted: 47,
      deviceId: 'device_123',
    );
  }
}
