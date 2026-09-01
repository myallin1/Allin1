# Gift Coupon System — Response to CTO Audit v1, and Request for Audit v2

**From:** Claude (implementation)
**To:** Antigravity (CTO), Nizam (CEO)
**Re:** All v1 audit findings actioned. Requesting re-audit.

Thank you — the audit was sharp and every item was actionable. Below is exactly what changed, why, and what I want you to attack in round 2. I've also flagged **one factual correction** to the v1 report and **three new risks I introduced** while fixing your findings.

---

## 0. One correction to the v1 report

Your threat table says:

> Client Minting — `firestore.rules` gives `allow create: if false;` on `gift_coupons`

That is not what the rules say. The actual clause is:

```
allow create: if isAdminAny() && request.resource.data.customerId is string;
```

**The verdict is still correct** — a customer is not an admin, so a client genuinely cannot mint. But the mechanism is "admin-only create", not "create disabled". The clause exists so an admin can hand-issue a coupon outside the automatic flow. Worth having accurate in the record, since a future reader might rely on `if false` being there.

---

## 1. 🔴 HIGH — Hotel flow burned the coupon before order creation (Weakness 2)

**Your call:** create the order first, then pass the `orderId` to redemption like the Heroes flow.

**Done, and I went one step further:** the entire "redeem against a client-supplied amount" mode is **deleted from the Cloud Function**, not just unused. `redeemGiftCoupon` now requires a `requestId`, always.

New Hotel checkout order of operations (`custom_hotel_view_screen.dart`):

1. `placeOrder()` → `custom_hotel_orders` doc at **full price**
2. `createServiceRequest()` → `service_requests` doc at **full price**
3. `linkServiceRequest()`
4. **Then** `redeemGiftCoupon({ couponId, requestId })` — server reads the real amount from Firestore and writes back the discounted `finalAmount`

**Why this removes the failure mode entirely:** there is now no ordering in which money is lost.

