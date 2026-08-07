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
- **RTDB rules discipline**: `database.rules.json` defaults to
  `.read: false, .write: false` at the top level. Every `.ref('...')`
  path used anywhere in `lib/` needs its own explicit rule block, or
  every write to it silently permission-denies. When a hero/customer
  reports a "permission error" or a write that "does nothing," check
  this file FIRST — grep every `.ref('` path against the rules file's
  top-level keys before looking anywhere else.

## 10. Closeout & Verification Protocol

1. Run `flutter analyze` and ensure ZERO errors.
2. Run `graphify update .` to keep the AST graph current (as per Section 4).
3. Remove stale or contradictory text from documentation.
4. Ensure branch naming, versioning, and CHANGELOG updates are complete if applicable.

