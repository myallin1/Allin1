/**
 * ================================================================
 * stockHoldHelpers.ts — shared transaction logic for the stock HOLD
 * system (Sep 2026 — structural close-out of the reserveMenuItemStock
 * abuse/payment-race gap).
 * ================================================================
 * THE PROBLEM THIS REPLACES: the old reserveMenuItemStock decremented
 * stock and returned success, with NOTHING tying that decrement to an
 * order actually being created. Two concrete failures fell out of
 * that:
 *   1. PhonePe checkout collects PAYMENT before this ever ran (see
 *      food_checkout_screen.dart's _payWithPhonePe) — so a stock
 *      shortage discovered AFTER payment left a customer who had
 *      genuinely paid, with no order and no stock.
 *   2. Any authenticated client could call the function directly,
 *      decrementing a seller's stock with no order, no payment, and no
 *      way to ever get it back — permanent damage from one call.
 *
 * THE FIX: a two-phase HOLD.
 *   Phase 1 (holdMenuItemStock.ts) — stock is decremented IMMEDIATELY
 *   when checkout starts, before the customer has even chosen a
 *   payment method, let alone paid. This is what makes "pay for an
 *   out-of-stock item" structurally impossible: if the hold fails, the
 *   checkout screen never opens, so no payment method — including
 *   PhonePe — is ever shown.
 *
 *   Phase 2a (confirmMenuItemStockHold.ts) — called once the order
 *   doc genuinely exists. Marks the hold permanent and credits the
 *   real app-sold counter.
 *
 *   Phase 2b (releaseMenuItemStockHold.ts) — called the moment the
 *   customer backs out of checkout without completing it. Restores
 *   the held stock immediately.
 *
 *   Safety net (releaseExpiredStockHoldsScheduled.ts) — a scheduled
 *   sweep that releases any hold whose customer never explicitly
 *   cancelled OR confirmed (app killed mid-PhonePe-payment, network
 *   drop, etc.). This is what turns the old "permanent" abuse case
 *   into a self-healing one bounded to HOLD_TTL_MINUTES.
 * ================================================================
 */

import * as admin from 'firebase-admin';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

export const db = admin.firestore();

export const HOLD_TTL_MINUTES = 15;

// Bounds the worst case of a single hold call — no real cart is ever
// this large, so this only ever affects a malicious/scripted caller.
export const MAX_QUANTITY_PER_ITEM = 500;

// Bounds how many holds ONE customer can have open simultaneously —
// without this, a malicious authenticated user could still tie up a
// seller's entire stock by opening many small holds back-to-back
// faster than they expire. This does not affect any real shopper: a
// real cart is one hold, and nobody has 5 unfinished checkouts open
// on the same seller at once.
export const MAX_CONCURRENT_HOLDS_PER_CUSTOMER = 5;

export interface HoldItem {
  itemId: string;
  quantity: number;
}

export interface ResolvedHoldItem {
  itemId: string;
  name: string;
  price: number;
  quantity: number;
  unit?: string;
}

/**
 * Restores the stock a hold reserved and marks it with [newStatus]
 * ('released' or 'expired'). Idempotent by design — safe to call on a
 * hold that's already been released/confirmed/doesn't exist; only a
 * hold still in 'held' status is ever mutated. Shared by the explicit
 * client-triggered release, and the scheduled sweep for abandoned ones.
 */
export async function releaseHoldInternal(
  holdId: string,
  newStatus: 'released' | 'expired',
): Promise<{ released: boolean }> {
  const holdRef = db.collection('stock_holds').doc(holdId);

  return db.runTransaction(async (transaction) => {
    const holdSnap = await transaction.get(holdRef);
    if (!holdSnap.exists) return { released: false };

    const hold = holdSnap.data()!;
    if (hold.status !== 'held') {
      // Already confirmed, released, or expired — never double-restore
      // stock. This is the exact idempotency guarantee that makes it
      // safe for BOTH an explicit cancel AND the scheduled sweep to
      // race on the same hold with no risk of over-crediting stock.
      return { released: false };
    }

    const sellerId = hold.sellerId as string;
    const items = (hold.items as ResolvedHoldItem[]) || [];
    const itemsRef = db.collection('sellers').doc(sellerId).collection('menu_items');

    for (const item of items) {
      transaction.update(itemsRef.doc(item.itemId), {
        stockQuantity: admin.firestore.FieldValue.increment(item.quantity),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    transaction.update(holdRef, {
      status: newStatus,
      [`${newStatus}At`]: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { released: true };
  });
}
