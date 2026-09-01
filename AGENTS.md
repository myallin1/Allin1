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

- **`custom_hotel_orders` now has a `firestore.rules` block (Aug 20
  2026)** — it previously had NONE, so every write silently hit the
  catch-all `if false` deny and the custom-hotel checkout died with
  permission-denied before `createServiceRequest` was ever called.
  Contract: create = `isRealUser()` with matching `customerId` (or
  admin); read = ordering customer / owning seller (`sellerId`) / admin;
  update = customer may ONLY merge `serviceRequestId`+`updatedAt` via a
  `hasOnly()` pin (linkServiceRequest), seller/admin may update; delete
  = admin only. If `CustomHotelService` ever writes new fields on
  create/update, re-check this block.

- **Custom-food menus render ONLY inside the seller's own shop page
  (Aug 20 2026)** — the duplicated global "Custom Hotels" grids in
  `food_hub_screen.dart` and `custom_food_order_screen.dart` were
  removed. A seller's `custom_hotels/{sellerId}/items` are now surfaced
  exclusively through `seller_detail_screen.dart`'s "Custom Menu" card
  (which opens `CustomHotelViewScreen` for that one seller). If you add
  a new customer-facing entry to `custom_hotels` data, it must go
  through the seller's own menu — do NOT reintroduce a global
  custom-hotel grid.

## 11. Known Bugs & Audits (Aug 27 2026)

- **Custom Hotel Order Payout Bug (DO NOT FIX UNLESS INSTRUCTED):** In `service_request_service.dart` (`_completeAndCreditSeller`), the system attempts to credit a seller using `details['subtotal']`. However, `custom_hotel_view_screen.dart` stores the order value as `details['totalAmount']`. If an admin manually completes the task without a hero-entered `finalAmount`, `creditAmount` evaluates to `0.0`, resulting in a ₹0 payout for the seller. **This is a known structural bug documented for future reference.**

## 12. Chitti AI Agent Contracts (Aug 27 2026)

Chitti's tool-calling is now driven by **one registry**, not by lists
repeated per surface. Read this before adding, removing or renaming any
Chitti tool.

- **`lib/services/chitti/chitti_tool_registry.dart` is the single source
  of truth.** It answers all three questions the old code answered in
  three separate places: is this action real (`isKnownAction`), may this
  app variant run it (`isAllowedFor`), and must a human confirm it
  (`requiresConfirmation`). Adding a tool there makes it live in BOTH
  the full chat screen and the floating overlay bubble at once.

- **Never reintroduce a per-surface allow-list.** The reason Chitti only
  ever acted on transport was that `guru_overlay_service.dart` listed
  six actions while the model was offered nine — `create_service_request`
  and `report_app_bug` were called correctly and then silently dropped.
  If you find yourself writing `if (action != 'x' && action != 'y')`,
  the registry is what you actually want.

- **`lib/services/chitti/chitti_section_registry.dart` owns every
  navigable section**, per variant, and the `navigate_to_section` enum is
  DERIVED from it. Do not hand-write section keys into a tool schema or
  a `switch` — add a `ChittiSection` instead.

- **`lib/services/chitti/chitti_action_executor.dart` owns what each
  tool DOES.** Hosts keep only what genuinely differs: rendering a
  message and pushing on their own Navigator. Two actions stay with the
  hosts by design — `check_and_update_app` (needs the host's PWA/native
  branch) and `analyze_screen_with_vision` (needs the attached image
  bytes, which only the chat screen has).

- **Token budget is a real constraint.** `routeDomains()` is local
  keyword matching, costs zero tokens, and sends only the 1–3 relevant
  tool groups. Do not replace it with "send everything" — the tool block
  ships on every message, and a bigger menu also raises wrong-tool picks.

- **Confirmation gate: money and cancellations only.** Today that is
  `create_service_request` and `cancel_order`. Everything else —
  navigation, every read, status toggles, bug reports — executes
  immediately (the Autonomous Interaction Rule). This is asserted in
  `test/chitti_tool_registry_test.dart`; changing it should mean changing
  that test deliberately.

