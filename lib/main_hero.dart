import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_navigator.dart';
import 'firebase_options.dart';
import 'screens/auth/profile_setup_screen.dart';
import 'screens/bike_taxi/hero_dashboard_shell.dart';
import 'screens/hero_login_screen.dart';
import 'screens/splash_setup_screen.dart';
import 'services/hero_ride_notification_service.dart';
import 'services/hero_web_audio_service.dart';
import 'services/map_service.dart';
import 'services/session_service.dart';
import 'widgets/hero_premium_loader.dart';
import 'package:flutter/foundation.dart';

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

Future<void> _ensureFirebaseInitialized() async {
  if (Firebase.apps.isNotEmpty) {
    return;
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Enable Firestore offline persistence
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') {
      debugPrint('[main_hero] Firebase already initialized, continuing.');
      return;
    }
    rethrow;
  }
}

// ── Global RTDB Hero Ping Listener (Auth-Aware) ──────────────────
// Survives UI dispose & handles Login/Logout dynamically
StreamSubscription<DatabaseEvent>? _globalHeroPingSub;
StreamSubscription<User?>? _authSub;

void _initGlobalHeroPingListener() {
  _authSub?.cancel();
  _authSub = FirebaseAuth.instance.authStateChanges().listen((User? user) {
    _globalHeroPingSub?.cancel(); // Clear existing listener

    if (user == null) {
      debugPrint('[GlobalPing] User logged out — stopping listener');
      return;
    }

    final uid = user.uid;
    debugPrint('[GlobalPing] Attaching global hero_pings/$uid listener');

    _globalHeroPingSub = FirebaseDatabase.instance
        .ref('hero_pings/$uid')
        .onChildAdded
        .listen((event) async {
      final pingData = event.snapshot.value as Map<dynamic, dynamic>?;
      final requestId = event.snapshot.key as String? ?? '';
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
      if (!HeroRideNotificationService.shouldProcessRideNotification(requestId)) {
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
          );
          debugPrint('[GlobalPing] 🔔 Notification fired for: $requestId');
        } catch (e) {
          debugPrint('[GlobalPing] Notification error: $e');
        }
      }
    }, onError: (Object e) {
      debugPrint('[GlobalPing] RTDB listener error: $e');
    });
  });
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await _ensureFirebaseInitialized();
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  final rideId = _rideIdFromPushData(message.data);
  if (rideId != null) {
    // ✅ FIX: When app is KILLED, FCM already shows a system notification.
    // Show local notification but suppress the loud ringtone to avoid
    // duplicate sound with the FCM system tray notification.
    await HeroRideNotificationService.showRideAssigned(
      rideId: rideId,
      data: message.data,
      playAlertTone: false,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPendingHeroRideIdKey, rideId);
  }
  debugPrint(
    '[main_hero] Background push received: ${message.messageId} '
    'title=${message.notification?.title}',
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await _ensureFirebaseInitialized();
  await HeroRideNotificationService.initialize();

  // Start global RTDB ping listener reacting to Auth changes
  _initGlobalHeroPingListener();

  runApp(const HeroApp());
  unawaited(_warmHeroServices());
}

Future<void> _warmHeroServices() async {
  try {
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
    return GestureDetector(
      onTap: () {
        if (kIsWeb) HeroWebAudioService().unlock();
      },
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'hero allin1',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFFFFBFE),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFFF4FA3),
          ).copyWith(
            primary: const Color(0xFFFF4FA3),
            secondary: const Color(0xFFFF9CCC),
            surface: Colors.white,
          ),
        ),
        initialRoute: '/',
        routes: {
          '/': (_) => const SplashSetupScreen(nextScreen: _HeroSetupGate()),
          '/hero-home': (_) => const SplashSetupScreen(nextScreen: _HeroSetupGate()),
          '/hero-ride': (_) => const SplashSetupScreen(nextScreen: _HeroSetupGate()),
        },
      ),
    );
  }
}

class _HeroSetupGate extends StatelessWidget {
  const _HeroSetupGate();

  Widget _buildLoadingScaffold(String title, String subtitle) {
    return HeroPremiumLoader(
      title: title,
      subtitle: subtitle,
      icon: Icons.electric_bike_rounded,
    );
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
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
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
          return _buildFadingChild('hero-login', const HeroLoginScreen());
        }

        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          // ── Cache-first: resolves from SQLite cache on return visits ──
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get(const GetOptions(source: Source.cache))
              .catchError((_) => FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .get()),
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
              return _buildFadingChild(
                'hero-profile-setup',
                const ProfileSetupScreen(preferredRole: UserType.hero),
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
  }
}
