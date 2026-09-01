# Gift Coupon Scratch-Card System — Design Brief & CTO Audit Request

**Project:** Allin1 / Erode Super App (`erode-super-app`)
**Stack:** Flutter (4 apps from one codebase: Customer / Hero / Seller / Admin) + Firebase (Firestore, Cloud Functions Gen1 Node 20, RTDB, FCM). Blaze plan.
**Status:** Implemented and deployed. Asking for a design + security audit before we call it done.

Please read the whole plan first and make sure the *logic* makes sense to you as a CTO would judge it — not just a line-by-line code review. Tell us where the reasoning is wrong, where it breaks under real usage, and what we've missed. Be blunt.

---

## 1. The business idea

A customer completes any service in our app (bike taxi, hero booking, food order, grocery, hotel order, electronics repair) and pays for it. As a thank-you, they earn a **gift coupon** — a scratch card.

The card does **not** open immediately. It stays sealed for a while. During that window, our admin decides what's actually inside it. Once the timer runs out, the customer scratches the card open in the app, sees their gift, and claims it.

The gift is one of two kinds:
- **₹ discount** — applied to a future Hero task bill or Hotel order checkout.
- **Gift item** — free text (e.g. "Free mobile cover"), collected in person at our shop.

Business intent: give customers a real reason to come back, while keeping us in control of how much we're giving away per customer, per order.

---

## 2. The flow, end to end

| Step | Actor | What happens | Where |
|---|---|---|---|
| 1 | System | Customer pays for a service → a **locked** coupon is auto-created, with a 24h unlock timer | `onServicePaidCreateCoupon` (Firestore trigger) |
| 2 | Admin | Opens Gift Coupons, sees the "NEEDS GIFT" queue, chooses ₹ discount or gift item, optionally changes the timer | `admin_gift_coupons_screen.dart` |
| 3 | Customer | After the timer, the card becomes scratchable in Rewards | `gift_scratch_card.dart` |
| 4 | Customer | Rubs the foil off → gift revealed | `scratchGiftCoupon` (callable) |
| 5 | Customer | ₹ discount → applied at a bill. Gift item → collected in person, admin marks handed over | `redeemGiftCoupon` (callable) / admin screen |

### Status machine (`gift_coupons/{id}.status`)

```
awaiting_gift  ──(admin sets gift)──▶  ready
                                        │
                            (timer done + customer scratches)
                                        ▼
                                    scratched
                                    ╱        ╲
                     (discount spent)        (item handed over)
                            ▼                        ▼
                        redeemed                  claimed
```

---

## 3. Data model

### `gift_coupons/{couponId}` — customer-readable
The doc ID **is** the source `service_requests` ID. That's deliberate: it makes coupon creation idempotent, so a retried Cloud Function delivery (at-least-once, not exactly-once) can never mint two coupons for one paid service.

```
customerId, customerName
status                      awaiting_gift | ready | scratched | redeemed | claimed
giftType                    null until scratched  ← see §5
value                       0 until scratched     ← see §5
giftLabel                   '' until scratched    ← see §5
sourceRequestId, sourceRequestType, sourceSummary
unlockAt                    Timestamp — scratching blocked until this
expiresAt                   Timestamp — 60 days
createdAt, giftSetAt, giftSetBy, scratchedAt, redeemedAt
redeemedOnRequestId, redeemedOnRequestType
```

### `gift_coupon_gifts/{couponId}` — admin-only, "the sealed envelope"

```
giftType    'discount' | 'item'
value       number
giftLabel   string
setBy, setAt
```

---

## 4. Cloud Functions (all the real logic is server-side)

**`onServicePaidCreateCoupon`** — Firestore `onUpdate` on `service_requests/{id}`. Fires only on the transition `paymentStatus != 'paid'` → `'paid'`. Creates the locked coupon with `.create()` (not `.set()`) so a duplicate delivery fails harmlessly instead of overwriting a coupon an admin already armed.

**`scratchGiftCoupon`** — callable. In one transaction: verifies ownership, verifies `status == 'ready'`, verifies not expired, **verifies `unlockAt <= now` against the server clock**, reads the sealed envelope, copies the gift onto the customer doc, sets `status = 'scratched'`, returns the gift.

**`redeemGiftCoupon`** — callable. Requires `status == 'scratched'` and `giftType == 'discount'`. Two modes:
- *Heroes bill* — caller passes `requestId`; the function reads the real `finalAmount`/`estimatedAmount` **off the Firestore doc** (never trusts a client-passed amount), applies `discount = min(value, billAmount)`, writes the new `finalAmount`, marks the coupon redeemed, returns the payable amount.
- *Hotel checkout* — the order doesn't exist yet, so the caller passes its own cart `orderAmount`. Marks the coupon redeemed and returns the payable amount for the client to write on the new order.

