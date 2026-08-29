// lib/main_seller.dart
// Allin1 — SELLER App Entry Point (Food/E-commerce Pipeline)

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_variant.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/seller_dashboard_screen.dart';
import 'screens/seller_home_kitchen_menu_screen.dart';
import 'screens/seller_onboarding_screen.dart';
import 'screens/seller_screen.dart';
import 'services/db_usage_tracker.dart';
import 'services/ai_activation_service.dart';
import 'services/localization_service.dart';
import 'services/migration_gate_service.dart';
import 'services/session_service.dart';
import 'services/theme_service.dart';
import 'services/seller_foreground_service.dart';
import 'services/seller_alert_notification_service.dart';
import 'widgets/branded_loading_screen.dart';
import 'widgets/migration_notice_overlay.dart';
import 'services/guru_overlay_service.dart';

// NEW (Issue 2 fix — "seller app not receiving any order notification").
// Zero-cost infra constraint: no Cloud Functions / Blaze plan, so this is
// NOT an FCM push. Reuses the EXACT SAME pattern main_hero.dart already
// runs in production for ride/service pings — a persistent RTDB
// `onChildAdded` listener attached at app boot (not scoped to a single
// screen, so it survives navigation) that fires a loud local notification
// via flutter_local_notifications. Same tradeoff hero already accepts:
// this only reaches a seller whose app process is still alive
// (foreground or backgrounded-but-not-killed, kept alive by
// SellerForegroundService) — there is no way to wake a fully killed app
// without a server push, which this project deliberately does not run.
//
// ServiceRequestService.createServiceRequest() writes the RTDB node this
// listens on (`seller_pings/{sellerId}/{requestId}`) — see that file for
// the write side and the 1GB-budget cleanup story.
StreamSubscription<User?>? _sellerPingAuthSub;
StreamSubscription<DatabaseEvent>? _sellerPingSub;

void _initSellerPingListener() {
  _sellerPingAuthSub?.cancel();
  _sellerPingAuthSub = FirebaseAuth.instance.authStateChanges().listen((user) {
    _sellerPingSub?.cancel();
    if (user == null) {
      debugPrint('[SellerPing] User logged out — stopping listener');
      return;
    }

    final uid = user.uid;
    debugPrint('[SellerPing] Attaching global seller_pings/$uid listener');

    _sellerPingSub = FirebaseDatabase.instance
        .ref('seller_pings/$uid')
        .onChildAdded
        .listen((event) async {
      final pingData = event.snapshot.value as Map<dynamic, dynamic>?;
      final requestId = event.snapshot.key ?? '';
      if (pingData == null || requestId.isEmpty) return;

      final nodeRef = FirebaseDatabase.instance.ref('seller_pings/$uid/$requestId');

      // 1GB RTDB budget (per Nizam/CTO's zero-cost constraint): a ping is
      // a wake-up trigger, not the order record itself (the seller's
      // order list is Firestore `service_requests`, already cached via
      // HiveCache in seller_dashboard_screen.dart) — so it is always safe
      // to delete it the moment it's been read, whether that's because
      // it fired a notification below or because it's stale. Nothing
      // else in the app depends on this node continuing to exist.
      final pingExpiresAt = (pingData['pingExpiresAt'] as num?)?.toInt();
      if (pingExpiresAt != null &&
          DateTime.now().toUtc().millisecondsSinceEpoch > pingExpiresAt) {
        debugPrint('[SellerPing] Expired ping — removing: $requestId');
        await nodeRef.remove();
        return;
      }

      debugPrint('[SellerPing] ✅ New order ping received: $requestId');

      if (!kIsWeb) {
        try {
          // The ping payload already carries everything needed to show
          // the alert (customerName/itemsSummary written at order-creation
          // time — see ServiceRequestService.createServiceRequest) so this
          // never needs an extra Firestore read just to notify.
          final customerName = pingData['customerName'] as String? ?? 'A customer';
          final itemsSummary = pingData['itemsSummary'] as String? ?? '';
          await SellerAlertNotificationService.showForegroundAlert(
            title: '🛎️ New Order Received!',
            body: itemsSummary.isNotEmpty
                ? '$customerName: $itemsSummary'
                : '$customerName placed a new order — open the app to accept and pack.',
            payloadId: 'order_$requestId',
          );
          debugPrint('[SellerPing] 🔔 Notification fired for: $requestId');
        } catch (e) {
          debugPrint('[SellerPing] Notification error: $e');
        }
      }

      await nodeRef.remove();
    }, onError: (Object e) {
      debugPrint('[SellerPing] RTDB listener error: $e');
    });
  });
}

