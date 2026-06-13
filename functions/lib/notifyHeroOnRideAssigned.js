"use strict";
/**
 * ================================================================
 * Cloud Function: notifyHeroOnRideAssigned
 * Trigger: Firestore onUpdate on rides/{rideId}
 * Purpose: Send FCM push notification to the targeted Hero
 *          when a ride is assigned to them by the matching engine.
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
exports.notifyHeroOnRideAssigned = void 0;
const functions = __importStar(require("firebase-functions"));
const firebase_functions_1 = require("firebase-functions");
const admin = __importStar(require("firebase-admin"));
if (admin.apps.length === 0) {
    admin.initializeApp();
}
const db = admin.firestore();
exports.notifyHeroOnRideAssigned = functions.firestore
    .document('rides/{rideId}')
    .onUpdate(async (change, context) => {
    var _a, _b, _c, _d, _e;
    const beforeData = change.before.data();
    const afterData = change.after.data();
    const rideId = context.params.rideId;
    if (!afterData) {
        firebase_functions_1.logger.warn('[notifyHeroOnRideAssigned] afterData is null for ride:', rideId);
        return null;
    }
    const beforeStatus = beforeData === null || beforeData === void 0 ? void 0 : beforeData.status;
    const afterStatus = afterData.status;
    if (afterStatus !== 'assigned') {
        return null;
    }
    if (beforeStatus === 'assigned') {
        return null;
    }
    const targetedHeroId = afterData.targeted_hero_id;
    if (!targetedHeroId || targetedHeroId.trim().length === 0) {
        firebase_functions_1.logger.warn('[notifyHeroOnRideAssigned] Ride assigned but no targeted_hero_id:', rideId);
        return null;
    }
    try {
        const heroDoc = await db.collection('heroes').doc(targetedHeroId).get();
        if (!heroDoc.exists) {
            firebase_functions_1.logger.warn('[notifyHeroOnRideAssigned] Hero document not found:', targetedHeroId);
            return null;
        }
        const heroData = heroDoc.data();
        if (!heroData) {
            firebase_functions_1.logger.warn('[notifyHeroOnRideAssigned] Hero data is null for:', targetedHeroId);
            return null;
        }
        const fcmToken = heroData.fcmToken;
        if (!fcmToken || fcmToken.trim().length === 0) {
            firebase_functions_1.logger.warn('[notifyHeroOnRideAssigned] Hero has no FCM token:', targetedHeroId);
            return null;
        }
        const pickupAddress = afterData.pickupAddress ||
            afterData.pickup ||
            'Pickup location';
        const dropAddress = afterData.dropAddress ||
            afterData.drop ||
            'Drop location';
        const estimatedFare = (_b = (_a = afterData.estimatedFare) !== null && _a !== void 0 ? _a : afterData.fare) !== null && _b !== void 0 ? _b : 0;
        const distanceKm = (_c = afterData.distanceKm) !== null && _c !== void 0 ? _c : '?';
        const heroScore = (_e = (_d = afterData.heroScore) !== null && _d !== void 0 ? _d : afterData.heroDistanceToPickup) !== null && _e !== void 0 ? _e : '?';
        const message = {
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
                body: `Pickup: ${String(pickupAddress).substring(0, 40)}` +
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
        firebase_functions_1.logger.info('[notifyHeroOnRideAssigned] FCM sent to hero', targetedHeroId, 'for ride', rideId, 'messageId:', response);
        return null;
    }
    catch (error) {
        firebase_functions_1.logger.error('[notifyHeroOnRideAssigned] Failed to notify hero:', error);
        return null;
    }
});
//# sourceMappingURL=notifyHeroOnRideAssigned.js.map