// ================================================================
// RewardModel — Local-First edge cache model
// Allin1 Super App — Rewards / NJ Coins system
// Backed by Hive (works on Android, iOS & PWA Web)
// ================================================================

import 'package:hive_flutter/hive_flutter.dart';

part 'reward_model.g.dart';

/// Status of a reward task from the user's perspective
enum RewardStatus { available, initiated, pending, verified, failed, expired }

@HiveType(typeId: 11)
class RewardModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String subtitle;

  @HiveField(3)
  final String emoji;

  @HiveField(4)
  final int coins;

  @HiveField(5)
  final String channel; // 'cpa', 'internal', 'local'

  @HiveField(6)
  final String? taskUrl;

  @HiveField(7)
  final String? internalAction;

  @HiveField(8)
  final bool isHot;

  /// Stored as string for Hive compatibility
  @HiveField(9)
  final String status; // maps to RewardStatus

  @HiveField(10)
  final String? expiresAt; // ISO-8601

  @HiveField(11)
  final String updatedAt; // from TrailBase

  @HiveField(12)
  final DateTime lastSynced;

  RewardModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.coins,
    required this.channel,
    required this.updatedAt,
    required this.lastSynced,
    this.taskUrl,
    this.internalAction,
    this.isHot = false,
    this.status = 'available',
    this.expiresAt,
  });

  RewardStatus get rewardStatus {
    switch (status) {
      case 'initiated':
        return RewardStatus.initiated;
      case 'pending':
        return RewardStatus.pending;
      case 'verified':
        return RewardStatus.verified;
      case 'failed':
        return RewardStatus.failed;
      case 'expired':
        return RewardStatus.expired;
      default:
        return RewardStatus.available;
    }
  }

  factory RewardModel.fromJson(Map<String, dynamic> json) => RewardModel(
        id: json['id'] as String,
        title: json['title'] as String,
        subtitle: (json['subtitle'] as String?) ?? '',
        emoji: (json['emoji'] as String?) ?? '🎁',
        coins: (json['coins'] as num?)?.toInt() ?? 0,
        channel: (json['channel'] as String?) ?? 'internal',
        taskUrl: json['task_url'] as String?,
        internalAction: json['internal_action'] as String?,
        isHot: (json['is_hot'] as bool?) ?? false,
        status: (json['status'] as String?) ?? 'available',
        expiresAt: json['expires_at'] as String?,
        updatedAt:
            (json['updated_at'] as String?) ?? DateTime.now().toIso8601String(),
        lastSynced: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'emoji': emoji,
        'coins': coins,
        'channel': channel,
        'task_url': taskUrl,
        'internal_action': internalAction,
        'is_hot': isHot,
        'status': status,
        'expires_at': expiresAt,
        'updated_at': updatedAt,
      };
}