// FIX (Aug 10 2026 — Nizam's "video every launch is too slow / disturbs
// repeat users" report, same pattern as main_customer.dart/main_hero.dart):
// gates whether the splash video plays at all. Set (once) only after the
// video has actually finished playing on a first-ever launch — see the
// branch in main() below. Every launch after that reads this as true and
// skips straight past the video AND past any blocking loading screen.
const String _kSplashVideoSeenEverKey = 'seller_splash_video_seen_ever_v1';

// FIX (Nizam's "video as natural visual buffer" request, task #108, same
// fix as main_customer.dart/main_hero.dart): paint app_splash.mp4 first,
// before Firebase even starts, so Flutter's first frame fires in
// milliseconds instead of after a Firebase network round-trip, AND the
// video itself becomes the boot buffer while Firebase inits in parallel
// behind it. Previously the video was shown AFTER Firebase, at the
// SellerApp '/' route below — moved here and removed there (see
// SellerApp.build for that change) so it's no longer a second screen
// stacked after this one. BrandedLoadingScreen is now only a rare
// fallback frame, shown only if Firebase init somehow outlasts the video.
//
// FIX (Aug 10 2026 — first-launch-only video): this class itself is
// UNCHANGED — still the video screen described above. What changed is
// main() no longer runApp()s it unconditionally: it now only does so the
// very first time this device/browser ever opens the seller app (see
// _kSplashVideoSeenEverKey above). Every later launch skips this widget
// entirely and goes straight to SellerApp — see the branch in main() below.
// UPDATED (Aug 12 2026 — CEO/CTO "nuke the videos"): this used to mount
// AppSplashVideoScreen, which streamed the 2.1MB app_splash.mp4 before
// anything else. On web that was 2.1MB of Firebase Hosting bandwidth per
// visitor for a decorative splash; the pure CSS/SVG route-draw animation
// now living in web/index.html covers that same pre-engine moment for
// zero bytes, and it paints even earlier (before main.dart.js is parsed).
// Native simply goes straight to the branded frame.
//
// CRITICAL: onVideoFinished completes the `videoDone` completer that
// main()'s boot sequence awaits. It MUST still fire exactly once or the
// app hangs on this screen forever — hence the StatefulWidget + a
// post-frame callback in initState (fires once per mount) rather than
// calling it from build(), which can run many times.
class _BootLoadingApp extends StatefulWidget {
  const _BootLoadingApp({required this.onVideoFinished});

  final VoidCallback onVideoFinished;

  @override
  State<_BootLoadingApp> createState() => _BootLoadingAppState();
}

