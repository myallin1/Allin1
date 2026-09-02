// lib/main_customer.dart
// Erode Super App - CUSTOMER PWA Entry Point
// Fixed: back button logout + routing + geolocator web crash

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
// hide Category (Aug 19 2026): flutter/foundation.dart exports its own
// `Category` annotation class (dart:core Category-adjacent metadata
// type), which collides with our own `Category` enum imported below
// from category_gateway_service.dart — dart2js refused to compile with
// "'Category' is imported from both ...". Hiding Flutter's unused
// annotation type resolves the ambiguity without touching the app's
// own Category enum or any of its ~dozens of call sites.
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart' hide Category;
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app_navigator.dart';
import 'config/api_config.dart';
import 'config/app_variant.dart';
import 'config/web_push_config.dart';
import 'firebase_options.dart';
import 'screens/ai_settings_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/coming_soon_screen.dart';
import 'screens/customer_login_screen.dart';
// GUEST MODE (Aug 11 2026): customer_welcome_login_screen.dart's import
// was removed here, not the FILE. _CustomerHomeGate was its only caller
// in the entire repo (verified by grep), so with the login wall gone the
// import became unused and would fail `flutter analyze`. The screen is
// left on disk, unrouted — same state welcome_screen.dart has been in
// since Aug 8 — so it can be restored in one line if Guest Mode is ever
// rolled back.
import 'screens/dashboard_screen.dart';
import 'services/daily_greeting_notification_service.dart';
import 'services/chitti_order_memory_service.dart';
import 'screens/guru_chat_screen.dart';
import 'screens/guru_offer_screen.dart';
import 'screens/hero_booking_screen.dart';
import 'screens/partner_shop_order_screen.dart';
import 'screens/seller_detail_screen.dart';
import 'screens/settings_screen.dart';
import 'services/category_gateway_service.dart' show Category;
import 'services/affiliate_service.dart';
import 'services/ai_activation_service.dart';
import 'services/analytics_service.dart';
import 'services/route_breadcrumb_observer.dart';
// GUEST MODE (Aug 11 2026): for ensureGuestSession() in main().
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/cache_service.dart';
import 'services/db_usage_tracker.dart';
import 'services/guru_overlay_service.dart';
import 'services/hive_cache.dart';
import 'services/local_sync_service.dart';
import 'services/localization_service.dart';
import 'services/map_service.dart';
import 'services/migration_gate_service.dart';
// receive_sharing_intent is Android/iOS only and has no web
// implementation, so importing it unconditionally broke `flutter build
// web`. Switch the implementation at compile time instead: web gets the
// no-op stub, mobile gets the real reader.
import 'services/share_intent_platform_stub.dart'
    if (dart.library.io) 'services/share_intent_platform_native.dart';
import 'services/shared_location_inbox.dart';
import 'services/soundbox_easter_egg_service.dart';
import 'services/theme_service.dart';
import 'services/map_simulation_service.dart';
import 'services/chitti/chitti_screen_tracker.dart';
import 'widgets/chitti_first_touch_greeter.dart';
import 'widgets/migration_notice_overlay.dart';
import './services/firestore_usage_tracking.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Enable Firestore offline persistence on web (PWA). Mobile
    // (Android/iOS) already has persistence on by default, so this is
    // guarded to web only; a capped 50MB cache (CTO-specified) keeps
    // browser storage bounded instead of unlimited.
    if (kIsWeb) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 52428800, // 50MB
        // FIX (Aug 10 2026 — root cause of "customer PWA la book
        // pannuna hero PWA la varala" on some devices/networks): the
        // Hero PWA's own browser console showed repeated
        // `net::ERR_QUIC_PROTOCOL_ERROR / QUIC_TOO_MANY_RTOS` on
        // firestore.googleapis.com — Firestore Web SDK defaults to
        // QUIC/HTTP3 for its real-time Listen channel, and some
        // networks (certain WiFi/mobile carriers/VPNs) silently
        // block or degrade QUIC (a UDP-based protocol), causing the
        // channel to keep failing to reconnect with no visible error
        // to the user — writes still succeed (this is why the
        // customer side worked fine finding heroes), but the
        // listener on the OTHER end never receives the update.
        // UPDATED (Aug 11 2026): auto-detect proved unreliable — Hero
        // PWA still hit the same QUIC error after this fix on some
        // networks, because QUIC_TOO_MANY_RTOS means the connection
        // keeps silently retrying rather than failing cleanly, so
        // auto-detect never gets a clean signal to fall back. Switched
        // to `experimentalForceLongPolling`, which skips QUIC/WebChannel
        // negotiation entirely — see main_hero.dart for the full
        // explanation. Applied here too for consistency across all 4 apps.
        webExperimentalForceLongPolling: true,
      );
    }
  }
  debugPrint(
    '[main_customer] Background push received: ${message.messageId} '
    'title=${message.notification?.title}',
  );
}

