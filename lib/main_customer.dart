// lib/main_customer.dart
// Erode Super App - CUSTOMER PWA Entry Point
// Fixed: back button logout + routing + geolocator web crash

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_navigator.dart';
import 'config/api_config.dart';
import 'firebase_options.dart';
import 'screens/ai_settings_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/coming_soon_screen.dart';
import 'screens/customer_login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/guru_chat_screen.dart';
import 'screens/guru_offer_screen.dart';
import 'screens/hero_booking_screen.dart';
import 'screens/intro_video_screen.dart';
import 'screens/video_splash_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/ai_activation_service.dart';
import 'services/analytics_service.dart';
import 'services/api_service.dart';
import 'services/cache_service.dart';
import 'services/db_usage_tracker.dart';
import 'services/guru_overlay_service.dart';
import 'services/hive_cache.dart';
import 'services/local_sync_service.dart';
import 'services/localization_service.dart';
import 'services/map_service.dart';
// receive_sharing_intent is Android/iOS only and has no web
// implementation, so importing it unconditionally broke `flutter build
// web`. Switch the implementation at compile time instead: web gets the
// no-op stub, mobile gets the real reader.
import 'services/share_intent_platform_stub.dart'
    if (dart.library.io) 'services/share_intent_platform_native.dart';
import 'services/shared_location_inbox.dart';
import 'services/soundbox_easter_egg_service.dart';
import 'services/theme_service.dart';
import 'widgets/branded_loading_screen.dart';

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
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Enable Firestore offline persistence on web (PWA). Mobile
    // (Android/iOS) already has persistence on by default.
    if (kIsWeb) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 52428800, // 50MB
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

// FIX (Nizam's "jet-speed startup" request, task #108): previously
// nothing painted at all until Firebase.initializeApp() + its retry loop
// + Hive boot phase 1 all finished -- a genuine network round-trip
// (Firebase init can hit the network, and is documented above as prone
// to "transient blip" failures on weak Erode connections) that blocked
// Flutter's very first frame. Flutter's `flutter-first-frame` web event
// (see web/index.html) only fires once something actually paints, so
// the customer sat on the JS splash's cycling status text the entire
// time -- which is what read as "3 animations before the app opens" on
// every single launch, not just the first.
//
// Fix: paint THIS tiny, dependency-free screen immediately (no Firebase,
// no providers, nothing it needs isn't available the instant the Dart
// VM boots) via an early runApp() call, before Firebase/Hive even start.
// That fires flutter-first-frame right away and swaps out the JS splash
// for this -- which looks IDENTICAL to BrandedLoadingScreen (same design
// as the JS splash by design, see branded_loading_screen.dart's own
// comment), so the customer never perceives a "swap" at all, just one
// continuous screen. Once Firebase/Hive phase 1 finish in the
// background, a second runApp(CustomerApp()) call below replaces this
// with the real app -- calling runApp() a second time is a normal,
// already-used pattern here (see _BootFailedApp below, which did this
// on the failure path before this fix existed).
class _BootLoadingApp extends StatelessWidget {
  const _BootLoadingApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: BrandedLoadingScreen(),
    );
  }
}

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

      // FIX (task #108, jet-speed startup): paint something -- anything
      // -- as the very first statement after the binding is ready, before
      // Firebase or Hive have even started. This is what actually kills
      // the "3 animations on every open" symptom: Flutter's first frame
      // now happens in milliseconds instead of after a Firebase network
      // round-trip, so the web JS splash (web/index.html) swaps out for
      // this near-instantly instead of sitting there for however long
      // Firebase takes. See _BootLoadingApp's comment above for why this
      // is safe to do a second runApp() over, below.
      runApp(const _BootLoadingApp());

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
      // FIX (boot-flicker root cause, task #108 follow-up): resolved
      // here, BEFORE runApp(CustomerApp(...)) below, instead of inside
      // _IntroGate's own initState() after the widget tree already
      // swapped over. A SharedPreferences read is a fast local
      // round-trip (not network) — doing it here costs a few
      // milliseconds added to the SAME already-in-flight boot phase 1
      // that's opening Hive boxes anyway, instead of forcing a THIRD
      // widget (the old _IntroGate's loading fallback) to mount after
      // runApp() just to wait for this exact same read.
      var showIntro = false;
      var showWelcome = false;

      try {
        await Hive.initFlutter();
        await CacheService().initCritical();

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

        final flags = await _resolveIntroFlags();
        showIntro = flags.showIntro;
        showWelcome = flags.showWelcome;

        // FIX (CTO mandate — Splash Screen Loop): the flags above are
        // the right source of truth for "has this device ever seen the
        // intro/welcome sequence" — that part already worked. This adds
        // a SECOND, independent guarantee on top: if a real, currently
        // signed-in Firebase session exists, skip both screens
        // regardless of what the flags say. Covers the case the flags
        // alone can't (e.g. app data partially cleared, or a device
        // that somehow never got the "seen" flag written but genuinely
        // has an active login) — a returning, logged-in customer should
        // never see onboarding again, full stop. `authStateChanges()`
        // is used instead of the synchronous `currentUser` getter
        // because on web the persisted session can still be loading
        // asynchronously immediately after Firebase.initializeApp()
        // returns; a bare `currentUser` check here could wrongly read
        // null for an actually-logged-in customer. Capped at 2s so a
        // slow/failed auth restore can never hang the cold boot the
        // rest of this file works hard to keep instant — falls back to
        // the flags-only result on timeout.
        try {
          final signedInUser = await FirebaseAuth.instance
              .authStateChanges()
              .first
              .timeout(const Duration(seconds: 2));
          if (signedInUser != null) {
            showIntro = false;
            showWelcome = false;
          }
        } catch (e) {
          debugPrint('[main_customer] auth-state bypass check skipped: $e');
        }
      } catch (error, stack) {
        debugPrint('Boot phase 1 error: $error\n$stack');
        if (AnalyticsService.isInitialized) {
          AnalyticsService.instance.recordError(error, stack);
        }
      }

      runApp(CustomerApp(showIntro: showIntro, showWelcome: showWelcome));

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
    },
  );
}

