/**
 * ================================================================
 * Cloud Function: onServiceRequestUpdated
 * Trigger: Firestore onUpdate on service_requests/{requestId}
 *
 * MERGED per CTO audit v2 (§8.2): this used to be two separate
 * onUpdate triggers on the SAME collection — onServicePaidCreateCoupon
 * and revokeCouponOnServiceCancelled. service_requests is this app's
 * highest-write collection (every dispatch state change, hero
 * location-ish update, seller kitchen stage), so two triggers meant
 * two Cloud Functions invocations, two cold-start risks, and double
 * billing on every single write to it — for logic that, in both cases,
 * exits in a few lines on the writes it doesn't care about. One
 * trigger with two independent branches halves that cost with zero
 * behavioural change.
 *
 * Branch 1 — mint: a paid service earns a locked coupon.
 * Branch 2 — revoke: a service cancelled/rejected before payment loses
 *            its (still-sealed) coupon. See giftCouponMaintenance.ts
 *            for why 'scratched' coupons are deliberately NOT touched
 *            here — that decision doesn't change by merging the file.
 * ================================================================
 */

import * as functions from 'firebase-functions';
import { logger } from 'firebase-functions';
import * as admin from 'firebase-admin';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

/** How long the card stays locked before the customer may scratch it. */
const DEFAULT_UNLOCK_HOURS = 24;

/** How long a coupon remains usable once it unlocks. */
const DEFAULT_VALID_DAYS = 60;

const CANCELLED_STATUSES = ['cancelled', 'canceled', 'rejected'];

export const onServiceRequestUpdated = functions.firestore
  .document('service_requests/{requestId}')
  .onUpdate(async (change, context) => {
    const requestId = context.params.requestId as string;
    const before = change.before.data();
    const after = change.after.data();
    if (!before || !after) return null;

    const justPaid =
      before.paymentStatus !== 'paid' && after.paymentStatus === 'paid';
    if (justPaid) {
      await mintCoupon(requestId, after);
      // A single write is realistically never BOTH "just paid" and
      // "just cancelled" — but if it somehow were, minting is the
      // right outcome (payment is the source of truth), so return
      // rather than also running the revoke branch below.
      return null;
    }

    const justCancelled =
      !CANCELLED_STATUSES.includes(before.status) &&
      CANCELLED_STATUSES.includes(after.status);
    if (justCancelled) {
      await revokeIfUnspent(requestId, `service ${after.status}`);
    }

    return null;
  });

// ── Branch 1: mint ────────────────────────────────────────────────
//
// IDEMPOTENCY: the coupon doc ID *is* the service request ID, so a
// retried trigger delivery (at-least-once, not exactly-once) can only
// ever write the same doc. .create() fails loudly-but-harmlessly on
// the duplicate (ALREADY_EXISTS, code 6) rather than overwriting a
// coupon an admin may already have armed.
async function mintCoupon(
  requestId: string,
  after: FirebaseFirestore.DocumentData,
): Promise<void> {
  const customerId = after.customerId as string | undefined;
  if (!customerId) {
    logger.warn('[onServiceRequestUpdated] no customerId on request:', requestId);
    return;
  }

  const now = Date.now();
  const couponRef = db.collection('gift_coupons').doc(requestId);

  try {
    await couponRef.create({
      customerId,
      customerName: (after.customerName as string) ?? '',
      status: 'awaiting_gift',
      // giftType/value/giftLabel are deliberately left unset — an
      // admin fills them in from the Gift Coupons screen, which is
      // what moves this to 'ready'.
      giftType: null,
      value: 0,
      giftLabel: '',
      sourceRequestId: requestId,
      sourceRequestType: (after.requestType as string) ?? '',
      sourceSummary: buildSourceSummary(after),
      unlockAt: admin.firestore.Timestamp.fromMillis(
        now + DEFAULT_UNLOCK_HOURS * 60 * 60 * 1000,
      ),
      expiresAt: admin.firestore.Timestamp.fromMillis(
        now + DEFAULT_VALID_DAYS * 24 * 60 * 60 * 1000,
      ),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    logger.info(`[onServiceRequestUpdated] coupon minted for request ${requestId}, customer ${customerId}`);
  } catch (error: any) {
    if (error?.code === 6) {
      logger.info(`[onServiceRequestUpdated] coupon already exists for ${requestId}, skipping`);
      return;
    }
    logger.error(`[onServiceRequestUpdated] mint failed for ${requestId}:`, error?.message ?? error);
  }
}

/**
 * A short "what did they buy" line, shown on both the customer's card
 * and the admin list so an admin can tell at a glance which service
 * earned the coupon.
 */
function buildSourceSummary(request: FirebaseFirestore.DocumentData): string {
  const details = (request.details ?? {}) as FirebaseFirestore.DocumentData;
  const shop = details.sellerName ?? details.hotelName;
  if (typeof shop === 'string' && shop.trim().length > 0) {
    return shop.trim();
  }
  const type = (request.requestType as string) ?? '';
  switch (type) {
    case 'hero_booking':
      return 'Hero booking';
    case 'grocery_order':
      return 'Grocery order';
    case 'custom_food_order':
    case 'catalog_food_order':
      return 'Food order';
    case 'custom_hotel_order':
      return 'Hotel order';
    case 'electronics_service':
      return 'Electronics service';
    case 'custom_order':
      return 'Custom order';
    default:
      return type.replace(/_/g, ' ');
  }
}

// ── Branch 2: revoke ─────────────────────────────────────────────
//
// Only ever reachable for an UNPAID request — see the doc comment at
// the top of this file and giftCouponMaintenance.ts for the full
// reasoning (cancel/reject is only ever offered pre-'completed' in
// this codebase, and a coupon only exists post-payment, so in
// practice this branch guards a state that can't currently occur; kept
// because "can't currently occur" is a property of today's UI, not a
// guarantee, and the check costs nothing).
async function revokeIfUnspent(requestId: string, reason: string): Promise<void> {
  const couponRef = db.collection('gift_coupons').doc(requestId);
  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(couponRef);
      if (!snap.exists) return;
      const status = snap.data()?.status as string | undefined;
      if (status !== 'awaiting_gift' && status !== 'ready') {
        logger.info(
          `[onServiceRequestUpdated] coupon ${requestId} already in '${status}' — leaving it alone`,
        );
        return;
      }
      tx.update(couponRef, {
        status: 'cancelled',
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
        cancelledReason: reason,
      });
    });
  } catch (error: any) {
    logger.error(
      `[onServiceRequestUpdated] revoke failed for ${requestId}:`,
      error?.message ?? error,
    );
  }
}
