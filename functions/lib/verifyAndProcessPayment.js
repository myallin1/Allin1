"use strict";
/**
 * ================================================================
 * Cloud Function: verifyAndProcessPayment
 * Purpose: Server-side daily coin cap enforcement (Bulletproof Security)
 * ================================================================
 */
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || function (mod) {
    if (mod && mod.__esModule) return mod;
    var result = {};
    if (mod != null) for (var k in mod) if (k !== "default" && Object.prototype.hasOwnProperty.call(mod, k)) __createBinding(result, mod, k);
    __setModuleDefault(result, mod);
    return result;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.verifyAndProcessPayment = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
if (admin.apps.length === 0) {
    admin.initializeApp();
}
const db = admin.firestore();
/**
 * ATOMIC PAYMENT PROCESSOR
 */
exports.verifyAndProcessPayment = functions.https.onCall(async (data, context) => {
    // 1. Auth Check
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in');
    }
    if (context.auth.uid !== data.userId) {
        throw new functions.https.HttpsError('permission-denied', 'Unauthorized access');
    }
    // 2. Input Validation
    if (!data.amount || data.amount <= 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid payment amount');
    }
    // 3. SECURE TRANSACTION LOOP
    try {
        return await db.runTransaction(async (transaction) => {
            var _a;
            const userRef = db.collection('users').doc(data.userId);
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) {
                throw new Error('USER_NOT_FOUND');
            }
            const userData = userDoc.data();
            const currentBalance = userData.njCoinsBalance || 0;
            const maxDailyLimit = userData.maxDailyCoinLimit || 500; // Hardcoded fallback for security
            // --- Daily Reset Logic (Server-Side Time) ---
            const lastUse = ((_a = userData.lastCoinUseDate) === null || _a === void 0 ? void 0 : _a.toDate()) || new Date(0);
            const today = new Date();
            today.setHours(0, 0, 0, 0);
            let dailyUsed = userData.dailyCoinsUsed || 0;
            if (lastUse < today) {
                dailyUsed = 0; // Reset for new day
            }
            // --- THE CRITICAL SECURITY CHECK (50% Loophole Fix) ---
            if (dailyUsed + data.amount > maxDailyLimit) {
                throw new Error('DAILY_LIMIT_EXCEEDED');
            }
            if (currentBalance < data.amount) {
                throw new Error('INSUFFICIENT_BALANCE');
            }
            // --- ATOMIC UPDATES ---
            const newBalance = currentBalance - data.amount;
            const newDailyUsed = dailyUsed + data.amount;
            transaction.update(userRef, {
                njCoinsBalance: newBalance,
                dailyCoinsUsed: newDailyUsed,
                lastCoinUseDate: admin.firestore.FieldValue.serverTimestamp(),
                lifetimeSpent: admin.firestore.FieldValue.increment(data.amount),
            });
            // Audit Trail
            const txnRef = db.collection('wallet_transactions').doc();
            transaction.set(txnRef, {
                userId: data.userId,
                amount: data.amount,
                type: 'debit',
                purpose: data.purpose,
                balanceBefore: currentBalance,
                balanceAfter: newBalance,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return {
                success: true,
                newBalance: newBalance,
                dailyRemaining: maxDailyLimit - newDailyUsed,
            };
        });
    }
    catch (error) {
        functions.logger.error(`Payment failed for user ${data.userId}:`, error.message);
        // Map internal errors to secure HttpsErrors
        if (error.message === 'DAILY_LIMIT_EXCEEDED') {
            throw new functions.https.HttpsError('resource-exhausted', 'Daily coin limit reached');
        }
        if (error.message === 'INSUFFICIENT_BALANCE') {
            throw new functions.https.HttpsError('failed-precondition', 'Insufficient NJ Coins');
        }
        throw new functions.https.HttpsError('internal', 'Payment processing failed');
    }
});
//# sourceMappingURL=verifyAndProcessPayment.js.map