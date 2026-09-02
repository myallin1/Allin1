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

import * as functions from 'firebase-functions';
import { releaseHoldInternal, db } from './stockHoldHelpers';

interface ReleaseHoldRequest {
  holdId: string;
}

export const releaseMenuItemStockHold = functions.https.onCall(
  async (data: ReleaseHoldRequest, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be logged in');
    }
    if (!data.holdId) {
      throw new functions.https.HttpsError('invalid-argument', 'holdId is required');
    }

    const holdSnap = await db.collection('stock_holds').doc(data.holdId).get();
    if (holdSnap.exists && holdSnap.data()?.customerId !== context.auth.uid) {
      throw new functions.https.HttpsError('permission-denied', 'Not your hold');
    }

    const result = await releaseHoldInternal(data.holdId, 'released');
    return result;
  },
);