class _BootLoadingAppState extends State<_BootLoadingApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onVideoFinished();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: BrandedLoadingScreen(),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // FIX (Aug 17 2026 — "seller app phone la install aiduchu but open
  // agama load aitruku", fresh install, nothing but Android/Sentry logs
  // and not a single I/flutter line):
  //
  // This used to be `await SellerAlertNotificationService.initialize();`
  // right here — the FIRST await in main(), before Sentry, before
  // Firebase, and critically before ANY runApp(). Two things made that
  // a boot-stopper on a freshly installed app:
  //
  //   1. initialize() ends with requestNotificationsPermission(). On
  //      Android 13+ that raises the POST_NOTIFICATIONS system dialog.
  //      Awaiting a user-facing permission dialog before the engine has
  //      painted a single frame means the app sits on the bare Android
  //      launch background until it is answered — which looks exactly
  //      like "loading forever", and taps land on nothing.
  //   2. initialize() had no try/catch of its own (it does now, see that
  //      file). Any throw from the plugin — and a fresh install is
  //      precisely when channel creation/permission plumbing is most
  //      likely to fail — propagated out of main() BEFORE runApp() had
  //      ever been called. The result is an app with no Flutter UI at
  //      all, forever, with no Dart error visible unless you are
  //      filtering logcat for it.
  //
  // Nothing is removed: notifications still initialise, just fired
  // unawaited AFTER runApp(SellerApp()) below — the same
  // "non-essential-to-first-frame work goes after runApp" pattern the
  // rest of this file (and main_customer.dart's _warmCustomerServices)
  // already follows. A seller's first order cannot arrive in the
  // milliseconds this saves, so there is no functional loss.
  //
  // SellerForegroundService.initialize() stays here: it is synchronous,
  // fully wrapped in its own try/catch, and never shows a dialog.
  SellerForegroundService.initialize();

  // FIX (audit finding — notifications_screen.dart hardcoded
  // 'customer' fallback): see lib/config/app_variant.dart.
  currentAppVariant = 'seller';

  await SentryFlutter.init(
    (options) {
      options.dsn =
          'https://208217846f0b9708dc26f1d5d812eefc@o4511799785553920.ingest.us.sentry.io/4511799822843904';
      options.tracesSampleRate = 1.0;
      // FIX (Aug 17 2026 — while diagnosing "seller app never opens"):
      // SentryFlutter defaults options.debug to kDebugMode, so on every
      // debug run the SDK prints its own internal chatter — "Serializing
      // object: {...}" for EVERY breadcrumb, plus one "Unable to find
      // scroll/click target" per touch event. That is hundreds of lines
      // a second, and it completely buries the Dart output (uncaught
      // exceptions, our own debugPrint) that we actually need to read to
      // find a boot failure. Error/crash REPORTING is untouched — this
      // only silences the SDK's own verbose logging about itself.
      options.debug = false;
    },
    appRunner: () async {
      // videoDone completes when app_splash.mp4 finishes playing; the
      // second runApp() below (SellerApp) awaits it so the video is never
      // cut short by a fast Firebase init.
      //
      // FIX (Aug 10 2026 — first-launch-only video, "rocket speed" repeat
      // opens): a SharedPreferences read (fast, local, no network) decides
      // right here whether this device has ever seen the video before.
      // First-ever launch: unchanged behavior — _BootLoadingApp (video)
      // paints immediately. Every later launch: videoDone is marked
      // complete immediately (nothing to wait for) and _BootLoadingApp is
      // never even built.
      final earlyPrefs = await SharedPreferences.getInstance();
      final hasSeenSplashVideoEver =
          earlyPrefs.getBool(_kSplashVideoSeenEverKey) ?? false;

      final videoDone = Completer<void>();
      if (!hasSeenSplashVideoEver) {
        runApp(_BootLoadingApp(onVideoFinished: () {
          if (!videoDone.isCompleted) videoDone.complete();
        }));
      } else {
        videoDone.complete();
      }
      // ================================================================
      // ROOT CAUSE FIX (Aug 17 2026) — "seller app phone la install
      // aiduchu but ulla pogave illa", stuck forever on the branded
      // loading screen.
      // ================================================================
      // This was a BARE, UNGUARDED call — the only one of the four apps
      // without a guard. Compare:
      //   main_admin.dart:263    if (Firebase.apps.isEmpty) { ...init... }
      //   main_customer.dart:109 if (Firebase.apps.isNotEmpty) return;  + try/catch + retry
      //   main_hero.dart:85      same guard + try/catch
      //   main_seller.dart       <- nothing
      //
      // Why that breaks ONLY on Android, and ONLY for seller:
      // android/app/google-services.json makes Firebase's native
      // FirebaseInitProvider create the [DEFAULT] app automatically,
      // before a single line of Dart runs — using the real appId
      // registered for com.njtech.allin1.seller. So by the time we get
      // here, Firebase.apps is already NON-empty. Calling
      // initializeApp() again with DIFFERENT options then throws
      // [core/duplicate-app].
      //
      // And the options genuinely are different: firebase_options.dart's
      // android appId is '1:357526153693:android:4aee34', which is not a
      // valid Firebase Android app id at all (real ones end in a long
      // hex string — this one looks like the tail of the WEB id pasted
      // in by hand). It matches no client in google-services.json.
      //
      // That throw escaped this appRunner closure, so
      // runApp(const SellerApp()) below was never reached — leaving
      // _BootLoadingApp's BrandedLoadingScreen on screen forever, with
      // no crash and no error dialog. Exactly the reported symptom.
      //
      // Fix mirrors what the other three apps already do: skip
      // initialisation when the native side has already done it, and
      // never let a failure here stop the app from painting. Nothing is
      // removed — on a platform where Firebase is NOT pre-initialised
      // (web), the options path runs exactly as before.
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        }
      } catch (e) {
        // Never fatal: a seller staring at a splash screen forever is
        // strictly worse than a seller getting into the app with a
        // degraded Firebase. Firestore/Auth calls will surface their own
        // errors in-app if initialisation really did fail.
        debugPrint('[main_seller] Firebase init issue (non-fatal): $e');
      }
      // Enable Firestore offline persistence on web (PWA). Mobile
      // (Android/iOS) already has persistence on by default, so this
      // is guarded to web only; a capped 50MB cache (CTO-specified)
      // keeps browser storage bounded instead of unlimited.
      if (kIsWeb) {
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: 52428800, // 50MB
          // FIX (Aug 10 2026, UPDATED Aug 11 2026 — same QUIC/
          // Firestore-Listen-channel fix applied to main_customer.dart/
          // main_hero.dart, for consistency across all 4 apps; switched
          // from auto-detect to forced long-polling since auto-detect
          // proved unreliable): see main_hero.dart for the full
          // explanation.
          webExperimentalForceLongPolling: true,
        );
      }
      DbUsageTracker.instance.init('seller');

      // NEW (Issue 2 fix — "seller app not receiving any order
      // notification"): attaches the global seller_pings/{uid} RTDB
      // listener the moment a seller is signed in (fresh login or a
      // warm session restored from disk) — same zero-cost RTDB pattern
      // main_hero.dart already runs for ride/service pings, no Cloud
      // Functions involved. See _initSellerPingListener above.
      _initSellerPingListener();

      // NOTE (boot-flicker audit, per Nizam's request to mirror the fix
      // across all 4 apps): unlike main_customer.dart/main_hero.dart/
      // main_admin.dart, SellerApp's root route goes straight to
      // LoginScreen ('/') with no auth-stream gate at the app root at
      // all — there's no second loading widget mounted after this
      // runApp() swap to collapse here. On a first-ever launch, the only
      // two screens painted during a seller cold boot are the pre-Firebase
      // _BootLoadingApp (video) and then LoginScreen itself — already a
      // single continuous mount, nothing to fix structurally. On every
      // later launch there's no splash frame at all — see below. (Separately
      // worth knowing: a seller with an existing Firebase Auth session
      // still sees the login FORM on every relaunch instead of skipping
      // straight to SellerDashboardScreen — a real UX gap, but a
      // different issue from the boot flicker asked about here.)
      //
      // Gate the real-app swap on the video having finished playing (it
      // almost always has, by now — Firebase init is the fast side of
      // this race) so the boot video is never truncated mid-playback. On a
      // repeat launch videoDone was already completed above (no video was
      // ever shown), so this resolves instantly and adds no wait — Firebase
      // init above (a local-session restore, not a fresh network call in
      // the common case) is the only thing standing between "app opens"
      // and runApp(SellerApp()) on a repeat launch.
      await videoDone.future;
      runApp(const SellerApp());

      // Moved down from the top of main() — see the long comment there.
      // Fire-and-forget: the seller's UI is already on screen, and a
      // failure here must never be able to stop the app from opening.
      unawaited(SellerAlertNotificationService.initialize());
      // NEW (Aug 12 2026 — "Zero-Budget Escape Hatch"): fire-and-forget,
      // fails open on any error — see MigrationGateService's own header.
      MigrationGateService.instance.start();

      // Mark the video as seen only now that it has actually finished
      // playing (videoDone is only completed by AppSplashVideoScreen's own
      // onFinished/safety-timer, or immediately above if it was already
      // skipped) — every launch from here on takes the "skip video" branch.
      if (!hasSeenSplashVideoEver) {
        unawaited(earlyPrefs.setBool(_kSplashVideoSeenEverKey, true));
      }
    },
  );
}

