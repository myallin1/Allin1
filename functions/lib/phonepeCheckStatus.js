"use strict";
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
exports.checkPhonePeOrderStatus = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
const crypto = __importStar(require("crypto"));
if (admin.apps.length === 0) {
    admin.initializeApp();
}
const db = admin.firestore();
const PHONEPE_ENV = process.env.PHONEPE_ENV || 'sandbox';
const PHONEPE_BASE_URL = PHONEPE_ENV === 'production'
    ? 'https://api.phonepe.com/apis/hermes'
    : 'https://api-preprod.phonepe.com/apis/pg-sandbox';
const MERCHANT_ID = process.env.PHONEPE_MERCHANT_ID || '';
const SALT_KEY = process.env.PHONEPE_SALT_KEY || '';
const SALT_INDEX = process.env.PHONEPE_SALT_INDEX || '1';
exports.checkPhonePeOrderStatus = functions.https.onCall(async (data, context) => {
    var _a;
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
    const order = orderDoc.data();
    if (order.customerId !== context.auth.uid) {
        throw new functions.https.HttpsError('permission-denied', 'Not your order');
    }
    // Already resolved (most likely: the webhook beat this call).
    if (order.status === 'paid' || order.status === 'failed') {
        return { status: order.status };
    }
    const path = `/pg/v1/status/${MERCHANT_ID}/${merchantTransactionId}`;
    const checksum = crypto.createHash('sha256').update(path + SALT_KEY).digest('hex') + '###' + SALT_INDEX;
    const response = await fetch(`${PHONEPE_BASE_URL}${path}`, {
        method: 'GET',
        headers: {
            'Content-Type': 'application/json',
            accept: 'application/json',
            'X-VERIFY': checksum,
            'X-MERCHANT-ID': MERCHANT_ID,
        },
    });
    const result = await response.json();
    const gatewayState = (_a = result === null || result === void 0 ? void 0 : result.data) === null || _a === void 0 ? void 0 : _a.state;
    const isSuccess = (result === null || result === void 0 ? void 0 : result.code) === 'PAYMENT_SUCCESS' && gatewayState === 'COMPLETED';
    const isTerminalFailure = gatewayState === 'FAILED';
    if (!isSuccess && !isTerminalFailure) {
        // Still pending on the gateway's side — nothing to reconcile yet.
        return { status: order.status };
    }
    const newStatus = isSuccess ? 'paid' : 'failed';
    await db.runTransaction(async (transaction) => {
        var _a, _b;
        const fresh = await transaction.get(orderRef);
        const freshData = fresh.data();
        // Re-check inside the transaction — the webhook may have landed
        // in the gap between the read above and this write.
        if (freshData.status === 'paid' || freshData.status === 'failed')
            return;
        transaction.update(orderRef, {
            status: newStatus,
            gatewayTransactionId: ((_a = result === null || result === void 0 ? void 0 : result.data) === null || _a === void 0 ? void 0 : _a.transactionId) || null,
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
                paymentGatewayTxnId: ((_b = result === null || result === void 0 ? void 0 : result.data) === null || _b === void 0 ? void 0 : _b.transactionId) || null,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
    });
    return { status: newStatus };
});
//# sourceMappingURL=phonepeCheckStatus.js.map