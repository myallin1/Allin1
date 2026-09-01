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

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

interface ScratchGiftCouponRequest {
  couponId: string;
}

interface ScratchGiftCouponResponse {
  success: true;
  giftType: string;
  value: number;
  giftLabel: string;
  giftDescription: string;
}

export const scratchGiftCoupon = functions.https.onCall(
  async (
    data: ScratchGiftCouponRequest,
    context: functions.https.CallableContext,
  ): Promise<ScratchGiftCouponResponse> => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be logged in');
    }
    const uid = context.auth.uid;

    const couponId = data?.couponId;
    if (!couponId || typeof couponId !== 'string') {
      throw new functions.https.HttpsError('invalid-argument', 'couponId is required');
    }

    try {
      return await db.runTransaction<ScratchGiftCouponResponse>(async (tx) => {
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
        const coupon = snap.data() as FirebaseFirestore.DocumentData;

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

        const expiresAt = coupon.expiresAt as admin.firestore.Timestamp | undefined;
        if (expiresAt && expiresAt.toMillis() < Date.now()) {
          throw new Error('EXPIRED');
        }

        // THE server-clock check the client cannot fake.
        const unlockAt = coupon.unlockAt as admin.firestore.Timestamp | undefined;
        if (unlockAt && unlockAt.toMillis() > Date.now()) {
          throw new Error('STILL_LOCKED');
        }

        // Open the envelope. A 'ready' coupon with no gift doc means an
        // admin armed it and the gift write was lost — surface that as
        // "not ready" rather than revealing an empty card.
        if (!giftSnap.exists) {
          throw new Error('NOT_READY');
        }
        const gift = giftSnap.data() as FirebaseFirestore.DocumentData;
        const giftType = (gift.giftType as string) ?? '';
        const value = typeof gift.value === 'number' ? gift.value : 0;
        const giftLabel = (gift.giftLabel as string) ?? '';

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
          giftDescription:
            giftType === 'discount' ? `₹${Math.round(value)} OFF` : giftLabel,
        };
      });
    } catch (error: any) {
      if (error instanceof functions.https.HttpsError) throw error;
      functions.logger.error(`scratchGiftCoupon failed for ${couponId}, user ${uid}:`, error?.message ?? error);

      switch (error?.message) {
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
  },
);
