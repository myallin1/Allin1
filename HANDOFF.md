# Allin1 — Session Handoff (read this first)

Complete context for continuing this project in a new Cowork session.
Everything here is verified against the code, not assumed. Read top to
bottom once and you have the whole picture.

---

## 1. The project

- **Repo:** `C:\Projects\Allin1`  (GitHub: `myallin1/Allin1`)
- **Active branch:** `test-2-consolidated-all` (pushed, up to date)
- **Four apps, one `lib/` tree:** `main_customer.dart`, `main_hero.dart`,
  `main_admin.dart`, `main_seller.dart` — each deploys to its own Firebase
  Hosting target (customer / hero / admin / seller). Customer = the main
  one at `my-allin1.web.app`.
- **Backend:** Firebase — Firestore (records), Realtime Database (live
  signalling), Auth. Plus TrailBase sync and Ola Maps.
- **Erode, Tamil Nadu super-app:** taxi, hero-for-hire, food, grocery,
  tech, etc.

## 2. Environment rules — these bit us, keep them

1. **No Flutter/Dart toolchain in the AI sandbox.** The AI can NEVER run
   `flutter analyze` / `build` / `pub get`, so it can't verify a build.
   Nizam runs those locally. Say this plainly when relevant.
2. **Line endings:** repo is LF, Windows working copy is CRLF. Run once:
   `git config core.autocrlf true` — then diffs show only real changes.
   A few files are genuinely LF on disk (`bike_taxi_screen.dart`,
   `customer_login_screen.dart`) — leave them.
3. **Deploy ONLY with `deploy_web.ps1`, never by hand.** It: wipes
   `build\web` before each app (Hero+Customer share one build folder — a
   stale half-build deploys otherwise); gates deploy on the build's exit
   code; auto-bumps the pubspec build number (the in-app version.json
   update-detection needs that number to change each deploy).
   - `.\deploy_web.ps1` = hero + customer
   - `.\deploy_web.ps1 -Only all` = all four
4. **`firebase.json` AND `.env` are gitignored.** They live only on
   Nizam's disk. `firebase.json` holds the COOP header (Google sign-in)
   and the dotfile-ignore fix (so `.env` deploys). `.env` holds the Ola
   key. A fresh clone won't have either.
5. **Git `index.lock`** kept getting stuck when commands were pasted all
   at once (commit + deploy racing). Run git commands ONE AT A TIME,
   waiting for the `PS>` prompt. If locked: `Stop-Process -Name git
   -Force` (ignore "not found"), then `Remove-Item ...\.git\index.lock
   -Force`, then `Test-Path` should be False.
6. **Verify every edit:** NUL bytes 0, CRLF vs lone-LF preserved,
   brace/paren/bracket balanced — byte-level python check via the shell.
7. **Plan → approve → implement. Surgical patches only. One concern per
   commit. Never edit `firestore.rules` directly. Never start a
   multi-file refactor you can't finish this session** — a half-done
   refactor that breaks the build is the biggest risk.
8. **Explanations to Nizam in pure Tamil** (Tamil script); English only
   for code/technical terms.

---

## 3. Done and committed (11 commits, all pushed)

```
2144d8d2  fix(pwa): drop SW unregister that raced and blanked the screen
6ad4fd06  chore(assets): drop unused images (bapx_nj_logo.gif 2.4MB, cover)
449190ef  perf(assets): resize oversized images (~366 KB)
61a86466  feat(onboarding): intro video + welcome screen + English pass + icons
9384c5a9  perf: parallel Hive init past runApp; PWA updates via version.json
cb61da12  fix(booking): typed addresses had no coordinates; search+picker+share
e19e6014  fix(maps): Ola-first place search, drop hardcoded Erode bias, picker
d913bb5d  build: add deploy_web.ps1
d27effaf  feat(hero-tasks): unified service-request flow
c14c5e9d  fix(taxi): real routed fare/distance, remove invented recent places
          (+ the two asset commits above)
```

