"use strict";
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
exports.createPhonePeOrder = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
const crypto = __importStar(require("crypto"));
if (admin.apps.length === 0) {
    admin.initializeApp();
}
const db = admin.firestore();
// Sandbox vs prod base URL — flip PHONEPE_ENV once you have production
// merchant credentials from PhonePe's business dashboard.
const PHONEPE_ENV = process.env.PHONEPE_ENV || 'sandbox';
const PHONEPE_BASE_URL = PHONEPE_ENV === 'production'
    ? 'https://api.phonepe.com/apis/hermes'
    : 'https://api-preprod.phonepe.com/apis/pg-sandbox';
const MERCHANT_ID = process.env.PHONEPE_MERCHANT_ID || '';
const SALT_KEY = process.env.PHONEPE_SALT_KEY || '';
const SALT_INDEX = process.env.PHONEPE_SALT_INDEX || '1';
// Where PhonePe's webhook (server-to-server) and the browser redirect
// (customer-facing, informational only) point to. Set these to your
// deployed function URLs / app deep link once known.
const CALLBACK_URL = process.env.PHONEPE_CALLBACK_URL || '';
const APP_REDIRECT_URL = process.env.PHONEPE_APP_REDIRECT_URL || 'https://myallin1.app/payment-return';
exports.createPhonePeOrder = functions.https.onCall(async (data, context) => {
    var _a, _b, _c, _d;
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in');
    }
    if (!MERCHANT_ID || !SALT_KEY || !CALLBACK_URL) {
        throw new functions.https.HttpsError('failed-precondition', 'PhonePe is not configured on the server (missing merchant/salt/callback env vars)');
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
    if (((_a = sourceDoc.data()) === null || _a === void 0 ? void 0 : _a.customerId) !== uid) {
        throw new functions.https.HttpsError('permission-denied', 'Not your order');
    }
    const merchantTransactionId = `MTX${data.requestId}${Date.now()}`;
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
    const checksum = crypto
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
        const result = await response.json();
        if (!response.ok || !(result === null || result === void 0 ? void 0 : result.success)) {
            functions.logger.error('PhonePe create-order failed', result);
            await db.collection('payment_orders').doc(merchantTransactionId).update({
                status: 'failed',
                failureReason: (result === null || result === void 0 ? void 0 : result.message) || 'Gateway rejected order creation',
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            throw new functions.https.HttpsError('internal', 'Could not start payment');
        }
        const redirectUrl = (_d = (_c = (_b = result.data) === null || _b === void 0 ? void 0 : _b.instrumentResponse) === null || _c === void 0 ? void 0 : _c.redirectInfo) === null || _d === void 0 ? void 0 : _d.url;
        if (!redirectUrl) {
            throw new functions.https.HttpsError('internal', 'Gateway did not return a checkout URL');
        }
        return { merchantTransactionId, redirectUrl };
    }
    catch (error) {
        functions.logger.error(`createPhonePeOrder failed for ${merchantTransactionId}:`, error);
        if (error instanceof functions.https.HttpsError)
            throw error;
        throw new functions.https.HttpsError('internal', 'Payment gateway request failed');
    }
});
//# sourceMappingURL=phonepeCreateOrder.js.map