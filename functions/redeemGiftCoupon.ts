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
  /**
   * The service_requests doc being discounted. ALWAYS required.
   *
   * FIX (CTO audit — Weakness 1 + Weakness 2, HIGH): there used to be a
   * second mode where the Hotel checkout passed its own `orderAmount`
   * for an order that did not exist yet, and redeemed BEFORE creating
   * it. That had two problems: the amount was client-authored, and a
   * failure during order creation burned the coupon for nothing.
   *
   * Both are gone. The Hotel flow now creates its order first and
   * redeems against the resulting service_requests doc, exactly like
   * the Heroes bill flow — so the amount is always read from Firestore,
   * and a redemption failure leaves an un-burned coupon the customer
   * can still apply later at the bill screen.
   */
  requestId: string;
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
    if (!requestId || typeof requestId !== 'string') {
      throw new functions.https.HttpsError('invalid-argument', 'requestId is required');
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

        // The bill is ALWAYS read off the doc — never client-supplied.
        const requestRef = db.collection('service_requests').doc(requestId);
        const requestSnap = await tx.get(requestRef);
        if (!requestSnap.exists) {
          throw new Error('REQUEST_NOT_FOUND');
        }
        const request = requestSnap.data() as FirebaseFirestore.DocumentData;
        if (request.customerId !== uid) {
          throw new Error('NOT_OWNER');
        }

        // Where the amount lives depends on requestType, so check every
        // place this codebase writes one, most-authoritative first:
        //   finalAmount     — set by completeWithFinalAmount() (hero tasks)
        //   estimatedAmount — set by setEstimatedAmount()
        //   details.totalAmount — written at creation by the priced-cart
        //                     order types (custom_hotel_order,
        //                     catalog_food_order); this is the one the
        //                     Hotel flow relies on, since its order is
        //                     created before any hero has billed it.
        const details = (request.details ?? {}) as FirebaseFirestore.DocumentData;
        const candidates = [
          request.finalAmount,
          request.estimatedAmount,
          details.totalAmount,
          details.subtotal,
        ];
        const baseAmount =
          candidates.find((c) => typeof c === 'number' && c > 0) ?? 0;

        if (baseAmount <= 0) {
          throw new Error('NO_BILL_AMOUNT');
        }

        const discount = Math.min(value, baseAmount);
        const payableAmount = Math.max(baseAmount - discount, 0);

        tx.update(requestRef, { finalAmount: payableAmount });
        tx.update(couponRef, {
          status: 'redeemed',
          redeemedAt: admin.firestore.FieldValue.serverTimestamp(),
          redeemedOnRequestId: requestId,
          redeemedOnRequestType: request.requestType ?? null,
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
        case 'NO_BILL_AMOUNT':
          throw new functions.https.HttpsError('failed-precondition', 'This order has no bill amount to discount yet.');
        default:
          if (error instanceof functions.https.HttpsError) throw error;
          throw new functions.https.HttpsError('internal', 'Could not redeem this coupon. Please try again.');
      }
    }
  },
);