- **Never let Chitti write state a screen owns.** Going online as a Hero
  needs a location fix, the RTDB radar entry and the ping listeners —
  writing the flag alone produces a hero who looks online to dispatch and
  receives nothing. `chitti_host_bridge.dart` is how a mounted screen
  lends Chitti its own logic; when no handler is registered, navigate
  there and say so instead of guessing.

- **Reads return finished sentences, never raw data**
  (`chitti_status_lookup_service.dart`,
  `chitti_role_lookup_service.dart`). A model handed a map will
  paraphrase a number wrong; a model handed a sentence relays it. Every
  query copies a shape an existing screen already uses, and filters
  date/status locally rather than depending on a composite index that may
  not be deployed — on Spark, a missing index is a hard failure.

- **Chitti reads the screen from the SEMANTICS TREE, never by OCR.**
  `chitti_screen_reader.dart` walks Flutter's accessibility tree for
  labels, values, buttons and fields — the original text, with roles,
  on web and native, for zero tokens. OCR was evaluated and rejected:
  we own the widget tree, so rendering it to pixels and guessing it
  back throws away perfect data (and Tamil OCR is materially worse),
  ML Kit does not run on the PWA, a screenshot costs a raster plus
  encode on budget phones, and screenshotting wallet balances and KYC
  documents is a privacy problem. OCR stays for content we do NOT own
  — a customer's DMart screenshot — which already has a vision path.

- **`ensureSemantics()` must be released.** The reader enables
  semantics, waits one frame, reads, and disposes the handle in a
  `finally`. Holding it open taxes every frame for the rest of the
  session. It is a per-request read, never a poll.

- **A new screen must work with nobody registering it.** That is the
  point of `chitti_screen_advisor.dart`: it offers the screen's OWN
  buttons as chips and names the blank field the customer still has to
  fill. The section registry is a nicety on top, not a prerequisite —
  if a change makes an unregistered screen useless to Chitti, the
  change is wrong.

- **The personality has a gate, and the gate is pessimistic.**
  `ChittiBuddy.isSafeMoment()` silences quips on money, SOS,
  cancellations, KYC, complaints and failures — including politely
  phrased ones ("I couldn't place that order" contains no failure
  word; the tests caught exactly that). Quips fire ~1 in 3, never
  twice running, and always AFTER the work. A missed joke costs
  nothing; a joke beside a lost payment costs the customer's trust.

- **The spoken welcome carries the day's quote from
  `DailyQuoteService`** — the same line the app displays. Never add a
  second quote list: hearing one quote and reading a different one is
  worse than silence.

## 13. Local-First Data Contracts (Aug 28 2026 — the WhatsApp model)

The customer's data lives on their phone and in THEIR Google Drive. Our
database holds what admin needs, written once. Breaking any of these
costs real money on a Spark plan and was measured, not guessed.

- **Read from the device, not the database.** Every Chitti lookup goes
  through `ChittiLocalRead`, which serves from Firestore's on-device
  cache (not billed, works offline) and reaches the server only when the
  cache is empty. Before this, one hero asking "how much did I earn
  today" cost **200 document reads**; a hundred heroes asking twice a day
  was 40,000 against a 50,000/day free quota, for that question alone.
  Never add a bare `.get()` to a Chitti path.

- **The wallet is the one exception, and it is deliberate.** Money stays
  server-authoritative so a balance cannot be edited on-device. It is
  still not read on every glance: `ChittiLocalRead.wallet()` goes to the
  server only when `markWalletChanged()` has been called, and clears its
  dirty flag only on a read that actually reached the server — a cache
  fallback must never leave a stale balance looking authoritative.

- **One Firestore write per activity, on completion.** Analytics used to
  emit `intent_requested` AND `intent_resolved` — two documents for one
  event, ~40,000 writes/day at a thousand customers against a 20,000/day
  quota, and it fired even for purely on-device Tier 1 actions, so the
  cheapest path in the app was the one paying the bill.