Future<void> _ensureFirebaseInitialized() async {
  if (Firebase.apps.isNotEmpty) {
    return;
  }
  try {
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.web,
      );
    } else {
      await Firebase.initializeApp();
    }
    // Enable Firestore offline persistence on web (PWA). Mobile
    // (Android/iOS) already has persistence on by default.
    if (kIsWeb) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 52428800, // 50MB
        // FIX (Aug 10 2026 — root cause of "customer PWA la book
        // pannuna hero PWA la varala" on some devices/networks): the
        // Hero PWA's own browser console showed repeated
        // `net::ERR_QUIC_PROTOCOL_ERROR / QUIC_TOO_MANY_RTOS` on
        // firestore.googleapis.com — Firestore Web SDK defaults to
        // QUIC/HTTP3 for its real-time Listen channel, and some
        // networks (certain WiFi/mobile carriers/VPNs) silently
        // block or degrade QUIC (a UDP-based protocol), causing the
        // channel to keep failing to reconnect with no visible error
        // to the user — writes still succeed (this is why the
        // customer side worked fine finding heroes), but the
        // listener on the OTHER end never receives the update.
        // UPDATED (Aug 11 2026): auto-detect proved unreliable — see
        // the matching comment above/main_hero.dart for the full
        // explanation. Switched to `experimentalForceLongPolling`.
        webExperimentalForceLongPolling: true,
      );
    }
    // FIX (Nizam's report — PWA "3 animations every reopen" audit): the
    // admin app already explicitly sets Persistence.LOCAL
    // (main_admin.dart) but the customer app never did — on web, Auth
    // persistence otherwise depends on the Firebase JS SDK's own
    // default, which is usually LOCAL already but isn't guaranteed
    // across browser/PWA versions. Setting it explicitly here removes
    // that one remaining variable: a signed-in customer's session is
    // now guaranteed to survive a full PWA close/reopen, not just
    // "probably does." Native (Android/iOS) already persists via the
    // platform SDK regardless — this call is a no-op there, so nothing
    // changes for the APK build.
    if (kIsWeb) {
      try {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      } catch (e) {
        debugPrint('[main_customer] setPersistence(LOCAL) failed: $e');
      }
    }
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') {
      debugPrint('[main_customer] Firebase already initialized, continuing.');
      return;
    }
    rethrow;
  }
}

// REMOVED (Aug 12 2026 — CTO mandate: "Splash Screen Overhaul & UX
// Animation" + "The Rebuild Bug"): _BootLoadingApp (the Flutter-side
// video splash, AppSplashVideoScreen) and its whole first-launch-vs-
// repeat-launch branch below are gone. Two independent reasons:
//
//   1. It was itself a forced ~6-11s watch (real completion-based, not
//      a fake Future.delayed, but still a hard floor on boot time no
//      matter how fast Firebase/Hive actually finished) — the CTO's own
//      framing was that an 11-second video is the "slow feeling"
//      startup, not merely "3 splashes."
//   2. It required a SECOND runApp() call (this widget, then
//      runApp(CustomerApp()) later) — a full root-binding-level
//      teardown-and-rebuild of the entire Flutter element tree, which
//      is one of the two confirmed causes of the "triple rebuild on
//      boot" bug (see CustomerApp's build() below for the other one,
//      the ValueKey/themeKey fix).
//
// The web/index.html HTML/CSS splash (see that file's category-icon
// shuffle preloader) is now the ONE and ONLY splash across the entire
// boot sequence — it already exists outside Flutter entirely, costs
// zero extra runApp() calls, and is torn down the instant
// `flutter-first-frame` fires, which now happens on the FIRST and ONLY
// runApp(CustomerApp()) call in main() below. The video asset itself
// and AppSplashVideoScreen/BrandedLoadingScreen widget files are left
// on disk, unrouted, in case product wants them reachable some other
// way later — same "unroute, don't delete" convention already used for
// IntroVideoScreen/WelcomeScreen elsewhere in this file.

// REMOVED (Aug 12 2026): _kSplashVideoSeenEverKey. It gated the now-
// removed Flutter video splash — see the removal note above
// _BootFailedApp's own class comment for the full reasoning.

