# Synthetic QA Test-Bot — Architecture Blueprint (Phase 1: 5 core screens)

Status: **PLAN ONLY — no code written yet.** This is the doc to review before
implementation starts, per the CTO's request.

Scope for Phase 1: Dashboard, Bike Booking, Grocery, Food, Profile.

---

## 1. What this is (and isn't)

**Is:** a scheduled, headless bot that runs the real Allin1 customer app
against a dedicated QA account, walks through the 5 screens above using
Flutter's own `integration_test` framework, takes screenshots at each step,
asks Groq's vision model "does anything look broken/confusing here?", and
files what it finds into a new Firestore collection that only the Admin
Quick Task chatbox reads.

**Is not:**
- Not watching or analyzing real customers — confirmed with the CTO this
  session, ruled out on privacy/consent grounds. Runs against one dedicated
  QA account only.
- Not a live in-app agent that customers ever see or interact with.
- Not able to place a real booking, a real payment, or write to any
  operational collection (`rides`, `orders`, `sellers`, etc.) — this bot's
  Firestore access should be scoped (see §6) to read + write only to
  `ux_audit_reports`.
- Not a DOM-crawling agent like Claude-in-Chrome. Flutter renders to a
  canvas (Skia/CanvasKit), not HTML — there's no DOM to inspect the way a
  browser extension would. `integration_test` drives the widget tree
  directly instead, which is the Flutter-native equivalent.

---

## 2. Honest starting-point audit (checked this session, not assumed)

- **Zero test infrastructure exists in this repo today.** No `test/` or
  `integration_test/` directory, `integration_test` isn't a
  `dev_dependency` in `pubspec.yaml`. This is a from-scratch build, not an
  extension of something already there.
- **No stable widget `Key`s on the interactive elements of any of the 5
  target screens** (checked `dashboard_screen.dart` directly — the only
  `Key`s present are for internal state, e.g. `_scaffoldKey`, nav-tab
  `GlobalKey`s for scroll positioning, not for testing). Without keys,
  `integration_test` has to fall back to `find.text('...')` or
  `find.byIcon(...)`, which breaks the moment copy or an icon changes —
  fragile by construction.
  **Consequence: adding `Key`s to the buttons/fields we want to test is a
  prerequisite, not optional polish.** This alone touches all 5 screen
  files, additively (a `key: const Key('...')` param never changes a
  widget's behavior), and should be its own first, small, easy-to-verify
  patch before any bot code is written.
- **Complexity varies a lot across the 5 screens** — this changes what
  "explore" can realistically mean per screen:
  - `dashboard_screen.dart` — 3,035 lines. Mostly navigation/display; safe
    to test broadly (tiles are present, tap → correct screen opens).
  - `bike_taxi/bike_booking_screen.dart` — 3,776 lines, GPS + live map +
    real-time fare calculation. A full "complete a booking" test would
    need location mocking and a live pricing dependency — out of scope for
    Phase 1. Testing "does the form render, can I pick a vehicle type,
    does the map load" is realistic; testing an actual fare quote is not.
  - `grocery_order_screen.dart` — 543 lines, form-based (already read this
    session for the Dual-Mode Grocery Cart work) — straightforward to
    test: type into `_listCtrl`, verify `_canSubmit` state changes.
  - `food_hub_screen.dart` — 145 lines, one of the simplest screens here.
  - `profile_screen.dart` — 624 lines, reads real account data — needs the
    QA account to have realistic seeded data so the screen isn't just
    testing an empty state every run.

---

## 3. Architecture

```
                     ┌─────────────────────────┐
   scheduled trigger │  QA Runner (CI job or   │
   (e.g. nightly,    │  local script)          │
   GitHub Actions) ─▶│  flutter test           │
                      │  integration_test/…     │
                      └───────────┬─────────────┘
                                  │ drives real app,
                                  │ signed in as QA account
                                  ▼
                     ┌─────────────────────────┐
                     │  Allin1 customer app     │
                     │  (Dashboard → Bike →     │
                     │   Grocery → Food →       │
                     │   Profile, scripted)     │
                     └───────────┬─────────────┘
                                  │ per-step screenshot
                                  │ (integration_test's
                                  │  built-in binding.takeScreenshot)
                                  ▼
                     ┌─────────────────────────┐
                     │  Vision analysis step    │
                     │  (reuses the exact Groq  │
                     │  vision pattern already  │
                     │  built for KYC OCR /     │
                     │  screenshot troubleshoot)│
                     └───────────┬─────────────┘
                                  │ findings
                                  ▼
                     ┌─────────────────────────┐
                     │  ux_audit_reports        │
                     │  (Firestore, new         │
                     │  collection, QA-bot-     │
                     │  scoped write access)    │
                     └───────────┬─────────────┘
                                  │ read-only
                                  ▼
                     ┌─────────────────────────┐
                     │  Admin Quick Task        │
                     │  chatbox — new           │
                     │  `run_ux_audit` tool,    │
                     │  same pattern as the     │
                     │  existing                │
                     │  audit_ui_sections tool  │
                     └─────────────────────────┘
```

Nothing here is customer-visible. The runner, the QA account, and the
Firestore writes all sit outside the customer app's own code path.

---

## 4. Per-screen test plan (Phase 1)

| Screen | What gets checked | Feasible now? |
|---|---|---|
| Dashboard | All service tiles present and tappable; tapping each opens the expected screen; no visible layout overflow/error banners | Yes, straightforward |
| Bike Booking | Screen opens from Dashboard tile; vehicle-type selector renders and is tappable; form fields present; **does not** attempt a real fare quote or booking (needs location mocking — Phase 2) | Partial — navigation + static UI only |
| Grocery | Screen opens; typing into the list field updates `_canSubmit`; "Send Order" button becomes enabled/disabled correctly; screenshot-upload UI renders (does not upload a real file) | Yes |
| Food | Screen opens; category/hotel list renders without error | Yes |
| Profile | Screen opens for the QA account; displays name/phone without crashing; edit fields are reachable | Yes, if QA account has seeded profile data |

A finding is anything that deviates from the expected state above: a
missing tile, a crash, a blank screen, an overflow warning, a tap that
goes nowhere, or — via the vision step — something a screenshot shows that
text-based widget assertions wouldn't catch (visual overlap, cut-off text,
a broken image).