- **Backups go to the customer's Drive, never to Firestore.**
  `ChittiBackupService` writes one JSON file to Drive's private
  `appDataFolder`. In: chat history, Chitti's memory, order memory,
  recent places, theme/language/voice. **Out: the wallet and any API
  key** — a balance in a file the customer controls is a balance the
  customer can edit. Both are asserted in
  `test/chitti_backup_service_test.dart`.

- **A backup carries `ownerUid`, and restore checks it.** A phone can be
  shared, and the Google account on the device is not necessarily the
  account in the app. Without the check, one person's history silently
  overwrites another's. Auto-backup requires a real (non-anonymous)
  account for the same reason.

- **Restoring must rehydrate in-memory caches.**
  `ChittiOrderMemoryService` reads its box once at boot, so writing Hive
  alone leaves Chitti not remembering the customer until the app is
  killed — precisely when the feature is meant to prove itself.
  `applyPayload()` calls `preload()`; keep it.

- **Tier 1.5 answers questions offline.**
  `chitti_local_answer_service.dart` answers "what is this page?", "what
  can you do?" and "how do I X?" from `kChittiSections` / `kChittiTools`
  / `currentScreen` — no API call. It runs only when there is no key
  (with one, the model answers better) and BEFORE the failure message.
  It must keep returning null for anything it does not genuinely know:
  a confidently wrong answer about the customer's own app is worse than
  admitting the full AI is unreachable. Never restore a bare "Chitti
  isn't available" dead end — say what still works.

- **Screen awareness comes from the Navigator, and has TWO paths.**
  Where the push site holds the widget, `ChittiNav` writes the registry
  label into `RouteSettings.name`. Everything else — the dashboard's
  direct pushes, Chitti's own navigation, every future screen — arrives
  unnamed and falls back to reading the screen's own title from the
  semantics tree. Both feed `ChittiScreenObserver`, which keeps
  `currentScreen` in step (pop restores from `previousRoute`, so there
  is no side map to drift). Do not delete the unnamed fallback: without
  it, coverage silently collapses to the handful of named routes, which
  is what the Aug 28 re-audit found.

- **Anything that opens a screen must carry its label.**
  `ChittiActionResult.openScreenLabel` travels with `openScreen` because
  a `WidgetBuilder` cannot be asked what it builds. Dropping it means
  Chitti opens a page and then cannot say which page you are on.

- **One voice at a time.** Five `FlutterTts` instances exist (chat,
  overlay, welcome, settings preview, admin). `ChittiVoiceService.apply()`
  claims the speech channel and stops whoever had it — the likely
  collision is the first-touch welcome against whatever that first touch
  opened. Every surface gets this by configuring its voice before
  speaking; do not speak without calling `apply()` first.

- **A modal must never race the mic.** The voice claim sheet is awaited,
  not fire-and-forget: unawaited, the mic began recording behind a sheet
  the customer had not finished reading.

- **`ChittiSection.screenType` must match what `builder` returns.** It
  is declared because a `WidgetBuilder` cannot be asked what it builds
  without building it, and it is what turns a pushed widget back into a
  section. A wrong type silently breaks screen awareness for that page.

- **Tier 1 runs before the model, always.**
  `chitti_local_intent_engine.dart` is a scored intent matcher over the
  same registries the cloud path uses — not a language model. It resolves
  navigation, every read, cancellations, language switches and the
  hero/seller toggles on device, in under a millisecond, offline, for
  zero tokens. Both surfaces call it before `extractAgentAction`, and
  both feed the result into the SAME `_dispatchAgentAction` the model
  feeds, so a local action and a model action are indistinguishable
  downstream. Analytics carry a `source` field (`local_engine` / `groq`)
  so the real hit rate is measurable rather than guessed.

