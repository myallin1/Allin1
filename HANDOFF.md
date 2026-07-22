# Allin1 — Session Handoff

Continuation notes for picking this project up in another environment
(e.g. Claude Code) after the Cowork session. Everything here is verified
against the code, not assumed.

---

## The project

- **Repo:** `C:\Projects\Allin1`  (GitHub: `myallin1/Allin1`)
- **Active branch:** `test-2-consolidated-all` (pushed)
- **Four apps, one `lib/` tree:** `main_customer.dart`, `main_hero.dart`,
  `main_admin.dart`, `main_seller.dart` — each deploys to its own
  Firebase Hosting target (customer / hero / admin / seller).
- **Backend:** Firebase (Firestore, RTDB, Auth), plus TrailBase sync and
  Ola Maps.

## Environment rules that bit us — keep them

1. **No Flutter/Dart toolchain in the AI sandbox.** `flutter analyze` /
   `build` / `pub get` must be run by Nizam locally. The AI can never
   verify a build itself.
2. **Line endings:** repo is LF; Windows working copy is CRLF. Run
   `git config core.autocrlf true` once so diffs show only real changes.
   Some files (e.g. `bike_taxi_screen.dart`, `customer_login_screen.dart`)
   are genuinely LF on disk — leave them.
3. **Deploy with `deploy_web.ps1`, never by hand.** It wipes `build\web`
   before each app (Hero+Customer share one build folder — a stale
   half-build gets deployed otherwise), gates deploy on the build's exit
   code, and auto-bumps the pubspec build number (the version.json
   update-detection depends on that number changing).
   - `.\deploy_web.ps1` = hero + customer
   - `.\deploy_web.ps1 -Only all` = all four
4. **`firebase.json` is gitignored** — its COOP header and `.env` fix live
   only on Nizam's disk. A fresh clone won't have them.
5. **Verify every edit:** NUL byte count 0, CRLF vs lone-LF preserved,
   brace/paren/bracket balanced. Byte-level python check via the shell.
6. **Plan → approve → implement.** Surgical patches only. One concern per
   commit. Never modify `firestore.rules` directly.
7. **Explanations to Nizam in pure Tamil** (Tamil script), English only
   for code/technical terms.

---

## Done this session (committed OR on disk)

**Committed (6 commits, pushed):**
- `feat(hero-tasks)` unified service-request flow
- `build` deploy_web.ps1
- `fix(maps)` Ola-first place search + map picker
- `fix(booking)` typed-address coordinates + shared-location intake
- `perf` parallel Hive init + version.json PWA updates
- `feat(onboarding)` intro video + welcome screen + English pass + icons

**On disk, NOT yet committed (the overnight round):**
- `bike_taxi_screen.dart` — real routed distance/fare (was straight-line),
  real route polyline (was a fake bezier), removed the 4 invented
  "recent places", removed dead `_fillPlace`/`_buildRecent`.
- `floating_companion.dart` — reduced to a no-op stub (was dead code with
  a per-frame repeating animation).
- `assets/images/*` — paytm_soundbox / top_bike / bike_marker_* resized
  (saved ~366 KB).

**COMMIT THESE FIRST** (see step 1 below) so the new environment sees them.

---

## Pending work — full detail

### #83 — Restrict the Ola Maps key (NIZAM, not code) 🔴
The key is publicly readable at `my-allin1.web.app/assets/.env`. Add a
domain restriction in the Ola/Krutrim console:
`my-allin1.web.app`, `hero-allin1.web.app`, `localhost`. Rotate the key
after. Unavoidable for a browser app — a key the browser uses is reachable.

