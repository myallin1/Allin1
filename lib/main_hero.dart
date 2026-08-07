import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_navigator.dart';
import 'config/api_config.dart';
import 'firebase_options.dart';
import 'screens/app_splash_video_screen.dart';
import 'screens/bike_taxi/hero_dashboard_shell.dart';
import 'screens/hero_login_screen.dart';
import 'screens/hero_pending_screen.dart';
import 'screens/hero_register_screen.dart';
import 'screens/splash_setup_screen.dart';
import 'services/db_usage_tracker.dart';
import 'services/hero_foreground_service.dart';
import 'services/hero_ride_notification_service.dart';
import 'services/hero_web_audio_service.dart';
import 'services/localization_service.dart';
import 'services/map_service.dart';
import 'services/theme_service.dart';
import 'widgets/branded_loading_screen.dart';

String? _rideIdFromPushData(Map<String, dynamic> data) {
  for (final key in const <String>[
    'rideId',
    'ride_id',
    'rideDocId',
    'ride_doc_id',
  ]) {
    final value = data[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}

// FCM Data Push Layer 2 (CTO mandate — instant dispatch to a killed
// app): the generic (non-bike-taxi) service_requests dispatch payload
// carries `requestId`/`requestType` rather than a ride ID — see the
// new Cloud Functions notifyHeroOnPing/notifyHeroOnServicePing in
// functions/, which fire on the exact same hero_pings/
// hero_service_pings RTDB writes every existing dispatch path
// (broadcast, admin manual assign, call-center pre-assign) already
// makes, so no client dispatch code needed to change.
String? _serviceRequestIdFromPushData(Map<String, dynamic> data) {
  for (final key in const <String>['requestId', 'request_id']) {
    final value = data[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}

const String kPendingHeroServiceRequestIdKey = 'pending_hero_service_request_id';

Future<void> _ensureFirebaseInitialized() async {
  if (Firebase.apps.isNotEmpty) {
    return;
  }

  try {
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
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') {
      debugPrint('[main_hero] Firebase already initialized, continuing.');
      return;
    }
    rethrow;
  }
}

// FIX (black/white-screen-stuck audit, per Nizam's request): fallback
// shown when Firebase can't be reached even after retries. Previously
// _ensureFirebaseInitialized() was awaited with NO try/catch at all in
// the appRunner below — on any failure (a transient network blip is a
// real possibility on weaker Erode mobile connections; this is a real
// network call) the exception just propagated out and runApp() below
// never ran. The Flutter engine had nothing to paint, forever — no
// error, no retry, just a permanently blank/black tab. Deliberately
// tiny/dependency-free here (no theming service, no providers) since
// those aren't initialized yet at this point in boot.
// FIX (Nizam's "jet-speed startup" request, task #108, same fix as
// main_customer.dart): paint this instantly, before Firebase/Hive start,
// so Flutter's first frame fires in milliseconds instead of after a
// Firebase network round-trip -- that wait was the actual cause of the
// "app takes a while to open with some animation running" symptom.
// Reuses BrandedLoadingScreen (already dependency-free, no Provider
// needed) rather than inventing a hero-specific one.
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

class _BootFailedApp extends StatelessWidget {
  final VoidCallback onRetry;
  const _BootFailedApp({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFFFFBFE),
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

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(ObjectFlagProperty<VoidCallback>.has('onRetry', onRetry));
  }
}

// ── Global RTDB Hero Ping Listener (Auth-Aware) ──────────────────
// Survives UI dispose & handles Login/Logout dynamically
StreamSubscription<DatabaseEvent>? _globalHeroPingSub;
StreamSubscription<DatabaseEvent>? _globalServicePingSub;
StreamSubscription<User?>? _authSub;
StreamSubscription<String>? _fcmTokenRefreshSub;

// FCM Data Push Layer 2 (CTO mandate — Task 1: entry-point setup):
// the Cloud Function send path (functions/notifyHeroOnPing.ts et al.)
// reads `heroes/{uid}.fcmToken` — nothing in the app wrote that field
// before this, so every send attempt would silently no-op on a missing
// token regardless of how well the send/receive plumbing worked.
// Captures the token once per auth session and keeps it current via
// onTokenRefresh (a real device can get a new token at any time — app
// reinstall, token rotation, etc.). Best-effort: a failure here must
// never block hero login/boot.
Future<void> _syncFcmTokenForHero(String uid) async {
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && token.trim().isNotEmpty) {
      // .set(merge:true) rather than .update() — a hero mid-registration
      // (auth session exists, heroes/{uid} doc doesn't yet) must not
      // silently fail the token write with a not-found error.
      await FirebaseFirestore.instance.collection('heroes').doc(uid).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('[FCM] Token synced for hero $uid');
    }
  } catch (e) {
    debugPrint('[FCM] Token sync failed for hero $uid: $e');
  }

  _fcmTokenRefreshSub?.cancel();
  _fcmTokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    unawaited(
      FirebaseFirestore.instance.collection('heroes').doc(uid).set({
        'fcmToken': newToken,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((Object e) {
        debugPrint('[FCM] Token refresh write failed for hero $uid: $e');
      }),
    );
  }, onError: (Object e) {
    debugPrint('[FCM] onTokenRefresh listener error: $e');
  });
}

void _initGlobalHeroPingListener() {
  _authSub?.cancel();
  _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
    _globalHeroPingSub?.cancel(); // Clear existing listener
    _globalServicePingSub?.cancel();

    if (user == null) {
      debugPrint('[GlobalPing] User logged out — stopping listener');
      _fcmTokenRefreshSub?.cancel();
      _fcmTokenRefreshSub = null;
      return;
    }

    final uid = user.uid;
    unawaited(_syncFcmTokenForHero(uid));
    debugPrint('[GlobalPing] Attaching global hero_pings/$uid listener');

    _globalHeroPingSub = FirebaseDatabase.instance
        .ref('hero_pings/$uid')
        .onChildAdded
        .listen((event) async {
      final pingData = event.snapshot.value as Map<dynamic, dynamic>?;
      final requestId = event.snapshot.key ?? '';
      if (pingData == null || requestId.isEmpty) return;

      // Expiry check
      final pingExpiresAt = (pingData['pingExpiresAt'] as num?)?.toInt();
      if (pingExpiresAt == null) return;
      if (DateTime.now().toUtc().millisecondsSinceEpoch > pingExpiresAt) {
        debugPrint('[GlobalPing] Expired ping — removing: $requestId');
        await FirebaseDatabase.instance.ref('hero_pings/$uid/$requestId').remove();
        return;
      }

      debugPrint('[GlobalPing] ✅ New ping received: $requestId');

      // De-duplication check
      if (!await HeroRideNotificationService.shouldProcessRideNotification(requestId)) {
        debugPrint('[GlobalPing] ⏭️ Duplicate ping skipped: $requestId');
        return;
      }

      // Fire local notification using the new v5 channel configuration
      // Note: playAlertTone: false here — ringtone will be triggered by _showRideRequestDialog
      // AFTER the dialog is visible, so it loops continuously while the hero sees it.
      if (!kIsWeb) {
        try {
          await HeroRideNotificationService.showRideAssigned(
            rideId: requestId,
            data: Map<String, dynamic>.from(pingData),
            playAlertTone: false,
            showDetails: false,
          );
          debugPrint('[GlobalPing] 🔔 Notification fired for: $requestId');
        } catch (e) {
          debugPrint('[GlobalPing] Notification error: $e');
        }
      }
    }, onError: (Object e) {
      debugPrint('[GlobalPing] RTDB listener error: $e');
    },);

    // ── Broadcast Order System — parallel ping channel ────────────
    // Same wake/notification mechanism as hero_pings, generic text.
    // The in-app accept dialog is handled by hero_home_screen.dart's
    // own hero_service_pings listener; this only fires the
    // lock-screen notification so the hero is woken up.
    debugPrint('[GlobalServicePing] Attaching global hero_service_pings/$uid listener');
    _globalServicePingSub = FirebaseDatabase.instance
        .ref('hero_service_pings/$uid')
        .onChildAdded
        .listen((event) async {
      final pingData = event.snapshot.value as Map<dynamic, dynamic>?;
      final requestId = event.snapshot.key ?? '';
      if (pingData == null || requestId.isEmpty) return;

      final pingExpiresAt = (pingData['pingExpiresAt'] as num?)?.toInt();
      if (pingExpiresAt == null) return;
      if (DateTime.now().toUtc().millisecondsSinceEpoch > pingExpiresAt) {
        debugPrint('[GlobalServicePing] Expired ping — removing: $requestId');
        await FirebaseDatabase.instance.ref('hero_service_pings/$uid/$requestId').remove();
        return;
      }

      debugPrint('[GlobalServicePing] ✅ New service ping received: $requestId');

      if (!await HeroRideNotificationService.shouldProcessRideNotification(requestId)) {
        debugPrint('[GlobalServicePing] ⏭️ Duplicate ping skipped: $requestId');
        return;
      }

      if (!kIsWeb) {
        try {
          await HeroRideNotificationService.showRideAssigned(
            rideId: requestId,
            data: Map<String, dynamic>.from(pingData),
            playAlertTone: false,
            showDetails: false,
            title: 'New Service Request',
            channelDescription:
                'Lock-screen ride and service-request alerts with ACCEPT action and ringtone.',
            ticker: 'New service request assigned',
            emptyBodyFallback: 'Tap ACCEPT to open the request.',
          );
          debugPrint('[GlobalServicePing] 🔔 Notification fired for: $requestId');
        } catch (e) {
          debugPrint('[GlobalServicePing] Notification error: $e');
        }
      }
    }, onError: (Object e) {
      debugPrint('[GlobalServicePing] RTDB listener error: $e');
    },);
  });
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await _ensureFirebaseInitialized();
  if (kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: 52428800, // 50MB
    );
  }
  final rideId = _rideIdFromPushData(message.data);
  if (rideId != null) {
    // FIX (per Nizam's bug report — "app close pannitu vachurunthalum
    // high ringtone adikka mattingithu"): this used to assume FCM's
    // system tray already plays a sound for a killed app, so it
    // suppressed our own ringtone to "avoid a duplicate". That's only
    // true for a `notification`-block FCM message — this pipeline
    // sends DATA-ONLY payloads specifically so the app controls the
    // whole UX (see the FCM Data Push Layer 2 comments elsewhere in
    // this file); Android never auto-plays any sound for a data-only
    // message on its own. Suppressing our own tone meant NOTHING ever
    // played when the app was killed. Now always plays it.
    await HeroRideNotificationService.showRideAssigned(
      rideId: rideId,
      data: message.data,
      playAlertTone: true,
      showDetails: false,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPendingHeroRideIdKey, rideId);
  } else {
    // FCM Data Push Layer 2 — same killed-app wake path as the ride
    // branch above, for the generic service_requests dispatch pipeline
    // (hero_booking / custom_food_order / grocery_order / etc.), keyed
    // by requestId instead of rideId.
    final requestId = _serviceRequestIdFromPushData(message.data);
    if (requestId != null) {
      await HeroRideNotificationService.showRideAssigned(
        rideId: requestId,
        data: message.data,
        playAlertTone: true,
        showDetails: false,
        title: 'New Service Request',
        channelDescription:
            'Lock-screen ride and service-request alerts with ACCEPT action and ringtone.',
        ticker: 'New service request assigned',
        emptyBodyFallback: 'Tap ACCEPT to open the request.',
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPendingHeroServiceRequestIdKey, requestId);
    }
  }
  debugPrint(
    '[main_hero] Background push received: ${message.messageId} '
    'title=${message.notification?.title}',
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sentry wraps the rest of main() as its appRunner — same pattern as
  // main_customer.dart. Firebase init, the ping listener, runApp(), and
  // the post-frame warm-up all run unchanged, just inside Sentry's zone.
  await SentryFlutter.init(
    (options) {
      options.dsn =
          'https://208217846f0b9708dc26f1d5d812eefc@o4511799785553920.ingest.us.sentry.io/4511799822843904';
      options.tracesSampleRate = 1.0;
    },
    appRunner: () async {
      // FIX (task #108, jet-speed startup): see _BootLoadingApp's comment
      // above -- this must run before anything Firebase/Hive-related.
      runApp(const _BootLoadingApp());

      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // FIX (black/white-screen-stuck audit, per Nizam's request): retry
      // a few times with a short delay (covers the common transient
      // network-blip case) before giving up; on total failure show an
      // in-app Retry screen instead of leaving the tab blank — see
      // _BootFailedApp comment above for the full failure mode this
      // closes.
      var firebaseReady = false;
      Object? lastFirebaseError;
      for (var attempt = 1; attempt <= 3 && !firebaseReady; attempt++) {
        try {
          await _ensureFirebaseInitialized();
          firebaseReady = true;
        } catch (e) {
          lastFirebaseError = e;
          debugPrint('[main_hero] Firebase init attempt $attempt failed: $e');
          if (attempt < 3) {
            await Future<void>.delayed(const Duration(seconds: 2));
          }
        }
      }
      if (!firebaseReady) {
        debugPrint('[main_hero] Fatal: Firebase init failed after retries: $lastFirebaseError');
        runApp(const _BootFailedApp(onRetry: main));
        return;
      }
      DbUsageTracker.instance.init('hero');
      await HeroRideNotificationService.initialize();
      // CTO mandate — FCM Layer 2 alternative, Option D: registers the
      // "You are Online" foreground-service notification channel.
      // Cheap/synchronous, does not start the service itself (that
      // only happens when a hero actually goes Online — see
      // hero_home_screen.dart's _syncOnlineStatus).
      HeroForegroundService.initialize();

      // Start global RTDB ping listener reacting to Auth changes
      _initGlobalHeroPingListener();

      runApp(const HeroApp());
      unawaited(_warmHeroServices());
    },
  );
}

