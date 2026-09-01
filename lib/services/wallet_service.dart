// ================================================================
// WalletService — Allin1 Super App
// Service layer for wallet operations with daily cap enforcement
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/user_wallet_model.dart';
import 'api_contracts.dart';

class WalletService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── GET USER WALLET ──────────────────────────────────────────
  Future<UserWalletModel> getUserWallet() async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        return const UserWalletModel(userId: 'temp');
      }

      final doc = await _firestore.collection('users').doc(userId).get();

      if (!doc.exists) {
        return const UserWalletModel(userId: 'temp');
      }

      return UserWalletModel.fromFirestore(doc.data()!, userId);
    } catch (e) {
      // FIX: this used to swallow every failure (network blip, permission
      // error, deserialization issue) and return a zero-balance 'temp'
      // wallet — identical to a user who genuinely has no wallet yet.
      // A transient Firestore error would make a user's real balance
      // silently vanish from the UI with no error indicator. Rethrow so
      // callers (e.g. a FutureBuilder) can show a real "couldn't load
      // wallet" + retry state instead of a fake zero balance.
      debugPrint('Get wallet error: $e');
      rethrow;
    }
  }

  // ── SPEND COINS (With Daily Cap Enforcement) ─────────────────
  Future<WalletResponse> spendCoins({
    required int amount,
    required String purpose,
    required String transactionId,
  }) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        return WalletResponse(
          success: false,
          message: 'User not authenticated',
          wallet: const UserWalletModel(userId: 'temp'),
        );
      }

      // Call cloud function for server-side daily cap check
      // In Phase 2, this calls verifyAndProcessPayment cloud function
      final result = await _callPaymentProcessor(
        userId: userId,
        amount: amount,
        purpose: purpose,
        transactionId: transactionId,
      );

      if (result['success'] != true) {
        return WalletResponse(
          success: false,
          message: result['message'] as String,
          wallet: await getUserWallet(),
        );
      }

      return WalletResponse(
        success: true,
        message: 'Payment successful',
        wallet: await getUserWallet(),
      );
    } catch (e) {
      // FIX: this used to always return the generic 'Payment failed',
      // hiding whether the real cause was insufficient balance, daily
      // limit, or a genuine backend/network failure — support couldn't
      // tell these apart from the message alone. Surface the real
      // error text (still falls back to a friendly default wallet on
      // the getUserWallet() call inside, which now itself rethrows on
      // real failures — catch that separately so a wallet-fetch error
      // here doesn't mask the original payment error).
      debugPrint('Spend coins error: $e');
      UserWalletModel wallet;
      try {
        wallet = await getUserWallet();
      } catch (_) {
        wallet = const UserWalletModel(userId: 'temp');
      }
      return WalletResponse(
        success: false,
        message: 'Payment failed: $e',
        wallet: wallet,
      );
    }
  }

  // ── CALL PAYMENT PROCESSOR CLOUD FUNCTION ────────────────────
  Future<Map<String, dynamic>> _callPaymentProcessor({
    required String userId,
    required int amount,
    required String purpose,
    required String transactionId,
  }) async {
    try {
      // In Phase 2, this will call the actual cloud function:
      // final callable = FirebaseFunctions.instance.httpsCallable('verifyAndProcessPayment');
      // final result = await callable.call({
      //   'userId': userId,
      //   'amount': amount,
      //   'purpose': purpose,
      //   'transactionId': transactionId,
      // });
      // return result.data;

      // For now, simulate server-side check
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data()!;

      final currentBalance = userData['njCoinsBalance'] as int? ?? 0;
      final dailyCoinsUsed = userData['dailyCoinsUsed'] as int? ?? 0;
      final maxDailyLimit = userData['maxDailyCoinLimit'] as int? ?? 500;
      final lastCoinUseDate =
          (userData['lastCoinUseDate'] as Timestamp?)?.toDate();

      // Check balance
      if (currentBalance < amount) {
        return {
          'success': false,
          'message': 'Insufficient balance',
          'errorCode': 'INSUFFICIENT_BALANCE',
        };
      }

      // Check daily cap
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final effectiveDailyUsed =
          (lastCoinUseDate == null || lastCoinUseDate.isBefore(today))
              ? 0
              : dailyCoinsUsed;

      if (effectiveDailyUsed + amount > maxDailyLimit) {
        return {
          'success': false,
          'message': 'Daily limit exceeded',
          'errorCode': 'DAILY_LIMIT_EXCEEDED',
          'dailyRemaining': maxDailyLimit - effectiveDailyUsed,
        };
      }

      // Update wallet (in Phase 2, this happens in cloud function)
      await _firestore.collection('users').doc(userId).update({
        'njCoinsBalance': FieldValue.increment(-amount),
        'dailyCoinsUsed': FieldValue.increment(amount),
        'lastCoinUseDate': FieldValue.serverTimestamp(),
        'lifetimeSpent': FieldValue.increment(amount),
      });

      // Create transaction record
      await _firestore.collection('wallet_transactions').add({
        'userId': userId,
        'amount': amount,
        'type': 'debit',
        'source': purpose,
        'balanceBefore': currentBalance,
        'balanceAfter': currentBalance - amount,
        'dailyCoinsUsed': effectiveDailyUsed + amount,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return {
        'success': true,
        'message': 'Payment successful',
        'newBalance': currentBalance - amount,
        'dailyRemaining': maxDailyLimit - (effectiveDailyUsed + amount),
      };
    } catch (e) {
      debugPrint('Payment processor error: $e');
      return {
        'success': false,
        'message': 'Payment processing failed',
        'errorCode': 'PROCESSING_ERROR',
      };
    }
  }

  // ── CHECK DAILY LIMIT ────────────────────────────────────────
  Future<Map<String, dynamic>> checkDailyLimit() async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        return {
          'success': false,
          'message': 'Not authenticated',
        };
      }

      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data()!;

      final dailyCoinsUsed = userData['dailyCoinsUsed'] as int? ?? 0;
      final maxDailyLimit = userData['maxDailyCoinLimit'] as int? ?? 500;
      final lastCoinUseDate =
          (userData['lastCoinUseDate'] as Timestamp?)?.toDate();

      // Check if new day
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final effectiveDailyUsed =
          (lastCoinUseDate == null || lastCoinUseDate.isBefore(today))
              ? 0
              : dailyCoinsUsed;

      return {
        'success': true,
        'dailyUsed': effectiveDailyUsed,
        'dailyLimit': maxDailyLimit,
        'dailyRemaining': maxDailyLimit - effectiveDailyUsed,
        'isNewDay': effectiveDailyUsed == 0 && dailyCoinsUsed > 0,
      };
    } catch (e) {
      debugPrint('Check daily limit error: $e');
      return {
        'success': false,
        'message': 'Failed to check limit',
      };
    }
  }

  // ── CREDIT COINS (From Task Completion) ──────────────────────
  Future<bool> creditCoins({
    required int amount,
    required String source,
    required String taskId,
    bool isPending = true,
  }) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return false;

      if (isPending) {
        // Credit to pending coins (awaiting affiliate verification)
        await _firestore.collection('users').doc(userId).update({
          'pendingCoins': FieldValue.increment(amount),
        });
      } else {
        // Move from pending to verified (after affiliate webhook)
        await _firestore.collection('users').doc(userId).update({
          'pendingCoins': FieldValue.increment(-amount),
          'njCoinsBalance': FieldValue.increment(amount),
        });
      }

      // Create transaction record
      await _firestore.collection('wallet_transactions').add({
        'userId': userId,
        'amount': amount,
        'type': isPending ? 'pending_credit' : 'verified_credit',
        'source': source,
        'taskId': taskId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      debugPrint('Credit coins error: $e');
      return false;
    }
  }

  // ── GET WALLET TRANSACTIONS ──────────────────────────────────
  Future<List<Map<String, dynamic>>> getTransactions({
    String? type,
    int limit = 50,
  }) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return [];

      Query query = _firestore
          .collection('wallet_transactions')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (type != null) {
        query = query.where('type', isEqualTo: type);
      }

      final snapshot = await query.get();

      return snapshot.docs.map((doc) {
        final data = doc.data()! as Map<String, dynamic>;
        return {
          ...data,
          'id': doc.id,
          'createdAt': (data['createdAt'] as Timestamp?)?.toDate(),
        };
      }).toList();
    } catch (e) {
      // FIX: this query combines a 'userId' equality filter with
      // .orderBy('createdAt') (and sometimes a second 'type' equality
      // filter) — a composite-index query. If the index isn't deployed
      // or is rebuilding, Firestore throws failed-precondition, which
      // this used to swallow into an empty list — indistinguishable
      // from "no transactions yet". Rethrow so the UI can show a real
      // error state instead of a fake empty history.
      debugPrint('Get transactions error: $e');
      rethrow;
    }
  }
}
