# Allin1 Super App - Trae AI Developer Guidelines

## 1. Project Context & Brand Identity

- **Business:** NJ Tech (Mobile, Laptops & Electronic Gadgets Service Center), located in Erode, Tamil Nadu.
- **App Name:** Allin1 Super App.
- **Core Theme:** Premium Pink & White signature theme. Always utilize existing color variables (e.g., `kPink`, `kBg`, `kSurface`, `kText`).

## 2. UI/UX Design Standards

- **Inspiration:** Follow PhonePe, Spotify, and Zaaroz app design standards for premium feel.
- **Components:** \* Use rounded corners heavily (`BorderRadius.circular(16)` to `24`).
  - Keep layouts clean, breathable, and avoid cluttered elements.
  - Use optimistic UI updates for Wallets and Rewards.
- **Banners & Ads:** Implement auto-scrolling features (PageViews with Timers) for promotional banners at the top or bottom of tabs.

## 3. Coding & Execution Rules

- **Surgical Strikes Only:** NEVER rewrite or delete entire files unless explicitly instructed. Apply exact, localized patches to specific widgets or methods.
- **Zero Breakage:** Ensure new UI features (like buttons or carousels) integrate seamlessly without breaking existing layouts, `SingleChildScrollView` structures, or Stack positions.
- **No Hallucinations:** Do not invent non-existent third-party packages or dummy assets. Stick strictly to the provided codebase architecture and imports.

***

## 4. graphify Rules (Knowledge Graph Navigation)

This project has a graphify knowledge graph at `graphify-out/`.

Rules:

- Before answering architecture or codebase questions, read `graphify-out/GRAPH_REPORT.md` for god nodes and community structure.
- If `graphify-out/wiki/index.md` exists, navigate it instead of reading raw files.
- For cross-module "how does X relate to Y" questions, prefer `graphify query "<question>"`, `graphify path "<A>" "<B>"`, or `graphify explain "<concept>"` over grep — these traverse the graph's EXTRACTED + INFERRED edges instead of scanning files.
- After modifying code files in this session, run `graphify update .` to keep the graph current (AST-only, no API cost).

## 5. Repository Knowledge & Durable Memory (DOCS-INDEX)

- **Agent Neutrality:** Agents must prioritize durable repository contracts (`AGENTS.md`, maps) over conversational memory. Do not rely on chat history for architectural rules.
- **Read Before Editing:** Agents MUST read this root `AGENTS.md` and any relevant child `AGENTS.md` before making changes.
- **Update After Editing:** If a meaningful change affects architecture, permissions, routing, or workflows, the agent MUST update this `AGENTS.md` (or the child doc) before concluding the task.

## 6. GitHub, PR, & Versioning Workflow

Treat feature requests and bug reports as issue work.

- **Branch Naming:** Use `agent/issue-<number>-<slug>` for existing issues, or `agent/<type>-<slug>` for issue-less work.
- **Versioning:** Use semantic versioning (vX.Y.Z).
- **Changelog:** Record user-facing, product, architecture, and workflow changes in `CHANGELOG.md` before a merge or release.

## 7. Hierarchical Documentation & Design Contracts

- **Child Docs:** When a folder becomes a durable boundary with its own specific rules, create a nested child `AGENTS.md` inside that folder. Child docs control local work details but cannot weaken root DOCS-INDEX rules.
- **Design Contracts:** Any major visual/UI project should route layout and brand work to a `Design.md` file before scaffolding the actual code.

## 8. Notification & Ping Timing Contracts (Hero App)

These are the CURRENT, verified values in code — keep this section in
sync whenever any of these constants change, so future agents don't
have to re-derive them from source:

- **Service-request broadcast ping expiry:** 90 seconds
  (`kServiceRequestPingExpirySeconds` in
  `lib/services/service_request_service.dart`). Applies to Hero
  Booking, Custom Order, Custom Food Order, and Grocery Order pings.