Future<void> _warmHeroServices() async {
  try {
    // MUST precede MapService(): constructing the singleton reads the Ola
    // API key from dotenv. This warm-up runs concurrently with runApp(),
    // so without this it used to beat SplashSetupScreen's load() on web
    // and cache an empty key for the whole session.
    await ApiConfig.ensureEnvLoaded();
    debugPrint('[main_hero] Initializing MapService...');
    await MapService().initialize();
    debugPrint(
      '[main_hero] MapService ready provider=${MapService().currentProvider.name} '
      'fallback=${MapService().isUsingFallback}',
    );
  } catch (e) {
    debugPrint('[main_hero] MapService init error: $e');
  }
}

class HeroApp extends StatelessWidget {
  const HeroApp({super.key});

  @override
  Widget build(BuildContext context) {
    // LocalizationService (en/ta/tg) is now available app-wide — see
    // hero_settings_screen.dart's language picker, which used to save
    // to a shared_preferences key nothing else ever read.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocalizationService()),
        // FIX (Nizam's 5-theme request): Hero app used to have its own
        // hardcoded pink ThemeData with no way to change it. Now shares
        // the same ThemeService as the customer app (5 selectable
        // themes), switchable from hero_settings_screen.dart.
        ChangeNotifierProvider(create: (_) => ThemeService()),
      ],
      child: Consumer<ThemeService>(
        builder: (context, themeService, _) => GestureDetector(
          onTap: () {
            if (kIsWeb) HeroWebAudioService().unlock();
          },
          child: MaterialApp(
            // FIX (CTO mandate — Task 2: Global Theme Propagation): the
            // customer app's MaterialApp already forces a full-tree
            // rebuild on theme change via a ValueKey keyed off
            // themeService.themeKey (see main_customer.dart) — the Hero
            // app's MaterialApp never had that, so while
            // theme: themeService.currentTheme WAS reactive at the
            // MaterialApp level itself, deeper widgets that read
            // ThemeService directly (rather than via Theme.of(context),
            // which already rebuilds correctly on its own) could lag
            // behind a live theme switch until their own screen
            // happened to rebuild for some other reason. Matching the
            // customer app's proven pattern here for consistency.
            key: ValueKey<String>('hero_${themeService.themeKey}'),
            navigatorKey: navigatorKey,
            title: 'hero allin1',
            debugShowCheckedModeBanner: false,
            theme: themeService.currentTheme,
            themeMode: ThemeMode.light,
            initialRoute: '/',
            routes: {
              // NEW (per Nizam's request — shared splash video, all 4
              // apps): AppSplashVideoScreen plays app_splash.mp4 first
              // (with audio, full-screen stretch, hard-capped so it can
              // never add real delay), THEN hands off to the existing
              // SplashSetupScreen exactly as before — its own warm-up/
              // auth-gating logic is completely untouched.
              '/': (_) => const AppSplashVideoScreen(
                    nextScreen: SplashSetupScreen(nextScreen: _HeroSetupGate()),
                  ),
              '/hero-home': (_) => const SplashSetupScreen(nextScreen: _HeroSetupGate()),
              '/hero-ride': (_) => const SplashSetupScreen(nextScreen: _HeroSetupGate()),
            },
          ),
        ),
      ),
    );
  }
}

