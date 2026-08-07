/**
 * ================================================================
 * Cloud Function: notifyAdminOnNewServiceRequest
 * Trigger: Firestore onCreate on service_requests/{requestId}
 * Purpose: Same WhatsApp-model closed-app alert as
 *          notifyAdminOnNewRide.ts, but for the Unified Hero Task
 *          System (hero_booking / custom_order / custom_food_order /
 *          grocery_order) — every ServiceRequestService.
 *          createServiceRequest() call writes exactly one doc here,
 *          so onCreate is reachable by construction for every request
 *          type without needing a per-category trigger.
 * ================================================================
 */

import * as functions from 'firebase-functions';
import { logger } from 'firebase-functions';
import * as admin from 'firebase-admin';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

export const notifyAdminOnNewServiceRequest = functions.firestore
  .document('service_requests/{requestId}')
  .onCreate(async (snap, context) => {
    const requestId = context.params.requestId;
    const data = snap.data();
    if (!data) {
      logger.warn('[notifyAdminOnNewServiceRequest] no data for request:', requestId);
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
        logger.warn('[notifyAdminOnNewServiceRequest] no admin FCM tokens registered');
        return null;
      }

      const requestType = (data.requestType as string) || 'service_request';
      const customerName = (data.customerName as string) || 'A customer';
      const details = (data.details as Record<string, unknown>) || {};
      const summary =
        (details.description as string) ||
        (details.itemsSummary as string) ||
        (details.notes as string) ||
        requestType;

      const message: admin.messaging.MulticastMessage = {
        tokens,
        data: {
          requestId,
          requestType,
          type: 'admin_new_service_request',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        notification: {
          title: `🛎️ New ${requestType.replace(/_/g, ' ')}`,
          body: `${customerName}: ${String(summary).substring(0, 60)}`,
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
        '[notifyAdminOnNewServiceRequest] sent',
        response.successCount,
        'of',
        tokens.length,
        'for request',
        requestId,
      );
      return null;
    } catch (error) {
      logger.error('[notifyAdminOnNewServiceRequest] failed:', error);
      return null;
    }
  });