// FIX (black/white-screen-stuck audit, per Nizam's request): the
// fallback shown when Firebase can't be reached even after retries —
// previously this scenario just left the tab blank with no runApp() at
// all. Deliberately tiny/dependency-free (no theming service, no
// providers) since those aren't initialized yet at this point in boot.
class _BootFailedApp extends StatelessWidget {
  final VoidCallback onRetry;
  const _BootFailedApp({required this.onRetry});

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(ObjectFlagProperty<VoidCallback>.has('onRetry', onRetry));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFFFFFFF),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded, color: Color(0xFF8F5A78), size: 48),
                const SizedBox(height: 16),
                const Text(
                  "Couldn't connect. Please check your internet and try again.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF3D1230), fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4FA3)),
                  child: const Text('Retry', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void main() async {
  // REGRESSION FIX (per Nizam's report: "Zone mismatch" + "Bad state:
  // Future already completed", 2-minute boot on Chrome web): Flutter
  // requires WidgetsFlutterBinding.ensureInitialized() and runApp() to be
  // called in the SAME zone. This used to call ensureInitialized() out
  // here, then SentryFlutter.init(appRunner: ...) below runs appRunner in
  // its own zone, then that appRunner ALSO wrapped part of its body in a
  // second, manually-nested runZonedGuarded() before calling runApp() --
  // three zones deep (root -> Sentry -> manual), with the binding
  // initialized in the outermost one. That mismatch is silent on most
  // devices/timings but can surface as exactly these two errors, and every
  // Firebase-init retry loop then reruns inside a broken zone stack, which
  // is consistent with the 2-minute stall. Fixed by moving
  // ensureInitialized() to be the very first statement INSIDE appRunner
  // (Sentry's own documented pattern) and removing the extra manual
  // runZonedGuarded() nesting below -- Sentry's appRunner zone already
  // captures uncaught errors app-wide, so the inner one was pure
  // redundancy and the actual source of the mismatch.
  await SentryFlutter.init(
    (options) {
      options
        ..dsn =
            'https://208217846f0b9708dc26f1d5d812eefc@o4511799785553920.ingest.us.sentry.io/4511799822843904'
        ..tracesSampleRate = 1.0;
    },
    appRunner: () async {
      WidgetsFlutterBinding.ensureInitialized();

      // DEEP LINKING (Aug 19 2026 — clean-URL PWA support): switches web
      // routing from the default hash strategy (my-allin1.web.app/#/shop/x)
      // to path-based URLs (my-allin1.web.app/shop/x) so a WhatsApp-shared
      // shop link looks like a normal URL and Android App Links can match
      // it by host+path. No-op on non-web platforms; guarded anyway since
      // the underlying platform channel only exists on web.
      if (kIsWeb) {
        usePathUrlStrategy();
      }

      // MEMORY FOOTPRINT CAP (Aug 19 2026 — cold-start-after-kill
      // mitigation, part C): Flutter's default image cache has no size
      // ceiling other than a 1000-image count, so a long dashboard
      // session with lots of scrolled-past listing photos can retain a
      // large amount of decoded-bitmap memory, making this app a more
      // likely OS memory-reclaim target while backgrounded. Capping it
      // does not prevent the OS from killing the process, it only
      // reduces how often this app is the one picked. 100MB is a
      // generous cap for a listings-heavy app; well below anything that
      // would cause visible re-decode thrashing during normal scrolling.
      PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20;

      // FIX (audit finding — notifications_screen.dart hardcoded
      // 'customer' fallback): explicit even though 'customer' is
      // already the default in app_variant.dart, so this entrypoint
      // doesn't silently rely on that default never changing.
      currentAppVariant = 'customer';

      // REMOVED (Aug 12 2026 — single-splash consolidation): the early
      // "paint _BootLoadingApp before Firebase starts" trick and the
      // first-launch-vs-repeat-launch video branching are both gone —
      // see the removal note above _BootFailedApp's class comment. The
      // web/index.html HTML/CSS splash now covers this entire wait
      // (Firebase init below, boot phase 1 further down) on its own,
      // with zero Dart-side runApp() calls needed to keep it on screen —
      // it is torn down by the SAME `flutter-first-frame` event this
      // file already relied on, just now triggered by the one and only
      // runApp(CustomerApp()) call below instead of an early throwaway
      // frame.
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      FlutterError.onError = (details) {
        debugPrint('Flutter error: ${details.exceptionAsString()}');
        if (AnalyticsService.isInitialized) {
          AnalyticsService.instance.recordError(
            details.exceptionAsString(),
            details.stack ?? StackTrace.current,
            fatal: true,
          );
        }
      };

      // FIX (black/white-screen-stuck audit, per Nizam's request): this
      // used to be a single try/attempt — on any Firebase.initializeApp
      // failure (a transient network blip is common on weaker Erode
      // mobile connections; this is a REAL network call, not local
      // setup) it just `return`ed, meaning runApp() below never ran.
      // Flutter's engine had nothing to paint, forever — no error, no
      // retry, just a permanently blank tab. Now: retry a few times with
      // a short delay (covers the common transient case), and if it's
      // still failing after that, show an in-app "Couldn't connect —
      // Retry" screen instead of leaving the tab blank.
      var firebaseReady = false;
      Object? lastFirebaseError;
      for (var attempt = 1; attempt <= 3 && !firebaseReady; attempt++) {
        try {
          await _ensureFirebaseInitialized();
          firebaseReady = true;
        } catch (e) {
          lastFirebaseError = e;
          debugPrint('[main_customer] Firebase init attempt $attempt failed: $e');
          if (attempt < 3) {
            await Future<void>.delayed(const Duration(seconds: 2));
          }
        }
      }
      if (!firebaseReady) {
        debugPrint('[main_customer] Fatal: Firebase init failed after retries: $lastFirebaseError');
        runApp(const _BootFailedApp(onRetry: main));
        return;
      }

      // DB usage monitor — tags every counted read/write from this app
      // as 'customer' so admin's DB Monitor screen can see per-app
      // Firestore usage. See lib/services/db_usage_tracker.dart.
      DbUsageTracker.instance.init('customer');

      // ── BOOT PHASE 1: only what the first screen genuinely needs ──
      //
      // Everything below used to run here, sequentially, before runApp():
      //   Analytics init, Hive.initFlutter, LocalSync (4 boxes),
      //   CacheService (5 boxes), ApiService (1 box + Dio), settings write.
      //
      // That's 10 Hive box opens one after another — each one a local
      // storage round-trip (IndexedDB on web) — while the customer stares
      // at a blank/splash screen. Hive caching makes the DATA free to
      // read; it does not make OPENING the boxes free, and that cost was
      // being paid serially on every single launch.
      //
      // Now: Hive core + the 3 boxes the home screen reads. Everything
      // else moved to _warmCustomerServices() (phase 2, post-runApp).
      //
      // NOTE: this used to be wrapped in its own nested runZonedGuarded()
      // with a matching (error, stack) handler. Removed as part of the
      // zone-mismatch fix above — Sentry's own appRunner zone (this whole
      // function body) already catches and reports uncaught errors here,
      // so the plain try/catch below covers exactly the same cases
      // without adding a second zone layer.
      // SIMPLIFIED (Aug 12 2026 — single-splash consolidation): the
      // first-launch-vs-repeat-launch split is gone. Every launch now
      // takes what used to be only the "repeat launch" path: paint the
      // real CustomerApp tree IMMEDIATELY — do not wait on Hive/cache
      // warm-up first. Firebase itself is still awaited above
      // (unavoidable: _CustomerHomeGate's boot-uid subscription reads
      // FirebaseAuth.instance.authStateChanges() the moment CustomerApp
      // builds, so Firebase must already be initialized by then), but
      // that's a local SDK call restoring an already-persisted session,
      // not a fresh network round-trip, so it's fast. Everything else
      // (Hive boxes, cache, shared-location inbox, system chrome) runs
      // unawaited in the background — the customer sees the dashboard
      // shell first, data fills in via the screens' own existing loading
      // states as it arrives. This is exactly the CTO's "snap instantly
      // to the Home Screen the millisecond it's ready" requirement: the
      // ONLY thing this runApp() call still waits on is the genuinely
      // real async work above (Firebase), never a fixed timer.
      runApp(const CustomerApp());
      unawaited(_runBootPhase1());

      // GUEST MODE (Aug 11 2026): give every customer a real uid from
      // the first frame, so the dozens of existing screens that read
      // FirebaseAuth.instance.currentUser! (or gate an RTDB read on
      // auth != null) keep working with no null-hardening audit.
      //
      // Placed AFTER both runApp() branches and unawaited() on purpose:
      // it is a network round-trip and must never sit between the app
      // and its first paint. It is also idempotent — if a real session
      // was already restored from disk it returns immediately without
      // touching it, so a signed-in customer is never downgraded to a
      // guest on relaunch.
      // NEW (Aug 12 2026 — Affiliate QR Generator): chained onto the same
      // unawaited future so the scan counter only fires once a session
      // (real or anonymous/guest) actually exists — Firestore would
      // reject the write otherwise. Both calls stay fire-and-forget;
      // neither can delay first paint.
      unawaited(
        AuthService()
            .ensureGuestSession()
            .then((_) => AffiliateService.instance.logScanIfPending()),
      );

      // Everything non-essential to the first frame runs here instead of
      // blocking runApp(): analytics, the deferred Hive boxes, the API
      // client, the Ola Maps availability ping, and the Firestore
      // active-ride lookup. Same pattern as main_hero.dart's
      // _warmHeroServices(). Worst case, an active-ride banner appears a
      // moment after the home screen instead of before it.
      //
      // _restoreActiveRideIfNeeded() only touches Firestore when Hive
      // already holds an active-ride marker — a customer with no ride in
      // progress costs zero database reads on launch.
      unawaited(_warmCustomerServices());
      unawaited(_restoreActiveRideIfNeeded());
      unawaited(_listenForSharedLocations());
      // NEW (Aug 12 2026 — "Zero-Budget Escape Hatch"): starts the live
      // migration-notice listener. Fire-and-forget, after runApp(), same
      // as every other post-boot warm-up above — never delays first
      // paint, and fails open (see MigrationGateService's own header
      // comment) so a Firestore hiccup here can never lock out a
      // healthy app.
      MigrationGateService.instance.start();
    },
  );
}

// FIX (Aug 10 2026 — extracted for first-launch-only video change): body
// unchanged from what used to sit inline in main() — Hive core + the
// boxes the home screen reads, the campaign-source capture, the
// share-intent capture, and the status-bar style. First-ever launch
// still `await`s this before runApp(); repeat launches fire it
// unawaited() instead. See the two call sites in main() above.
Future<void> _runBootPhase1() async {
  try {
    await Hive.initFlutter();
    // NEW (Aug 25 2026 — Super Chitti Phase 1, Step 2): warms
    // ChittiOrderMemoryService's in-memory cache so recentSummary() can
    // stay synchronous when guru_api_service.dart builds a system
    // prompt. Safe to skip on failure — the service just falls back to
    // returning no history until the next record() call.
    unawaited(ChittiOrderMemoryService.preload());
    await CacheService().initCritical();

    // FIX (Poster Campaign Tracking): Cache the 'source' parameter
    // from the PWA URL into SharedPreferences before Google Sign-In
    // redirects clear it.
    if (kIsWeb) {
      final sourceParam = Uri.base.queryParameters['source'];
      if (sourceParam != null && sourceParam.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('campaign_source', sourceParam);
      }
      // NEW (Aug 12 2026 — Affiliate QR Generator): same pattern as the
      // 'source' capture above, for ?ref=CODE&rtype=... links generated
      // by the new Admin Affiliate QR screen. The actual scan/signup
      // writes happen later (see AuthService().ensureGuestSession()
      // .then(...) below, and auth_service.dart's new-account block) —
      // this just grabs the code before Google Sign-In's redirect can
      // clear the URL.
      //
      // FIX (Aug 13 2026 audit — "QR/link flow propera run agala"):
      // this used to be `unawaited(...)`, racing against the
      // ensureGuestSession().then(logScanIfPending) chain below. Both
      // are fire-and-forget futures started around the same moment;
      // logScanIfPending() reads kPendingCodeKey from SharedPreferences,
      // and there was no guarantee captureRefFromUrl() had FINISHED
      // WRITING it first — on a fast device / fast connection,
      // logScanIfPending() would frequently run first, find nothing
      // pending yet, and the scan/signup for that link would silently
      // never be counted. captureRefFromUrl() is two cheap
      // SharedPreferences calls (no network), so awaiting it here costs
      // nothing measurable and removes the race entirely: by the time
      // _runBootPhase1() returns, the pending code (if any) is
      // guaranteed to be on disk before anything downstream can read it.
      await AffiliateService.instance.captureRefFromUrl();
      
      // Aug 16 2026: Check clipboard for APK install tracking
      await AffiliateService.instance.captureRefFromClipboard();
    }

    // If this launch came from Android's share sheet (customer shared a
    // location out of WhatsApp/Maps into Allin1), the shared text is on
    // the launch URL. Read it now, before any screen builds, so the
    // hero booking screen finds it already waiting. Cheap, synchronous,
    // and a no-op on an ordinary launch.
    SharedLocationInbox.instance.captureFromLaunchUrl();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  } catch (error, stack) {
    debugPrint('Boot phase 1 error: $error\n$stack');
    if (AnalyticsService.isInitialized) {
      AnalyticsService.instance.recordError(error, stack);
    }
  }
}

// ── BOOT PHASE 2: everything that can wait for the first frame ──
// Runs unawaited() after runApp(). Nothing in here is needed to paint
// the home screen; the customer sees UI while this finishes in the
// background. Each block is independently try/caught so one failure
// can't take the rest of the warm-up down with it.
Future<void> _warmCustomerServices() async {
  // Independent of each other, so let them overlap instead of queueing.
  await Future.wait([
    _warmAnalytics(),
    _warmDeferredCaches(),
    _warmMapStack(),
  ]);
  _syncCustomerFcmToken();
}

StreamSubscription<User?>? _customerFcmAuthSub;
StreamSubscription<String>? _customerFcmRefreshSub;

// NEW (CTO audit — gift coupon push): the customer app set up a
// BACKGROUND HANDLER (see FirebaseMessaging.onBackgroundMessage above)
// but never registered a token anywhere, so `users/{uid}.fcmToken` did
// not exist and there was no address to push a customer notification
// to. notifyCustomerOnCouponReady reads exactly that field.
//
// Mirrors main_hero.dart's _syncFcmTokenForHero: capture once per auth
// session, keep current via onTokenRefresh, and never let a failure
// here block boot — a missing token degrades to "no push", which the
// Cloud Function already handles by logging and returning.
void _syncCustomerFcmToken() {
  _customerFcmAuthSub?.cancel();
  _customerFcmAuthSub =
      FirebaseAuth.instance.authStateChanges().listen((user) async {
    _customerFcmRefreshSub?.cancel();
    _customerFcmRefreshSub = null;
    // Guests are anonymous and have no users/{uid} doc worth writing to.
    if (user == null || user.isAnonymous) return;

    final uid = user.uid;
    try {
      // getToken() on web REQUIRES a vapidKey or it throws outright;
      // native platforms ignore the parameter. Same call shape as the
      // hero app — see web_push_config.dart.
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb ? WebPushConfig.vapidKey : null,
      );
      if (token != null && token.trim().isNotEmpty) {
        // merge:true — a customer mid-signup may not have a users/{uid}
        // doc yet, and a not-found update would silently lose the token.
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('[FCM] Token synced for customer $uid');
      }
    } catch (e) {
      debugPrint('[FCM] Customer token sync failed for $uid: $e');
    }

    _customerFcmRefreshSub =
        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      unawaited(
        FirebaseFirestore.instance.collection('users').doc(uid).set({
          'fcmToken': newToken,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).catchError((Object e) {
          debugPrint('[FCM] Customer token refresh write failed for $uid: $e');
        }),
      );
    }, onError: (Object e) {
      debugPrint('[FCM] Customer onTokenRefresh listener error: $e');
    });
  });
}

