/**
 * ================================================================
 * Cloud Function: notifyHeroOnRideAssigned
 * Trigger: Firestore onUpdate on rides/{rideId}
 * Purpose: Send FCM push notification to the targeted Hero
 *          when a ride is assigned to them by the matching engine.
 * ================================================================
 */

import * as functions from 'firebase-functions';
import { logger } from 'firebase-functions';
import * as admin from 'firebase-admin';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

export const notifyHeroOnRideAssigned = functions.firestore
  .document('rides/{rideId}')
  .onUpdate(async (change, context) => {
    const beforeData = change.before.data();
    const afterData = change.after.data();
    const rideId = context.params.rideId;

    if (!afterData) {
      logger.warn('[notifyHeroOnRideAssigned] afterData is null for ride:', rideId);
      return null;
    }

    const beforeStatus = beforeData?.status as string | undefined;
    const afterStatus = afterData.status as string | undefined;

    if (afterStatus !== 'assigned') {
      return null;
    }

    if (beforeStatus === 'assigned') {
      return null;
    }

    const targetedHeroId = afterData.targeted_hero_id as string | undefined;
    if (!targetedHeroId || targetedHeroId.trim().length === 0) {
      logger.warn(
        '[notifyHeroOnRideAssigned] Ride assigned but no targeted_hero_id:',
        rideId,
      );
      return null;
    }

    try {
      const heroDoc = await db.collection('heroes').doc(targetedHeroId).get();
      if (!heroDoc.exists) {
        logger.warn(
          '[notifyHeroOnRideAssigned] Hero document not found:',
          targetedHeroId,
        );
        return null;
      }

      const heroData = heroDoc.data();
      if (!heroData) {
        logger.warn(
          '[notifyHeroOnRideAssigned] Hero data is null for:',
          targetedHeroId,
        );
        return null;
      }

      const fcmToken = heroData.fcmToken as string | undefined;
      if (!fcmToken || fcmToken.trim().length === 0) {
        logger.warn(
          '[notifyHeroOnRideAssigned] Hero has no FCM token:',
          targetedHeroId,
        );
        return null;
      }

      const pickupAddress =
        (afterData.pickupAddress as string) ||
        (afterData.pickup as string) ||
        'Pickup location';
      const dropAddress =
        (afterData.dropAddress as string) ||
        (afterData.drop as string) ||
        'Drop location';
      const estimatedFare = afterData.estimatedFare ?? afterData.fare ?? 0;
      const distanceKm = afterData.distanceKm ?? '?';
      const heroScore = afterData.heroScore ?? afterData.heroDistanceToPickup ?? '?';

      const message: admin.messaging.Message = {
        token: fcmToken,
        data: {
          rideId: rideId,
          rideDocId: rideId,
          ride_id: rideId,
          ride_doc_id: rideId,
          pickupAddress: String(pickupAddress),
          dropAddress: String(dropAddress),
          estimatedFare: String(estimatedFare),
          distanceKm: String(distanceKm),
          heroScore: String(heroScore),
          type: 'new_ride_assigned',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        notification: {
          title: '🏍️ New Ride Assigned!',
          body:
            `Pickup: ${String(pickupAddress).substring(0, 40)}` +
            ` • ₹${estimatedFare}`,
        },
        android: {
          priority: 'high',
          notification: {
            channelId: 'hero_ride_alerts_v4',
            priority: 'max',
            sound: 'default',
            defaultSound: true,
            visibility: 'public',
          },
        },
        apns: {
          headers: {
            'apns-priority': '10',
          },
          payload: {
            aps: {
              sound: 'default',
              badge: 1,
              contentAvailable: true,
            },
          },
        },
      };

      const response = await admin.messaging().send(message);
      logger.info(
        '[notifyHeroOnRideAssigned] FCM sent to hero',
        targetedHeroId,
        'for ride',
        rideId,
        'messageId:',
        response,
      );

      return null;
    } catch (error) {
      logger.error(
        '[notifyHeroOnRideAssigned] Failed to notify hero:',
        error,
      );
      return null;
    }
  });