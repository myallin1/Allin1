/**
 * ================================================================
 * Cloud Function: notifyAdminOnNewRide
 * Trigger: Firestore onCreate on rides/{rideId}
 * Purpose: WhatsApp-model closed-app push — send an FCM alert to
 *          every registered admin device the instant a customer
 *          creates a new taxi ride booking, so the Admin app can show
 *          a lock-screen notification even fully closed/backgrounded.
 * ================================================================
 * Mirrors notifyHeroOnRideAssigned.ts's structure exactly, but fans
 * out to every doc in `admins/` (an admin app can be installed on
 * more than one phone) instead of a single targeted hero. onCreate is
 * used (not onUpdate) because ride creation always happens exactly
 * once per booking, unlike the deprecated targeted_hero_id field on
 * the onUpdate trigger above — this is reachable by construction.
 */

import * as functions from 'firebase-functions';
import { logger } from 'firebase-functions';
import * as admin from 'firebase-admin';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

export const notifyAdminOnNewRide = functions.firestore
  .document('rides/{rideId}')
  .onCreate(async (snap, context) => {
    const rideId = context.params.rideId;
    const data = snap.data();
    if (!data) {
      logger.warn('[notifyAdminOnNewRide] no data for ride:', rideId);
      return null;
    }

    try {
      const adminsSnap = await db.collection('admins').get();
      const tokens: string[] = [];
      adminsSnap.forEach((doc) => {
        const t = doc.data().fcmToken as string | undefined;
        if (t && t.trim().length > 0) tokens.push(t);
      });

      if (tokens.length === 0) {
        logger.warn('[notifyAdminOnNewRide] no admin FCM tokens registered');
        return null;
      }

      const pickupAddress =
        (data.pickupAddress as string) || (data.pickup as string) || 'Pickup location';
      const dropAddress =
        (data.dropAddress as string) || (data.drop as string) || 'Drop location';
      const estimatedFare = data.estimatedFare ?? data.fare ?? 0;
      const vehicleType = data.vehicleType ?? 'ride';

      const message: admin.messaging.MulticastMessage = {
        tokens,
        data: {
          rideId,
          type: 'admin_new_ride',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
          pickupAddress: String(pickupAddress),
          dropAddress: String(dropAddress),
          estimatedFare: String(estimatedFare),
          vehicleType: String(vehicleType),
        },
        notification: {
          title: `🚕 New ${String(vehicleType)} booking`,
          body: `${String(pickupAddress).substring(0, 40)} → ${String(dropAddress).substring(0, 40)}`,
        },
        android: {
          priority: 'high',
          notification: {
            channelId: 'admin_alerts_v1',
            priority: 'max',
            sound: 'default',
            defaultSound: true,
            visibility: 'public',
          },
        },
        apns: {
          headers: { 'apns-priority': '10' },
          payload: { aps: { sound: 'default', badge: 1, contentAvailable: true } },
        },
      };

      const response = await admin.messaging().sendEachForMulticast(message);
      logger.info(
        '[notifyAdminOnNewRide] sent',
        response.successCount,
        'of',
        tokens.length,
        'for ride',
        rideId,
      );
      return null;
    } catch (error) {
      logger.error('[notifyAdminOnNewRide] failed:', error);
      return null;
    }
  });