Future<void> _warmAnalytics() async {
  try {
    await AnalyticsService.instance.initialize();
  } catch (e) {
    debugPrint('[main_customer] Analytics init error: $e');
  }
}

Future<void> _warmDeferredCaches() async {
  try {
    // ads_cache + ride_fares_cache (CacheService), the four tb_* boxes
    // (LocalSyncService) and api_cache (ApiService) — none of which the
    // home screen reads on first paint.
    //
    // ApiService reads ApiConfig.primaryBaseUrl when it configures Dio,
    // and LocalSyncService reads TRAILBASE_URL from dotenv, so make sure
    // .env is loaded first. ensureEnvLoaded() is idempotent and
    // race-safe, so calling it here as well as in _warmMapStack() is
    // fine — whichever gets there first wins, the other no-ops.
    await ApiConfig.ensureEnvLoaded();

    await Future.wait([
      CacheService().initDeferred(),
      LocalSyncService.instance.initialize(),
      ApiService.instance.initialize(),
    ]);

    // Arm tomorrow's good-morning (Aug 28 2026 — Nizam: "daily morning
    // ovvoru customer kum good morning boss nu solli, motivational
    // quote kaatanum... database and server yethume use agakudathu").
    //
    // Deliberately NOT awaited: the OS holds the schedule, so there is
    // nothing here worth delaying first paint for, and a failure to
    // schedule a greeting must never be able to stop the app opening.
    // Re-arming on every start is what keeps it alive across reboots,
    // app updates and a customer changing their language.
    unawaited(DailyGreetingNotificationService.instance.scheduleNext());

    await CacheService().cacheSettings({
      'bikeTaxiBaseFare': 25.0,
      'bikeTaxiPerKm': 12.0,
      'coinValue': 100,
      'riderCommission': 15.0,
      'sellerCommission': 18.0,
      'platformFee': 2.0,
      'upiZeroFee': true,
    });
  } catch (e) {
    debugPrint('[main_customer] Deferred cache warm-up error: $e');
  }
}