### #95 — Seller ↔ customer ↔ admin wiring 🔴 (highest value)
Seller onboarding, menu setup, seller dashboard, and the customer browse
UI (`category_screen.dart` → `SellerCard` → `SellerDetailScreen`, 752
lines) are ALL already built. Decisions from Nizam: no approval step
(register = live, `SellerModel.status` already defaults to `'active'`);
customer browses sellers inside the existing food order page, below the
form; `CustomFoodOrderScreen` (service_requests) stays. Three verified
gaps to close — each self-contained:
  1. **Seller location never captured.** `seller_onboarding_screen.dart`
     line ~80 hardcodes `latitude:0.0, longitude:0.0`. Collects a text
     address, no coordinates, no "use current location". Every seller
     sits at (0,0). FIX: reuse `LocationService` + the map picker
     (`location_picker_screen.dart`) already built for taxi/hero.
  2. **`CategoryScreen` has no entry point.** Nothing constructs it. The
     dashboard 'food' tile goes to `CustomFoodOrderScreen`. FIX: mount the
     seller list inside the food page, below the form, grouped by category.
  3. **Menu subcollection name mismatch.** Seller writes
     `sellers/{id}/menu_items`; `SellerDetailScreen` reads via
     `CategoryGatewayService.loadSellerProducts()` →
     `sellers/{id}/products`. So the menu comes back empty. FIX: standardise
     on `menu_items`.
  4. **Admin has no seller monitoring.** Admin reads 14 collections, none
     of `sellers` / `menu_items` / `food_orders`. Add an admin screen.

### #94 — Migrate to ARB / gen-l10n (compile-time-safe i18n)
Current `LocalizationService.t()` falls back silently — a missing Tamil
string renders English or the raw key, so nothing fails and nobody
notices (how 83 screens ended up unlocalized). Move to Flutter's ARB
pipeline (`lib/l10n/app_en.arb` + `app_ta.arb` + `app_tg.arb`,
`flutter gen-l10n`, `AppLocalizations.of(context).x`) so a missing key is
a COMPILE ERROR. Plus a guard script that flags raw `Text('...')` literals.
Keep `LocalizationService` as the language-selection ChangeNotifier — it
stops being the translation table. Must not break the ~8 screens already
using `t()`. Nizam chose full scope; do it in priority order and keep the
app compiling at every step. This is a whole-session job.

### #93 — Migrate all 83 screens onto the ARB foundation
Depends on #94. Priority: dashboard → taxi journey → hero booking →
rewards/play_zone/profile/settings → payment/checkout → auth/welcome →
food/grocery/tech/custom-order → admin/seller (lowest).

### #96 — Hoist 27 inline Firestore streams
No leaked listeners (audited — every `.listen()` cancels). But 27
`StreamBuilder`s across 22 files build their stream inline in `build()`,
so each rebuild tears down and re-opens the Firestore listener = a full
re-read. FIX (mechanical): hoist into a `late final Stream<...> _x = ...;`
field, use `stream: _x`. Worst offenders: admin dashboards (open all day),
then `hero_screen` / `hero_home_screen`. 22 files, verify each.

### #88 — Dashboard not localized
`dashboard_screen.dart` uses `t()` zero times — its text is hardcoded.
That's why language changes don't affect the home page. Folds into #93.

### #71 — Off-screen animations (LOW value, left deliberately)
Two `..repeat()` controllers in `dashboard_screen.dart` are
AnimationController-based; Flutter's TickerMode already pauses them on
route change. VisibilityDetector wiring adds a dependency and risk for
little gain. The raw `Timer.periodic` marquees (the real offenders) were
already fixed.

### Old / stale (from prior sessions — confirm still relevant first)
#10 SOS overlay dismiss+timeout · #15 PR · #16/#18/#19/#20 patch files ·
#32 FCM on hero_assigned.

---

## Live diagnostics still open
- Test that after a fresh `deploy_web.ps1`, `my-allin1.web.app/assets/.env`
  returns the real `.env` (not the app HTML) and console shows
  `Ola API key present=true length=40`.
- Confirm the taxi fare log:
  `[BikeTaxi] route: X km ... straight line was Y km` — the gap X−Y is
  what the hero was previously losing on every ride.