class SellerApp extends StatelessWidget {
  const SellerApp({super.key});

  @override
  Widget build(BuildContext context) {
    // LocalizationService (en/ta/tg) made available app-wide, same as
    // customer/hero/admin apps — seller had zero language
    // infrastructure before this (see language-system audit).
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocalizationService()),
        // FIX (Nizam's request: same theme-switcher pattern as customer
        // and hero apps): seller app used to have a hardcoded dark
        // ThemeData with no way to change it, and no Settings screen to
        // change it from. Now shares the same ThemeService (5 selectable
        // themes), switchable from seller_settings_screen.dart.
        ChangeNotifierProvider(create: (_) => ThemeService()),
        // REQUIRED as of Aug 19 2026 — see the identical note in
        // main_hero.dart. GlobalGuruFab reads activation state from
        // here to decide whether Chitti is visible at all.
        ChangeNotifierProvider(create: (_) => AiActivationService()),
      ],
      child: Consumer<ThemeService>(
        builder: (context, themeService, _) => MaterialApp(
      title: 'Allin1 Partner Dashboard',
      debugShowCheckedModeBanner: false,
      // FIX (Nizam's request): was a hardcoded ThemeData.dark() copyWith
      // -- now driven by ThemeService.currentTheme so the seller can
      // actually change it from Settings, same as customer/hero. The
      // textTheme/brand-font handling ThemeService.currentTheme applies
      // internally already matches what this hardcoded block used to do
      // by hand (AppBrandTheme.brandTextTheme with the Tamil fallback).
      theme: themeService.currentTheme,
      initialRoute: '/',
      routes: {
        // FIX (video-as-natural-buffer, per Nizam's request): app_splash.mp4
        // plays pre-Firebase as the very first boot frame (see
        // _BootLoadingApp above) instead of here — this route used to wrap
        // LoginScreen in a second AppSplashVideoScreen play, which would
        // have shown the same video twice back to back on every launch.
        // Now goes straight to LoginScreen.
        // UPDATED (Aug 10 2026): the pre-Firebase video itself is now
        // first-ever-launch-only (see _kSplashVideoSeenEverKey in main())
        // — on every later launch nothing plays before this route at all.
        '/': (_) => const LoginScreen(
              presetUserType: UserType.customer,
              lockUserType: true,
              title: 'Seller Login',
              subtitle: 'Manage your Allin1 store',
              lockedUserLabel: 'Seller',
              postLoginRoute: '/seller-home',
            ),
        '/seller-home': (_) => const SellerDashboardScreen(),
        '/seller-store': (_) => const SellerScreen(),
        '/seller-onboarding': (_) => const SellerOnboardingScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/seller-menu-setup') {
          final sellerId = settings.arguments! as String;
          // FIX (per Nizam's request): every seller authors their own
          // custom dishes now — see seller_dashboard_screen.dart and
          // seller_onboarding_screen.dart for the same change.
          return MaterialPageRoute(
            builder: (_) => SellerHomeKitchenMenuScreen(sellerId: sellerId, title: 'My Menu', categoryName: 'Menu'),
          );
        }
        return null;
      },
      // NEW (Aug 12 2026 — "Zero-Budget Escape Hatch"): Seller app had no
      // builder: before this — added purely to host MigrationGate, same
      // pattern as the other 3 apps. child can briefly be null on the very
      // first MaterialApp build, so fall back to an empty box.
      // Also hosts GlobalGuruFab for Seller Chitti Assistant.
      builder: (context, child) => Stack(
        children: [
          MigrationGate(child: child ?? const SizedBox.shrink()),
          const GlobalGuruFab(),
        ],
      ),
        ),
      ),
    );
  }
}