// ── Native share-target receiver ─────────────────────────────────
// Android side of "share a WhatsApp location into Allin1". The
// ACTION_SEND intent-filter in AndroidManifest.xml is what puts the app
// in the share sheet; this is what reads the text that comes with it.
//
// Two cases to cover, and missing either one makes the feature look
// broken half the time:
//   getInitialMedia() — the share COLD-STARTED the app. The intent is
//     already waiting when Dart boots.
//   getMediaStream()  — the app was already running. A fresh intent
//     arrives while it's in memory.
//
// Web/PWA never reaches this: the plugin has no web implementation, and
// SharedLocationInbox.captureFromLaunchUrl() has already handled the
// equivalent job from the launch URL's query string.
Future<void> _listenForSharedLocations() async {
  await const ShareIntentPlatform().listen((text) {
    final accepted = SharedLocationInbox.instance.deliver(text);
    if (!accepted) {
      return;
    }

    // If the customer is already somewhere else in the app, take them to
    // the booking form — that's the only screen that can act on this,
    // and it prompts "Pickup or Drop?" as soon as it builds.
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      return;
    }
    unawaited(navigator.push<void>(
      MaterialPageRoute<void>(builder: (_) => const HeroBookingScreen()),
    ),);
  });
}

Future<void> _warmMapStack() async {
  try {
    // MUST precede MapService() — see the matching comment in
    // main_hero.dart and ApiConfig.ensureEnvLoaded().
    await ApiConfig.ensureEnvLoaded();
    debugPrint('[main_customer] Initializing MapService...');
    await MapService().initialize();
    // RESTORED (Aug 19 2026 — Nizam's explicit request): Fake vehicles are
    // back on the customer app to make the map look active, driven by the
    // Admin Drawer's 3-mode selector (Normal/Busy/Peak/Off) in Firestore.
    // They now use the same strict road-snapping logic (no more ghosts).
    FirebaseFirestore.instance.collection('system_settings').doc('app_status').trackedSnapshots().listen((snapshot) {
      final data = snapshot.data();
      final mode = data?['simulation_mode'] as String? ?? 'off';
      if (mode == 'off') {
        MapSimulationService.instance.stop();
      } else {
        SimulationDensity density = SimulationDensity.normal;
        if (mode == 'busy') density = SimulationDensity.busy;
        if (mode == 'peak') density = SimulationDensity.peak;
        MapSimulationService.instance.start(density: density);
      }
    });
    debugPrint(
      '[main_customer] MapService ready provider=${MapService().currentProvider.name} '
      'fallback=${MapService().isUsingFallback}',
    );
  } catch (e) {
    debugPrint('[main_customer] MapService init error: $e');
  }
}

