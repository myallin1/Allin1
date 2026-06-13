// ================================================================
// TaskModel — Allin1 Super App
// Affiliate Task Wall - Phase 1 (Dummy Data Ready)
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

class TaskModel {
  final String taskId;
  final String title;
  final String description;
  final String partnerName;
  final String partnerLogo;
  final int rewardCoins;
  final String category;
  final bool isActive;
  final String? trackingUrl; // Phase 3: Added for affiliate redirect

  // CEO Guardrails - Fraud Prevention
  final int expiryDays; // Days until task expires
  final int maxPerUser; // Max completions per user (1 = one-time)
  final int cooldownMinutes; // Minutes before user can do similar task

  // Analytics (Dummy for Phase 1)
  final int totalCompletions;
  final int availableSlots;
  final DateTime? expiresAt;

  // UI Helpers
  final String scarcityTag; // "🔥 Only 20 slots left!"
  final Duration? countdown; // For time-limited tasks

  const TaskModel({
    required this.taskId,
    required this.title,
    required this.description,
    required this.partnerName,
    required this.partnerLogo,
    required this.rewardCoins,
    this.category = 'general',
    this.isActive = true,
    this.expiryDays = 30,
    this.maxPerUser = 1,
    this.cooldownMinutes = 0,
    this.totalCompletions = 0,
    this.availableSlots = 100,
    this.expiresAt,
    this.scarcityTag = '',
    this.countdown,
    this.trackingUrl,
  });

  // Factory from Firestore (Phase 2)
  factory TaskModel.fromFirestore(Map<String, dynamic> data, String id) {
    return TaskModel(
      taskId: id,
      title: data['title'] as String? ?? 'Untitled Task',
      description: data['description'] as String? ?? '',
      partnerName: data['partnerName'] as String? ?? 'Partner',
      partnerLogo: data['partnerLogo'] as String? ?? '',
      rewardCoins: data['rewardCoins'] as int? ?? 0,
      category: data['category'] as String? ?? 'general',
      isActive: data['isActive'] as bool? ?? true,
      expiryDays: data['expiryDays'] as int? ?? 30,
      maxPerUser: data['maxPerUser'] as int? ?? 1,
      cooldownMinutes: data['cooldownMinutes'] as int? ?? 0,
      totalCompletions: data['totalCompletions'] as int? ?? 0,
      availableSlots: data['availableSlots'] as int? ?? 100,
      trackingUrl: data['trackingUrl'] as String?,
    );
  }

  // Convert to Firestore (Phase 2)
  Map<String, dynamic> toFirestore() {
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
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'trackingUrl': trackingUrl,
    };
  }

  // Check if task is available for user
  bool isAvailableForUser() {
    if (!isActive) {
      return false;
    }
    if (availableSlots <= 0) {
      return false;
    }
    if (expiresAt != null && DateTime.now().isAfter(expiresAt!)) {
      return false;
    }
    return true;
  }

  // Get scarcity message
  String getScarcityMessage() {
    if (availableSlots <= 5) {
      return '🔥 Only $availableSlots slots left!';
    } else if (availableSlots <= 20) {
      return '⚡ $availableSlots slots remaining';
    } else if (countdown != null) {
      final hours = countdown!.inHours;
      final minutes = countdown!.inMinutes % 60;
      final seconds = countdown!.inSeconds % 60;
      return '⏳ Expires in ${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '';
  }
}

// ================================================================
// DUMMY DATA FOR PHASE 1 TESTING
// ================================================================

abstract final class DummyTasks {
  static List<TaskModel> getSampleTasks() {
    final now = DateTime.now();

    return [
      // App Downloads
      TaskModel(
        taskId: 'task_001',
        title: 'Download Swiggy & Order Food',
        description: 'First-time users get ₹100 off + earn 20 NJ Coins!',
        partnerName: 'Swiggy',
        partnerLogo: '🍔',
        rewardCoins: 20,
        category: 'food_delivery',
        expiryDays: 7,
        availableSlots: 20,
        scarcityTag: '🔥 Only 20 slots left!',
        countdown: const Duration(hours: 2, minutes: 15),
        expiresAt: now.add(const Duration(hours: 2, minutes: 15)),
      ),
      TaskModel(
        taskId: 'task_002',
        title: 'Install Zepto & First Purchase',
        description: 'Get groceries delivered in 10 minutes + 25 NJ Coins',
        partnerName: 'Zepto',
        partnerLogo: '⚡',
        rewardCoins: 25,
        category: 'grocery',
        expiryDays: 14,
        availableSlots: 8,
        scarcityTag: '🔥 Only 8 slots left!',
        countdown: const Duration(hours: 5, minutes: 30),
        expiresAt: now.add(const Duration(hours: 5, minutes: 30)),
      ),

      // Registration Tasks
      const TaskModel(
        taskId: 'task_003',
        title: 'Register on Groww Investment App',
        description: 'Start your investment journey + earn 50 NJ Coins',
        partnerName: 'Groww',
        partnerLogo: '📈',
        rewardCoins: 50,
        category: 'finance',
        availableSlots: 45,
        scarcityTag: '⚡ 45 slots remaining',
      ),
      const TaskModel(
        taskId: 'task_004',
        title: 'Sign Up for Amazon Pay',
        description: 'Activate Amazon Pay wallet + get 30 NJ Coins',
        partnerName: 'Amazon Pay',
        partnerLogo: '📦',
        rewardCoins: 30,
        category: 'finance',
        expiryDays: 21,
        availableSlots: 120,
      ),

      // Premium Tasks
      const TaskModel(
        taskId: 'task_005',
        title: 'Open Demat Account (Zerodha)',
        description: 'Start stock trading + earn 100 NJ Coins (KYC Required)',
        partnerName: 'Zerodha',
        partnerLogo: '💹',
        rewardCoins: 100,
        category: 'finance_premium',
        expiryDays: 60,
        cooldownMinutes: 1440, // 24 hours cooldown
        availableSlots: 3,
        scarcityTag: '🔥 Only 3 slots left!',
        countdown: Duration(
          hours: 1,
          minutes: 45,
        ),
      ),

      // Quick Tasks
      const TaskModel(
        taskId: 'task_006',
        title: 'Watch 30-Second Ad Video',
        description: 'Simple video task + instant 5 NJ Coins',
        partnerName: 'Ad Network',
        partnerLogo: '📺',
        rewardCoins: 5,
        category: 'quick',
        expiryDays: 1,
        maxPerUser: 5, // Can do 5 times
        cooldownMinutes: 60, // 1 hour cooldown
        availableSlots: 500,
      ),
      const TaskModel(
        taskId: 'task_007',
        title: 'Complete Survey (5 min)',
        description: 'Share your opinion + earn 15 NJ Coins',
        partnerName: 'SurveyMonkey',
        partnerLogo: '📝',
        rewardCoins: 15,
        category: 'survey',
        expiryDays: 3,
        maxPerUser: 3,
        cooldownMinutes: 240, // 4 hours
        availableSlots: 75,
      ),

      // Flash Task (Limited Time)
      const TaskModel(
        taskId: 'task_008',
        title: '⚡ FLASH: Download PhonePe',
        description: '24-hour special! Install + activate = 40 NJ Coins',
        partnerName: 'PhonePe',
        partnerLogo: '📱',
        rewardCoins: 40,
        category: 'flash',
        expiryDays: 1,
        availableSlots: 15,
        scarcityTag: '⏰ FLASH: Ends in 24 hours!',
        countdown: Duration(hours: 23, minutes: 59),
      ),
    ];
  }
}
