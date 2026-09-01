"use strict";
/**
 * ================================================================
 * Cloud Function: notifyCustomerOnCouponReady
 * Trigger: Firestore onUpdate on gift_coupons/{couponId}
 * Purpose: CTO audit blind spot — the moment a card is armed, tell the
 *          customer there's a mystery gift waiting. This is the hook
 *          that actually brings them back into the app; without it the
 *          card just sits in Rewards until they happen to look.
 *
 * NOTE ON WHAT THIS DOES **NOT** SAY: the push never contains the
 * gift. It's a "you have something to scratch" nudge only — putting
 * the prize in a notification payload would defeat the sealed-envelope
 * design (functions/scratchGiftCoupon.ts), since a push payload is
 * readable on-device without ever opening the card.
 *
 * Fires on 'awaiting_gift' -> 'ready' regardless of whether a human
 * admin or armStaleGiftCoupons did the arming, so both paths notify.
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
exports.notifyCustomerOnCouponReady = void 0;
const functions = __importStar(require("firebase-functions"));
const firebase_functions_1 = require("firebase-functions");
const admin = __importStar(require("firebase-admin"));
if (admin.apps.length === 0) {
    admin.initializeApp();
}
const db = admin.firestore();
exports.notifyCustomerOnCouponReady = functions.firestore
    .document('gift_coupons/{couponId}')
    .onUpdate(async (change, context) => {
    var _a, _b;
    const couponId = context.params.couponId;
    const before = change.before.data();
    const after = change.after.data();
    if (!before || !after)
        return null;
    if (before.status !== 'awaiting_gift' || after.status !== 'ready') {
        return null;
    }
    const customerId = after.customerId;
    if (!customerId)
        return null;
    try {
        const userDoc = await db.collection('users').doc(customerId).get();
        const fcmToken = (_a = userDoc.data()) === null || _a === void 0 ? void 0 : _a.fcmToken;
        if (!fcmToken || fcmToken.trim().length === 0) {
            firebase_functions_1.logger.info(`[notifyCustomerOnCouponReady] no FCM token for customer ${customerId} — card still waiting in Rewards`);
            return null;
        }
        // If the card is still on a timer, say so rather than telling
        // them to scratch something that won't open yet.
        const unlockAt = after.unlockAt;
        const stillLocked = unlockAt ? unlockAt.toMillis() > Date.now() : false;
        await admin.messaging().send({
            token: fcmToken,
            data: {
                couponId,
                type: 'gift_coupon_ready',
                click_action: 'FLUTTER_NOTIFICATION_CLICK',
            },
            notification: {
                title: '🎁 A mystery gift is waiting!',
                body: stillLocked
                    ? 'Your scratch card is almost ready — open Allin1 Rewards to see the countdown.'
                    : 'Open Allin1 Rewards and scratch your card to see what you won!',
            },
        });
        firebase_functions_1.logger.info(`[notifyCustomerOnCouponReady] notified customer ${customerId} for coupon ${couponId}`);
    }
    catch (error) {
        // Never let a failed push break the arming flow — the coupon is
        // already 'ready' and will be found in Rewards regardless.
        firebase_functions_1.logger.error(`[notifyCustomerOnCouponReady] send failed for ${couponId}:`, (_b = error === null || error === void 0 ? void 0 : error.message) !== null && _b !== void 0 ? _b : error);
    }
    return null;
});
//# sourceMappingURL=notifyCustomerOnCouponReady.js.map