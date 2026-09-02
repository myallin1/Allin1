"use strict";
/**
 * ================================================================
 * Cloud Function: holdMenuItemStock
 * Phase 1 of the stock HOLD system — see stockHoldHelpers.ts's header
 * for the full design and why this replaces reserveMenuItemStock.
 * ================================================================
 * Called the moment a customer taps "Checkout" — BEFORE they see any
 * payment method, let alone pay. Stock is decremented immediately (the
 * "lock" — nobody else can buy these units while held) and a
 * stock_holds/{holdId} doc records exactly what was reserved, for how
 * long, and by whom. The caller gets holdId + the resolved item
 * names/prices back and carries them through the checkout screen;
 * confirmMenuItemStockHold.ts is what makes the decrement permanent
 * once — and only once — an order genuinely exists.
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
exports.holdMenuItemStock = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
const stockHoldHelpers_1 = require("./stockHoldHelpers");
exports.holdMenuItemStock = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in');
    }
    if (!data.sellerId || !Array.isArray(data.items) || data.items.length === 0) {
        throw new functions.https.HttpsError('invalid-argument', 'sellerId and items are required');
    }
    for (const it of data.items) {
        if (!it.itemId || !it.quantity || it.quantity <= 0 || it.quantity > stockHoldHelpers_1.MAX_QUANTITY_PER_ITEM) {
            throw new functions.https.HttpsError('invalid-argument', 'Each item needs a valid itemId and a reasonable quantity');
        }
    }
    const uid = context.auth.uid;
    // Bounds how many holds this customer can have open at once — see
    // stockHoldHelpers.ts's own comment on MAX_CONCURRENT_HOLDS_PER_CUSTOMER
    // for why this matters even though holds already self-expire.
    const openHolds = await stockHoldHelpers_1.db
        .collection('stock_holds')
        .where('customerId', '==', uid)
        .where('status', '==', 'held')
        .limit(stockHoldHelpers_1.MAX_CONCURRENT_HOLDS_PER_CUSTOMER)
        .get();
    if (openHolds.size >= stockHoldHelpers_1.MAX_CONCURRENT_HOLDS_PER_CUSTOMER) {
        throw new functions.https.HttpsError('resource-exhausted', 'You have too many pending checkouts — finish or cancel one first.');
    }
    const itemsRef = stockHoldHelpers_1.db.collection('sellers').doc(data.sellerId).collection('menu_items');
    const holdRef = stockHoldHelpers_1.db.collection('stock_holds').doc();
    try {
        const resolvedItems = await stockHoldHelpers_1.db.runTransaction(async (transaction) => {
            // ── 1. READ + VALIDATE every item first ──
            const snaps = await Promise.all(data.items.map((it) => transaction.get(itemsRef.doc(it.itemId))));
            const shortages = [];
            const resolved = [];
            snaps.forEach((snap, i) => {
                var _a;
                const requestedQty = data.items[i].quantity;
                if (!snap.exists) {
                    shortages.push(`${data.items[i].itemId} (no longer available)`);
                    return;
                }
                const item = snap.data();
                const stock = (_a = item.stockQuantity) !== null && _a !== void 0 ? _a : null;
                const isAvailable = item.isAvailable !== false;
                if (!isAvailable) {
                    shortages.push(`${item.name} (currently unavailable)`);
                    return;
                }
                // A null/undefined stockQuantity means "not stock-tracked" —
                // treated as always in stock, matching MenuItemModel's own
                // optional-stockQuantity semantics used elsewhere in the app.
                if (stock !== null && stock < requestedQty) {
                    shortages.push(`${item.name} (only ${stock} left)`);
                    return;
                }
                resolved.push({
                    itemId: data.items[i].itemId,
                    name: item.name || 'Item',
                    price: item.price || 0,
                    quantity: requestedQty,
                    unit: item.unit,
                });
            });
            // ── 2. ALL-OR-NOTHING: any shortage aborts before any write ──
            // This is the guarantee the whole hold system exists to make
            // load-bearing: if ANY item is short, NOTHING is decremented,
            // no hold is created, and the caller's checkout screen never
            // opens — so no payment method is ever shown for a cart that
            // can't be fulfilled.
            if (shortages.length > 0) {
                throw new functions.https.HttpsError('failed-precondition', `Some items are no longer available: ${shortages.join(', ')}`);
            }
            // ── 3. Decrement stock AND create the hold record, atomically ──
            // Deliberately does NOT touch appOrderSoldCount here — that
            // counter should only reflect orders that actually happened,
            // and this hold might still be released. confirmMenuItemStockHold
            // .ts is what increments it, once the order is real.
            snaps.forEach((snap, i) => {
                const requestedQty = data.items[i].quantity;
                const item = snap.data();
                const stock = item.stockQuantity;
                if (stock !== null) {
                    transaction.update(snap.ref, {
                        stockQuantity: admin.firestore.FieldValue.increment(-requestedQty),
                        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                }
            });
            const expiresAtMs = Date.now() + stockHoldHelpers_1.HOLD_TTL_MINUTES * 60 * 1000;
            transaction.set(holdRef, {
                sellerId: data.sellerId,
                customerId: uid,
                items: resolved,
                status: 'held',
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                expiresAtMs,
            });
            return resolved;
        });
        const subtotal = resolvedItems.reduce((sum, it) => sum + it.price * it.quantity, 0);
        return { holdId: holdRef.id, items: resolvedItems, subtotal, expiresInMinutes: stockHoldHelpers_1.HOLD_TTL_MINUTES };
    }
    catch (error) {
        functions.logger.error(`holdMenuItemStock failed for ${uid}:`, error);
        if (error instanceof functions.https.HttpsError)
            throw error;
        throw new functions.https.HttpsError('internal', 'Could not hold stock');
    }
});
//# sourceMappingURL=holdMenuItemStock.js.map