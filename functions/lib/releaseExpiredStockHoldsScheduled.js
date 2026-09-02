"use strict";
/**
 * ================================================================
 * Cloud Function: releaseExpiredStockHoldsScheduled
 * Safety-net sweep for the stock HOLD system — see stockHoldHelpers
 * .ts's header for the full design.
 * ================================================================
 * Runs every 5 minutes. Finds any hold still 'held' past its
 * expiresAtMs — the customer closed the app mid-PhonePe-payment,
 * network dropped before releaseMenuItemStockHold.ts's explicit call,
 * or (the old, now-closed abuse path) someone called holdMenuItemStock
 * directly and never followed through — and restores that stock.
 *
 * This is what makes hold-based abuse SELF-HEALING and bounded to
 * HOLD_TTL_MINUTES, instead of the old reserveMenuItemStock's
 * PERMANENT damage from a single unaccompanied call.
 *
 * ONE-TIME SETUP NOTE: `firebase deploy` will prompt to enable the
 * Cloud Scheduler API the first time a scheduled function is deployed
 * (requires Blaze, already confirmed active on this project). This
 * uses Firebase's default Pub/Sub topic — no extra configuration
 * needed beyond accepting that one prompt.
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
exports.releaseExpiredStockHoldsScheduled = void 0;
const functions = __importStar(require("firebase-functions"));
const stockHoldHelpers_1 = require("./stockHoldHelpers");
exports.releaseExpiredStockHoldsScheduled = functions.pubsub
    .schedule('every 5 minutes')
    .onRun(async () => {
    const now = Date.now();
    // Capped per run — an expired hold that isn't swept THIS run is
    // simply swept next run 5 minutes later; there's no correctness
    // reason to process an unbounded batch in one invocation.
    //
    // REQUIRES the composite index on stock_holds (status ASC,
    // expiresAtMs ASC) in firestore.indexes.json — this combines an
    // equality filter with a range filter on a DIFFERENT field, which
    // Firestore cannot serve from automatic single-field indexes alone
    // (unlike holdMenuItemStock.ts's pure-equality customerId+status
    // query, which needs no composite index at all). Without that
    // index deployed, this throws on every single run and the entire
    // safety net silently never functions — wrapped so that failure is
    // at least loud in Cloud Functions logs instead of an opaque
    // crashed invocation.
    let expiredSnap;
    try {
        expiredSnap = await stockHoldHelpers_1.db
            .collection('stock_holds')
            .where('status', '==', 'held')
            .where('expiresAtMs', '<', now)
            .limit(200)
            .get();
    }
    catch (error) {
        functions.logger.error('releaseExpiredStockHoldsScheduled: query failed (missing index?):', error);
        return null;
    }
    if (expiredSnap.empty)
        return null;
    let releasedCount = 0;
    for (const doc of expiredSnap.docs) {
        try {
            const result = await (0, stockHoldHelpers_1.releaseHoldInternal)(doc.id, 'expired');
            if (result.released)
                releasedCount++;
        }
        catch (error) {
            functions.logger.error(`Failed to release expired hold ${doc.id}:`, error);
        }
    }
    functions.logger.info(`releaseExpiredStockHoldsScheduled: released ${releasedCount}/${expiredSnap.size} expired holds`);
    return null;
});
//# sourceMappingURL=releaseExpiredStockHoldsScheduled.js.map