Future<void> _restoreActiveRideIfNeeded() async {
  try {
    // Map<dynamic, dynamic> (not Map<String, dynamic>) deliberately:
    // Hive deserializes this as a raw dynamic-keyed map, and
    // HiveCache.get<T>() does a plain `as T?` cast — casting to
    // Map<String, dynamic> here would throw (Dart generics are
    // invariant) and get<T>()'s catch-all would silently swallow it as
    // null, quietly breaking active-ride restore. This keeps the exact
    // same runtime behavior as the old raw `Map` while still satisfying
    // the strict-raw-types analyzer setting with explicit type args.
    final cached =
        await HiveCache.get<Map<dynamic, dynamic>>(HiveCache.kActiveRide);
    if (cached == null) {
      return;
    }
    final rideDocId = cached['rideDocId'] as String?;
    if (rideDocId == null || rideDocId.isEmpty) {
      return;
    }
    final snap = await FirebaseFirestore.instance
        .collection('rides')
        .doc(rideDocId)
        .trackedGet();
    final status = snap.data()?['status'] as String? ?? '';
    final activeStatuses = ['accepted', 'arriving', 'in_progress'];
    if (!activeStatuses.contains(status)) {
      await HiveCache.evict(HiveCache.kActiveRide);
      debugPrint('[main_customer] Stale active ride cleared: $status');
      return;
    }
    debugPrint('[main_customer] Active ride restored: $rideDocId status=$status');
  } catch (e) {
    debugPrint('[main_customer] Ride restore error: $e');
  }
}

class CustomerApp extends StatelessWidget {
  // BOOT-SEQUENCE CONSOLIDATION (per CTO mandate — single splash screen
  // for all 4 apps): this used to carry showIntro/showWelcome booleans
  // resolved in main()'s boot phase 1, threaded down into _IntroGate to
  // decide whether to also play IntroVideoScreen and/or WelcomeScreen
  // before the shared AppSplashVideoScreen. Both of those screens are
  // now removed from the boot chain entirely (see _IntroGate below), so
  // there is nothing left to gate and no flags left to carry.
  const CustomerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocalizationService()),
        ChangeNotifierProvider(create: (_) => ThemeService()),
        ChangeNotifierProvider(create: (_) => AiActivationService()),
        ChangeNotifierProvider<SoundboxEasterEggService>(
          create: (_) {
            final svc = SoundboxEasterEggService();
            svc.init(); // loads SharedPreferences: tap count + permanent hide flag
            return svc;
          },
        ),
      ],
      child: Consumer2<LocalizationService, ThemeService>(
        builder: (context, localization, themeService, _) => MaterialApp(
          // languageCode used to be part of this key. Changing the key
          // makes Flutter throw the ENTIRE MaterialApp away and build a
          // fresh one — which also destroys the Navigator and every
          // screen on it. So picking a language on the welcome screen
          // blew that screen away mid-tap and dumped the customer
          // straight onto the home screen, skipping the sign-in choice
          // completely.
          //
          // It was never needed: the Consumer2 wrapper below already
          // rebuilds on notifyListeners(), so anything reading
          // context.watch<LocalizationService>() re-renders in the new
          // language without nuking navigation.
          //
          // FIX (Aug 12 2026 — "triple rebuild on boot" root cause):
          // themeKey WAS still keying this MaterialApp (left in place
          // "for now" by the note above, which is exactly what regressed
          // it). ThemeService's constructor fires an async _loadTheme()
          // that, for any customer who ever picked a non-default theme,
          // resolves to a DIFFERENT value than the hardcoded default
          // ('pink_white') a moment after first paint and calls
          // notifyListeners() — and because THIS key was built from that
          // value, Flutter treated it as a brand-new widget and threw
          // away the entire tree (Navigator + every screen + all state)
          // a second time, on top of whatever boot-sequence rebuilds
          // were already happening. Removed entirely: MaterialApp has no
          // key here at all now, exactly like every other flavor's app
          // root. Consumer2 already handles reactive theme swaps by
          // rebuilding `theme:` in place — no tree destruction needed
          // for that, ever.
          navigatorKey: navigatorKey,
          title: localization.t('app_title'),
          debugShowCheckedModeBanner: false,
          theme: themeService.currentTheme,
          themeMode: ThemeMode.light,
          home: const _IntroGate(),
          routes: {
            '/login': (_) => const CustomerLoginScreen(),
            '/dashboard': (_) => const DashboardScreen(),
            '/settings': (_) => const SettingsScreen(),
            '/ai-settings': (_) => const AiSettingsScreen(),
            '/ai-assistant': (_) => const GuruChatScreen(),
            '/guru-offer': (_) => const GuruOfferScreen(),
            '/checkout': (_) => const CheckoutScreen(),
            '/rider': (_) => const ComingSoonScreen(role: 'Rider'),
            '/seller': (_) => const ComingSoonScreen(role: 'Seller'),
          },
          // NEW (Aug 19 2026 — deep-breadcrumb restore, food/restaurant
          // browsing only): SellerDetailScreen normally takes a full
          // seller Map fetched by the category list — too heavy to carry
          // through PrefsCache (breadcrumb args must be JSON primitives,
          // see route_breadcrumb_observer.dart). So '/food_shop_detail'
          // is a NAMED route that carries only {sellerId, categoryName}
          // and re-fetches the seller doc from Firestore before building
          // the real screen. This is deliberately the ONLY detail screen
          // wired this way in this pass — see kBreadcrumbSafeRoutes for
          // exactly which flows this covers (restaurant/menu browsing,
          // pre-checkout) and which it explicitly excludes (checkout,
          // payment, order tracking).
          onGenerateRoute: (settings) {
            if (settings.name == '/food_shop_detail') {
              final args = settings.arguments;
              final map = args is Map ? args : const <String, dynamic>{};
              final sellerId = map['sellerId'] as String?;
              final categoryName = map['categoryName'] as String?;
              if (sellerId == null || sellerId.isEmpty) return null;
              final category = Category.values.firstWhere(
                (c) => c.name == categoryName,
                orElse: () => Category.food,
              );
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => _FoodShopDetailRestoreLoader(
                  sellerId: sellerId,
                  category: category,
                ),
              );
            }
            if (settings.name == '/partner_shop_detail') {
              final args = settings.arguments;
              final map = args is Map ? args : const <String, dynamic>{};
              final shopName = map['shopName'] as String?;
              PartnerShop? shop;
              if (shopName != null) {
                for (final s in kPartnerShops) {
                  if (s.name == shopName) {
                    shop = s;
                    break;
                  }
                }
              }
              if (shop == null) return null;
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => PartnerShopOrderScreen(shop: shop!),
              );
            }
            return null;
          },
          navigatorObservers: [
            // Keeps ChittiMemoryService.currentScreen in step with the
            // navigator so Chitti knows which page the customer is on.
            ChittiScreenObserver(),
            AnalyticsService.instance.getObserver(),
            RouteBreadcrumbObserver(),
            chittiRouteObserver,
          ],
          // NEW (CTO mandate — Quick Task Global AI Overlay): the launcher
          // FAB lives here so it appears above every screen with zero
          // per-screen wiring, exactly like the CTO's "travels with the
          // user across ALL screens" requirement. The actual chat panel
          // is NOT built here -- it's a separate root-level OverlayEntry
          // (see GuruOverlayService.show()) inserted via `navigatorKey`,
          // so it survives Navigator.push/pop the same way this FAB does.
          // NEW (Aug 12 2026 — "Zero-Budget Escape Hatch"): MigrationGate
          // wraps EVERYTHING else here, including the AI FAB — a
          // migration lock must hide the whole app, not sit under a
          // still-interactive overlay.
          // NEW (Aug 28 2026): ChittiFirstTouchGreeter wraps the whole
          // app so Chitti's spoken welcome fires on the first touch of
          // the session — not on open, because browsers discard speech
          // that happens before a user gesture and this build ships as
          // a PWA. It passes every pointer straight through and removes
          // itself once the greeting has run.
          builder: (context, child) => ChittiFirstTouchGreeter(
            child: MigrationGate(
              child: Stack(
                children: [
                  if (child != null) child,
                  const GlobalGuruFab(),
                ],
              ),
            ),
          ),
          // The bouncing Paytm soundbox used to be mounted HERE, at the
          // MaterialApp builder — meaning it sat on top of every single
          // screen in the app with a Ticker firing on every frame for
          // the entire lifetime of the app, even on screens where it
          // made no sense. It now lives only inside the Rewards screen
          // (RewardsSoundboxOverlay), so the rest of the app pays
          // nothing for it. Feature kept, scope narrowed.
        ),
      ),
    );
  }
}