/// Reads (and, on first-ever launch, sets) the two "have they seen this
/// already" SharedPreferences flags that decide whether _IntroGate shows
/// the intro video and/or the language/sign-in welcome screen. Split out
/// of the old _IntroGateState.checkFirstLaunch() unchanged in behavior —
/// only WHEN it runs changed (see the boot-flicker fix comment above its
/// call site, and on _IntroGate itself, for why).
({bool showIntro, bool showWelcome}) _introFlagsResult(bool seenIntro, bool seenWelcome) =>
    (showIntro: !seenIntro, showWelcome: !seenWelcome);

Future<({bool showIntro, bool showWelcome})> _resolveIntroFlags() async {
  const seenIntroKey = 'has_seen_intro_video_v1';
  const seenWelcomeKey = 'has_seen_welcome_v1';
  try {
    final prefs = await SharedPreferences.getInstance();

    final seenIntro = prefs.getBool(seenIntroKey) ?? false;
    if (!seenIntro) {
      await prefs.setBool(seenIntroKey, true);
    }

    // Tracked separately from the video. They were introduced at
    // different times, so a customer who already has the intro flag set
    // from an earlier version should still be offered the language/
    // sign-in screen once.
    final seenWelcome = prefs.getBool(seenWelcomeKey) ?? false;
    if (!seenWelcome) {
      await prefs.setBool(seenWelcomeKey, true);
    }

    return _introFlagsResult(seenIntro, seenWelcome);
  } catch (e) {
    debugPrint('[main_customer] intro-flags check failed: $e');
    return _introFlagsResult(true, true); // seen=true -> show=false, safest default
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
        .get();
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
  // FIX (boot-flicker root cause): resolved once in main()'s boot phase
  // 1 (see _resolveIntroFlags()), before this widget is ever built, so
  // _IntroGate below never needs an async gap / loading placeholder of
  // its own. See _IntroGate's comment for the full story.
  final bool showIntro;
  final bool showWelcome;

  const CustomerApp({required this.showIntro, required this.showWelcome, super.key});

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
          // themeKey is left in place for now — same concern applies to
          // it, but theme switching mid-session isn't part of this fix
          // and changing it here would be an unrelated behaviour change.
          key: ValueKey('customer_${themeService.themeKey}'),
          navigatorKey: navigatorKey,
          title: localization.t('app_title'),
          debugShowCheckedModeBanner: false,
          theme: themeService.currentTheme,
          themeMode: ThemeMode.light,
          home: _IntroGate(showIntro: showIntro, showWelcome: showWelcome),
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
          navigatorObservers: [
            AnalyticsService.instance.getObserver(),
          ],
          // NEW (CTO mandate — Quick Task Global AI Overlay): the launcher
          // FAB lives here so it appears above every screen with zero
          // per-screen wiring, exactly like the CTO's "travels with the
          // user across ALL screens" requirement. The actual chat panel
          // is NOT built here -- it's a separate root-level OverlayEntry
          // (see GuruOverlayService.show()) inserted via `navigatorKey`,
          // so it survives Navigator.push/pop the same way this FAB does.
          builder: (context, child) => Stack(
            children: [
              if (child != null) child,
              const GlobalGuruFab(),
            ],
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
// First-launch intro video gate.
//
// FIX (task #108 follow-up, "3x animation flicker" root cause): this
// used to be a StatefulWidget that itself awaited SharedPreferences
// inside initState() and showed ANOTHER fresh BrandedLoadingScreen
// while that resolved (see the comment that used to be here about "no
// 4th different-looking flash" — the flash it was talking about
// avoiding was a visual-design difference, not the flicker itself).
// The real problem: that async gap happened INSIDE _IntroGate, which
// only exists after the boot sequence's second runApp(CustomerApp())
// call has already thrown away and rebuilt the entire widget tree from
// _BootLoadingApp. So a full cold boot painted BrandedLoadingScreen
// TWICE as two completely separate Elements — once as _BootLoadingApp
// pre-Firebase, once again here post-runApp() — and Flutter genuinely
// tears down/repaints the whole screen at that runApp() swap, which is
// what reads as a restart/flicker even though the two screens look
// pixel-identical.
//
// Fixed by resolving showIntro/showWelcome in main()'s boot phase 1
// (see _resolveIntroFlags()) BEFORE the second runApp() ever fires, and
// threading the two already-known booleans down through CustomerApp
// into this now-plain StatelessWidget. There is no async gap left in
// this widget at all, so it can never show a loading placeholder of
// its own — the ONLY loading screen in the entire cold-boot path is
// _BootLoadingApp, painted exactly once.
// ================================================================
class _IntroGate extends StatelessWidget {
  final bool showIntro;
  final bool showWelcome;

  const _IntroGate({required this.showIntro, required this.showWelcome});

  @override
  Widget build(BuildContext context) {
    // First launch runs the whole sequence:
    //   intro video -> welcome (language + sign-in) -> video splash -> home
    // Every launch after that goes straight to video splash -> home.
    // NEW (CTO mandate — Video Splash Screen, every launch): was
    // SplashSetupScreen (still used as-is by main_hero.dart — do not
    // touch that file/screen, this Customer-only swap must not affect
    // Hero). VideoSplashScreen wraps the exact same background
    // warm-up call, just layers the new splash video on top, capped at
    // a hard 5s so it can never add more delay than that regardless of
    // video/network state.
    const home = VideoSplashScreen(nextScreen: _CustomerHomeGate());
    final afterIntro =
        showWelcome ? const WelcomeScreen(next: home) : home;

    if (showIntro) {
      return IntroVideoScreen(next: afterIntro);
    }
    return afterIntro;
  }
}

class _CustomerHomeGate extends StatefulWidget {
  const _CustomerHomeGate();

  @override
  State<_CustomerHomeGate> createState() => _CustomerHomeGateState();
}

class _CustomerHomeGateState extends State<_CustomerHomeGate> {
  String? _lastUid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        final currentUid = user?.uid;

        if (_lastUid != currentUid) {
          _lastUid = currentUid;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            unawaited(context.read<AiActivationService>().refreshForUser(user));
          });
        }

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
        return const DashboardScreen();
      },
    );
  }
}
