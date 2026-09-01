/**
 * ================================================================
 * Cloud Function: notifyHeroOnPing
 * Trigger: RTDB onCreate on hero_pings/{heroId}/{requestId}
 * Purpose: FCM Data Push Layer 2 (CTO mandate) — every existing
 *          bike-taxi ride dispatch path (customer self-booking
 *          broadcast in ride_search_screen.dart, admin/call-center
 *          pre-assignment in admin_ride_dispatch_service.dart) already
 *          writes this exact RTDB node as its Layer-1 "wake the hero"
 *          mechanism. That only reaches a hero whose app process is
 *          still alive (foreground or backgrounded-but-not-killed) —
 *          this trigger adds the FCM send for a fully killed app,
 *          without requiring any of those dispatch call sites to
 *          change: they all already write the one node this listens
 *          on.
 * ================================================================
 */

import * as functions from 'firebase-functions';
import { logger } from 'firebase-functions';
import * as admin from 'firebase-admin';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

export const notifyHeroOnPing = functions.database
  .ref('/hero_pings/{heroId}/{requestId}')
  .onCreate(async (snapshot, context) => {
    const heroId = context.params.heroId as string;
    const pingKey = context.params.requestId as string;
    const data = snapshot.val() as Record<string, unknown> | null;
    if (!data) {
      return null;
    }

    try {
      const heroDoc = await db.collection('heroes').doc(heroId).get();
      const fcmToken = heroDoc.data()?.fcmToken as string | undefined;
      if (!fcmToken || fcmToken.trim().length === 0) {
        logger.info(
          '[notifyHeroOnPing] No FCM token for hero (RTDB ping still delivered live-app-only):',
          heroId,
        );
        return null;
      }

      // hero_home_screen.dart's ride-push handlers (_rideIdFromPush,
      // _fetchTargetedRideOnce) resolve against the Firestore `rides`
      // collection by doc id — dispatchRideToHero() deliberately keeps
      // that as a SEPARATE `firestoreDocId` field from the RTDB push
      // key (`requestId` here), since the two aren't guaranteed equal.
      // Prefer firestoreDocId; fall back to the RTDB key for the
      // (more common) broadcast path where they do coincide.
      const rideId =
        (data.firestoreDocId as string | undefined) ||
        (data.requestId as string | undefined) ||
        pingKey;

      const pickupAddress =
        (data.pickupAddress as string | undefined) || 'Pickup location';
      const dropAddress =
        (data.dropAddress as string | undefined) || 'Drop location';
      const estimatedFare = data.estimatedFare ?? 0;

      const message: admin.messaging.Message = {
        token: fcmToken,
        data: {
          rideId,
          ride_id: rideId,
          rideDocId: rideId,
          ride_doc_id: rideId,
          type: 'new_ride_ping',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        notification: {
          title: '🏍️ New Ride Request!',
          body: `Pickup: ${String(pickupAddress).substring(0, 40)} • ₹${estimatedFare}`,
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
          headers: { 'apns-priority': '10' },
          payload: {
            aps: { sound: 'default', badge: 1, contentAvailable: true },
          },
        },
      };

      const response = await admin.messaging().send(message);
      logger.info(
        '[notifyHeroOnPing] FCM sent to hero',
        heroId,
        'for ride ping',
        pingKey,
        '(rideId',
        rideId,
        ', drop:',
        dropAddress,
        ') messageId:',
        response,
      );
      return null;
    } catch (error) {
      logger.error('[notifyHeroOnPing] Failed to notify hero:', error);
      return null;
    }
  });