// ================================================================
// Post-boot-frame gate.
//
// BOOT-SEQUENCE CONSOLIDATION (per CTO mandate — exactly ONE splash
// screen between the static boot frame and the real home/auth-gated
// screen, across all 4 apps): this used to conditionally chain
// IntroVideoScreen (first-launch-only intro.mp4, had its own Skip
// button) and/or WelcomeScreen (first-launch-only language + optional
// sign-in) in FRONT of the shared AppSplashVideoScreen, based on
// SharedPreferences "have they seen this" flags — meaning a first-time
// customer could see up to three full-screen widgets back-to-back
// before ever reaching the app (intro video -> welcome -> splash video
// -> home). Both are now removed from this boot chain:
//
//   - IntroVideoScreen: removed entirely from the reachable path. It
//     is not load-bearing (no consent/permission collection, purely a
//     branded clip) and duplicated the exact kind of "competing splash
//     video" the shared AppSplashVideoScreen was introduced to
//     consolidate. The widget file/class itself is left in place
//     (not deleted) in case product wants a "replay intro" entry point
//     elsewhere later — it is simply never routed to from boot anymore.
//   - WelcomeScreen: removed from the boot chain too. JUDGMENT CALL
//     (flagged for owner review): WelcomeScreen has no auto-advance
//     timer — it is a static, manual-tap screen — but everything it
//     does is optional and duplicated elsewhere: its language picker
//     is the same LocalizationService the Settings screen's own
//     language picker already drives (see settings_screen.dart's
//     _showLanguagePicker), and its "Continue with Google" sign-in is
//     explicitly optional even on the screen itself ("Sign in later"
//     button, "we'll only ask you to sign in when you book"). Nothing
//     it collects is required to use the app. Treated as decorative/
//     skippable per the task's criteria and removed from boot; the
//     WelcomeScreen widget/file is not deleted, only unrouted, in case
//     product wants it reachable some other way later.
//
// UPDATED (Aug 12 2026 — single-splash consolidation): the Flutter-side
// video boot frame this comment used to describe (_BootLoadingApp /
// AppSplashVideoScreen) is gone entirely now — see the removal note
// above _BootFailedApp's class comment near the top of this file. This
// widget (_IntroGate) has nothing left to gate and always goes straight
// to the real home screen (_CustomerHomeGate); the ONE splash for the
// whole boot sequence is now the HTML/CSS one in web/index.html, which
// lives outside Flutter entirely and needs no widget here to manage it.
// ================================================================
// ================================================================
// _FoodShopDetailRestoreLoader — Aug 19 2026
//
// Reconstructs SellerDetailScreen from just a seller id + category on
// cold-start deep restore (see onGenerateRoute above and
// route_breadcrumb_observer.dart). Refetches the seller doc directly
// from Firestore's 'sellers' collection — same shape CategoryGatewayService
// produces ('id': doc.id, ...doc.data()) — so SellerDetailScreen sees an
// identical `seller` map to a normal category-browse navigation.
//
// Fails soft: if the doc is gone/unreachable (seller deactivated,
// offline, etc.) this shows a small error screen with a way back to the
// dashboard rather than crashing or looping — restoring a breadcrumb
// must never be able to strand the customer.
// ================================================================
class _FoodShopDetailRestoreLoader extends StatelessWidget {
  final String sellerId;
  final Category category;