class _HeroSetupGate extends StatefulWidget {
  const _HeroSetupGate();

  @override
  State<_HeroSetupGate> createState() => _HeroSetupGateState();
}

class _HeroSetupGateState extends State<_HeroSetupGate> {
  // FIX (root cause of "hero silently goes offline after visiting
  // Profile/Earnings and coming back"): these two .get() calls used to
  // be created INLINE inside build() (as `future: FirebaseFirestore...
  // .get()`), so every time this StatelessWidget rebuilt — which
  // happens on every authStateChanges() emission, and Firebase Auth's
  // web SDK re-emits that stream on things like tab/window focus
  // changes and ID token refresh, not just real login/logout — brand
  // new Futures were handed to FutureBuilder. FutureBuilder resets to
  // ConnectionState.waiting for a new Future instance, which made
  // _buildFadingChild render the 'hero-approval-check-loading' key
  // instead of 'hero-dashboard'. Because AnimatedSwitcher tears down
  // and rebuilds its child whenever the KeyedSubtree's key changes,
  // this fully UNMOUNTED the live HeroDashboardShell (resetting its
  // bottom-nav tab back to Home) and disposed HeroHomeScreen's State —
  // whose dispose() removes the hero's `online_heroes/{uid}` RTDB
  // radar entry. The hero then saw a fresh HeroHomeScreen that starts
  // `_isOnline = false` until its own async reload catches up, exactly
  // matching the reported "toggle Online, visit Profile/Earnings, come
  // back to Home and it's Offline again."
  //
  // Caching the Futures per-uid (only recreated on an ACTUAL uid
  // change, i.e. a real login/logout) means repeat authStateChanges
  // emissions for the same signed-in hero reuse an already-completed
  // Future, so FutureBuilder stays at ConnectionState.done and
  // _buildFadingChild keeps rendering the SAME 'hero-dashboard' key —
  // AnimatedSwitcher then treats it as an unchanged child and never
  // tears down HeroDashboardShell.
  String? _cachedUid;
  Future<DocumentSnapshot<Map<String, dynamic>>>? _usersDocFuture;
  Future<DocumentSnapshot<Map<String, dynamic>>>? _heroDocFuture;