---

## 5. Firestore schema — `ux_audit_reports`

```
ux_audit_reports/{autoId}:
  runId: string            // groups all findings from one run together
  screen: string            // 'dashboard' | 'bike_booking' | 'grocery' | 'food' | 'profile'
  step: string               // e.g. 'tile_tap_food', 'form_render'
  status: 'ok' | 'finding'
  findingText: string?       // present only when status == 'finding'
  screenshotUrl: string?     // uploaded via the same Cloudinary path already used elsewhere
  timestamp: Timestamp
```

Read-only for the Admin app (via the new `run_ux_audit` tool); write access
scoped to the QA runner's own service identity only — never touched by the
customer app or any customer-facing code.

---

## 6. Access & safety boundaries (mirrors this session's established pattern)

- QA runner authenticates as a dedicated `qa_bot@` Firebase Auth account —
  never a real customer's session.
- Firestore rules (reviewed, not auto-edited — per the standing rule in
  this repo to never touch `firestore.rules` directly) should restrict
  that account to: read on the 5 screens' own already-public data, write
  only to `ux_audit_reports`. No access to `rides`, `orders`, `sellers`,
  `heroes`, or any payment-adjacent collection.
- The bot never taps a real "Confirm"/"Book"/"Pay" button — Phase 1
  explicitly stops before that point on every screen (see §4).
- Admin-side consumption reuses the exact `audit_ui_sections` pattern
  already shipped this session: read-only, no gate needed to view a
  report, any follow-up action (if ever added) would go through the
  existing Yes/No write gate, unchanged.

---

## 7. Phased rollout

1. **Prep (small, additive, verify-safely):** add `integration_test` to
   `dev_dependencies`; add `Key`s to the interactive elements on the 5
   screens (no behavior change).
2. **Phase 1 (this doc's scope):** the 5-screen navigation/render/form-state
   checks in §4, manually triggered locally first.
3. **Phase 1.5:** wire the vision-analysis step + `ux_audit_reports` writes
   + the Admin `run_ux_audit` tool.
4. **Phase 2 (separate, later decision):** scheduling (CI cron), deeper
   flows (location-mocked bike booking, seller browsing), more screens.

---

## 8. Open questions for the CTO before coding starts

1. OK to add `integration_test` as a new `dev_dependency` (SDK-bundled,
   no version pinning risk, dev-only — never ships in the release build)?
2. Who provisions the `qa_bot@` Firebase Auth account and seeds its
   profile/location data?
3. Where should the runner actually execute — a local machine (`flutter
   test integration_test/`) for now, or is GitHub Actions/CI wanted from
   day one? (Local first is simpler to verify and matches this repo's
   "verify before automating" habit so far.)
4. Confirm Firestore rules for `ux_audit_reports` + the QA account's
   restricted access get written by Nizam (per the existing rule that I
   never edit `firestore.rules` directly).

---

*No code has been written for this yet. Once reviewed, Phase 1 implementation
is a self-contained, additive patch: new `integration_test/` directory,
`Key` additions to 5 existing screens (behavior-preserving), one new
Firestore collection, and one new read-only Admin tool — nothing here
removes or modifies existing app logic.*
