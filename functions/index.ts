/**
 * Allin1 Super App - Phase 2 Cloud Functions
 * Entry Point
 */

export { affiliatePostbackWebhook } from './affiliatePostbackWebhook';
export { verifyAndProcessPayment } from './verifyAndProcessPayment';

// PhonePe Payment Gateway (0% commission UPI collection) — replaces
// trusting the client's own UPI intent result. createPhonePeOrder asks
// PhonePe for a checkout URL; phonepeWebhook is the ONLY thing allowed
// to mark a payment_orders doc 'paid' (server-to-server, checksum-
// verified); checkPhonePeOrderStatus is a belt-and-braces reconciliation
// call for when the app returns from checkout before the webhook lands.
export { createPhonePeOrder } from './phonepeCreateOrder';
export { phonepeWebhook } from './phonepeWebhook';
export { checkPhonePeOrderStatus } from './phonepeCheckStatus';
export { checkDeviceFingerprint } from './checkDeviceFingerprint';
// Gift Coupons (repair/replacement -> Hero/Hotel bill discount, per
// Nizam's request). Server-authoritative redemption — see
// redeemGiftCoupon.ts for why this can't be a client-side Firestore
// transaction for a discount that moves real money.
//
// onServiceRequestUpdated mints a locked coupon the moment ANY service
// is marked paid, and revokes an unspent one if the service is
// cancelled before payment — MERGED into one onUpdate trigger per CTO
// audit v2 (§8.2), since service_requests is the highest-write
// collection in the app and two separate onUpdate triggers on it meant
// double the invocations on every write. scratchGiftCoupon enforces
// the unlock timer against the SERVER clock and is the only thing that
// reveals the gift; redeemGiftCoupon spends a scratched discount on a
// bill.
export { onServiceRequestUpdated } from './onServiceRequestUpdated';
export { scratchGiftCoupon } from './scratchGiftCoupon';
export { redeemGiftCoupon } from './redeemGiftCoupon';
// CTO-audit lifecycle gaps: revoke a coupon whose service was deleted
// (the customer's own cancel path deletes the doc rather than setting
// a status, so this needs its own onDelete trigger — see
// giftCouponMaintenance.ts for why it isn't merged into the onUpdate
// trigger above), and auto-arm coupons an admin never got to so a
// customer is never stuck on "preparing your gift" forever.
export {
  revokeCouponOnServiceDeleted,
  armStaleGiftCoupons,
} from './giftCouponMaintenance';
// Brings the customer back into the app the moment their card is armed.
export { notifyCustomerOnCouponReady } from './notifyCustomerOnCouponReady';
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
