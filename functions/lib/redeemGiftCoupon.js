"use strict";
/**
 * ================================================================
 * Cloud Function: redeemGiftCoupon
 * Purpose: Server-authoritative redemption of a gift coupon (issued by
 * an admin against a completed mobile repair/replacement service
 * request) as a discount on a Hero task bill or a Hotel order.
 *
 * SECURITY: per Nizam's explicit call — client-side Firestore
 * transactions + security rules are NOT sufficient for a discount that
 * moves real money. This function is the ONLY thing allowed to flip a
 * gift_coupons doc from 'active' to 'redeemed'; firestore.rules denies
 * every client write to that field. The Flutter client sends only the
 * coupon id and the order it's being applied to — all validation,
 * discount math, and the status flip happen here inside one atomic
 * Firestore transaction, so a coupon can never be redeemed twice even
 * under a race (two taps, two devices, retried request).
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
exports.redeemGiftCoupon = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
if (admin.apps.length === 0) {
    admin.initializeApp();
}
const db = admin.firestore();
exports.redeemGiftCoupon = functions.https.onCall(async (data, context) => {
    var _a;
    // ── AUTH CHECK ────────────────────────────────────────────────
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in');
    }
    const uid = context.auth.uid;
    // ── INPUT VALIDATION ─────────────────────────────────────────
    const couponId = data.couponId;
    if (!couponId || typeof couponId !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'couponId is required');
    }
    const requestId = data.requestId;
    const orderAmount = data.orderAmount;
    if (!requestId && (orderAmount === undefined || orderAmount === null)) {
        throw new functions.https.HttpsError('invalid-argument', 'Either requestId (existing bill) or orderAmount (new order) is required');
    }
    if (orderAmount !== undefined && (typeof orderAmount !== 'number' || orderAmount < 0)) {
        throw new functions.https.HttpsError('invalid-argument', 'orderAmount must be a non-negative number');
    }
    try {
        return await db.runTransaction(async (tx) => {
            var _a, _b;
            const couponRef = db.collection('gift_coupons').doc(couponId);
            const couponSnap = await tx.get(couponRef);
            if (!couponSnap.exists) {
                throw new Error('COUPON_NOT_FOUND');
            }
            const coupon = couponSnap.data();
            // Ownership — a customer can only redeem their OWN coupon.
            if (coupon.customerId !== uid) {
                throw new Error('NOT_OWNER');
            }
            if (coupon.status !== 'active') {
                throw new Error('ALREADY_REDEEMED');
            }
            const expiresAt = coupon.expiresAt;
            if (expiresAt && expiresAt.toDate() < new Date()) {
                throw new Error('EXPIRED');
            }
            const value = typeof coupon.value === 'number' ? coupon.value : 0;
            let baseAmount;
            let requestRef = null;
            let resolvedRequestType = (_a = data.requestType) !== null && _a !== void 0 ? _a : null;
            if (requestId) {
                // Case A — Heroes bill: read the REAL bill off the doc, never
                // trust a client-passed amount here.
                requestRef = db.collection('service_requests').doc(requestId);
                const requestSnap = await tx.get(requestRef);
                if (!requestSnap.exists) {
                    throw new Error('REQUEST_NOT_FOUND');
                }
                const request = requestSnap.data();
                if (request.customerId !== uid) {
                    throw new Error('NOT_OWNER');
                }
                baseAmount =
                    (typeof request.finalAmount === 'number' && request.finalAmount) ||
                        (typeof request.estimatedAmount === 'number' && request.estimatedAmount) ||
                        0;
                resolvedRequestType = (_b = request.requestType) !== null && _b !== void 0 ? _b : resolvedRequestType;
            }
            else {
                // Case B — Hotel checkout: no bill doc exists yet.
                baseAmount = orderAmount;
            }
            const discount = Math.min(value, baseAmount);
            const payableAmount = Math.max(baseAmount - discount, 0);
            if (requestRef) {
                tx.update(requestRef, { finalAmount: payableAmount });
            }
            tx.update(couponRef, {
                status: 'redeemed',
                redeemedAt: admin.firestore.FieldValue.serverTimestamp(),
                redeemedOnRequestId: requestId !== null && requestId !== void 0 ? requestId : null,
                redeemedOnRequestType: resolvedRequestType,
            });
            return { success: true, discount, payableAmount };
        });
    }
    catch (error) {
        functions.logger.error(`redeemGiftCoupon failed for coupon ${couponId}, user ${uid}:`, (_a = error === null || error === void 0 ? void 0 : error.message) !== null && _a !== void 0 ? _a : error);
        switch (error === null || error === void 0 ? void 0 : error.message) {
            case 'COUPON_NOT_FOUND':
                throw new functions.https.HttpsError('not-found', 'This coupon does not exist.');
            case 'NOT_OWNER':
                throw new functions.https.HttpsError('permission-denied', 'This coupon does not belong to you.');
            case 'ALREADY_REDEEMED':
                throw new functions.https.HttpsError('failed-precondition', 'This coupon has already been used.');
            case 'EXPIRED':
                throw new functions.https.HttpsError('failed-precondition', 'This coupon has expired.');
            case 'REQUEST_NOT_FOUND':
                throw new functions.https.HttpsError('not-found', 'The bill for this order could not be found.');
            default:
                if (error instanceof functions.https.HttpsError)
                    throw error;
                throw new functions.https.HttpsError('internal', 'Could not redeem this coupon. Please try again.');
        }
    }
});
//# sourceMappingURL=redeemGiftCoupon.js.map