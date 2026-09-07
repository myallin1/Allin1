/**
 * ================================================================
 * Cloud Function: createPhonePeOrder
 * Purpose: Server-to-server "create payment order" call to PhonePe's
 * Standard Checkout API. Returns a hosted-page redirect URL that the
 * Flutter app opens — the customer never sees our merchant salt key,
 * it never leaves this function.
 * ================================================================
 * Money flow this feeds:
 *   1. Flutter calls this callable with {requestId, amount}.
 *   2. This function creates a `payment_orders/{merchantTransactionId}`
 *      doc (status: 'created') and asks PhonePe for a checkout URL.
 *   3. Flutter opens that URL (webview or external browser). Customer
 *      pays via whichever UPI app they have installed.
 *   4. PhonePe calls phonepeWebhook.ts server-to-server with the
 *      result — THAT write (not anything from the client) is what
 *      flips payment_orders/.status to 'paid' and cascades to the
 *      linked service_requests/orders doc. This function never marks
 *      anything paid itself.
 * ================================================================
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as crypto from 'crypto';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

// Sandbox vs prod base URL — flip PHONEPE_ENV once you have production
// merchant credentials from PhonePe's business dashboard.
const PHONEPE_ENV = process.env.PHONEPE_ENV || 'sandbox';
const PHONEPE_BASE_URL =
  PHONEPE_ENV === 'production'
    ? 'https://api.phonepe.com/apis/hermes'
    : 'https://api-preprod.phonepe.com/apis/pg-sandbox';

const MERCHANT_ID = process.env.PHONEPE_MERCHANT_ID || '';
const SALT_KEY = process.env.PHONEPE_SALT_KEY || '';
const SALT_INDEX = process.env.PHONEPE_SALT_INDEX || '1';

// Where PhonePe's webhook (server-to-server) and the browser redirect
// (customer-facing, informational only) point to. Set these to your
// deployed function URLs / app deep link once known.
const CALLBACK_URL = process.env.PHONEPE_CALLBACK_URL || '';
const APP_REDIRECT_URL =
  process.env.PHONEPE_APP_REDIRECT_URL || 'https://myallin1.app/payment-return';

interface CreateOrderRequest {
  requestId: string; // links back to service_requests/{requestId} (or any order doc)
  amount: number; // rupees, NOT paise — this function converts
  collection?: string; // defaults to 'service_requests'
}

// FIX (food-section audit, Sep 2026 — critical, currently-live gap):
// this is a 1st-gen Cloud Function (`functions.https.onCall`, not the
// v2 API). A 1st-gen function ONLY receives a Secret-Manager-stored
// value in process.env if it explicitly declares
// `.runWith({ secrets: [...] })` — without this, MERCHANT_ID/SALT_KEY/
// etc. above read as '' regardless of whether the secrets were ever
// set via `firebase functions:secrets:set`, and every PhonePe checkout
// attempt fails with "PhonePe is not configured on the server."
export const createPhonePeOrder = functions
  .runWith({
    secrets: [
      'PHONEPE_MERCHANT_ID',
      'PHONEPE_SALT_KEY',
      'PHONEPE_SALT_INDEX',
      'PHONEPE_ENV',
      'PHONEPE_CALLBACK_URL',
      'PHONEPE_APP_REDIRECT_URL',
    ],
  })
  .https.onCall(
  async (data: CreateOrderRequest, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be logged in');
    }
    if (!MERCHANT_ID || !SALT_KEY || !CALLBACK_URL) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'PhonePe is not configured on the server (missing merchant/salt/callback env vars)',
      );
    }
    if (!data.requestId || typeof data.requestId !== 'string') {
      throw new functions.https.HttpsError('invalid-argument', 'requestId is required');
    }
    if (!data.amount || data.amount <= 0) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid amount');
    }

    const sourceCollection = data.collection || 'service_requests';
    const uid = context.auth.uid;
    const amountPaise = Math.round(data.amount * 100);

    // Ownership check — a customer can only start a payment for their
    // own order, never on someone else's requestId.
    const sourceDoc = await db.collection(sourceCollection).doc(data.requestId).get();
    if (!sourceDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Order not found');
    }
    const sourceData = sourceDoc.data()!;
    if (sourceData.customerId !== uid) {
      throw new functions.https.HttpsError('permission-denied', 'Not your order');
    }

    // FIX (re-audit, Sep 2026 — found while wiring this into food
    // checkout for real money): this function trusted the CLIENT-
    // SUPPLIED [data.amount] outright, with nothing checked against
    // what the order itself was actually created for. Once a real
    // screen calls this (food checkout now does), an attacker could
    // call it directly with the true requestId but an arbitrary LOWER
    // amount, and PhonePe would happily collect that lower sum while
    // the order's own item list/subtotal — and the seller's/hero's
    // payout math, which reads details.subtotal — still reflects the
    // full price. Cross-checks against every amount field this
    // codebase's own order docs actually use (finalAmount ->
    // estimatedAmount -> details.subtotal/totalAmount, the same
    // fallback chain ServiceRequestModel.displayAmount already applies
    // client-side) — small rounding tolerance for float noise, never
    // exact-equality on money. An order shape with NONE of those
    // fields resolves to `null` and is let through unchanged — this
    // function is deliberately generic over "any order doc" per its
    // own header, so an unrecognised shape must never be silently
    // treated as invalid.
    const details = (sourceData.details as Record<string, unknown>) || {};
    const expectedAmount =
      (sourceData.finalAmount as number | undefined) ??
      (sourceData.estimatedAmount as number | undefined) ??
      (details.subtotal as number | undefined) ??
      (details.totalAmount as number | undefined) ??
      null;
    if (expectedAmount !== null && Math.abs(expectedAmount - data.amount) > 0.5) {
      functions.logger.error('createPhonePeOrder: amount mismatch', {
        requestId: data.requestId,
        expected: expectedAmount,
        received: data.amount,
      });
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Payment amount does not match the order total',
      );
    }

    // FIX (re-audit, Sep 2026 — real bug, previously undetectable
    // because nothing reachable ever called this function): PhonePe's
    // Standard Checkout API caps merchantTransactionId at 35 characters,
    // alphanumeric only. The old format — 'MTX' + a 20-char Firestore
    // auto-id + a 13-digit Date.now() — is 36 characters, ONE over the
    // limit, which means PhonePe would reject every single order
    // creation call at the gateway itself. Embedding requestId in the
    // transaction id was never actually necessary for traceability —
    // it's already stored as its own field on this payment_orders doc
    // a few lines below, so a much shorter, still-unique id (timestamp
    // + a short random suffix, well under the limit) works exactly the
    // same for lookups and cannot collide within the same millisecond.
    const merchantTransactionId = `MTX${Date.now()}${crypto.randomBytes(4).toString('hex')}`;

    const payload = {
      merchantId: MERCHANT_ID,
      merchantTransactionId,
      merchantUserId: uid,
      amount: amountPaise,
      redirectUrl: `${APP_REDIRECT_URL}?mtx=${merchantTransactionId}`,
      redirectMode: 'REDIRECT',
      callbackUrl: CALLBACK_URL,
      paymentInstrument: { type: 'PAY_PAGE' },
    };

    const base64Payload = Buffer.from(JSON.stringify(payload)).toString('base64');
    const checksum =
      crypto
        .createHash('sha256')
        .update(base64Payload + '/pg/v1/pay' + SALT_KEY)
        .digest('hex') +
      '###' +
      SALT_INDEX;

    // Write the pending order BEFORE calling out — if the outbound
    // call fails partway, we still have a record to reconcile/retry
    // against instead of a payment PhonePe might process with nothing
    // on our side referencing it.
    await db.collection('payment_orders').doc(merchantTransactionId).set({
      merchantTransactionId,
      requestId: data.requestId,
      sourceCollection,
      customerId: uid,
      amount: data.amount,
      amountPaise,
      status: 'created',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    try {
      const response = await fetch(`${PHONEPE_BASE_URL}/pg/v1/pay`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          accept: 'application/json',
          'X-VERIFY': checksum,
        },
        body: JSON.stringify({ request: base64Payload }),
      });

      const result: any = await response.json();

      if (!response.ok || !result?.success) {
        functions.logger.error('PhonePe create-order failed', result);
        await db.collection('payment_orders').doc(merchantTransactionId).update({
          status: 'failed',
          failureReason: result?.message || 'Gateway rejected order creation',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        throw new functions.https.HttpsError('internal', 'Could not start payment');
      }

      const redirectUrl = result.data?.instrumentResponse?.redirectInfo?.url;
      if (!redirectUrl) {
        throw new functions.https.HttpsError('internal', 'Gateway did not return a checkout URL');
      }

      return { merchantTransactionId, redirectUrl };
    } catch (error: any) {
      functions.logger.error(`createPhonePeOrder failed for ${merchantTransactionId}:`, error);
      // FIX (full re-audit, Sep 2026): the `!response.ok` branch above
      // explicitly marks payment_orders 'failed' before throwing, but
      // an error thrown BEFORE that check runs at all (e.g.
      // response.json() itself throwing on a malformed/non-JSON
      // response — a real possibility for a gateway error page, not
      // just a network drop) skipped that update entirely. The
      // customer still sees an error either way, but the doc was left
      // stuck on 'created' forever instead of clearly 'failed' — a
      // stale, ambiguous record for anyone reconciling payment_orders
      // later. Best-effort and non-blocking: a failure HERE must never
      // mask the original error being thrown below.
      try {
        await db.collection('payment_orders').doc(merchantTransactionId).update({
          status: 'failed',
          failureReason: error?.message || 'Unexpected error before gateway response',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (cleanupError) {
        functions.logger.error(`createPhonePeOrder: failure-status cleanup also failed for ${merchantTransactionId}:`, cleanupError);
      }
      if (error instanceof functions.https.HttpsError) throw error;
      throw new functions.https.HttpsError('internal', 'Payment gateway request failed');
    }
  },
);
