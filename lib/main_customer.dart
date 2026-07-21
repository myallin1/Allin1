// lib/main_customer.dart
// Erode Super App - CUSTOMER PWA Entry Point
// Fixed: back button logout + routing + geolocator web crash

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_navigator.dart';
import 'firebase_options.dart';
import 'config/api_config.dart';
import 'screens/ai_settings_screen.dart';
import 'screens/auth/profile_setup_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/coming_soon_screen.dart';
import 'screens/customer_login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/guru_chat_screen.dart';
import 'screens/guru_offer_screen.dart';
import 'screens/hero_booking_screen.dart';
import 'screens/intro_video_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_setup_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/ai_activation_service.dart';
import 'services/analytics_service.dart';
import 'services/api_service.dart';
import 'services/cache_service.dart';
import 'services/hive_cache.dart';
import 'services/local_sync_service.dart';
import 'services/localization_service.dart';
import 'services/map_service.dart';
import 'services/session_service.dart';
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
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

    // Enable Firestore offline persistence
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }
  debugPrint(
    '[main_customer] Background push received: ${message.messageId} '
    'title=${message.notification?.title}',
  );
}

Future<void> _ensureFirebaseInitialized() async {
  if (Firebase.apps.isNotEmpty) return;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') {
      debugPrint('[main_customer] Firebase already initialized, continuing.');
      return;
    }
    rethrow;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  try {
    await _ensureFirebaseInitialized();
  } catch (e) {
    debugPrint('[main_customer] Fatal: Firebase init failed: $e');
    return;
  }

  await runZonedGuarded(() async {
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
  }, (error, stack) {
    debugPrint('Zone error: $error\n$stack');
    if (AnalyticsService.isInitialized) {
      AnalyticsService.instance.recordError(
        error,
        stack,
      );
    }
  });

  runApp(const CustomerApp());

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
    if (!accepted) return;

    // If the customer is already somewhere else in the app, take them to
    // the booking form — that's the only screen that can act on this,
    // and it prompts "Pickup or Drop?" as soon as it builds.
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
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
    final cached = await HiveCache.get<Map>(HiveCache.kActiveRide);
    if (cached == null) return;
    final rideDocId = cached['rideDocId'] as String?;
    if (rideDocId == null || rideDocId.isEmpty) return;
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
          // themeKey is left in place for now — same concern applies to
          // it, but theme switching mid-session isn't part of this fix
          // and changing it here would be an unrelated behaviour change.
          key: ValueKey('customer_${themeService.themeKey}'),
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
          navigatorObservers: [
            AnalyticsService.instance.getObserver(),
          ],
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
// First-launch intro video gate. Shows IntroVideoScreen exactly once
// per customer (shared_preferences flag), then never again — every
// launch after that goes straight to the normal splash → home flow.
// The "still checking" placeholder (a very fast local read, not
// network) uses the same BrandedLoadingScreen as everything else, so
// there's no 4th different-looking flash on screen while it resolves.
// ================================================================
class _IntroGate extends StatefulWidget {
  const _IntroGate();

  @override
  State<_IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<_IntroGate> {
  static const String _seenIntroKey = 'has_seen_intro_video_v1';
  static const String _seenWelcomeKey = 'has_seen_welcome_v1';

  bool? _showIntro; // null while the shared_preferences check is in flight
  bool _showWelcome = false;

  @override
  void initState() {
    super.initState();
    unawaited(_checkFirstLaunch());
  }

  Future<void> _checkFirstLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final seenIntro = prefs.getBool(_seenIntroKey) ?? false;
      if (!seenIntro) {
        await prefs.setBool(_seenIntroKey, true);
      }

      // Tracked separately from the video. They were introduced at
      // different times, so a customer who already has the intro flag
      // set from an earlier version should still be offered the
      // language/sign-in screen once.
      final seenWelcome = prefs.getBool(_seenWelcomeKey) ?? false;
      if (!seenWelcome) {
        await prefs.setBool(_seenWelcomeKey, true);
      }

      if (mounted) {
        setState(() {
          _showIntro = !seenIntro;
          _showWelcome = !seenWelcome;
        });
      }
    } catch (e) {
      debugPrint('[IntroGate] first-launch check failed: $e');
      if (mounted) {
        setState(() {
          _showIntro = false;
          _showWelcome = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showIntro == null) {
      return const BrandedLoadingScreen();
    }

    // First launch runs the whole sequence:
    //   intro video -> welcome (language + sign-in) -> splash -> home
    // Every launch after that goes straight to splash -> home.
    const home = SplashSetupScreen(nextScreen: _CustomerHomeGate());
    final afterIntro =
        _showWelcome ? const WelcomeScreen(next: home) : home;

    if (_showIntro == true) {
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

  // Same shared design SplashSetupScreen and _IntroGate use — see
  // branded_loading_screen.dart. This screen's own copy of the design
  // used to be the ONLY place with this exact look; now it's the
  // single source of truth for it.
  Widget _buildLoadingScaffold() => const BrandedLoadingScreen();

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

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingScaffold();
        }

        if (!(snapshot.hasData && user != null)) {
          return const DashboardScreen();
        }

        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          // ── Optimistic / cache-first profile read ──────────────────
          // Attempt local cache first so the gate resolves instantly on
          // second launch without showing a blocking spinner.  The SDK
          // automatically falls back to network when cache is empty.
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get(const GetOptions(source: Source.cache))
              .catchError((_) => FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .get()),
          builder: (context, userSnapshot) {
            // Only show spinner on genuine first-ever cold start (no cache)
            if (userSnapshot.connectionState == ConnectionState.waiting &&
                !userSnapshot.hasData) {
              return _buildLoadingScaffold();
            }

            final userData = userSnapshot.data?.data() ?? <String, dynamic>{};
            final phone =
                (userData['phoneNumber'] as String?)?.trim().isNotEmpty ?? false
                    ? (userData['phoneNumber'] as String).trim()
                    : ((userData['phone'] as String?)?.trim() ?? '');
            final isSetupComplete = userData['isSetupComplete'] == true;
            final needsSetup = phone.isEmpty || !isSetupComplete;

            final child = needsSetup
                ? const ProfileSetupScreen(
                    preferredRole: UserType.customer,
                  )
                : const DashboardScreen();

            return child;
          },
        );
      },
    );
  }
}
