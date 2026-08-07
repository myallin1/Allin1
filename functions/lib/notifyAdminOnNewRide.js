"use strict";
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
exports.notifyAdminOnNewRide = void 0;
const functions = __importStar(require("firebase-functions"));
const firebase_functions_1 = require("firebase-functions");
const admin = __importStar(require("firebase-admin"));
if (admin.apps.length === 0) {
    admin.initializeApp();
}
const db = admin.firestore();
exports.notifyAdminOnNewRide = functions.firestore
    .document('rides/{rideId}')
    .onCreate(async (snap, context) => {
    var _a, _b, _c;
    const rideId = context.params.rideId;
    const data = snap.data();
    if (!data) {
        firebase_functions_1.logger.warn('[notifyAdminOnNewRide] no data for ride:', rideId);
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
            firebase_functions_1.logger.warn('[notifyAdminOnNewRide] no admin FCM tokens registered');
            return null;
        }
        const pickupAddress = data.pickupAddress || data.pickup || 'Pickup location';
        const dropAddress = data.dropAddress || data.drop || 'Drop location';
        const estimatedFare = (_b = (_a = data.estimatedFare) !== null && _a !== void 0 ? _a : data.fare) !== null && _b !== void 0 ? _b : 0;
        const vehicleType = (_c = data.vehicleType) !== null && _c !== void 0 ? _c : 'ride';
        const message = {
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
        firebase_functions_1.logger.info('[notifyAdminOnNewRide] sent', response.successCount, 'of', tokens.length, 'for ride', rideId);
        return null;
    }
    catch (error) {
        firebase_functions_1.logger.error('[notifyAdminOnNewRide] failed:', error);
        return null;
    }
});
//# sourceMappingURL=notifyAdminOnNewRide.js.map