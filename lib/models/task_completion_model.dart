// ================================================================
// TaskCompletionModel — Allin1 Super App
// Tracks task completions with pending/verified status
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

enum CoinStatus {
  pending, // Coins awarded but not yet verified by affiliate network
  verified, // Affiliate confirmed completion, coins spendable
  rejected, // Affiliate rejected (fraud/invalid)
  expired, // Task completion expired before verification
}

class TaskCompletionModel {
  final String completionId;
  final String taskId;
  final String userId;

  // Status Tracking
  final CoinStatus coinStatus;
  final DateTime? submittedAt; // When user submitted completion
  final DateTime? clickedAt;
  final DateTime? validatedAt;
  final DateTime? creditedAt;
  final DateTime? rejectedAt;

  // Validation Data
  final Map<String, dynamic>? validationData;
  final String? externalRefId; // Affiliate network's transaction ID
  final String? deviceId;
  final String? ipAddress;

  // Payout
  final int payoutAmount; // NJ Coins to be awarded
  final DateTime? expiryDate; // Must verify by this date

  // Fraud Detection
  final double riskScore; // 0-1 scale
  final bool requiresManualReview;
  final String? rejectionReason;

  const TaskCompletionModel({
    required this.completionId,
    required this.taskId,
    required this.userId,
    required this.payoutAmount,
    this.coinStatus = CoinStatus.pending,
    this.submittedAt,
    this.clickedAt,
    this.validatedAt,
    this.creditedAt,
    this.rejectedAt,
    this.validationData,
    this.externalRefId,
    this.deviceId,
    this.ipAddress,
    this.expiryDate,
    this.riskScore = 0.0,
    this.requiresManualReview = false,
    this.rejectionReason,
  });

  // Factory from Firestore
  factory TaskCompletionModel.fromFirestore(
      Map<String, dynamic> data, String id,) {
    return TaskCompletionModel(
      completionId: id,
      taskId: data['taskId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      coinStatus: CoinStatus.values.firstWhere(
        (e) => e.name == data['coinStatus'],
        orElse: () => CoinStatus.pending,
      ),
      submittedAt: data['submittedAt'] != null
          ? (data['submittedAt'] as Timestamp).toDate()
          : null,
      clickedAt: data['clickedAt'] != null
          ? (data['clickedAt'] as Timestamp).toDate()
          : null,
      validatedAt: data['validatedAt'] != null
          ? (data['validatedAt'] as Timestamp).toDate()
          : null,
      creditedAt: data['creditedAt'] != null
          ? (data['creditedAt'] as Timestamp).toDate()
          : null,
      rejectedAt: data['rejectedAt'] != null
          ? (data['rejectedAt'] as Timestamp).toDate()
          : null,
      validationData: data['validationData'] as Map<String, dynamic>?,
      externalRefId: data['externalRefId'] as String?,
      deviceId: data['deviceId'] as String?,
      ipAddress: data['ipAddress'] as String?,
      payoutAmount: data['payoutAmount'] as int? ?? 0,
      expiryDate: data['expiryDate'] != null
          ? (data['expiryDate'] as Timestamp).toDate()
          : null,
      riskScore: (data['riskScore'] as num?)?.toDouble() ?? 0.0,
      requiresManualReview: data['requiresManualReview'] as bool? ?? false,
      rejectionReason: data['rejectionReason'] as String?,
    );
  }

  // Convert to Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'taskId': taskId,
      'userId': userId,
      'coinStatus': coinStatus.name,
      'submittedAt':
          submittedAt != null ? Timestamp.fromDate(submittedAt!) : null,
      'clickedAt': clickedAt != null ? Timestamp.fromDate(clickedAt!) : null,
      'validatedAt':
          validatedAt != null ? Timestamp.fromDate(validatedAt!) : null,
      'creditedAt': creditedAt != null ? Timestamp.fromDate(creditedAt!) : null,
      'rejectedAt': rejectedAt != null ? Timestamp.fromDate(rejectedAt!) : null,
      'validationData': validationData,
      'externalRefId': externalRefId,
      'deviceId': deviceId,
      'ipAddress': ipAddress,
      'payoutAmount': payoutAmount,
      'expiryDate': expiryDate != null ? Timestamp.fromDate(expiryDate!) : null,
      'riskScore': riskScore,
      'requiresManualReview': requiresManualReview,
      'rejectionReason': rejectionReason,
    };
  }

  // Check if completion is still valid
  bool isValid() {
    if (coinStatus == CoinStatus.verified ||
        coinStatus == CoinStatus.rejected ||
        coinStatus == CoinStatus.expired) {
      return false;
    }

    if (expiryDate != null && DateTime.now().isAfter(expiryDate!)) {
      return false;
    }

    return true;
  }

  // Get status display text
  String getStatusText() {
    switch (coinStatus) {
      case CoinStatus.pending:
        return 'Pending Verification';
      case CoinStatus.verified:
        return 'Verified - Coins Spendable';
      case CoinStatus.rejected:
        return 'Rejected: $rejectionReason';
      case CoinStatus.expired:
        return 'Expired';
    }
  }
}
