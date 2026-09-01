"use strict";
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
exports.notifyHeroOnPing = void 0;
const functions = __importStar(require("firebase-functions"));
const firebase_functions_1 = require("firebase-functions");
const admin = __importStar(require("firebase-admin"));
if (admin.apps.length === 0) {
    admin.initializeApp();
}
const db = admin.firestore();
exports.notifyHeroOnPing = functions.database
    .ref('/hero_pings/{heroId}/{requestId}')
    .onCreate(async (snapshot, context) => {
    var _a, _b;
    const heroId = context.params.heroId;
    const pingKey = context.params.requestId;
    const data = snapshot.val();
    if (!data) {
        return null;
    }
    try {
        const heroDoc = await db.collection('heroes').doc(heroId).get();
        const fcmToken = (_a = heroDoc.data()) === null || _a === void 0 ? void 0 : _a.fcmToken;
        if (!fcmToken || fcmToken.trim().length === 0) {
            firebase_functions_1.logger.info('[notifyHeroOnPing] No FCM token for hero (RTDB ping still delivered live-app-only):', heroId);
            return null;
        }
        // hero_home_screen.dart's ride-push handlers (_rideIdFromPush,
        // _fetchTargetedRideOnce) resolve against the Firestore `rides`
        // collection by doc id — dispatchRideToHero() deliberately keeps
        // that as a SEPARATE `firestoreDocId` field from the RTDB push
        // key (`requestId` here), since the two aren't guaranteed equal.
        // Prefer firestoreDocId; fall back to the RTDB key for the
        // (more common) broadcast path where they do coincide.
        const rideId = data.firestoreDocId ||
            data.requestId ||
            pingKey;
        const pickupAddress = data.pickupAddress || 'Pickup location';
        const dropAddress = data.dropAddress || 'Drop location';
        const estimatedFare = (_b = data.estimatedFare) !== null && _b !== void 0 ? _b : 0;
        const message = {
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
        firebase_functions_1.logger.info('[notifyHeroOnPing] FCM sent to hero', heroId, 'for ride ping', pingKey, '(rideId', rideId, ', drop:', dropAddress, ') messageId:', response);
        return null;
    }
    catch (error) {
        firebase_functions_1.logger.error('[notifyHeroOnPing] Failed to notify hero:', error);
        return null;
    }
});
//# sourceMappingURL=notifyHeroOnPing.js.map