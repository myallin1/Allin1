// ================================================================
// API Contracts — Allin1 Super App
// Expected JSON Response Formats for Phase 2 Backend Integration
// ================================================================

import '../models/user_wallet_model.dart';

// ================================================================
// TASK API RESPONSES
// ================================================================

/// Response from: GET /api/tasks
class TaskListResponse {
  final bool success;
  final String message;
  final List<TaskData> tasks;
  final int total;

  TaskListResponse({
    required this.success,
    required this.message,
    required this.tasks,
    required this.total,
  });

  factory TaskListResponse.fromJson(Map<String, dynamic> json) {
    return TaskListResponse(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      tasks: (json['tasks'] as List?)
              ?.map((t) => TaskData.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      total: json['total'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
      'tasks': tasks.map((t) => t.toJson()).toList(),
      'total': total,
    };
  }
}

/// Individual Task Data Model
class TaskData {
  final String taskId;
  final String title;
  final String description;
  final String partnerName;
  final String partnerLogo;
  final int rewardCoins;
  final String category;
  final bool isActive;
  final int expiryDays;
  final int maxPerUser;
  final int cooldownMinutes;
  final int totalCompletions;
  final int availableSlots;
  final DateTime? expiresAt;
  final String? trackingUrl; // Phase 3: Added for redirection

  TaskData({
    required this.taskId,
    required this.title,
    required this.description,
    required this.partnerName,
    required this.partnerLogo,
    required this.rewardCoins,
    required this.category,
    required this.isActive,
    required this.expiryDays,
    required this.maxPerUser,
    required this.cooldownMinutes,
    required this.totalCompletions,
    required this.availableSlots,
    this.expiresAt,
    this.trackingUrl,
  });

  factory TaskData.fromJson(Map<String, dynamic> json) {
    return TaskData(
      taskId: json['taskId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      partnerName: json['partnerName'] as String? ?? '',
      partnerLogo: json['partnerLogo'] as String? ?? '',
      rewardCoins: json['rewardCoins'] as int? ?? 0,
      category: json['category'] as String? ?? 'general',
      isActive: json['isActive'] as bool? ?? true,
      expiryDays: json['expiryDays'] as int? ?? 30,
      maxPerUser: json['maxPerUser'] as int? ?? 1,
      cooldownMinutes: json['cooldownMinutes'] as int? ?? 0,
      totalCompletions: json['totalCompletions'] as int? ?? 0,
      availableSlots: json['availableSlots'] as int? ?? 100,
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      trackingUrl: json['trackingUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'taskId': taskId,
      'title': title,
      'description': description,
      'partnerName': partnerName,
      'partnerLogo': partnerLogo,
      'rewardCoins': rewardCoins,
      'category': category,
      'isActive': isActive,
      'expiryDays': expiryDays,
      'maxPerUser': maxPerUser,
      'cooldownMinutes': cooldownMinutes,
      'totalCompletions': totalCompletions,
      'availableSlots': availableSlots,
      'expiresAt': expiresAt?.toIso8601String(),
      'trackingUrl': trackingUrl,
    };
  }
}

// ================================================================
// WALLET API RESPONSES
// ================================================================

/// Response from: GET /api/wallet
class WalletResponse {
  final bool success;
  final String message;
  final UserWalletModel wallet;

  WalletResponse({
    required this.success,
    required this.message,
    required this.wallet,
  });

  factory WalletResponse.fromJson(Map<String, dynamic> json) {
    return WalletResponse(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      wallet: UserWalletModel.fromFirestore(
          json['wallet'] as Map<String, dynamic>,
          json['wallet']['userId'] as String? ?? '',),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
      'wallet': wallet.toFirestore(),
    };
  }
}

/// Wallet Data Model
class WalletData {
  final String userId;
  final int njCoinsBalance;
  final int njCoinsExpiring;
  final int njCoinsPending;
  final int currentStreak;
  final int longestStreak;
  final DateTime? lastTaskDate;
  final int dailyEarnedCoins;
  final int userLevel;
  final int levelProgress;
  final int levelGoal;
  final int lifetimeEarned;
  final int lifetimeSpent;
  final int tasksCompleted;
  final bool flaggedForReview;

  WalletData({
    required this.userId,
    required this.njCoinsBalance,
    required this.njCoinsExpiring,
    required this.njCoinsPending,
    required this.currentStreak,
    required this.longestStreak,
    required this.dailyEarnedCoins,
    required this.userLevel,
    required this.levelProgress,
    required this.levelGoal,
    required this.lifetimeEarned,
    required this.lifetimeSpent,
    required this.tasksCompleted,
    required this.flaggedForReview,
    this.lastTaskDate,
  });

  factory WalletData.fromJson(Map<String, dynamic> json) {
    return WalletData(
      userId: json['userId'] as String? ?? '',
      njCoinsBalance: json['njCoinsBalance'] as int? ?? 0,
      njCoinsExpiring: json['njCoinsExpiring'] as int? ?? 0,
      njCoinsPending: json['njCoinsPending'] as int? ?? 0,
      currentStreak: json['currentStreak'] as int? ?? 0,
      longestStreak: json['longestStreak'] as int? ?? 0,
      lastTaskDate: json['lastTaskDate'] != null
          ? DateTime.parse(json['lastTaskDate'] as String)
          : null,
      dailyEarnedCoins: json['dailyEarnedCoins'] as int? ?? 0,
      userLevel: json['userLevel'] as int? ?? 1,
      levelProgress: json['levelProgress'] as int? ?? 0,
      levelGoal: json['levelGoal'] as int? ?? 500,
      lifetimeEarned: json['lifetimeEarned'] as int? ?? 0,
      lifetimeSpent: json['lifetimeSpent'] as int? ?? 0,
      tasksCompleted: json['tasksCompleted'] as int? ?? 0,
      flaggedForReview: json['flaggedForReview'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'njCoinsBalance': njCoinsBalance,
      'njCoinsExpiring': njCoinsExpiring,
      'njCoinsPending': njCoinsPending,
      'currentStreak': currentStreak,
      'longestStreak': longestStreak,
      'lastTaskDate': lastTaskDate?.toIso8601String(),
      'dailyEarnedCoins': dailyEarnedCoins,
      'userLevel': userLevel,
      'levelProgress': levelProgress,
      'levelGoal': levelGoal,
      'lifetimeEarned': lifetimeEarned,
      'lifetimeSpent': lifetimeSpent,
      'tasksCompleted': tasksCompleted,
      'flaggedForReview': flaggedForReview,
    };
  }
}

// ================================================================
// TASK COMPLETION API REQUEST/RESPONSE
// ================================================================

/// Request to: POST /api/tasks/{taskId}/complete
class TaskCompletionRequest {
  final String taskId;
  final String userId;
  final String deviceId;
  final String? validationData; // Screenshot URL, deep link result, etc.

  TaskCompletionRequest({
    required this.taskId,
    required this.userId,
    required this.deviceId,
    this.validationData,
  });

  Map<String, dynamic> toJson() {
    return {
      'taskId': taskId,
      'userId': userId,
      'deviceId': deviceId,
      'validationData': validationData,
    };
  }
}

/// Response from: POST /api/tasks/{taskId}/complete
class TaskCompletionResponse {
  final bool success;
  final String message;
  final String status; // pending, validated, credited, rejected
  final int rewardCoins;
  final DateTime? creditedAt;
  final String? trackingUrl; // Phase 3: Added for launching

  TaskCompletionResponse({
    required this.success,
    required this.message,
    required this.status,
    required this.rewardCoins,
    this.creditedAt,
    this.trackingUrl,
  });

  factory TaskCompletionResponse.fromJson(Map<String, dynamic> json) {
    return TaskCompletionResponse(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      rewardCoins: json['rewardCoins'] as int? ?? 0,
      creditedAt: json['creditedAt'] != null
          ? DateTime.parse(json['creditedAt'] as String)
          : null,
      trackingUrl: json['trackingUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
      'status': status,
      'rewardCoins': rewardCoins,
      'creditedAt': creditedAt?.toIso8601String(),
      'trackingUrl': trackingUrl,
    };
  }
}

// ================================================================
// ERROR RESPONSES
// ================================================================

/// Standard Error Response Format
class ErrorResponse {
  final bool success;
  final String message;
  final String errorCode;
  final Map<String, dynamic>? details;

  ErrorResponse({
    required this.success,
    required this.message,
    required this.errorCode,
    this.details,
  });

  factory ErrorResponse.fromJson(Map<String, dynamic> json) {
    return ErrorResponse(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      errorCode: json['errorCode'] as String? ?? 'UNKNOWN_ERROR',
      details: json['details'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
      'errorCode': errorCode,
      'details': details,
    };
  }
}

// ================================================================
// EXPECTED ENDPOINTS DOCUMENTATION
// ================================================================

/*
PHASE 2 API ENDPOINTS:

1. GET /api/tasks
   - Returns: TaskListResponse
   - Query Params: category, limit, offset
   - Auth: Required (Bearer token)

2. GET /api/tasks/{taskId}
   - Returns: TaskData (single task)
   - Auth: Required

3. POST /api/tasks/{taskId}/start
   - Request: { userId, deviceId }
   - Returns: { success, message, affiliateUrl }
   - Auth: Required

4. POST /api/tasks/{taskId}/complete
   - Request: TaskCompletionRequest
   - Returns: TaskCompletionResponse
   - Auth: Required

5. GET /api/wallet
   - Returns: WalletResponse
   - Auth: Required

6. POST /api/wallet/spend
   - Request: { userId, amount, purpose }
   - Returns: { success, message, newBalance }
   - Auth: Required

7. GET /api/wallet/transactions
   - Returns: { success, transactions: [] }
   - Query Params: type, limit, offset
   - Auth: Required

ERROR CODES:
- TASK_NOT_FOUND: Task ID doesn't exist
- TASK_EXPIRED: Task past expiry date
- TASK_ALREADY_COMPLETED: User already completed this task
- COOLDOWN_ACTIVE: User must wait before similar task
- INVALID_VALIDATION: Task completion validation failed
- INSUFFICIENT_BALANCE: Not enough NJ Coins for spend
- FRAUD_DETECTED: Suspicious activity flagged
*/
