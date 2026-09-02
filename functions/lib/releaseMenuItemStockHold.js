"use strict";
/**
 * ================================================================
 * Cloud Function: releaseMenuItemStockHold
 * Phase 2b of the stock HOLD system — see stockHoldHelpers.ts's header.
 * ================================================================
 * Called the moment a customer backs out of checkout (closes
 * FoodCheckoutScreen without completing any payment method) — restores
 * the held stock immediately instead of waiting for the scheduled
 * sweep, so the item is available to other customers right away
 * rather than sitting locked for up to HOLD_TTL_MINUTES.
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
exports.releaseMenuItemStockHold = void 0;
const functions = __importStar(require("firebase-functions"));
const stockHoldHelpers_1 = require("./stockHoldHelpers");
exports.releaseMenuItemStockHold = functions.https.onCall(async (data, context) => {
    var _a;
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in');
    }
    if (!data.holdId) {
        throw new functions.https.HttpsError('invalid-argument', 'holdId is required');
    }
    const holdSnap = await stockHoldHelpers_1.db.collection('stock_holds').doc(data.holdId).get();
    if (holdSnap.exists && ((_a = holdSnap.data()) === null || _a === void 0 ? void 0 : _a.customerId) !== context.auth.uid) {
        throw new functions.https.HttpsError('permission-denied', 'Not your hold');
    }
    const result = await (0, stockHoldHelpers_1.releaseHoldInternal)(data.holdId, 'released');
    return result;
});
//# sourceMappingURL=releaseMenuItemStockHold.js.map