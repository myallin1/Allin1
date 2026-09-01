# Custom Food Order — "My Orders" Live Status List

**For:** CTO + Coder review
**Branch:** `dev-n`
**Author:** Nizam (via Claude)
**Status:** Proposal — awaiting sign-off before implementation

---

## 1. The Problem (current behaviour on `custom_food_order_screen.dart`)

Right now the Food Genie page is **write-only**. A customer fills the form (shop, items, name, address), taps *Place Order*, and we `pushReplacement` them straight into `ServiceRequestTrackingScreen` for **that single request**.

Consequences:

- **No overview.** Once the customer leaves that one tracking screen, there is no place on the food page to see their orders. If they placed 2–3 orders, they can't see all of them together or which stage each is at.
- **Status is not visible where the customer starts.** The order-lifecycle status (`pending → hero_assigned → in_progress → nearing_completion → completed`, plus `admin_review`) already lives in Firestore and updates live — but the food page itself never shows it. The customer has to be inside the single-request tracker to know anything.
- **Re-entry is awkward.** Because we `pushReplacement`, coming back to the food page after an order doesn't restore any order context.

Net: the data (live status per order) already exists in the pipeline; we simply aren't surfacing it on the page the customer actually lands on.

## 2. The Idea (proposed solution)

Add a **"My Orders"** live list to the food page, directly below the order form. It streams the customer's own custom-food-order requests from Firestore and shows each one's current status as a chip, tappable into the existing detailed tracker.

- **Query:** `service_requests` where `customerId == uid` AND `requestType == 'custom_food_order'`, ordered by `createdAt desc`, via `.snapshots()` (live). A hero/admin status change reflects instantly.
- **Each card:** shop name (`details.restaurantOrPreference`), items summary, time, and a **status chip** using the existing goods-type labels:
  - `pending` → *Waiting for confirmation*
  - `hero_assigned` → *Order confirmed*
  - `in_progress` → *On process*
  - `nearing_completion` → *On the way*
  - `completed` → *Delivered*
  - `admin_review` → *Team arranging a hero*
- **Tap → `ServiceRequestTrackingScreen`** (the full stepper we already have). No new tracking UI needed.

This reuses the entire existing broadcast/accept pipeline unchanged — we only *read and display* what's already there.

## 3. Files touched (3)

1. **New shared helper** — e.g. `lib/utils/service_request_labels.dart`.
   Today `_statusIndex()` and `_kGoodsLabels` are **private** inside `service_request_tracking_screen.dart`. We extract them so the new list and the tracker share **one** status→label→colour source. The pipeline code explicitly warns *"single source of truth — never introduce a second enum"*, so we must not duplicate this mapping.
2. **`custom_food_order_screen.dart`** — add the "My Orders" `StreamBuilder` section + loading state + empty state (~80 lines). No change to the existing form or `_placeOrder()` logic.
3. **`firestore.indexes.json`** — add the composite index `customerId + requestType + createdAt`.

## 4. Risks / things to decide

- **Composite index is mandatory.** Without deploying `customerId + requestType + createdAt`, the query throws and the list won't load. Needs `firebase deploy --only firestore:indexes`.
- **Navigation flow.** Placing an order currently does `pushReplacement` → the food page is replaced by the tracker. To make the list feel natural on re-entry we should decide: keep `pushReplacement`, or `push` (so back returns to the food page + refreshed list). Small change, needs a call.
- **Read cost.** One live stream per customer over their own orders — low volume, acceptable.
- **Scope.** This is display-only. It does **not** fix the separate reliability gap where the 90s timeout runs client-side (`Future.delayed` in the screen) and is skipped if the app is killed — that's a follow-up, not part of this change.

## 5. Effort

Small. One extracted helper + ~80 lines of UI + one index entry. Additive, built on top of the existing pipeline; no pipeline logic is modified.

---

**Decision needed:** approve as-is, or adjust (esp. the `push` vs `pushReplacement` navigation call). On sign-off I'll implement on `dev-n` and share the diff.
