"use strict";
/**
 * ================================================================
 * Cloud Function: scratchGiftCoupon
 * Purpose: Step 3 of the gift-coupon scratch-card flow — the customer
 *          scratches a coupon open and the gift inside is revealed.
 *
 * SECURITY: the whole feature rests on the coupon staying sealed until
 * its `unlockAt`, and on an admin having chosen what's inside. Neither
 * can be enforced on the client — a device clock is trivially changed,
 * and the reveal UI necessarily runs on the customer's phone. So the
 * gift is NOT sent to the client until this function has verified,
 * against the SERVER clock, that the timer has actually run out; the
 * customer app renders the foil over a placeholder and only learns the
 * real gift from this response. firestore.rules denies clients every
 * write to gift_coupons, so 'ready' -> 'scratched' happens only here.
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
exports.scratchGiftCoupon = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
if (admin.apps.length === 0) {
    admin.initializeApp();
}
const db = admin.firestore();
exports.scratchGiftCoupon = functions.https.onCall(async (data, context) => {
    var _a;
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in');
    }
    const uid = context.auth.uid;
    const couponId = data === null || data === void 0 ? void 0 : data.couponId;
    if (!couponId || typeof couponId !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'couponId is required');
    }
    try {
        return await db.runTransaction(async (tx) => {
            var _a, _b;
            const couponRef = db.collection('gift_coupons').doc(couponId);
            // The sealed envelope — what's actually inside. Kept in a
            // collection the customer cannot read, so the prize is unknown
            // to the client until this function copies it across below.
            const giftRef = db.collection('gift_coupon_gifts').doc(couponId);
            const snap = await tx.get(couponRef);
            const giftSnap = await tx.get(giftRef);
            if (!snap.exists) {
                throw new Error('NOT_FOUND');
            }
            const coupon = snap.data();
            if (coupon.customerId !== uid) {
                throw new Error('NOT_OWNER');
            }
            if (coupon.status === 'awaiting_gift') {
                // Admin hasn't picked the gift yet — there is genuinely
                // nothing inside to reveal.
                throw new Error('NOT_READY');
            }
            if (coupon.status !== 'ready') {
                throw new Error('ALREADY_SCRATCHED');
            }
            const expiresAt = coupon.expiresAt;
            if (expiresAt && expiresAt.toMillis() < Date.now()) {
                throw new Error('EXPIRED');
            }
            // THE server-clock check the client cannot fake.
            const unlockAt = coupon.unlockAt;
            if (unlockAt && unlockAt.toMillis() > Date.now()) {
                throw new Error('STILL_LOCKED');
            }
            // Open the envelope. A 'ready' coupon with no gift doc means an
            // admin armed it and the gift write was lost — surface that as
            // "not ready" rather than revealing an empty card.
            if (!giftSnap.exists) {
                throw new Error('NOT_READY');
            }
            const gift = giftSnap.data();
            const giftType = (_a = gift.giftType) !== null && _a !== void 0 ? _a : '';
            const value = typeof gift.value === 'number' ? gift.value : 0;
            const giftLabel = (_b = gift.giftLabel) !== null && _b !== void 0 ? _b : '';
            // Copy the gift onto the customer-visible doc — from this point
            // the card is open, so there is nothing left to hide, and
            // redeemGiftCoupon reads `value`/`giftType` from here.
            tx.update(couponRef, {
                status: 'scratched',
                giftType,
                value,
                giftLabel,
                scratchedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return {
                success: true,
                giftType,
                value,
                giftLabel,
                giftDescription: giftType === 'discount' ? `₹${Math.round(value)} OFF` : giftLabel,
            };
        });
    }
    catch (error) {
        if (error instanceof functions.https.HttpsError)
            throw error;
        functions.logger.error(`scratchGiftCoupon failed for ${couponId}, user ${uid}:`, (_a = error === null || error === void 0 ? void 0 : error.message) !== null && _a !== void 0 ? _a : error);
        switch (error === null || error === void 0 ? void 0 : error.message) {
            case 'NOT_FOUND':
                throw new functions.https.HttpsError('not-found', 'This coupon does not exist.');
            case 'NOT_OWNER':
                throw new functions.https.HttpsError('permission-denied', 'This coupon does not belong to you.');
            case 'NOT_READY':
                throw new functions.https.HttpsError('failed-precondition', 'Your gift is still being prepared. Please check back soon!');
            case 'ALREADY_SCRATCHED':
                throw new functions.https.HttpsError('failed-precondition', 'This card has already been scratched.');
            case 'STILL_LOCKED':
                throw new functions.https.HttpsError('failed-precondition', 'This card has not unlocked yet.');
            case 'EXPIRED':
                throw new functions.https.HttpsError('failed-precondition', 'This coupon has expired.');
            default:
                throw new functions.https.HttpsError('internal', 'Could not open this card. Please try again.');
        }
    }
});
//# sourceMappingURL=scratchGiftCoupon.js.map