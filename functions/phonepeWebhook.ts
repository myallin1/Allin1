/**
 * ================================================================
 * Cloud Function: phonepeWebhook
 * Purpose: Server-to-server payment result callback from PhonePe.
 * This — NOT anything the Flutter app reports about its own UPI
 * intent — is the ONLY thing allowed to mark a payment 'paid'.
 * Security: X-VERIFY checksum verification + idempotency lock,
 * same pattern as affiliatePostbackWebhook.ts's HMAC + lock-doc.
 * ================================================================
 */

import * as functions from 'firebase-functions';
import { logger } from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as crypto from 'crypto';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

const SALT_KEY = process.env.PHONEPE_SALT_KEY || '';
const SALT_INDEX = process.env.PHONEPE_SALT_INDEX || '1';

interface PhonePeCallbackData {
  merchantId: string;
  merchantTransactionId: string;
  transactionId: string; // PhonePe's own txn id
  amount: number; // paise
  state: string; // 'COMPLETED' | 'FAILED' | 'PENDING'
  responseCode: string;
}

interface PhonePeCallbackBody {
  code: string; // 'PAYMENT_SUCCESS' | 'PAYMENT_ERROR' | ...
  merchantId: string;
  message: string;
  data: PhonePeCallbackData;
}

// FIX (audit pass — critical gap, same as phonepeCreateOrder.ts): a
// 1st-gen function must declare `.runWith({ secrets: [...] })` for a
// Secret-Manager-stored value to ever reach process.env — without
// this, PHONEPE_SALT_KEY reads as '', which means EVERY webhook
// checksum verification fails (line ~65's comparison can never match
// a real PhonePe-computed checksum against an empty salt), so every
// real payment callback gets rejected as "Invalid signature."
export const phonepeWebhook = functions
  .runWith({ secrets: ['PHONEPE_SALT_KEY', 'PHONEPE_SALT_INDEX'] })
  .https.onRequest(async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).json({ success: false, message: 'Method not allowed' });
    return;
  }

  const base64Response: string | undefined = req.body?.response;
  const receivedChecksum = req.headers['x-verify'] as string | undefined;

  if (!base64Response || !receivedChecksum) {
    res.status(400).json({ success: false, message: 'Malformed callback' });
    return;
  }

  // --- 1. Signature verification (Bulletproof Security) ---
  // PhonePe's own spec: X-VERIFY = sha256(base64Response + saltKey) + "###" + saltIndex.
  // Recomputed from the RAW base64 body, never from the parsed JSON —
  // any re-serialization (key order, whitespace) would break the hash.
  const expectedChecksum =
    crypto.createHash('sha256').update(base64Response + SALT_KEY).digest('hex') +
    '###' +
    SALT_INDEX;

  if (receivedChecksum !== expectedChecksum) {
    logger.warn('phonepeWebhook: checksum mismatch — rejecting callback', {
      receivedChecksum,
    });
    res.status(401).json({ success: false, message: 'Invalid signature' });
    return;
  }

  let payload: PhonePeCallbackBody;
  try {
    payload = JSON.parse(Buffer.from(base64Response, 'base64').toString('utf-8'));
  } catch (e) {
    res.status(400).json({ success: false, message: 'Could not decode callback payload' });
    return;
  }

  const { merchantTransactionId, state, transactionId, amount } = payload.data || ({} as PhonePeCallbackData);
  if (!merchantTransactionId) {
    res.status(400).json({ success: false, message: 'Missing merchantTransactionId' });
    return;
  }

  const isSuccess = payload.code === 'PAYMENT_SUCCESS' && state === 'COMPLETED';

  try {
    const orderRef = db.collection('payment_orders').doc(merchantTransactionId);

    const outcome = await db.runTransaction(async (transaction) => {
      const orderDoc = await transaction.get(orderRef);
      if (!orderDoc.exists) {
        throw new Error('ORDER_NOT_FOUND');
      }

      const order = orderDoc.data()!;

      // --- 2. Idempotency lock ---
      // PhonePe can and does retry webhooks. Once an order is already
      // 'paid' or 'failed', re-processing it must be a safe no-op —
      // never double-credit, never overwrite a terminal state.
      if (order.status === 'paid' || order.status === 'failed') {
        return { alreadyProcessed: true, status: order.status };
      }

      // --- 3. Amount sanity check ---
      // Defends against a forged/replayed callback claiming success
      // for a different (usually smaller) amount than what this
      // specific order was created for.
      if (typeof amount === 'number' && amount !== order.amountPaise) {
        logger.error('phonepeWebhook: amount mismatch', {
          merchantTransactionId,
          expected: order.amountPaise,
          received: amount,
        });
        transaction.update(orderRef, {
          status: 'failed',
          failureReason: 'Amount mismatch on callback',
          gatewayTransactionId: transactionId || null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return { alreadyProcessed: false, status: 'failed' };
      }

      const newStatus = isSuccess ? 'paid' : 'failed';

      transaction.update(orderRef, {
        status: newStatus,
        gatewayTransactionId: transactionId || null,
        gatewayState: state || null,
        rawCallback: payload,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Cascade to the actual order/booking doc this payment was for.
      // Admin SDK write — bypasses Firestore rules by design, since
      // this is the one path allowed to set a GATEWAY-verified paid
      // status, distinct from the existing hero-marks-paid cash/UPI-QR
      // flow that service_requests' own security rules already govern.
      //
      // FIX (food-checkout pay-before-order-exists flow, Sep 2026): this
      // used to call `transaction.update(sourceRef, ...)` unconditionally
      // — but Firestore's transaction.update() throws NOT_FOUND at COMMIT
      // time if the target doc doesn't exist yet, which aborts the ENTIRE
      // transaction, including the payment_orders write above. Food
      // checkout collects payment BEFORE seller_detail_screen.dart
      // creates the service_requests doc (see phonepeCreateOrder.ts's
      // header for why), so that doc genuinely does not exist yet at the
      // moment this webhook fires — without this guard, the payment
      // would come back from PhonePe successfully and this webhook would
      // silently retry-and-fail forever, with payment_orders itself stuck
      // on 'created'. Now: link immediately if the doc already exists
      // (the pay-AFTER-order-exists case, unchanged); otherwise skip the
      // cascade here and let phonepeConfirmLink.ts finish the link once
      // the client creates that doc moments later.
      if (newStatus === 'paid') {
        const sourceRef = db.collection(order.sourceCollection || 'service_requests').doc(order.requestId);
        const sourceSnap = await transaction.get(sourceRef);
        if (sourceSnap.exists) {
          transaction.update(sourceRef, {
            paymentStatus: 'paid',
            paymentMethod: 'phonepe',
            paymentGatewayTxnId: transactionId || null,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } else {
          logger.info(
            `phonepeWebhook: source doc ${order.sourceCollection}/${order.requestId} ` +
            'not created yet — deferring paymentStatus cascade to phonepeConfirmLink.ts',
          );
        }
      }

      return { alreadyProcessed: false, status: newStatus };
    });

    logger.info('phonepeWebhook processed', { merchantTransactionId, outcome });
    // PhonePe only checks HTTP status, not body — 200 tells it to stop retrying.
    res.status(200).json({ success: true });
  } catch (error: any) {
    if (error.message === 'ORDER_NOT_FOUND') {
      logger.error(`phonepeWebhook: no payment_orders doc for ${merchantTransactionId}`);
      // 200 here too — this is either a stale/foreign txn id or a race
      // with createPhonePeOrder's own write; returning 5xx would just
      // make PhonePe hammer retries on something we can never resolve.
      res.status(200).json({ success: false, message: 'Unknown order' });
      return;
    }
    logger.error('phonepeWebhook failed:', error);
    res.status(500).json({ success: false, message: 'Internal error' });
  }
});
