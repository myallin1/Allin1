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
