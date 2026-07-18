// ================================================================
// TaskService — Allin1 Super App
// Service layer for task completion with security checks
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../models/task_completion_model.dart';
import '../models/task_model.dart';
import 'api_contracts.dart';

class TaskService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // ignore: unused_field - Reserved for future RTDB task sync
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── START TASK (With Device Fingerprint Check) ───────────────
  Future<TaskCompletionResponse> startTask(
    String taskId,
    String deviceId,
  ) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        return TaskCompletionResponse(
          success: false,
          message: 'User not authenticated',
          status: 'error',
          rewardCoins: 0,
        );
      }

      // STEP 1: Check device fingerprint (prevent device farming)
      final deviceCheck =
          await _checkDeviceFingerprint(userId, deviceId, taskId);

      if (deviceCheck['allowed'] != true) {
        return TaskCompletionResponse(
          success: false,
          message: deviceCheck['message'] as String,
          status: 'rejected',
          rewardCoins: 0,
        );
      }

      // STEP 2: Get task details
      final taskDoc =
          await _firestore.collection('affiliate_tasks').doc(taskId).get();

      if (!taskDoc.exists) {
        return TaskCompletionResponse(
          success: false,
          message: 'Task not found',
          status: 'error',
          rewardCoins: 0,
        );
      }

      final task = TaskModel.fromFirestore(taskDoc.data()!, taskDoc.id);

      // STEP 3: Check if user already completed this task
      final existingCompletion = await _firestore
          .collection('task_completions')
          .where('userId', isEqualTo: userId)
          .where('taskId', isEqualTo: taskId)
          .where('coinStatus', whereIn: ['pending', 'verified'])
          .limit(1)
          .get();

      if (existingCompletion.docs.isNotEmpty) {
        return TaskCompletionResponse(
          success: false,
          message: 'You have already completed this task',
          status: 'already_completed',
          rewardCoins: 0,
        );
      }

      // STEP 4: Create completion record (pending status)
      final completionRef = _firestore.collection('task_completions').doc();
      final completion = TaskCompletionModel(
        completionId: completionRef.id,
        taskId: taskId,
        userId: userId,
        submittedAt: DateTime.now(),
        deviceId: deviceId,
        payoutAmount: task.rewardCoins,
        expiryDate: DateTime.now().add(Duration(days: task.expiryDays)),
      );

      await completionRef.set(completion.toFirestore());

      // STEP 5: Credit PENDING coins (not spendable yet)
      await _firestore.collection('users').doc(userId).update({
        'pendingCoins': FieldValue.increment(task.rewardCoins),
      });

      return TaskCompletionResponse(
        success: true,
        message: 'Task started. Complete the action to earn coins!',
        status: 'pending',
        rewardCoins: task.rewardCoins,
        trackingUrl: task.trackingUrl, // Phase 3: Added for redirection
      );
    } catch (e) {
      debugPrint('Start task error: $e');
      return TaskCompletionResponse(
        success: false,
        message: 'Failed to start task',
        status: 'error',
        rewardCoins: 0,
      );
    }
  }

  // ── CHECK DEVICE FINGERPRINT ──────────────────────────────────
  Future<Map<String, dynamic>> _checkDeviceFingerprint(
    String userId,
    String deviceId,
    String taskId,
  ) async {
    try {
      // Call cloud function for device check
      // In Phase 2, this will call the actual cloud function
      // For now, we do a local check

      final completions = await _firestore
          .collection('task_completions')
          .where('taskId', isEqualTo: taskId)
          .where('deviceId', isEqualTo: deviceId)
          .where('coinStatus', whereIn: ['pending', 'verified'])
          .limit(1)
          .get();

      if (completions.docs.isNotEmpty) {
        return {
          'allowed': false,
          'message': 'This task was already completed on this device',
        };
      }

      return {
        'allowed': true,
        'message': 'Device check passed',
      };
    } catch (e) {
      debugPrint('Device fingerprint check error: $e');
      return {
        'allowed': false,
        'message': 'Device check failed',
      };
    }
  }

  // ── VALIDATE TASK COMPLETION ─────────────────────────────────
  Future<TaskCompletionResponse> validateCompletion(
    String completionId,
    Map<String, dynamic> validationData,
  ) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        return TaskCompletionResponse(
          success: false,
          message: 'User not authenticated',
          status: 'error',
          rewardCoins: 0,
        );
      }

      final completionRef =
          _firestore.collection('task_completions').doc(completionId);
      final completionDoc = await completionRef.get();

      if (!completionDoc.exists) {
        return TaskCompletionResponse(
          success: false,
          message: 'Completion not found',
          status: 'error',
          rewardCoins: 0,
        );
      }

      final completion = TaskCompletionModel.fromFirestore(
        completionDoc.data()!,
        completionDoc.id,
      );

      // Check if user owns this completion
      if (completion.userId != userId) {
        return TaskCompletionResponse(
          success: false,
          message: 'Unauthorized',
          status: 'error',
          rewardCoins: 0,
        );
      }

      // Check if already verified
      if (completion.coinStatus != CoinStatus.pending) {
        return TaskCompletionResponse(
          success: false,
          message: 'Completion already processed',
          status: completion.coinStatus.name,
          rewardCoins: completion.payoutAmount,
        );
      }

      // Update with validation data
      await completionRef.update({
        'validationData': validationData,
        'validatedAt': FieldValue.serverTimestamp(),
      });

      // In Phase 2: This will wait for affiliate webhook
      // For now, we auto-verify after validation
      return TaskCompletionResponse(
        success: true,
        message: 'Completion submitted for verification',
        status: 'pending',
        rewardCoins: completion.payoutAmount,
      );
    } catch (e) {
      debugPrint('Validate completion error: $e');
      return TaskCompletionResponse(
        success: false,
        message: 'Validation failed',
        status: 'error',
        rewardCoins: 0,
      );
    }
  }

  // ── GET USER PENDING COMPLETIONS ─────────────────────────────
  Future<List<TaskCompletionModel>> getPendingCompletions() async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        return [];
      }

      final snapshot = await _firestore
          .collection('task_completions')
          .where('userId', isEqualTo: userId)
          .where('coinStatus', isEqualTo: 'pending')
          .orderBy('submittedAt', descending: true)
          .limit(50)
          .get();

      return snapshot.docs
          .map((doc) => TaskCompletionModel.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint('Get pending completions error: $e');
      return [];
    }
  }

  // ── GET USER VERIFIED COMPLETIONS ────────────────────────────
  Future<List<TaskCompletionModel>> getVerifiedCompletions() async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        return [];
      }

      final snapshot = await _firestore
          .collection('task_completions')
          .where('userId', isEqualTo: userId)
          .where('coinStatus', isEqualTo: 'verified')
          .orderBy('creditedAt', descending: true)
          .limit(50)
          .get();

      return snapshot.docs
          .map((doc) => TaskCompletionModel.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint('Get verified completions error: $e');
      return [];
    }
  }
}