Highlights of what those changed, so you don't re-investigate:
- **Taxi fare/route:** was straight-line (Haversine) distance + a fake
  bezier map line. Now uses `MapService.getRoute()` (Ola→OSRM) real road
  distance; fare based on it; shows "~" prefix / "Finding the best
  route…" while loading. Removed 4 invented "recent places" that booked
  rides to made-up addresses.
- **Location search:** Ola-first (OSM was winning and returning junk).
  Map picker (`location_picker_screen.dart`) + WhatsApp/Maps
  shared-location intake (`shared_location_inbox.dart`,
  `location_link_parser.dart`, PWA `share_target` + Android ACTION_SEND).
- **Onboarding:** intro video (first launch only), welcome screen
  (language pick + "sign in later"), English-only UI pass, icons resized
  from 402 KB each to sane sizes.
- **PWA:** Google sign-in COOP header; install fixed (manifest + service
  worker were missing from a stale build/web); update detection moved
  from the self-unregistering service worker to `/version.json` polling;
  "Check for update" in the drawer; the blank-screen race just fixed.
- **Boot speed:** 10 sequential Hive box opens → 3 critical parallel +
  the rest deferred past `runApp()`. Soundbox overlay scoped to Rewards
  only (was an app-wide per-frame ticker).
- **Hero booking:** lists ALL active bookings (was showing only the
  newest); voice input locale/dictation/double-text fixed.

## 4. NOT committed / NOT done — the pending work

Ordered by what to do first. Each block is self-contained; none started,
because context ran out and half-doing them would break a working app.

### 4a. NIZAM'S JOBS (not code)
- **Restrict the Ola Maps key** 🔴 URGENT. It's publicly readable at
  `my-allin1.web.app/assets/.env`. In the Ola/Krutrim console
  (`maps.olakrutrim.com`), add a domain/HTTP-referrer restriction to the
  key: `my-allin1.web.app`, `hero-allin1.web.app`, `localhost` (bare
  hosts, no `https://`, no `www.`). Then test that search still works in
  the app. Rotate the key after. (A Cloud Function proxy would hide it
  fully — separate, later.)
- **Deploy the blank-screen fix:** `.\deploy_web.ps1`, then test the
  drawer "Check for update" doesn't blank the app.

### 4b. HOME UI cleanup (#99) — Nizam asked for this, do it first
`dashboard_screen.dart`.
1. Merge "Custom Order" into Hero Booking; remove the separate "Call for
   Customise Order" banner (they mean the same thing).
2. Fix DUPLICATE content that reads as a bug: the top "Services" carousel
   shows the same 6 icons twice; the dark-purple horizontal strip repeats
   Mobile/Spare/AI/Broadband/Repairs/Delivery twice. Find the doubling
   (likely a `+ list` concat or a seamless-scroll marquee) and show each
   once.
3. Section emoji rows (🍔🍕🐔… under Food, etc.) aren't obviously
   tappable — either make them labelled tappable category chips or drop
   them.
LEAVE the "What do you need today?" section list alone — title + subtitle
+ chevron is clear and is the strong part of the screen.

### 4c. TAXI booking finetune (#98) — architecture, real cost saving
Nizam's WhatsApp-style plan (RTDB push for the live request, Firestore
only for the settled ride, no DB polling) is ALREADY the design:
- Hero listens to RTDB `hero_pings/{uid}.onChildAdded` — no polling. Good.
- `online_heroes/{uid}` in RTDB tracks who's online.
- `admin_ride_dispatch_service` pushes to RTDB, writes the ride to
  Firestore. RTDB = live signal, Firestore = record. Good.
GAPS to close:
1. **Customer still waits on Firestore.** `bike_taxi_screen.dart:~2124`
   opens a Firestore `.snapshots()` on `rides/{id}` to watch for the hero
   to accept — a live Firestore listener held open for the whole search.
   That's the "customer app disturbing the DB" cost. Move the accept
   signal to RTDB; read Firestore only once the ride is settled.
2. Booking writes straight to `collection('rides').add()` (line ~2093)
   before any hero has it. Consider writing the live request to RTDB
   first (cheap, ephemeral), persist to Firestore only on accept, so
   abandoned searches never touch Firestore.
3. Confirm `online_heroes` has an RTDB `onDisconnect()` so a hero who
   drops signal is auto-removed (else stale heroes get pinged).