  const _FoodShopDetailRestoreLoader({
    required this.sellerId,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('sellers')
          .doc(sellerId)
          .trackedGet(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data;
        if (snapshot.hasError || data == null || !data.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Restaurant')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('This shop is no longer available.'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Go back'),
                  ),
                ],
              ),
            ),
          );
        }
        final seller = <String, dynamic>{'id': data.id, ...?data.data()};
        return SellerDetailScreen(seller: seller, category: category);
      },
    );
  }
}

class _IntroGate extends StatelessWidget {
  const _IntroGate();

  @override
  Widget build(BuildContext context) {
    // NEW (CTO mandate — Video Splash Screen, every launch): shared
    // AppSplashVideoScreen widget so every one of the 4 apps plays
    // app_splash.mp4 through the exact same code path — one file to
    // touch on the next video swap, not up to 4. Same asset, same
    // BoxFit.fill full-screen stretch, same 11s safety-timer ceiling,
    // same unmuted playback as before.
    //
    // The warm-up work IntroVideoScreen/WelcomeScreen never actually
    // did (ApiConfig.ensureEnvLoaded() + MapService().initialize()) is
    // unaffected by this change either way — main()'s
    // _warmMapStack() (part of _warmCustomerServices(), fired
    // unawaited() right after runApp(), independent of whichever
    // screens are mounted) already covers it.
    return const _CustomerHomeGate();
  }
}

class _CustomerHomeGate extends StatefulWidget {
  const _CustomerHomeGate();

  @override
  State<_CustomerHomeGate> createState() => _CustomerHomeGateState();
}

class _CustomerHomeGateState extends State<_CustomerHomeGate> {
  String? _lastUid;
  StreamSubscription<User?>? _authSub;

  // FIX (Aug 12 2026 — "triple rebuild on boot" root cause, contributing
  // factor): this used to be a StreamBuilder whose `builder` re-ran on
  // EVERY authStateChanges() emission (the boot-time guest sign-in lands
  // a moment after the initial cached-user read, so that's at least two
  // emissions on a normal launch) — harmless in practice only because it
  // always returned the exact same `const DashboardScreen()` either way,
  // but it was still an extra build pass sitting in the hottest part of
  // the boot path for zero visual benefit. Converted to a manual
  // StreamSubscription that exists ONLY to fire the
  // AiActivationService.refreshForUser() side effect when the uid
  // actually changes — it never calls setState, so this widget now
  // builds DashboardScreen exactly once, full stop, regardless of how
  // many auth events land during boot.
  @override
  void initState() {
    super.initState();
    final initialUser = FirebaseAuth.instance.currentUser;
    _lastUid = initialUser?.uid;
    if (initialUser != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(context.read<AiActivationService>().refreshForUser(initialUser));
      });
    }
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      final currentUid = user?.uid;
      if (_lastUid == currentUid) return;
      _lastUid = currentUid;
      if (!mounted) return;
      unawaited(context.read<AiActivationService>().refreshForUser(user));
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // FIX (CTO mandate — Task 1: Remove Legacy Profile Setup): this
    // gate used to run a whole extra Firestore FutureBuilder here
    // just to decide whether to swap in ProfileSetupScreen — that
    // "still needs onboarding" case can no longer genuinely happen
    // for the customer app. customer_login_screen.dart's new
    // mobile-number-first Sign Up flow now writes `phoneNumber`,
    // `phone`, AND `isSetupComplete: true` into users/{uid} at the
    // exact moment the account is created (see that file's
    // _signUpWithGoogle()) — so by the time ANY customer reaches
    // this gate, either they're not signed in yet (handled above)
    // or their profile is already complete. Removed the
    // Firestore-profile-read FutureBuilder and the ProfileSetupScreen
    // branch entirely; every signed-in customer now goes straight to
    // DashboardScreen, unconditionally, every time. Zero network
    // round trip added to this gate anymore.
    //
    // NOTE: ProfileSetupScreen the WIDGET is not deleted — it's
    // still a real, actively-used screen for other app types via
    // lib/screens/login_screen.dart's generic Google sign-in
    // handler (Admin/Seller/other-role flows), so removing the
    // FILE would break those. Only this customer-specific gate
    // stopped routing to it.
    //
    // SUPERSEDED (Aug 8 2026 — Unified Welcome Screen): a signed-out
    // customer used to see CustomerWelcomeLoginScreen here on every
    // launch, with a "Login Later" button letting them through.
    //
    // GUEST MODE (Aug 11 2026): the login wall is gone entirely. A
    // null user here no longer means "signed out" — every customer
    // is signed in ANONYMOUSLY from boot (see
    // AuthService.ensureGuestSession(), fired unawaited in main()
    // below). Null now only means that sub-second network call has
    // not landed yet, which is not a state worth showing a whole
    // login screen for. Returning DashboardScreen unconditionally is
    // what guarantees the acceptance criterion of exactly ONE
    // transition on boot: HTML splash -> Home. Any branch here would
    // reintroduce a second frame swap.
    //
    // Screens that genuinely need a real, contactable account call
    // requireRealAuth() at the moment of the action instead — see
    // lib/services/auth_prompt_service.dart. The gate is enforced
    // server-side too: firestore.rules' isRealUser() blocks writes
    // from anonymous uids, so this is not merely a UI convention.
    //
    // Do NOT re-add a login gate here.
    //
    // CustomerWelcomeLoginScreen the FILE is intentionally not
    // deleted — only unrouted. See the import block at the top.
    return const DashboardScreen();
  }
}
