"use strict";
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
exports.notifyAdminOnNewServiceRequest = void 0;
const functions = __importStar(require("firebase-functions"));
const firebase_functions_1 = require("firebase-functions");
const admin = __importStar(require("firebase-admin"));
if (admin.apps.length === 0) {
    admin.initializeApp();
}
const db = admin.firestore();
exports.notifyAdminOnNewServiceRequest = functions.firestore
    .document('service_requests/{requestId}')
    .onCreate(async (snap, context) => {
    const requestId = context.params.requestId;
    const data = snap.data();
    if (!data) {
        firebase_functions_1.logger.warn('[notifyAdminOnNewServiceRequest] no data for request:', requestId);
        return null;
    }
    try {
        const adminsSnap = await db.collection('admins').get();
        const tokens = [];
        adminsSnap.forEach((doc) => {
            const t = doc.data().fcmToken;
            if (t && t.trim().length > 0)
                tokens.push(t);
        });
        if (tokens.length === 0) {
            firebase_functions_1.logger.warn('[notifyAdminOnNewServiceRequest] no admin FCM tokens registered');
            return null;
        }
        const requestType = data.requestType || 'service_request';
        const customerName = data.customerName || 'A customer';
        const details = data.details || {};
        const summary = details.description ||
            details.itemsSummary ||
            details.notes ||
            requestType;
        const message = {
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
        firebase_functions_1.logger.info('[notifyAdminOnNewServiceRequest] sent', response.successCount, 'of', tokens.length, 'for request', requestId);
        return null;
    }
    catch (error) {
        firebase_functions_1.logger.error('[notifyAdminOnNewServiceRequest] failed:', error);
        return null;
    }
});
//# sourceMappingURL=notifyAdminOnNewServiceRequest.js.map