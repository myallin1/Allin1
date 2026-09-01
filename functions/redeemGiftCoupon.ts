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

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

interface RedeemGiftCouponRequest {
  couponId: string;
  // Case A — Heroes bill: an EXISTING service_requests doc whose
  // finalAmount/estimatedAmount is the authoritative bill amount. The
  // function reads that amount itself; it never trusts a client-passed
  // number for this case.
  requestId?: string;
  // Case B — Hotel checkout: the order doesn't exist yet (it's created
  // right after this call succeeds, using the returned payableAmount),
  // so there is no Firestore doc to read the bill amount from. The
  // client's own cart subtotal is passed as orderAmount — this is the
  // SAME trust level the app already gives the client for the
  // undiscounted order total (custom_hotel_view_screen.dart has always
  // written its own computed totalAmount when creating an order; this
  // does not weaken that).
  orderAmount?: number;
  requestType?: string;
}

interface RedeemGiftCouponResponse {
  success: true;
  discount: number;
  payableAmount: number;
}

export const redeemGiftCoupon = functions.https.onCall(
  async (
    data: RedeemGiftCouponRequest,
    context: functions.https.CallableContext,
  ): Promise<RedeemGiftCouponResponse> => {
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
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Either requestId (existing bill) or orderAmount (new order) is required',
      );
    }
    if (orderAmount !== undefined && (typeof orderAmount !== 'number' || orderAmount < 0)) {
      throw new functions.https.HttpsError('invalid-argument', 'orderAmount must be a non-negative number');
    }

    try {
      return await db.runTransaction<RedeemGiftCouponResponse>(async (tx) => {
        const couponRef = db.collection('gift_coupons').doc(couponId);
        const couponSnap = await tx.get(couponRef);

        if (!couponSnap.exists) {
          throw new Error('COUPON_NOT_FOUND');
        }
        const coupon = couponSnap.data()!;

        // Ownership — a customer can only redeem their OWN coupon.
        if (coupon.customerId !== uid) {
          throw new Error('NOT_OWNER');
        }
        // Only a card the customer has actually scratched open can be
        // spent — 'awaiting_gift'/'ready' means they haven't seen the
        // gift yet, and anything past 'scratched' is already spent.
        if (coupon.status !== 'scratched') {
          throw new Error(
            coupon.status === 'awaiting_gift' || coupon.status === 'ready'
              ? 'NOT_SCRATCHED'
              : 'ALREADY_REDEEMED',
          );
        }
        // An 'item' gift is collected offline, not applied to a bill.
        if (coupon.giftType !== 'discount') {
          throw new Error('NOT_A_DISCOUNT');
        }
        const expiresAt: admin.firestore.Timestamp | undefined = coupon.expiresAt;
        if (expiresAt && expiresAt.toDate() < new Date()) {
          throw new Error('EXPIRED');
        }
        const value: number = typeof coupon.value === 'number' ? coupon.value : 0;

        let baseAmount: number;
        let requestRef: admin.firestore.DocumentReference | null = null;
        let resolvedRequestType = data.requestType ?? null;

        if (requestId) {
          // Case A — Heroes bill: read the REAL bill off the doc, never
          // trust a client-passed amount here.
          requestRef = db.collection('service_requests').doc(requestId);
          const requestSnap = await tx.get(requestRef);
          if (!requestSnap.exists) {
            throw new Error('REQUEST_NOT_FOUND');
          }
          const request = requestSnap.data()!;
          if (request.customerId !== uid) {
            throw new Error('NOT_OWNER');
          }
          baseAmount =
            (typeof request.finalAmount === 'number' && request.finalAmount) ||
            (typeof request.estimatedAmount === 'number' && request.estimatedAmount) ||
            0;
          resolvedRequestType = request.requestType ?? resolvedRequestType;
        } else {
          // Case B — Hotel checkout: no bill doc exists yet.
          baseAmount = orderAmount as number;
        }

        const discount = Math.min(value, baseAmount);
        const payableAmount = Math.max(baseAmount - discount, 0);

        if (requestRef) {
          tx.update(requestRef, { finalAmount: payableAmount });
        }
        tx.update(couponRef, {
          status: 'redeemed',
          redeemedAt: admin.firestore.FieldValue.serverTimestamp(),
          redeemedOnRequestId: requestId ?? null,
          redeemedOnRequestType: resolvedRequestType,
        });

        return { success: true, discount, payableAmount };
      });
    } catch (error: any) {
      functions.logger.error(`redeemGiftCoupon failed for coupon ${couponId}, user ${uid}:`, error?.message ?? error);

      switch (error?.message) {
        case 'COUPON_NOT_FOUND':
          throw new functions.https.HttpsError('not-found', 'This coupon does not exist.');
        case 'NOT_OWNER':
          throw new functions.https.HttpsError('permission-denied', 'This coupon does not belong to you.');
        case 'ALREADY_REDEEMED':
          throw new functions.https.HttpsError('failed-precondition', 'This coupon has already been used.');
        case 'NOT_SCRATCHED':
          throw new functions.https.HttpsError('failed-precondition', 'Scratch this card open in Rewards first.');
        case 'NOT_A_DISCOUNT':
          throw new functions.https.HttpsError('failed-precondition', 'This gift is collected in person, not applied to a bill.');
        case 'EXPIRED':
          throw new functions.https.HttpsError('failed-precondition', 'This coupon has expired.');
        case 'REQUEST_NOT_FOUND':
          throw new functions.https.HttpsError('not-found', 'The bill for this order could not be found.');
        default:
          if (error instanceof functions.https.HttpsError) throw error;
          throw new functions.https.HttpsError('internal', 'Could not redeem this coupon. Please try again.');
      }
    }
  },
);
