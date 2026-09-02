/**
 * ================================================================
 * Cloud Function: confirmMenuItemStockHold
 * Phase 2a of the stock HOLD system — see stockHoldHelpers.ts's header.
 * ================================================================
 * Called right after the order doc is actually created (immediately
 * following ServiceRequestService.createServiceRequest() on the Dart
 * side). Marks the hold permanent — the stock decrement from
 * holdMenuItemStock.ts stands, forever — and credits the real
 * app-sold counter, which deliberately was NOT touched at hold time
 * (a hold that gets released must never have counted as a sale).
 *
 * Idempotent: calling this twice for the same holdId (a retried
 * request after a dropped response) is a safe no-op the second time —
 * see the status check below.
 * ================================================================
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { db } from './stockHoldHelpers';

interface ConfirmHoldRequest {
  holdId: string;
  requestId: string;
}

export const confirmMenuItemStockHold = functions.https.onCall(
  async (data: ConfirmHoldRequest, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be logged in');
    }
    if (!data.holdId || !data.requestId) {
      throw new functions.https.HttpsError('invalid-argument', 'holdId and requestId are required');
    }

    const holdRef = db.collection('stock_holds').doc(data.holdId);

    return db.runTransaction(async (transaction) => {
      const holdSnap = await transaction.get(holdRef);
      if (!holdSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'Stock hold not found');
      }
      const hold = holdSnap.data()!;
      if (hold.customerId !== context.auth!.uid) {
        throw new functions.https.HttpsError('permission-denied', 'Not your hold');
      }

      // Idempotent retry — already confirmed for this exact order.
      if (hold.status === 'confirmed' && hold.requestId === data.requestId) {
        return { confirmed: true, alreadyConfirmed: true };
      }
      if (hold.status !== 'held') {
        // Expired (swept) or released (customer cancelled) — the stock
        // this hold reserved is already back in the pool, possibly sold
        // to someone else. The caller must re-hold before it can order.
        throw new functions.https.HttpsError(
          'failed-precondition',
          `This reservation is no longer active (${hold.status}) — please try again.`,
        );
      }

      const sellerId = hold.sellerId as string;
      const items = (hold.items as { itemId: string; quantity: number }[]) || [];
      const itemsRef = db.collection('sellers').doc(sellerId).collection('menu_items');

      for (const item of items) {
        transaction.update(itemsRef.doc(item.itemId), {
          appOrderSoldCount: admin.firestore.FieldValue.increment(item.quantity),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      transaction.update(holdRef, {
        status: 'confirmed',
        requestId: data.requestId,
        confirmedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { confirmed: true, alreadyConfirmed: false };
    });
  },
);