  void _ensureFuturesFor(String uid) {
    if (_cachedUid == uid && _usersDocFuture != null && _heroDocFuture != null) {
      return;
    }
    _cachedUid = uid;
    _usersDocFuture =
        FirebaseFirestore.instance.collection('users').doc(uid).get();
    _heroDocFuture =
        FirebaseFirestore.instance.collection('heroes').doc(uid).get();
  }

  // FIX (per Nizam's request — Hero app startup speed): this used to
  // mount HeroPremiumLoader for both the 'profile-check-loading' and
  // 'hero-approval-check-loading' gate states below — each one runs
  // its own continuous, indefinitely-repeating AnimationController
  // (2.8s pulse/glow/light-streak loop, see hero_premium_loader.dart)
  // the entire time its Firestore .get() is in flight. On a genuinely
  // warm/already-signed-in reopen the 'auth-loading' state is skipped
  // (StreamBuilder's initialData short-circuits it), so in practice
  // these two heavy loaders were the ones actually flashing back-to-
  // back on every cold start — exactly the "2 unwanted animations"
  // slowing the app open. Swapped for the same lightweight, static
  // BrandedLoadingScreen already used for the very first boot frame
  // (_BootLoadingApp above) — one continuous, un-animated look across
  // the whole startup sequence instead of two different animated
  // cards flashing by. HeroPremiumLoader itself is untouched and still
  // used as designed for its other, legitimate in-app loading states
  // (hero_home_screen.dart, hero_history_screen.dart,
  // hero_profile_tab.dart) — this only stops using it during boot.
  Widget _buildLoadingScaffold(String title, String subtitle) {
    return BrandedLoadingScreen(statusText: subtitle);
  }