- **Do not extend Tier 1 to slot-extracting tools.**
  `create_service_request`, `report_app_bug` and
  `seller_set_item_availability` need free text pulled out of a sentence
  and belong to the model. A wrong guess there places a wrong paid order
  or silently hides the wrong menu item; falling through costs a few
  hundred milliseconds. A Tier 1 miss must cost latency, never
  correctness — that is why `confidenceThreshold` is set high.

- **Section aliases are nouns, intent phrases are verbs.** Sections live
  in `chitti_section_registry.dart`'s `aliases`; tool phrasings live in
  the engine's `_rules`. Adding a section must not require editing the
  engine.

- **An offline LLM was evaluated and rejected (Aug 28 2026).** ~550MB for
  the smallest usable model against a 50-80MB APK; unusable on the PWA
  (WebGPU, ~1GB browser memory, cross-origin isolation); poor colloquial
  Tamil at that size; unreliable tool selection across ~27 tools. The
  header of `chitti_local_intent_engine.dart` records this so it is not
  re-litigated. Chitti's intent space is closed, which makes matching the
  correct tool for the job.

- **The spoken welcome is tap-gated, not on-open.** Browsers discard
  speech synthesis issued before a user gesture, and the customer build
  is a PWA — greeting from `initState` would pass a native APK test and
  silently do nothing for most real customers. `ChittiFirstTouchGreeter`
  wraps the app in `main_customer.dart` and fires on the first
  pointer-down. Never "simplify" it back to an on-open call.

- **Every question Chitti asks must carry tappable options.** Executor
  paths that ask something populate `ChittiActionResult.suggestions`, and
  the conversational prompt makes the `[SUGGESTIONS: ...]` line mandatory
  whenever the reply asks a question. Both surfaces already render these
  as chips; the failure mode to avoid is a question the user has to type
  a free-text answer to.

- **Chitti is never gated behind an API key.** Three gates used to hide
  it: the whole-chat `_SuperHeroActivationScreen` swap, the mic's
  `isProUnlocked` claim sheet, and `_isGatedApp()` hiding the FAB for
  Hero/Seller. All removed — 20 of 25 tools run on device. The
  activation flow is still reachable from the banner in the chat, so
  unlocking full model-backed chat is one tap; do not re-add a blocking
  gate.

- **Swapping the splash logo means THREE sources, and never editing
  `launch_background.xml` by hand.**
  1. `web/splash_logo.png` + `web/icons/splash_logo.webp` — what
     `web/index.html` actually loads. (`assets/images/myallin1_splash_logo.*`
     is only `BrandedLoadingScreen`, an admin/hero fallback frame — a
     customer never sees it, so changing only that changes nothing.)
  2. `assets/splash/splash_logo.png` — the SOURCE for native, then run
     `dart run flutter_native_splash:create`. Android and iOS launch
     resources are generated; editing `launch_background.xml` directly
     works until the next regeneration silently reverts it. Keep the
     428x428 canvas with the art inside ~62% — Android 12+ masks the
     splash icon to a circle and clips anything wider.
  3. The launcher icon is separate again (`assets/images/app_icon.png`,
     via flutter_launcher_icons) — do not touch it when swapping the
     splash.

- **`setSpeechRate` means different things on web and native.**
  flutter_tts documents 0.0–1.0, and Android (`rate * 2.0`) and iOS
  (AVSpeech, 0.5 = normal) honour it — but web assigns the value
  straight to `SpeechSynthesisUtterance.rate`, where **1.0** is normal.
  Every profile rate therefore ran at half speed on the PWA until
  `ChittiVoiceService.platformRate()` was added. Write profile rates on
  the 0.5-is-normal scale and let that function convert; never call
  `setSpeechRate` with a raw profile value. Pitch needs no such
  handling — all three pass it through with 1.0 as normal.

- **Never pitch-shift UP to sound less feminine.** Pitch moves the
  fundamental, not the formants, so raising it on a female voice makes
  it childlike, not male; lowering it too far makes it sound like a
  slowed recording. Take drag out with RATE, keep pitch moderate, and
  treat the voice picker as the real fix. `ChittiVoiceService.apply()`
  logs when no male voice exists — that log is the diagnosis.