- **Ride-taxi ping staleness window:** 10 seconds (hardcoded as
  `pingExpiresAt - 10000` in `hero_home_screen.dart`'s
  `_listenForHeroPings`). Used only to derive when a ride ping was
  created from its expiry timestamp.
- **Ride-alert local-notification auto-dismiss:** 15000ms
  (`timeoutAfter: 15000` in
  `lib/services/hero_ride_notification_service.dart`). This is an
  Android notification auto-dismiss timer, NOT a ping or ringtone
  timeout — do not confuse it with the two values above.
- **Hero-side notification de-duplication window:** 18 seconds
  (`_deduplicationWindow` in `hero_ride_notification_service.dart`),
  backed by `HiveCache` (persists across the FCM background-isolate /
  main-isolate boundary, unlike a plain static field). Prevents the
  same ride/service ping from firing a duplicate ringtone+notification
  when the hero backgrounds and then reopens the app shortly after a
  push already arrived.

## 9. Notification Architecture Contracts (read before touching any push/alert code)

- **No Cloud Functions / no Blaze plan — deliberate decision, not TODO.**
  Two dormant Cloud Function files exist (`functions/notifyAdminOnNewRide.ts`,
  `functions/notifyAdminOnNewServiceRequest.ts`, exported from
  `functions/index.ts`) but must NOT be deployed unless Nizam explicitly
  says he's upgraded to Blaze. `firebase deploy --only functions` should
  not be run casually.
- **Admin app notifications are 100% client-side, free-tier**: a
  low-priority Android foreground service
  (`lib/services/admin_foreground_service.dart`) keeps the process alive
  while an admin is logged in, so a live Firestore listener
  (`lib/services/admin_live_alert_service.dart`, watching `rides`/
  `service_requests` for docs created after the listener started) can
  fire a local notification
  (`lib/services/admin_alert_notification_service.dart`) even with the
  app closed. Ceiling: force-stopping the app from Android Settings, or
  a device reboot without reopening the app, stops this until the app
  is opened again — accepted trade-off, do not "fix" by silently
  re-introducing Cloud Functions.
