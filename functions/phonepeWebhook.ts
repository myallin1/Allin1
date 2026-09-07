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

// FIX (food-section audit, Sep 2026 — same critical gap as
// phonepeCreateOrder.ts): without `.runWith({ secrets: [...] })`,
// SALT_KEY reads as '' regardless of Secret Manager, so the checksum
// verification below can never match a real PhonePe-computed
// signature — every genuine payment callback gets rejected as
// "Invalid signature," silently stranding the order as unpaid forever.
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

      // Collected into one object and written via a SINGLE
      // transaction.update(orderRef, ...) call below (see the
      // cascadeFailed branch further down) — deliberately avoiding two
      // separate .update() calls against the same DocumentReference
      // within one transaction. The Admin SDK's actual behavior for
      // that isn't clearly documented either way, so rather than rely
      // on unverified behavior, every field this function might write
      // to orderRef is merged into one map and applied once.
      const orderUpdate: { [key: string]: any } = {
        status: newStatus,
        gatewayTransactionId: transactionId || null,
        gatewayState: state || null,
        rawCallback: payload,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      // Cascade to the actual order/booking doc this payment was for.
      // Admin SDK write — bypasses Firestore rules by design, since
      // this is the one path allowed to set a GATEWAY-verified paid
      // status, distinct from the existing hero-marks-paid cash/UPI-QR
      // flow that service_requests' own security rules already govern.
      //
      // FIX (re-audit, Sep 2026 — real, previously-undetectable bug
      // now that this path is reachable from real food checkouts): this
      // used to call transaction.update(sourceRef, ...) UNCONDITIONALLY.
      // This app deletes a cancelled order's doc entirely rather than
      // soft-deleting it (see ServiceRequestService.cancelServiceRequest)
      // — a real, available action while a payment can genuinely be in
      // flight. Firestore's transaction.update() throws NOT_FOUND at
      // COMMIT time against a missing doc, which aborts the WHOLE
      // transaction — including the payment_orders status write just
      // above. Net effect before this fix: a customer whose order got
      // cancelled mid-payment would have PhonePe genuinely take their
      // money, then this webhook would fail every single retry forever,
      // leaving payment_orders stuck on 'created' with no record
      // anywhere that the payment actually succeeded. Checking
      // existence first means the payment_orders record — which is
      // what actually matters for reconciling real money — always
      // correctly reflects the true outcome, regardless of what
      // happened to the order doc in the meantime.
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
          // FIX (re-audit, Sep 2026 — the "manual reconciliation" this
          // comment promised didn't actually exist anywhere: nothing in
          // the app ever reads payment_orders, so a log line only an
          // engineer manually tailing Cloud Functions logs would ever
          // see wasn't a real safety net. Folded into orderUpdate (see
          // above) rather than a second transaction.update(orderRef,
          // ...) call, so this doc is only ever written once per
          // invocation — this flag is what lets
          // admin_payment_reconciliation_screen.dart surface it without
          // having to re-check every single 'paid' row's linked order
          // for existence.
          orderUpdate.cascadeFailed = true;
          orderUpdate.cascadeFailedReason = 'Order doc no longer existed when payment succeeded';
          logger.error(
            `phonepeWebhook: payment succeeded but order ${order.sourceCollection || 'service_requests'}/` +
            `${order.requestId} no longer exists (likely cancelled mid-payment) — payment_orders is still ` +
            'marked paid for manual reconciliation, but nothing was cascaded.',
            { merchantTransactionId },
          );
        }
      }

      transaction.update(orderRef, orderUpdate);

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
