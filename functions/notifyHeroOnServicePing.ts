/**
 * ================================================================
 * Cloud Function: notifyHeroOnServicePing
 * Trigger: RTDB onCreate on hero_service_pings/{heroId}/{requestId}
 * Purpose: FCM Data Push Layer 2 (CTO mandate) — the generic
 *          service_requests dispatch pipeline's Layer-1 mechanism
 *          (hero_booking / custom_food_order / grocery_order / etc.).
 *          Every dispatch path that assigns a hero to a service
 *          request writes this exact RTDB node: the broadcast path in
 *          service_request_service.dart's _broadcastToEligibleHeroes(),
 *          AND the admin-manual assignment path (adminAssignHero(),
 *          called from AssignHeroSheet) — which previously wrote NO
 *          ping at all until this same change added one (see the
 *          adminAssignHero() doc comment). Both are now covered by
 *          this single trigger with zero per-call-site FCM code.
 * ================================================================
 */

import * as functions from 'firebase-functions';
import { logger } from 'firebase-functions';
import * as admin from 'firebase-admin';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

export const notifyHeroOnServicePing = functions.database
  .ref('/hero_service_pings/{heroId}/{requestId}')
  .onCreate(async (snapshot, context) => {
    const heroId = context.params.heroId as string;
    const requestId = context.params.requestId as string;
    const data = snapshot.val() as Record<string, unknown> | null;
    if (!data) {
      return null;
    }

    try {
      const heroDoc = await db.collection('heroes').doc(heroId).get();
      const fcmToken = heroDoc.data()?.fcmToken as string | undefined;
      if (!fcmToken || fcmToken.trim().length === 0) {
        logger.info(
          '[notifyHeroOnServicePing] No FCM token for hero (RTDB ping still delivered live-app-only):',
          heroId,
        );
        return null;
      }

      // Unlike hero_pings (bike-taxi), the RTDB key here IS the
      // Firestore `service_requests` doc id directly — no separate
      // firestoreDocId field, confirmed against
      // service_request_service.dart's acceptServiceRequest()/
      // adminAssignHero(), both of which use `requestId` consistently
      // as both the RTDB key and the Firestore doc id.
      const requestType = (data.requestType as string | undefined) || 'service_request';
      const customerName = (data.customerName as string | undefined) || 'a customer';

      const message: admin.messaging.Message = {
        token: fcmToken,
        data: {
          requestId,
          request_id: requestId,
          requestType,
          type: 'new_service_request',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        notification: {
          title: '📋 New Service Request!',
          body: `${_humanizeRequestType(requestType)} for ${customerName}`,
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
        '[notifyHeroOnServicePing] FCM sent to hero',
        heroId,
        'for service request',
        requestId,
        'messageId:',
        response,
      );
      return null;
    } catch (error) {
      logger.error('[notifyHeroOnServicePing] Failed to notify hero:', error);
      return null;
    }
  });

function _humanizeRequestType(requestType: string): string {
  switch (requestType) {
    case 'hero_booking':
      return 'New Hero Booking';
    case 'custom_food_order':
    case 'catalog_food_order':
      return 'New Food Order';
    case 'grocery_order':
      return 'New Grocery Order';
    case 'custom_hotel_order':
      return 'New Hotel Order';
    case 'electronics_service':
      return 'New Electronics Service Request';
    default:
      return 'New Service Request';
  }
}