---

## 5. Security reasoning — please attack this

Our threat model is a customer running a patched client, with a device clock they fully control.

**No customer write to `gift_coupons` exists at all.** Firestore rules give the customer read-on-own-docs and nothing else. Minting, revealing, and spending are each a Cloud Function running as Admin SDK.

**The unlock timer is enforced on the server clock**, inside `scratchGiftCoupon`'s transaction. Winding the phone forward changes only what the UI *displays*.

**The gift is not on the customer-readable doc until it's scratched.** This is the part we fixed late: our first version wrote `giftType`/`value`/`giftLabel` onto `gift_coupons` when the admin armed the card. The customer can read their own coupon doc (they have to — that's how the countdown renders), so a patched client could have read the prize before scratching. Money was never at risk (redeeming needs `status == 'scratched'`, which only the server sets), but the *surprise* was — and the surprise is the whole feature. So the gift now lives in `gift_coupon_gifts`, which has no customer read clause, and `scratchGiftCoupon` copies it across at reveal time.

**Idempotent minting** via doc-ID-equals-request-ID, as above.

---

## 6. Things we already know are weak — please confirm or correct, and add what we missed

1. **Hotel checkout trusts a client-supplied `orderAmount`.** There's no order document to read yet at redemption time. We reasoned this adds no *new* hole, because that same client already writes its own `totalAmount` when creating the order (pre-existing behaviour). Is that reasoning sound, or should redemption move to after order creation?

2. **Hotel flow burns the coupon before the order exists.** We redeem first, then create the order. If order creation fails after a successful redemption, the coupon is gone and the customer got nothing. We abort the order if redemption fails, but there's no compensating action in the reverse direction. How would you make this atomic — or is a reconciliation/refund path enough?

3. **No auto-fallback if admin never arms a card.** A coupon sits in `awaiting_gift` forever and the customer just sees "your gift is being prepared". Should there be a scheduled function that assigns a default gift after N days, or is an admin queue enough?

4. **Every paid service mints a coupon — no minimum order value, no per-customer rate limit.** A customer placing ten ₹40 orders earns ten coupons. Admin can set ₹0-value gifts, but the queue still fills. Where would you put the throttle — mint-time rules, or admin-side bulk actions?

5. **`streamMyCoupons` has no `limit()`.** It reads every non-terminal coupon for the customer on every Rewards open. Small today; unbounded in principle.

6. **Scratch reveal fires on first touch.** We call `scratchGiftCoupon` as soon as the finger lands, so the answer is ready by the time enough foil is gone. But that means a single accidental tap marks the card `scratched` server-side even if the customer never actually saw the reveal. On reopen the card shows as already revealed, so nothing is lost — but is that the right trade vs. a laggy reveal?

7. **Node 20 is deprecated** (decommissioned 2026-10-30) and `firebase-functions` is on 4.9.0. Not part of this feature, but it's the runtime this ships on.

---

## 7. What we want from you

1. Does the **logic** hold together as a business mechanic — the timer, the admin-in-the-middle, the two gift kinds?
2. Is the **security reasoning** in §5 actually correct, or are we fooling ourselves somewhere?
3. Which of the weaknesses in §6 would you block a release on, and which are acceptable for v1?
4. What have we **not thought of** — abuse vectors, cost blowups, failure modes, UX dead-ends?

Please be specific about severity. If something is fine, say it's fine — we'd rather ship than gold-plate.

---

## 8. Files to read

| File | What it holds |
|---|---|
| `lib/models/gift_coupon_model.dart` | Status machine, lifecycle doc comment |
| `lib/services/gift_coupon_service.dart` | Client access layer, admin writes, sealed-gift stream |
| `lib/widgets/gift_scratch_card.dart` | The four card states + the foil painter |
| `lib/screens/rewards_screen.dart` | Customer "My Gift Coupons" section |
| `lib/screens/admin/admin_gift_coupons_screen.dart` | Admin queue (Overview → MANAGE → Gift Coupons) |
| `lib/screens/service_request_payment_screen.dart` | Heroes bill redemption |
| `lib/screens/custom_hotel_view_screen.dart` | Hotel checkout redemption |
| `functions/onServicePaidCreateCoupon.ts` | Auto-mint trigger |
| `functions/scratchGiftCoupon.ts` | Reveal + server-clock check |
| `functions/redeemGiftCoupon.ts` | Spend a discount |
| `firestore.rules` | `gift_coupons` + `gift_coupon_gifts` blocks |