  Widget _buildFadingChild(String key, Widget child) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 550),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: KeyedSubtree(
        key: ValueKey<String>(key),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // FIX (boot-flicker root cause, mirrors main_customer.dart's fix):
    // this StreamBuilder used to have no `initialData`, so on EVERY
    // relaunch — even for an already-signed-in hero — it started at
    // ConnectionState.waiting and mounted a brand-new HeroPremiumLoader
    // ('auth-loading') while waiting for authStateChanges()'s first
    // emission, right after the boot sequence's second runApp(HeroApp())
    // call had already thrown away and rebuilt the whole tree away from
    // _BootLoadingApp's BrandedLoadingScreen. Two different-looking full-
    // screen loaders, back to back, is exactly the "3x animation
    // flicker" symptom. FirebaseAuth.instance.currentUser is already
    // available SYNCHRONOUSLY the moment Firebase finishes initializing
    // (it's restored from the SDK's own persisted session, no network
    // wait) — seeding it as initialData means a returning hero with an
    // existing session skips this loading mount entirely and goes
    // straight to the profile/approval checks below, which already have
    // their own optimistic-render handling.
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildFadingChild(
            'auth-loading',
            _buildLoadingScaffold(
              'Launching NJ Tech Hero',
              'Initializing premium ride controls and authentication',
            ),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          _cachedUid = null;
          _usersDocFuture = null;
          _heroDocFuture = null;
          return _buildFadingChild('hero-login', const HeroLoginScreen());
        }

        _ensureFuturesFor(user.uid);

        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          // FIX (approved-hero stuck on pending, root cause): this used to
          // force GetOptions(source: Source.cache) with a catchError that
          // only falls back to the server if the cache read fails
          // outright. A cache HIT is not the same as a FRESH value — once
          // this device had cached this doc (e.g. right after profile
          // setup), that stale snapshot was reused forever, since
          // FirebaseAuth.signOut() does not clear Firestore's local
          // persistence (it's a separate on-device store, survives across
          // logout/login on the same browser). A plain get() still uses
          // the local cache automatically when genuinely offline (that's
          // the SDK's built-in behavior), but prefers a fresh server read
          // whenever one is reachable — which is what an approval-status
          // gate actually needs to be correct.
          future: _usersDocFuture,
          builder: (context, userSnapshot) {
            // Show loader only on true cold start when cache is empty
            if (userSnapshot.connectionState == ConnectionState.waiting &&
                !userSnapshot.hasData) {
              return _buildFadingChild(
                'profile-check-loading',
                _buildLoadingScaffold(
                  'Checking Hero Access',
                  'Verifying your dashboard profile and routing your workspace',
                ),
              );
            }

            final userData = userSnapshot.data?.data() ?? <String, dynamic>{};
            final phone =
                (userData['phoneNumber'] as String?)?.trim().isNotEmpty ?? false
                    ? (userData['phoneNumber'] as String).trim()
                    : ((userData['phone'] as String?)?.trim() ?? '');
            final isSetupComplete = userData['isSetupComplete'] == true;
            final needsSetup = phone.isEmpty || !isSetupComplete;

            if (needsSetup) {
              // FIX (merge duplicate registration forms): this branch used
              // to route to ProfileSetupScreen — a lightweight generic form
              // (phone + vehicle category only) shared with the customer
              // app, which wrote a heroes/{uid} doc with zero identity
              // fields for admin to actually verify against. HeroRegisterScreen
              // (the full form with name/DOB/address/license/aadhaar/pan +
              // mandatory doc photos, used by the phone-OTP hero login path)
              // is now the single source of truth for hero onboarding.
              return _buildFadingChild(
                'hero-profile-setup',
                const HeroRegisterScreen(),
              );
            }

            // FIX (admin-approval bypass): this branch used to jump straight
            // to HeroDashboardShell whenever a Firebase Auth session already
            // existed and the generic cross-role `users/{uid}` doc looked
            // "set up" — a flag any of the 4 Allin1 apps can set, since they
            // all share one Firebase Auth pool. It never checked the
            // hero-specific `heroes/{uid}.approvalStatus` field, so anyone
            // with a session from ANY app (or a pre-approval session) could
            // reach the hero dashboard without admin approval. HeroLoginScreen
            // already enforces this correctly for fresh logins — we mirror
            // that same check here for the "session already exists" path.
            return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              // FIX: same stale-cache-lockout bug as the users/{uid} read
              // above, but worse here — this is the actual approvalStatus
              // check. A hero approved by admin AFTER this device had
              // already cached their 'pending' heroes doc would be stuck
              // seeing HeroPendingScreen forever (logout/login doesn't
              // clear the on-device cache), because the forced
              // Source.cache read always "succeeded" with the old value
              // and catchError never fired. Plain get() fixes this the
              // same way.
              future: _heroDocFuture,
              builder: (context, heroSnapshot) {
                if (heroSnapshot.connectionState == ConnectionState.waiting &&
                    !heroSnapshot.hasData) {
                  return _buildFadingChild(
                    'hero-approval-check-loading',
                    _buildLoadingScaffold(
                      'Checking Hero Access',
                      'Verifying your admin approval status',
                    ),
                  );
                }

                final heroDoc = heroSnapshot.data;
                final heroData = heroDoc?.data();
                final approvalStatus = heroData?['approvalStatus']
                    ?.toString()
                    .trim()
                    .toLowerCase();
                final isApproved =
                    (heroDoc?.exists ?? false) && approvalStatus == 'approved';

                if (!isApproved) {
                  return _buildFadingChild(
                    'hero-pending',
                    const HeroPendingScreen(),
                  );
                }

                return _buildFadingChild(
                  'hero-dashboard',
                  const HeroDashboardShell(),
                );
              },
            );
          },
        );
      },
    );
  }
}