- **Hero's ride/service-request alert channel** already plays a loud
  custom tone (`ride_alert.mp3`) through the Android ALARM audio stream
  (`audioAttributesUsage: AudioAttributesUsage.alarm` in
  `AndroidNotificationDetails`) — this alone bypasses silent mode/DND.
  Never add a second, separate `FlutterRingtonePlayer`/system-alarm call
  alongside a notification that already has this — that's a
  double-sound bug already found and fixed once this project
  (`hero_ride_notification_service.dart`'s `showRideAssigned`).
- **`flutter_local_notifications` v21 API**: `_plugin.show()` takes
  NAMED parameters (`id:`, `title:`, `body:`, `notificationDetails:`),
  not positional ones. A positional call is a build error, not a
  runtime warning.
- **Ride-taxi ping window is now 90 seconds, matching service-request
  pings** (changed Aug 8 2026, Task 2 broadcast dispatch — see below).
  If you ever see `- 10000` near `pingExpiresAt` in
  `hero_home_screen.dart`'s `_listenForHeroPings`, that's the OLD
  15s-per-hero sequential-model magic number and is a bug — it must be
  `- 90000` to match the current broadcast window, or the "ignore
  pings that existed before this listener attached" dedup silently
  stops working and dismissed rides can re-pop the Accept dialog.
- **RTDB rules discipline**: `database.rules.json` defaults to
  `.read: false, .write: false` at the top level. Every `.ref('...')`
  path used anywhere in `lib/` needs its own explicit rule block, or
  every write to it silently permission-denies. When a hero/customer
  reports a "permission error" or a write that "does nothing," check
  this file FIRST — grep every `.ref('` path against the rules file's
  top-level keys before looking anywhere else.

## 10. Unified Popup, Admin Lazy-Load & KYC Guard Contracts (Aug 8 2026)

- **Unified Accept/Minimize/Reject popup**: both the taxi ping dialog
  (`_PingCountdownDialog` in `hero_home_screen.dart`) and the service-
  request dialog (`_doShowServiceDialog`) now expose the same 3-button
  contract. MINIMIZE never touches the RTDB ping node (request stays
  valid for the rest of its window) — only REJECT removes it.
- **Service-request location display**: grocery/food/hero-booking DO
  capture pickup/delivery locations at creation
  (`grocery_order_screen.dart` -> `details['deliveryAddress']`;
  `custom_food_order_screen.dart` -> `details['shopAddress']`/
  `details['deliveryAddress']`; `hero_booking_screen.dart` ->
  `details['fromLocation']`/`details['location']`) and it already
  reaches the hero's RTDB ping intact. `_serviceRequestLocationLines()`
  in `hero_home_screen.dart` is what renders it — if a location ever
  looks missing from the popup, check that function's field-name
  mapping first, not the write path.
- **Admin lists must never open per-row live listeners.** Two real
  instances of this were found and fixed: `admin_ride_tracking_screen.dart`
  (was an unbounded `.snapshots()` on `rides`, now a one-time
  `.get(limit: 50)` + pull-to-refresh) and
  `admin_service_requests_screen.dart` (was opening a live RTDB
  `active_service_requests/{id}` listener PER RENDERED CARD, now
  removed — the list only shows the Firestore-derived status). Live
  per-task data (RTDB location/transient-status merges) must only ever
  be opened by a detail/tracking screen after the admin taps into that
  one specific task — see `admin_ride_tracking_detail_screen.dart` and
  `service_request_tracking_screen.dart` for the correct pattern.
- **Hero KYC approval is now gated**, not automatic. Both approve paths
  (`hero_approvals_screen.dart`'s `_approveHero`/`_missingKycItems`, and
  the AI co-pilot's `AdminKycWriteService.approveHero`) check
  `selfieUrl`, `aadhaarDocUrl`, `panDocUrl`, `licenseDocUrl`, `name`,
  `phone` are non-empty before allowing approval — these two checks are
  a deliberate byte-for-byte mirror (per that file's own header
  comment) and MUST be kept in sync if the required-fields list ever
  changes.

- **A leftover service worker from an old deploy can permanently shadow
  Firebase Hosting's `no-cache` headers on a specific device.** If
  someone reports a bug that a fresh rebuild+redeploy doesn't fix
  (e.g. Aug 8 2026's Hero PWA selfie `MissingPluginException` that
  persisted after multiple correct rebuilds), suspect a stale
  `flutter_service_worker.js` still controlling that browser/device
  from before `pwa_fallback_sw.js` was introduced — a controlling SW's
  fetch handler runs before Cache-Control is ever consulted, and
  survives normal hard-reloads. `web/index.html` now self-heals this
  automatically (unregisters anything that isn't
  `pwa_fallback_sw.js` on every load), but any device that already hit
  this needs one more visit for the fix itself to take effect.

- **Hero notification payloads now carry a `type` field** (`'ride'` or
  `'service_request'`) — added Aug 8 2026 to fix a real bug where
  EVERY notification tap (regardless of real type) wrote the tapped id
  into the ride-only `kPendingHeroRideIdKey`/`kPendingHeroAcceptRideIdKey`
  SharedPreferences keys, so tapping a grocery/food/hero-booking
  notification silently never opened its accept dialog (the id got
  looked up in the wrong Firestore collection by the ride-only
  consumer). Every `showRideAssigned(...)` call site for a
  service-request push MUST pass `pushType: 'service_request'` — grep
  for `showRideAssigned(` before adding a new call site and check
  whether it needs this param.
- **Every ride/service-request local notification now has 3 actions:
  VIEW / ACCEPT / MINIMIZE** (`hero_ride_notification_service.dart`'s
  `viewRideActionId`/`acceptRideActionId`/`minimizeRideActionId`).
  MINIMIZE deliberately writes NO pending-* key — that's what stops the
  accept dialog from opening; the request itself stays untouched (no
  reject write), mirroring the in-app dialogs' own MINIMIZE button.
  VIEW and ACCEPT both open the dialog; ACCEPT additionally fast-accepts
  for rides only (service requests still need the dialog's own ACCEPT
  tap).
- **`didChangeAppLifecycleState`'s resumed-case handler
  (`hero_home_screen.dart`) must never be gated on `_isOnline`.** It
  was previously `if (!_isOnline || _user == null) return;` at the top
  of the whole method — since presence (`_isOnline`) routinely reads
  false for a moment right after a background→foreground transition
  (the RTDB WebSocket drops while backgrounded), this silently skipped
  `_consumePendingRidePush()`/`_consumePendingServiceRequestPush()` on
  exactly the most common real path: hero backgrounds the app, gets a
  push, taps the notification to bring it forward. Fixed to only gate
  on `_user == null`.
- **`HeroRideNotificationService.initialize()` now calls
  `getNotificationAppLaunchDetails()`** to recover a tap that
  cold-launched a fully-killed app — `onDidReceiveNotificationResponse`
  never fires for that specific tap (nothing was listening yet). Without
  this, a hero tapping ACCEPT directly from the lock screen on a killed
  app silently downgraded to "just open the dialog" instead of
  fast-accepting, since `kPendingHeroAcceptRideIdKey` was only ever set
  inside the (never-called-on-cold-launch) response handler.
- **`_HeroSetupGate` in `main_hero.dart` must never decide "needs
  registration" from `users/{uid}.isSetupComplete` alone.** It now
  falls back to checking `heroes/{uid}.approvalStatus` first if
  `isSetupComplete` reads false — an already-submitted-but-not-yet-
  approved hero must never be sent back through the registration form.
  `hero_register_screen.dart`'s `_submitRegistration()` now writes both
  `heroes/{uid}` and `users/{uid}` in a single `WriteBatch` (was two
  independent `.set()` calls) specifically so this desync can't happen
  for a fresh submission going forward.

- **Hero selfie capture on web (`selfie_capture_screen.dart`) no longer
  uses `camera`/`image_picker` at all** — after extensive investigation
  those two plugins persistently threw `MissingPluginException` in the
  deployed Hero PWA despite every structural check (manifest, pubspec,
  plugin registration, fresh builds/deploys) coming back correct. The
  one plugin proven to actually work on web in this exact deployment is
  `file_picker` (used by the 3 KYC doc uploads on the same registration
  flow) — `_initCamera()` now skips straight to the file-picker fallback
  on `kIsWeb` instead of attempting `availableCameras()`, and
  `_useGalleryFallback()` uses `FilePicker.platform.pickFiles(...)` on
  web instead of `ImagePicker().pickImage(...)`. Native (Android/iOS)
  behavior is completely unchanged — still live in-app camera preview
  via `camera`, gallery fallback via `image_picker`. If `camera`/
  `image_picker` are ever confirmed working on web again (e.g. after a
  Flutter/plugin upgrade), this can be revisited — but don't remove the
  `kIsWeb` branch without re-testing on an actual deployed PWA first.

- **`hero_approvals_screen.dart` now has a Pending / Rejected tab
  toggle** (Aug 8 2026) — it used to ONLY ever query
  `approvalStatus == 'pending'`, so a rejected hero vanished from admin
  view entirely with no way to reverse the decision, while
  `hero_pending_screen.dart` signs that hero straight out with a
  "Contact Admin" message and no in-app path back in. The Rejected tab
  reuses the exact same `_HeroApprovalCard`/`_approveHero`/`_rejectHero`
  methods as Pending — re-approving a rejected hero from this tab
  passes the same KYC/selfie completeness guard as any other approval
  (their original selfie/doc URLs are still on the doc, reject never
  clears them), so it just works the same way approving a fresh
  submission does.

## 11. Closeout & Verification Protocol

1. Run `flutter analyze` and ensure ZERO errors.
2. Run `graphify update .` to keep the AST graph current (as per Section 4).
3. Remove stale or contradictory text from documentation.
4. Ensure branch naming, versioning, and CHANGELOG updates are complete if applicable.

