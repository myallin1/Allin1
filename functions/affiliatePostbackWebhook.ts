/**
 * ================================================================
 * Cloud Function: affiliatePostbackWebhook
 * Purpose: Handle S2S postbacks from affiliate networks (Swiggy, Zepto, etc.)
 * Security: Idempotency lock to prevent double-crediting
 * ================================================================
 */

import * as functions from 'firebase-functions';
import { logger } from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as crypto from 'crypto';

// Initialize admin only if not already initialized
if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

interface AffiliatePostback {
  provider: string;        // 'swiggy', 'zepto', 'groww', etc.
  transactionId: string;   // Affiliate network's unique transaction ID
  userId: string;          // Our user ID (passed in tracking link)
  taskId: string;          // Our task ID
  status: string;          // 'validated', 'rejected', 'pending'
  payout: number;          // Real cash payout to us (₹50)
  timestamp: number;       // Unix timestamp
  signature: string;       // HMAC signature for verification
}

/**
 * WEBHOOK ENDPOINT
 */
export const affiliatePostbackWebhook = functions.https.onRequest(
  async (req: functions.https.Request, res: functions.Response) => {
    // 1. Only accept POST
    if (req.method !== 'POST') {
      res.status(405).json({ success: false, message: 'Method not allowed' });
      return;
    }

    const postback: AffiliatePostback = req.body;
    const HMAC_SECRET = process.env.AFFILIATE_HMAC_SECRET || 'dev-secret-key';

    // 2. Input Validation
    if (!postback.provider || !postback.transactionId || !postback.userId || !postback.taskId) {
      res.status(400).json({ success: false, message: 'Missing required fields' });
      return;
    }

    // 3. Signature Verification (Bulletproof Security)
    const { signature, ...payload } = postback;
    const expectedSignature = crypto
      .createHmac('sha256', HMAC_SECRET)
      .update(JSON.stringify(payload))
      .digest('hex');

    if (postback.signature !== expectedSignature) {
      logger.warn(`Invalid signature for txn ${postback.transactionId}`);
      res.status(401).json({ success: false, message: 'Invalid signature' });
      return;
    }

    // 4. Status Check (Strictly 'validated' as per CEO request)
    if (postback.status !== 'validated') {
      logger.info(`Postback ignored: status is ${postback.status}`);
      res.json({ success: true, message: `Status ${postback.status} received (ignored)` });
      return;
    }

    // 5. Atomic Idempotency Lock & Balance Update
    try {
      const lockRef = db.collection('idempotencyLocks').doc(`${postback.provider}_${postback.transactionId}`);
      
      const response = await db.runTransaction(async (transaction) => {
        const lockDoc = await transaction.get(lockRef);

        if (lockDoc.exists) {
          return { success: true, message: 'Transaction already processed (Idempotent)' };
        }

        // --- Core Logic ---
        const userRef = db.collection('users').doc(postback.userId);
        const userDoc = await transaction.get(userRef);
        
        if (!userDoc.exists) {
          throw new Error('USER_NOT_FOUND');
        }

        const userData = userDoc.data()!;
        const njCoinsToCredit = Math.floor(postback.payout * 0.4); // CEO rule: 40% payout logic

        // Update Wallet & Stats
        transaction.update(userRef, {
          njCoinsBalance: admin.firestore.FieldValue.increment(njCoinsToCredit),
          njCoinsPending: admin.firestore.FieldValue.increment(-njCoinsToCredit),
          lifetimeEarned: admin.firestore.FieldValue.increment(njCoinsToCredit),
        });

        // Create Lock Artifact (Persistence)
        transaction.set(lockRef, {
          provider: postback.provider,
          transactionId: postback.transactionId,
          userId: postback.userId,
          creditedAt: admin.firestore.FieldValue.serverTimestamp(),
          amount: njCoinsToCredit,
        });

        // Log Transaction for Audit Trail
        const txnRef = db.collection('wallet_transactions').doc();
        transaction.set(txnRef, {
          userId: postback.userId,
          amount: njCoinsToCredit,
          type: 'credit',
          source: 'affiliate_completion',
          provider: postback.provider,
          externalId: postback.transactionId,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return { success: true, message: `Credited ${njCoinsToCredit} NJ Coins` };
      });

      res.json(response);
    } catch (error: any) {
      logger.error('Webhook processing failed:', error);
      res.status(error.message === 'USER_NOT_FOUND' ? 404 : 500).json({ 
        success: false, 
        message: error.message || 'Internal Server Error' 
      });
    }
  }
);