- **`awaitSpeakCompletion` can never fire on web.** Both `_speak()`
  implementations wrap `speak()` in a 20s timeout for exactly that
  reason; without it the hands-free loop freezes with no error. Do not
  remove the timeout, and do not "fix" a voice hang by lengthening the
  silence timer — that makes it worse.

- **The overlay panel stacks by insertion order.** Anything shown after
  it lands on top, so `bringToFront()` (remove + re-insert) is what puts
  it back above dialogs. Position is unrelated. The positioning clamp
  must keep using `_kPanelWidth`/`_kPanelHeight` with the limit floored
  at zero — `num.clamp` throws when lower > upper, which is a real crash
  in landscape.

- **Address terms are noise; stated needs are intents.** `_fillerWords`
  in the intent engine strips dude/bro/machan/boss/பாஸ் and trailing
  da/na/ya so casual speech collapses onto phrasing the tables already
  know. Separately, a stated NEED with no service named ("pasikuthu",
  "phone odanjiduchu", "veetuku poganum") maps straight to an intent.
  Keep those phrases multi-word and specific — a bare "pasi" would fire
  on half the sentences in Tamil.

- **Hands-free loop: the echo guard is load-bearing.** Barge-in means
  the mic stays open while Chitti speaks, so on a phone speaker it hears
  its own TTS. `ChittiConversationController.isSelfEcho()` discards
  anything overlapping what Chitti is currently saying; without it,
  Chitti answers itself forever and burns the quota doing it. `_speak()`
  must keep using `awaitSpeakCompletion(true)` — reopening the mic
  before playback finishes recreates the loop.

- **The loop has three exits and the user picks the policy.** Stop word
  (English/Tanglish/Tamil), silence, or task completion.
  `ChittiConversationPrefs` stores auto-stop (default) vs call mode. A
  pending confirmation always keeps the session alive — never hang up
  inside Chitti's own question.

- **The mic is not API-gated.** `isAiActivated` used to `return` out of
  `_onMicTapped`, so voice did nothing without a key while typing worked
  fine. Since Tier 1, most spoken requests resolve on device; do not
  re-add that gate.

- **Speech input: `ta` and `tg` are NOT the same locale.** `ta` is
  Tamil, `tg` is Tanglish — someone who picked Tanglish has told us they
  code-switch, and a Tamil-constrained recogniser mangles the English
  half of "Bike book pannu". `ChittiVoiceService.speechLocaleFor()` owns
  this: `ta` → Tamil, `tg` → `en-IN`, everything else → device default.
  It is a SPLIT, not a flip — sending everyone to `en-IN` re-opens the
  fragmented "ErodeErode busErode bus stand" bug that made `ta-IN` get
  forced originally.

- **`speech_to_text` already uses Google's networked recogniser** — the
  same engine Gboard's mic uses. `onDevice` defaults to false and is now
  stated explicitly in both surfaces. Do not "switch to Gboard for better
  accuracy": the engine is identical, and Gboard's real advantage
  (editable text) is covered by leaving an unconfident transcript in the
  input box. `RecognizerIntent` was rejected — Android-only, so it does
  nothing on the PWA, which is the primary customer surface.

- **Use the recogniser's `alternates`, do not throw them away.**
  `ChittiLocalIntentEngine.resolveBest()` tests every candidate
  transcription against the intent tables and takes the best confident
  match. The recogniser ranks by how the audio sounded; only the app
  knows which sentences are plausible here. This costs nothing and is
  only possible because Tier 1 exists.

- **Voice goes through Tier 1, not a booking-only parser.** A confident
  match executes immediately; anything else lands in the input box with
  a "I heard: ... — send it, or fix it first" turn. Never auto-send an
  unconfident transcript: it burns an API call and answers a question the
  customer never asked.

