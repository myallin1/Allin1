/**
 * ================================================================
 * Cloud Function: checkPhonePeOrderStatus
 * Purpose: Fallback reconciliation only. phonepeWebhook.ts is the
 * source of truth for marking a payment 'paid' — this callable exists
 * because the customer's app returns from the PhonePe checkout page
 * before the webhook is guaranteed to have landed, and the UI needs
 * something to poll (via Firestore stream is the primary path; this
 * is only for the "stream hasn't updated in N seconds" belt-and-
 * braces case). Still 100% server-to-server: this calls PhonePe's
 * own Status API, never trusts anything the client claims.
 * ================================================================
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as crypto from 'crypto';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

const PHONEPE_ENV = process.env.PHONEPE_ENV || 'sandbox';
const PHONEPE_BASE_URL =
  PHONEPE_ENV === 'production'
    ? 'https://api.phonepe.com/apis/hermes'
    : 'https://api-preprod.phonepe.com/apis/pg-sandbox';

const MERCHANT_ID = process.env.PHONEPE_MERCHANT_ID || '';
const SALT_KEY = process.env.PHONEPE_SALT_KEY || '';
const SALT_INDEX = process.env.PHONEPE_SALT_INDEX || '1';

interface CheckStatusRequest {
  merchantTransactionId: string;
}

export const checkPhonePeOrderStatus = functions.https.onCall(
  async (data: CheckStatusRequest, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be logged in');
    }
    const { merchantTransactionId } = data;
    if (!merchantTransactionId) {
      throw new functions.https.HttpsError('invalid-argument', 'merchantTransactionId required');
    }

    const orderRef = db.collection('payment_orders').doc(merchantTransactionId);
    const orderDoc = await orderRef.get();
    if (!orderDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Order not found');
    }
    const order = orderDoc.data()!;
    if (order.customerId !== context.auth.uid) {
      throw new functions.https.HttpsError('permission-denied', 'Not your order');
    }

    // Already resolved (most likely: the webhook beat this call).
    if (order.status === 'paid' || order.status === 'failed') {
      return { status: order.status };
    }

    const path = `/pg/v1/status/${MERCHANT_ID}/${merchantTransactionId}`;
    const checksum =
      crypto.createHash('sha256').update(path + SALT_KEY).digest('hex') + '###' + SALT_INDEX;

    const response = await fetch(`${PHONEPE_BASE_URL}${path}`, {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
        accept: 'application/json',
        'X-VERIFY': checksum,
        'X-MERCHANT-ID': MERCHANT_ID,
      },
    });
    const result: any = await response.json();

    const gatewayState = result?.data?.state;
    const isSuccess = result?.code === 'PAYMENT_SUCCESS' && gatewayState === 'COMPLETED';
    const isTerminalFailure = gatewayState === 'FAILED';

    if (!isSuccess && !isTerminalFailure) {
      // Still pending on the gateway's side — nothing to reconcile yet.
      return { status: order.status };
    }

    const newStatus = isSuccess ? 'paid' : 'failed';

    await db.runTransaction(async (transaction) => {
      const fresh = await transaction.get(orderRef);
      const freshData = fresh.data()!;
      // Re-check inside the transaction — the webhook may have landed
      // in the gap between the read above and this write.
      if (freshData.status === 'paid' || freshData.status === 'failed') return;

      transaction.update(orderRef, {
        status: newStatus,
        gatewayTransactionId: result?.data?.transactionId || null,
        gatewayState: gatewayState || null,
        reconciledBy: 'checkPhonePeOrderStatus',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      if (newStatus === 'paid') {
        const sourceRef = db
          .collection(freshData.sourceCollection || 'service_requests')
          .doc(freshData.requestId);
        transaction.update(sourceRef, {
          paymentStatus: 'paid',
          paymentMethod: 'phonepe',
          paymentGatewayTxnId: result?.data?.transactionId || null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    });

    return { status: newStatus };
  },
);
