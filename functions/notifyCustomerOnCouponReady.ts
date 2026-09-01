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

import * as functions from 'firebase-functions';
import { logger } from 'firebase-functions';
import * as admin from 'firebase-admin';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

export const notifyCustomerOnCouponReady = functions.firestore
  .document('gift_coupons/{couponId}')
  .onUpdate(async (change, context) => {
    const couponId = context.params.couponId as string;
    const before = change.before.data();
    const after = change.after.data();
    if (!before || !after) return null;

    if (before.status !== 'awaiting_gift' || after.status !== 'ready') {
      return null;
    }

    const customerId = after.customerId as string | undefined;
    if (!customerId) return null;

    try {
      const userDoc = await db.collection('users').doc(customerId).get();
      const fcmToken = userDoc.data()?.fcmToken as string | undefined;
      if (!fcmToken || fcmToken.trim().length === 0) {
        logger.info(
          `[notifyCustomerOnCouponReady] no FCM token for customer ${customerId} — card still waiting in Rewards`,
        );
        return null;
      }

      // If the card is still on a timer, say so rather than telling
      // them to scratch something that won't open yet.
      const unlockAt = after.unlockAt as admin.firestore.Timestamp | undefined;
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

      logger.info(`[notifyCustomerOnCouponReady] notified customer ${customerId} for coupon ${couponId}`);
    } catch (error: any) {
      // Never let a failed push break the arming flow — the coupon is
      // already 'ready' and will be found in Rewards regardless.
      logger.error(
        `[notifyCustomerOnCouponReady] send failed for ${couponId}:`,
        error?.message ?? error,
      );
    }

    return null;
  });