4. Vehicle picker UX: 4 icons at entry, a list after locations set —
   Nizam wants that section neatened (layout pass).

### 4d. SELLER wiring (#95) — ~80% already built, just connect it
Decisions from Nizam: NO approval step (Gmail login + hotel
name/location/address = seller live immediately;
`SellerModel.status` already defaults to `'active'`); customer browses
sellers inside the existing food order page, below the form;
`CustomFoodOrderScreen` (service_requests) STAYS.
Already built & working: `seller_onboarding_screen`, `seller_menu_setup`,
`seller_dashboard` (has `listenToIncomingOrders`), and the customer
browse UI `category_screen.dart` → `SellerCard` → `SellerDetailScreen`
(752 lines: menu, cart, order). Three verified gaps:
1. **Seller location never captured.** `seller_onboarding_screen.dart`
   ~line 80 hardcodes `latitude:0.0, longitude:0.0`. Collects a text
   address, no coordinates. Every seller sits at (0,0). FIX: reuse
   `LocationService` + `location_picker_screen.dart`.
2. **`CategoryScreen` has no entry point.** Nothing constructs it; the
   dashboard 'food' tile goes to `CustomFoodOrderScreen`. FIX: mount the
   seller list inside the food page, below the form, grouped by category.
3. **Menu subcollection name mismatch.** Seller writes
   `sellers/{id}/menu_items`; `SellerDetailScreen` reads via
   `CategoryGatewayService.loadSellerProducts()` → `sellers/{id}/products`
   → menu comes back empty. FIX: standardise on `menu_items`.
4. Admin reads none of `sellers`/`menu_items`/`food_orders` — add an
   admin seller/order monitoring screen.

### 4e. LOCALIZATION (#94 then #93) — Nizam wants full Tamil+English
Current `LocalizationService.t()` falls back SILENTLY (missing Tamil →
English or raw key), which is how 83 of 91 screens ended up unlocalized
without anyone noticing. Plan:
- **#94 first:** migrate to Flutter ARB / gen-l10n (`lib/l10n/app_en.arb`
  + `app_ta.arb` + `app_tg.arb`, `flutter gen-l10n`,
  `AppLocalizations.of(context).x`). A missing key becomes a COMPILE
  ERROR — so future features can't ship without their Tamil string, which
  is exactly what Nizam asked for ("no more overnight localization
  work"). Add a guard script flagging raw `Text('...')` literals. Keep
  `LocalizationService` as the language-selection ChangeNotifier (welcome
  screen + settings drive it); it stops being the translation table.
  Don't break the ~8 screens already using `t()`.
- **#93:** migrate screens onto that foundation, priority order:
  dashboard → taxi journey → hero booking → rewards/play_zone/profile/
  settings → payment/checkout → auth/welcome → food/grocery/tech/custom →
  admin/seller (lowest). Whole-session job; keep the app compiling at
  every step.
Note: 4 Tamil strings intentionally remain — the language names in the
pickers (`தமிழ்`) and a code comment. Those are correct as-is.

### 4f. Smaller / lower priority
- **#96 Firestore streams:** 27 `StreamBuilder`s across 22 files build
  their stream inline in `build()`, so each rebuild re-opens the listener
  = a full re-read. No leaked listeners (audited — every `.listen()`
  cancels). FIX: hoist each into a `late final Stream _x = …;` field.
  Worst: admin dashboards (open all day), then `hero_screen`/`hero_home`.
- **#71 off-screen animations:** low value — the two `..repeat()` in
  dashboard are AnimationController-based (TickerMode already pauses on
  route change). Left deliberately.
- **Old/stale (confirm still relevant):** #10 SOS overlay dismiss+timeout,
  #16/#18/#19/#20 patch files, #32 FCM on hero_assigned.

---

## 5. First message for the new session

> Read HANDOFF.md — that's the full context. Follow the environment rules
> in it (no flutter build in your sandbox — I run it; verify every edit;
> explain in Tamil; never start a multi-file refactor you can't finish).
> Start with the HOME UI cleanup (#99): merge Custom Order into Hero and
> fix the duplicate strips.