- **Voice lives in `chitti_voice_service.dart`, and only there.** Both
  Chitti surfaces used to carry their own `_applyChittiMaleVoice()`, and
  both matched the substring `"male"` against the voice name — which
  Google's Android/Chrome voices (`ta-in-x-tag-local`,
  `en-in-x-ene-network`) never contain, so both always fell through to
  pitching the same female voice down. Voice selection uses a real
  per-engine name/code table with explicit female vetoes, a saved
  per-device override, and three tone profiles. Never re-add a
  `contains('male')` check; add codes/names to the tables instead.

- **Voice availability is device-dependent, so the picker is the real
  fix.** `AiSettingsScreen` lists the voices that exist on THIS device,
  previews them, and pins one. The heuristic is only the default.

- **The "naughty Chitti" character is bounded.** Cheek is allowed in the
  framing and never in the facts, and it switches off entirely for
  money, cancellations, emergencies and complaints. Both prompts in
  `guru_api_service.dart` (conversational and one-line tool replies)
  carry the same rule — changing one without the other produces two
  different-sounding assistants.

- **The Admin Quick Task co-pilot is a separate pipeline**
  (`admin_quick_task_service.dart` + `admin_ai_tools_schema.dart`, 5
  tools, its own propose-then-confirm write gate). It is deliberately NOT
  part of this registry. The `admin` variant here only gets the Chitti
  bubble's own tools — which, since Aug 28 2026, includes oversight
  reads (see below), not navigation alone.

### 12b. Variant parity (Aug 28 2026)

Chitti must be able to say something substantive in EVERY build, not
just the customer one. Admin previously had three tools — navigate,
report a bug, check for updates — so it could open the approvals screen
and then had nothing to say about what was on it, while its own persona
promised exact figures.

Rules when adding a tool for `hero` / `seller` / `admin`:

- **Two places, not one.** `chitti_tool_registry.dart` is what the
  MODEL sees; `chitti_local_intent_engine.dart` is what works with no
  API key. Registering in only the first leaves the tool unreachable
  offline — and the admin build is the one most likely to run without a
  key configured. `chitti_offline_capability_test.dart` fails if a tool
  is classified offline-capable with no phrasing that reaches it.
- **Admin reads are capped and cache-first.** Admin queues are
  unbounded; counting one exactly means reading every document. Use
  `ChittiLocalRead` with `_adminCountCap`, and render through
  `_countLabel()` so a capped count says "100 or more" rather than
  claiming to be exact. On the Spark plan's 50,000 reads/day, one owner
  repeatedly asking "how many pending?" must not spend a meaningful
  slice of the platform's daily budget.
- **Oversight tools are reads only.** No tool in the `admin` domain
  writes, so none needs a confirmation gate — a wrong call yields a
  wrong answer, never a wrong action.
- **`ChittiDomain.admin` is separate from `support` on purpose.**
  Support is "something is broken, help me"; admin is "how is the
  business doing". Folded together, the model reached for
  `report_app_bug` on every admin question containing "problem".
- **Enquiries reach sellers too** (`admin_open_enquiries` is in both
  variants). Nizam's rule: a price enquiry is monitored on "seller and
  admin phone". A seller who cannot see the lead cannot answer it.

### 12c. Chat history is capped

`ChittiChatHistoryService.maxSavedMessages` (300) bounds the saved
conversation, keeping the RECENT tail. This is not a memory
optimisation — the box is part of the Drive backup, so unbounded
history means a backup that grows forever inside the CUSTOMER's own
15GB quota, re-uploaded from their phone. Trimming the wrong end would
make Chitti remember the oldest conversation and forget what was said a
minute ago.

## 13. Closeout & Verification Protocol

1. Run `flutter analyze` and ensure ZERO errors.
2. Run `graphify update .` to keep the AST graph current (as per Section 4).
3. Remove stale or contradictory text from documentation.
4. Ensure branch naming, versioning, and CHANGELOG updates are complete if applicable.

