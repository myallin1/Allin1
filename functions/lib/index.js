"use strict";
/**
 * Allin1 Super App - Phase 2 Cloud Functions
 * Entry Point
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.notifyAdminOnNewServiceRequest = exports.notifyAdminOnNewRide = exports.notifyHeroOnServicePing = exports.notifyHeroOnPing = exports.notifyHeroOnRideAssigned = exports.manageHeroApproval = exports.notifyCustomerOnCouponReady = exports.armStaleGiftCoupons = exports.revokeCouponOnServiceDeleted = exports.redeemGiftCoupon = exports.scratchGiftCoupon = exports.onServiceRequestUpdated = exports.checkDeviceFingerprint = exports.checkPhonePeOrderStatus = exports.phonepeWebhook = exports.createPhonePeOrder = exports.verifyAndProcessPayment = exports.affiliatePostbackWebhook = void 0;
var affiliatePostbackWebhook_1 = require("./affiliatePostbackWebhook");
Object.defineProperty(exports, "affiliatePostbackWebhook", { enumerable: true, get: function () { return affiliatePostbackWebhook_1.affiliatePostbackWebhook; } });
var verifyAndProcessPayment_1 = require("./verifyAndProcessPayment");
Object.defineProperty(exports, "verifyAndProcessPayment", { enumerable: true, get: function () { return verifyAndProcessPayment_1.verifyAndProcessPayment; } });
// PhonePe Payment Gateway (0% commission UPI collection) — replaces
// trusting the client's own UPI intent result. createPhonePeOrder asks
// PhonePe for a checkout URL; phonepeWebhook is the ONLY thing allowed
// to mark a payment_orders doc 'paid' (server-to-server, checksum-
// verified); checkPhonePeOrderStatus is a belt-and-braces reconciliation
// call for when the app returns from checkout before the webhook lands.
var phonepeCreateOrder_1 = require("./phonepeCreateOrder");
Object.defineProperty(exports, "createPhonePeOrder", { enumerable: true, get: function () { return phonepeCreateOrder_1.createPhonePeOrder; } });
var phonepeWebhook_1 = require("./phonepeWebhook");
Object.defineProperty(exports, "phonepeWebhook", { enumerable: true, get: function () { return phonepeWebhook_1.phonepeWebhook; } });
var phonepeCheckStatus_1 = require("./phonepeCheckStatus");
Object.defineProperty(exports, "checkPhonePeOrderStatus", { enumerable: true, get: function () { return phonepeCheckStatus_1.checkPhonePeOrderStatus; } });
var checkDeviceFingerprint_1 = require("./checkDeviceFingerprint");
Object.defineProperty(exports, "checkDeviceFingerprint", { enumerable: true, get: function () { return checkDeviceFingerprint_1.checkDeviceFingerprint; } });
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
var onServiceRequestUpdated_1 = require("./onServiceRequestUpdated");
Object.defineProperty(exports, "onServiceRequestUpdated", { enumerable: true, get: function () { return onServiceRequestUpdated_1.onServiceRequestUpdated; } });
var scratchGiftCoupon_1 = require("./scratchGiftCoupon");
Object.defineProperty(exports, "scratchGiftCoupon", { enumerable: true, get: function () { return scratchGiftCoupon_1.scratchGiftCoupon; } });
var redeemGiftCoupon_1 = require("./redeemGiftCoupon");
Object.defineProperty(exports, "redeemGiftCoupon", { enumerable: true, get: function () { return redeemGiftCoupon_1.redeemGiftCoupon; } });
// CTO-audit lifecycle gaps: revoke a coupon whose service was deleted
// (the customer's own cancel path deletes the doc rather than setting
// a status, so this needs its own onDelete trigger — see
// giftCouponMaintenance.ts for why it isn't merged into the onUpdate
// trigger above), and auto-arm coupons an admin never got to so a
// customer is never stuck on "preparing your gift" forever.
var giftCouponMaintenance_1 = require("./giftCouponMaintenance");
Object.defineProperty(exports, "revokeCouponOnServiceDeleted", { enumerable: true, get: function () { return giftCouponMaintenance_1.revokeCouponOnServiceDeleted; } });
Object.defineProperty(exports, "armStaleGiftCoupons", { enumerable: true, get: function () { return giftCouponMaintenance_1.armStaleGiftCoupons; } });
// Brings the customer back into the app the moment their card is armed.
var notifyCustomerOnCouponReady_1 = require("./notifyCustomerOnCouponReady");
Object.defineProperty(exports, "notifyCustomerOnCouponReady", { enumerable: true, get: function () { return notifyCustomerOnCouponReady_1.notifyCustomerOnCouponReady; } });
var manageHeroApproval_1 = require("./manageHeroApproval");
Object.defineProperty(exports, "manageHeroApproval", { enumerable: true, get: function () { return manageHeroApproval_1.manageHeroApproval; } });
var notifyHeroOnRideAssigned_1 = require("./notifyHeroOnRideAssigned");
Object.defineProperty(exports, "notifyHeroOnRideAssigned", { enumerable: true, get: function () { return notifyHeroOnRideAssigned_1.notifyHeroOnRideAssigned; } });
// FCM Data Push Layer 2 (CTO mandate). Unlike notifyHeroOnRideAssigned
// above (a Firestore `rides` onUpdate trigger keyed off `targeted_hero_id`
// — a field nothing in the app actually writes, confirmed dead in
// practice), these two trigger off the RTDB `hero_pings`/
// `hero_service_pings` writes every existing dispatch path already
// makes, so they're reachable by construction rather than requiring a
// specific write shape no caller produces.
var notifyHeroOnPing_1 = require("./notifyHeroOnPing");
Object.defineProperty(exports, "notifyHeroOnPing", { enumerable: true, get: function () { return notifyHeroOnPing_1.notifyHeroOnPing; } });
var notifyHeroOnServicePing_1 = require("./notifyHeroOnServicePing");
Object.defineProperty(exports, "notifyHeroOnServicePing", { enumerable: true, get: function () { return notifyHeroOnServicePing_1.notifyHeroOnServicePing; } });
// NEW (per Nizam's request — Admin app "WhatsApp model" closed-app
// alerts): mirrors notifyHeroOnRideAssigned's send pattern, but fans
// out to every doc in admins/ instead of one hero, triggered on
// creation of rides/service_requests (always happens exactly once per
// booking, unlike the deprecated targeted_hero_id onUpdate path).
var notifyAdminOnNewRide_1 = require("./notifyAdminOnNewRide");
Object.defineProperty(exports, "notifyAdminOnNewRide", { enumerable: true, get: function () { return notifyAdminOnNewRide_1.notifyAdminOnNewRide; } });
var notifyAdminOnNewServiceRequest_1 = require("./notifyAdminOnNewServiceRequest");
Object.defineProperty(exports, "notifyAdminOnNewServiceRequest", { enumerable: true, get: function () { return notifyAdminOnNewServiceRequest_1.notifyAdminOnNewServiceRequest; } });
// NOTE: seller order alerts (Issue 2 fix) deliberately do NOT use a
// Cloud Function — zero-cost infra constraint (no Blaze plan). See
// lib/main_seller.dart's _initSellerPingListener and
// ServiceRequestService.createServiceRequest's seller_pings/ RTDB write
// for the client-side-only replacement.
//# sourceMappingURL=index.js.map