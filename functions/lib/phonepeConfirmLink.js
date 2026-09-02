"use strict";
/**
 * ================================================================
 * Cloud Function: confirmPhonePeLink
 * Purpose: Closes the loop for the "pay BEFORE the order doc exists"
 * flow — food_checkout_screen.dart collects payment for a RESERVED
 * requestId before seller_detail_screen.dart ever creates the
 * service_requests doc, so phonepeWebhook.ts's own cascade (which runs
 * at payment time) has nothing to write paymentStatus onto yet and
 * skips it (see that file's comment). Once the client has actually
 * created the order with that same id, it calls this callable to
 * finish the link.
 *
 * Still never trusts the client's word that payment succeeded — this
 * re-reads payment_orders/{merchantTransactionId}, which only
 * phonepeWebhook.ts's checksum-verified callback can ever set to
 * 'paid', and only acts if that is already true.
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
exports.confirmPhonePeLink = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
if (admin.apps.length === 0) {
    admin.initializeApp();
}
const db = admin.firestore();
exports.confirmPhonePeLink = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in');
    }
    const { merchantTransactionId, requestId } = data;
    if (!merchantTransactionId || !requestId) {
        throw new functions.https.HttpsError('invalid-argument', 'merchantTransactionId and requestId are required');
    }
    const orderRef = db.collection('payment_orders').doc(merchantTransactionId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'Payment order not found');
    }
    const order = orderSnap.data();
    if (order.customerId !== context.auth.uid) {
        throw new functions.https.HttpsError('permission-denied', 'Not your payment');
    }
    // Defends against a mismatched/forged pairing — the requestId this
    // call names must be the exact one this payment was created for.
    if (order.requestId !== requestId) {
        throw new functions.https.HttpsError('failed-precondition', 'requestId does not match this payment order');
    }
    if (order.status !== 'paid') {
        // Not an error — the webhook may simply not have landed yet. The
        // client's own Firestore stream on payment_orders is what it
        // should really be waiting on; this callable only ever confirms
        // an ALREADY-verified payment, never advances one.
        return { linked: false, status: order.status };
    }
    const sourceRef = db.collection(order.sourceCollection || 'service_requests').doc(requestId);
    await db.runTransaction(async (transaction) => {
        var _a;
        const sourceSnap = await transaction.get(sourceRef);
        if (!sourceSnap.exists) {
            throw new functions.https.HttpsError('not-found', 'Order doc not created yet — create it before confirming the link');
        }
        // Idempotent — a retry (double-tap, app killed after a first
        // successful call) must never re-stamp fields or error out.
        if (((_a = sourceSnap.data()) === null || _a === void 0 ? void 0 : _a.paymentStatus) === 'paid')
            return;
        transaction.update(sourceRef, {
            paymentStatus: 'paid',
            paymentMethod: 'phonepe',
            paymentGatewayTxnId: order.gatewayTransactionId || null,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    });
    return { linked: true, status: 'paid' };
});
//# sourceMappingURL=phonepeConfirmLink.js.map