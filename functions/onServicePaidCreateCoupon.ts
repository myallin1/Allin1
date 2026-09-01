/**
 * ================================================================
 * Cloud Function: onServicePaidCreateCoupon
 * Trigger: Firestore onUpdate on service_requests/{requestId}
 * Purpose: Step 1 of the gift-coupon scratch-card flow (per Nizam) —
 *          when a customer finishes ANY service in the app and it is
 *          marked paid, they earn a locked gift coupon.
 *
 * WHY A TRIGGER AND NOT A CLIENT WRITE: the coupon is a reward with
 * real value, so a client must never be able to mint one. This fires
 * off the exact write that already settles every service —
 * ServiceRequestService.markServiceRequestPaymentReceived() /
 * markServiceRequestPaid() setting paymentStatus:'paid' — so it is
 * reachable by construction for every requestType (hero_booking,
 * custom_order, custom_food_order, catalog_food_order,
 * custom_hotel_order, grocery_order, electronics_service) without a
 * per-category trigger.
 *
 * IDEMPOTENCY: the coupon doc ID *is* the service request ID, so a
 * retried trigger delivery (Cloud Functions guarantees at-least-once,
 * not exactly-once) can only ever write the same doc — one paid
 * service can never mint two coupons. The create() call below fails
 * loudly-but-harmlessly on the duplicate rather than overwriting a
 * coupon an admin may already have set a gift on.
 * ================================================================
 */

import * as functions from 'firebase-functions';
import { logger } from 'firebase-functions';
import * as admin from 'firebase-admin';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

/**
 * How long the card stays locked before the customer may scratch it.
 * The whole point of the delay is to give admin a window to decide
 * what goes inside — see admin_gift_coupons_screen.dart, where this is
 * also adjustable per coupon.
 */
const DEFAULT_UNLOCK_HOURS = 24;

/** How long a coupon remains usable once it unlocks. */
const DEFAULT_VALID_DAYS = 60;

export const onServicePaidCreateCoupon = functions.firestore
  .document('service_requests/{requestId}')
  .onUpdate(async (change, context) => {
    const requestId = context.params.requestId as string;
    const before = change.before.data();
    const after = change.after.data();

    if (!before || !after) return null;

    // Only the moment payment flips to 'paid' — not every later write
    // to an already-paid request.
    if (before.paymentStatus === 'paid' || after.paymentStatus !== 'paid') {
      return null;
    }

    const customerId = after.customerId as string | undefined;
    if (!customerId) {
      logger.warn('[onServicePaidCreateCoupon] no customerId on request:', requestId);
      return null;
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

      logger.info(`[onServicePaidCreateCoupon] coupon minted for request ${requestId}, customer ${customerId}`);
    } catch (error: any) {
      // ALREADY_EXISTS (code 6) is the expected outcome of a retried
      // delivery — the coupon is already there, nothing to do.
      if (error?.code === 6) {
        logger.info(`[onServicePaidCreateCoupon] coupon already exists for ${requestId}, skipping`);
        return null;
      }
      logger.error(`[onServicePaidCreateCoupon] failed for ${requestId}:`, error?.message ?? error);
    }

    return null;
  });

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
