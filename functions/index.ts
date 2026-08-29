/**
 * Allin1 Super App - Phase 2 Cloud Functions
 * Entry Point
 */

export { affiliatePostbackWebhook } from './affiliatePostbackWebhook';
export { verifyAndProcessPayment } from './verifyAndProcessPayment';
export { checkDeviceFingerprint } from './checkDeviceFingerprint';
export { manageHeroApproval } from './manageHeroApproval';
export { notifyHeroOnRideAssigned } from './notifyHeroOnRideAssigned';
// FCM Data Push Layer 2 (CTO mandate). Unlike notifyHeroOnRideAssigned
// above (a Firestore `rides` onUpdate trigger keyed off `targeted_hero_id`
// — a field nothing in the app actually writes, confirmed dead in
// practice), these two trigger off the RTDB `hero_pings`/
// `hero_service_pings` writes every existing dispatch path already
// makes, so they're reachable by construction rather than requiring a
// specific write shape no caller produces.
export { notifyHeroOnPing } from './notifyHeroOnPing';
export { notifyHeroOnServicePing } from './notifyHeroOnServicePing';

// NEW (per Nizam's request — Admin app "WhatsApp model" closed-app
// alerts): mirrors notifyHeroOnRideAssigned's send pattern, but fans
// out to every doc in admins/ instead of one hero, triggered on
// creation of rides/service_requests (always happens exactly once per
// booking, unlike the deprecated targeted_hero_id onUpdate path).
export { notifyAdminOnNewRide } from './notifyAdminOnNewRide';
export { notifyAdminOnNewServiceRequest } from './notifyAdminOnNewServiceRequest';

// NOTE: seller order alerts (Issue 2 fix) deliberately do NOT use a
// Cloud Function — zero-cost infra constraint (no Blaze plan). See
// lib/main_seller.dart's _initSellerPingListener and
// ServiceRequestService.createServiceRequest's seller_pings/ RTDB write
// for the client-side-only replacement.