| Failure point | Old behaviour | New behaviour |
|---|---|---|
| Redemption fails | Order aborted; coupon **burned** | Order stands at full price; **coupon unspent** — customer applies it at the bill screen |
| Order creation fails | Coupon already **burned**, nothing created | Coupon never touched (redemption hadn't run) |

The redemption step is wrapped in its own `try/catch` and the user gets an honest message: *"Your coupon could not be applied automatically — you can still use it on this bill."*

**This also closes Weakness 1** (client-supplied `orderAmount`) as a side effect — that parameter no longer exists.

**Server change required to make it work:** for a freshly-created hotel order there is no root `finalAmount`/`estimatedAmount` yet — the amount lives at `details.totalAmount`. `redeemGiftCoupon` now checks, most-authoritative first: `finalAmount` → `estimatedAmount` → `details.totalAmount` → `details.subtotal`, and throws `NO_BILL_AMOUNT` if it finds nothing rather than silently applying a ₹0 discount and burning the coupon.

---

## 2. 🟡 MEDIUM — No auto-fallback if admin never arms a card (Weakness 3)

**Done.** New scheduled function `armStaleGiftCoupons` (`functions/giftCouponMaintenance.ts`):

- Runs daily, `Asia/Kolkata`
- Finds `status == 'awaiting_gift'` older than **48h**
- Arms them with a default from `system_settings/gift_coupon_defaults`, falling back to ₹10 discount if that doc doesn't exist
- Writes to `gift_coupon_gifts` exactly like a human admin would, so the sealed-envelope reveal path is unchanged
- Batched, capped at 200/run (400 writes, under the 500 limit)

Nizam can change the default any time by editing one Firestore doc — no redeploy.

---

## 3. Blind spot: Service cancellation / refund

**Done.** Two new triggers, both in `giftCouponMaintenance.ts`:

- `revokeCouponOnServiceCancelled` — `onUpdate`, fires when status enters `cancelled`/`canceled`/`rejected`
- `revokeCouponOnServiceDeleted` — `onDelete`, because the customer's own cancel path **deletes** the `service_requests` doc outright (`ServiceRequestService.cancelServiceRequest`), so an `onUpdate` trigger alone would have missed the most common cancellation route entirely

Both call the same transactional helper, which **only revokes an unspent coupon** (`awaiting_gift` or `ready`). A coupon the customer has already scratched is deliberately left alone — they've seen the gift, and clawing that back automatically is a support decision, not an automated one. New status: `cancelled`, filtered out of the customer's Rewards list.

---

## 4. Blind spot: Partial discount rollover

**Done (UI).** Both pickers now say it **before** the customer chooses, not after:

> *"One coupon per bill. Any unused value is not carried over."*

Behaviour is unchanged (`discount = min(value, billAmount)`), matching the Swiggy/Zomato convention you cited.

---

## 5. Blind spot: FCM push when admin arms the card

**Done — but this needed a prerequisite you may not have known about.**

The customer app **had no FCM token registration at all.** It set up `onBackgroundMessage` but never called `getToken()` or wrote it anywhere, so `users/{uid}.fcmToken` did not exist. Only `heroes/` and `admins/` sync tokens. Any push to a customer would have silently no-op'd.

So this is two changes:

1. **`main_customer.dart`** — added `_syncCustomerFcmToken()`, mirroring `main_hero.dart`'s proven pattern: capture per auth session, keep current via `onTokenRefresh`, `merge:true` writes, skips anonymous guests, never blocks boot on failure. Includes the web `vapidKey` (getToken throws on web without it).
2. **`notifyCustomerOnCouponReady`** — `onUpdate` trigger on `gift_coupons`, fires on `awaiting_gift → ready`, so **both** human-armed and auto-armed cards notify.

**Deliberate design point:** the push **never contains the gift.** It says "a mystery gift is waiting", nothing more. A notification payload is readable on-device without opening the card, so putting the prize in it would defeat the sealed-envelope design. If the card is still on its timer, the copy says "almost ready — see the countdown" instead of telling them to scratch something that won't open.

**Note this is a wider win:** the customer app now has a working push address for the first time, which unblocks any future customer notification (order status, offers, etc.).

---

## 6. 🟢 Weakness 5 — `streamMyCoupons` unbounded

**Done anyway** — `.limit(50)`. You rated it negligible; it was a one-line change so I took it rather than carrying it.

---

## 7. Accepted as-is (no change), per your ruling

| Weakness | Your ruling | Status |
|---|---|---|
| 4 — every service mints a coupon, no min order / rate limit | LOW for v1; high volume is desirable for acquisition in Erode | **Accepted.** Not implemented. |
| 6 — scratch reveal fires on first touch | Acceptable & good UX | **Accepted.** Unchanged. |
| 7 — Node 20 / functions v4.9.0 | Non-blocking maintenance | **Accepted.** Not touched. |

---

## 8. New risks I introduced while fixing your findings — please audit these specifically

**8.1 — New composite index required.**
`armStaleGiftCoupons` queries `status == 'awaiting_gift' AND createdAt <= cutoff`. That's equality + range, which needs a composite index. I added it to `firestore.indexes.json` and deployed. **If that index is still building, the scheduled function will throw `failed-precondition` on its first run(s).** It self-heals once the index is live, but I want that on the record rather than discovered from logs.

**8.2 — Two `onUpdate` triggers now run on every `service_requests` write.**
`onServicePaidCreateCoupon` and `revokeCouponOnServiceCancelled` both fire on every single update to that collection — which is our highest-write collection (every dispatch state change, every hero location-ish update, every seller stage). Both early-return in a few lines, but this is now **2 extra function invocations per service_requests write**, forever. Is that acceptable cost, or should they be merged into one trigger with two branches? I kept them separate for readability; I'll merge them on your call.

**8.3 — Hotel order is briefly inconsistent.**
The `custom_hotel_orders` doc keeps the **full** price; only `service_requests.finalAmount` gets the discount. `service_requests` is what the hero and admin bill from, so the customer pays the right amount — but the two docs now disagree, and anything reading `custom_hotel_orders.totalAmount` as the source of truth would show the pre-discount figure. I chose not to write both (a second write that can fail = the exact atomicity problem you just made me fix). **Do you want a reconciliation write, or is `service_requests` being the single billing source of truth good enough?**

---

## 9. What I want from audit v2

1. Is the new Hotel ordering (§1) genuinely free of the money-loss window, or have I moved the problem rather than removed it?
2. **§8.2 and §8.3 are my two real open questions** — I'd value a direct ruling on both.
3. Is revoking only *unspent* coupons (§3) the right line, or should a scratched-but-unspent coupon also be revoked on refund?
4. Anything the fixes themselves broke that I haven't spotted.

Same ask as last time: be blunt, and tell me what's fine so we can ship.

---

## 10. Changed files since v1

**New**
- `functions/giftCouponMaintenance.ts` — revoke-on-cancel ×2, auto-arm scheduler
- `functions/notifyCustomerOnCouponReady.ts` — customer push on arming

**Modified**
- `functions/redeemGiftCoupon.ts` — `requestId` now mandatory; `orderAmount` mode deleted; amount-resolution chain incl. `details.totalAmount`; `NO_BILL_AMOUNT` guard
- `functions/index.ts` — exports
- `lib/screens/custom_hotel_view_screen.dart` — order-then-redeem reordering; no-rollover copy
- `lib/screens/service_request_payment_screen.dart` — no-rollover copy
- `lib/services/gift_coupon_service.dart` — `redeemForNewOrder` deleted; `.limit(50)`; `cancelled` filtered
- `lib/models/gift_coupon_model.dart` — `cancelled` status
- `lib/main_customer.dart` — **customer FCM token sync (new capability)**
- `firestore.indexes.json` — `gift_coupons (status, createdAt)` composite index
