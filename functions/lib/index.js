"use strict";
/**
 * Allin1 Super App - Phase 2 Cloud Functions
 * Entry Point
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.notifyAdminOnNewServiceRequest = exports.notifyAdminOnNewRide = exports.notifyHeroOnServicePing = exports.notifyHeroOnPing = exports.notifyHeroOnRideAssigned = exports.manageHeroApproval = exports.checkDeviceFingerprint = exports.verifyAndProcessPayment = exports.affiliatePostbackWebhook = void 0;
var affiliatePostbackWebhook_1 = require("./affiliatePostbackWebhook");
Object.defineProperty(exports, "affiliatePostbackWebhook", { enumerable: true, get: function () { return affiliatePostbackWebhook_1.affiliatePostbackWebhook; } });
var verifyAndProcessPayment_1 = require("./verifyAndProcessPayment");
Object.defineProperty(exports, "verifyAndProcessPayment", { enumerable: true, get: function () { return verifyAndProcessPayment_1.verifyAndProcessPayment; } });
var checkDeviceFingerprint_1 = require("./checkDeviceFingerprint");
Object.defineProperty(exports, "checkDeviceFingerprint", { enumerable: true, get: function () { return checkDeviceFingerprint_1.checkDeviceFingerprint; } });
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
//# sourceMappingURL=index.js.map