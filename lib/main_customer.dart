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

import 'app_navigator.dart';
import 'firebase_options.dart';
import 'screens/ai_settings_screen.dart';
import 'screens/auth/profile_setup_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/coming_soon_screen.dart';
import 'screens/customer_login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/guru_chat_screen.dart';
import 'screens/guru_offer_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_setup_screen.dart';
import 'services/ai_activation_service.dart';
import 'services/analytics_service.dart';
import 'services/api_service.dart';
import 'services/cache_service.dart';
import 'services/hive_cache.dart';
import 'services/local_sync_service.dart';
import 'services/localization_service.dart';
import 'services/map_service.dart';
import 'services/session_service.dart';
import 'services/soundbox_easter_egg_service.dart';
import 'services/theme_service.dart';
import 'widgets/soundbox_easter_egg_overlay.dart';

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
    try {
      await AnalyticsService.instance.initialize();
    } catch (e) {
      debugPrint('Firebase/Analytics init error: $e');
    }

    await Hive.initFlutter();
    await LocalSyncService.instance.initialize();
    await CacheService().init();
    await ApiService.instance.initialize();
    try {
      debugPrint('[main_customer] Initializing MapService...');
      await MapService().initialize();
      debugPrint(
        '[main_customer] MapService ready provider=${MapService().currentProvider.name} '
        'fallback=${MapService().isUsingFallback}',
      );
    } catch (e) {
      debugPrint('[main_customer] MapService init error: $e');
    }

    await CacheService().cacheSettings({
      'bikeTaxiBaseFare': 25.0,
      'bikeTaxiPerKm': 12.0,
      'coinValue': 100,
      'riderCommission': 15.0,
      'sellerCommission': 18.0,
      'platformFee': 2.0,
      'upiZeroFee': true,
    });

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

  await _restoreActiveRideIfNeeded();
  runApp(const CustomerApp());
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
          key: ValueKey(
            'customer_${localization.languageCode}_${themeService.themeKey}',
          ),
          navigatorKey: navigatorKey,
          title: localization.t('app_title'),
          debugShowCheckedModeBanner: false,
          theme: themeService.currentTheme,
          themeMode: ThemeMode.light,
          home: const SplashSetupScreen(nextScreen: _CustomerHomeGate()),
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
          builder: (context, child) {
            return SoundboxEasterEggOverlayScope(
              child: child ?? const SizedBox.shrink(),
            );
          },
        ),
      ),
    );
  }
}

class _CustomerHomeGate extends StatefulWidget {
  const _CustomerHomeGate();

  @override
  State<_CustomerHomeGate> createState() => _CustomerHomeGateState();
}

class _CustomerHomeGateState extends State<_CustomerHomeGate> {
  String? _lastUid;

  Widget _buildLoadingScaffold() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 94,
                  height: 94,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF4FA3), Color(0xFFFF92C8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x24FF4FA3),
                        blurRadius: 24,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        strokeWidth: 3.2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "That'll Bapx NJ Tech",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF4A1236),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'made love ❤ with erode',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF8A4E72),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
