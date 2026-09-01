"use strict";
/**
 * ================================================================
 * Gift Coupon maintenance — the two lifecycle gaps the CTO audit
 * flagged as blind spots in the original design.
 *
 *  1. revokeCouponOnServiceDeleted — the customer's own cancel path
 *     (ServiceRequestService.cancelServiceRequest) doesn't set a
 *     'cancelled' status, it DELETES the service_requests doc outright
 *     — so the cancel branch of onServiceRequestUpdated.ts (an
 *     onUpdate trigger) can never see it. This onDelete trigger is the
 *     only way to catch that path.
 *
 *  2. armStaleGiftCoupons — a coupon sits in 'awaiting_gift' until an
 *     admin decides what's inside. If the admin is away, the customer
 *     stares at "your gift is being prepared" indefinitely, which is
 *     worse for trust than a small guaranteed gift. After a grace
 *     period we arm it with a configurable default.
 *
 * NOT MERGED with onServiceRequestUpdated.ts: onDelete and onUpdate
 * are different trigger types on the same document path — Cloud
 * Functions has no single-trigger equivalent that fires on both, so
 * this has to stay a separate function. The CTO's cost concern (§8.2)
 * was specifically about running two onUpdate handlers on every write;
 * a delete is comparatively rare (test cleanup, explicit cancels), so
 * this one function firing on those is not the same cost problem.
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
exports.armStaleGiftCoupons = exports.revokeCouponOnServiceDeleted = void 0;
const functions = __importStar(require("firebase-functions"));
const firebase_functions_1 = require("firebase-functions");
const admin = __importStar(require("firebase-admin"));
if (admin.apps.length === 0) {
    admin.initializeApp();
}
const db = admin.firestore();
/** Hours a coupon may wait for an admin before a default is applied. */
const STALE_AFTER_HOURS = 48;
/** Used when system_settings/gift_coupon_defaults doesn't exist yet. */
const HARDCODED_FALLBACK = { giftType: 'discount', value: 10, giftLabel: '' };
// ================================================================
// 1. Revoke a coupon whose service was deleted (customer cancel path).
// ================================================================
//
// Only an UNSPENT coupon is revoked ('awaiting_gift' or 'ready').
//
// DELIBERATELY does not touch 'scratched' — verified against actual
// reachability, not just left alone by default:
//   - No refund concept exists anywhere in this codebase.
//   - A coupon only exists once paymentStatus == 'paid', which in this
//     codebase only happens once status == 'completed'.
//   - Every cancel entry point (customer's hero_booking_tracking_
//     screen.dart, admin's admin_new_orders_screen.dart) is explicitly
//     gated to pre-'completed' requests only — see their own comments.
//   So a coupon can never reach 'scratched' by way of a request that
//   later gets cancelled through the SAME channel a customer paid
//   through.
// What CAN delete an already-completed+paid request is the hero's
// "Delete Task" cleanup button and admin's test-data cleanup tools —
// both hard deletes with NO refund attached. Revoking an already-
// scratched coupon on THAT path would let routine cleanup silently
// take back a reward the customer has already been shown, for no
// financial reason. That's a worse outcome than leaving it, so this
// stays scoped to 'awaiting_gift'/'ready' only.
exports.revokeCouponOnServiceDeleted = functions.firestore
    .document('service_requests/{requestId}')
    .onDelete(async (snap, context) => {
    var _a;
    const requestId = context.params.requestId;
    const couponRef = db.collection('gift_coupons').doc(requestId);
    try {
        await db.runTransaction(async (tx) => {
            var _a;
            const couponSnap = await tx.get(couponRef);
            if (!couponSnap.exists)
                return;
            const status = (_a = couponSnap.data()) === null || _a === void 0 ? void 0 : _a.status;
            if (status !== 'awaiting_gift' && status !== 'ready') {
                firebase_functions_1.logger.info(`[revokeCouponOnServiceDeleted] coupon ${requestId} already in '${status}' — leaving it alone`);
                return;
            }
            tx.update(couponRef, {
                status: 'cancelled',
                cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
                cancelledReason: 'service request deleted',
            });
        });
    }
    catch (error) {
        firebase_functions_1.logger.error(`[revokeCouponOnServiceDeleted] revoke failed for ${requestId}:`, (_a = error === null || error === void 0 ? void 0 : error.message) !== null && _a !== void 0 ? _a : error);
    }
    return null;
});
// ================================================================
// 2. Arm coupons the admin never got to.
// ================================================================
//
// Runs daily. Anything still in 'awaiting_gift' past the grace period
// gets the default gift from system_settings/gift_coupon_defaults, so
// the customer always ends up with SOMETHING to scratch.
//
// Writes the gift to gift_coupon_gifts (the sealed envelope), exactly
// like an admin arming it by hand — the reveal path is unchanged.
exports.armStaleGiftCoupons = functions.pubsub
    .schedule('every 24 hours')
    .timeZone('Asia/Kolkata')
    .onRun(async () => {
    var _a, _b, _c;
    const cutoff = admin.firestore.Timestamp.fromMillis(Date.now() - STALE_AFTER_HOURS * 60 * 60 * 1000);
    let fallback = HARDCODED_FALLBACK;
    try {
        const settings = await db
            .collection('system_settings')
            .doc('gift_coupon_defaults')
            .get();
        const data = settings.data();
        if (data && typeof data.value === 'number') {
            fallback = {
                giftType: (_a = data.giftType) !== null && _a !== void 0 ? _a : 'discount',
                value: data.value,
                giftLabel: (_b = data.giftLabel) !== null && _b !== void 0 ? _b : '',
            };
        }
    }
    catch (error) {
        firebase_functions_1.logger.warn('[armStaleGiftCoupons] could not read defaults, using hardcoded:', (_c = error === null || error === void 0 ? void 0 : error.message) !== null && _c !== void 0 ? _c : error);
    }
    const stale = await db
        .collection('gift_coupons')
        .where('status', '==', 'awaiting_gift')
        .where('createdAt', '<=', cutoff)
        .limit(200)
        .get();
    if (stale.empty) {
        firebase_functions_1.logger.info('[armStaleGiftCoupons] nothing stale');
        return null;
    }
    // One batch per run; 200 coupons * 2 writes stays under the 500
    // write cap.
    const batch = db.batch();
    for (const doc of stale.docs) {
        batch.set(db.collection('gift_coupon_gifts').doc(doc.id), {
            ...fallback,
            setBy: 'system:armStaleGiftCoupons',
            setAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        batch.update(doc.ref, {
            status: 'ready',
            giftSetBy: 'system:armStaleGiftCoupons',
            giftSetAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
    await batch.commit();
    firebase_functions_1.logger.info(`[armStaleGiftCoupons] auto-armed ${stale.size} coupon(s)`);
    return null;
});
//# sourceMappingURL=giftCouponMaintenance.js.map