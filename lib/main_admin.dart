// lib/main_admin.dart
// Allin1 — ADMIN Panel Entry Point
// HIDDEN — Not for public!

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app_navigator.dart';
import 'config/app_variant.dart';
import 'config/web_push_config.dart';
import 'firebase_options.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/app_splash_video_screen.dart';
import 'screens/admin/ads_management_screen.dart';
import 'screens/admin/credentials_admin_screen.dart';
import 'screens/admin/fare_management_screen.dart';
import 'screens/admin/super_admin_home_screen.dart';
import 'screens/admin/task_approvals_screen.dart';
import 'screens/login_screen.dart';
import 'services/admin_alert_notification_service.dart';
import 'services/admin_foreground_service.dart';
import 'services/admin_live_alert_service.dart';
import 'services/admin_quick_task_service.dart';
import 'services/db_usage_tracker.dart';
import 'services/localization_service.dart';
import 'services/session_service.dart';
import 'services/theme_service.dart';
import 'widgets/branded_loading_screen.dart';

// NEW (per Nizam's request — Admin "WhatsApp model" closed-app alerts):
// mirrors main_hero.dart's _firebaseMessagingBackgroundHandler. Must be
// a top-level/static function with this exact pragma — FCM invokes it
// on a separate background isolate that has no access to any app
// state, so it can only do isolate-safe work (here: nothing extra is
// needed, since the paired Cloud Functions send a `notification` block
// that Android displays automatically when the app is backgrounded/
// killed; this handler exists so the OS actually wakes/registers the
// background messaging pipeline at all).
@pragma('vm:entry-point')
Future<void> _adminFirebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[main_admin] Background push received: ${message.messageId}');
}

StreamSubscription<User?>? _adminAuthSub;
StreamSubscription<String>? _adminFcmTokenRefreshSub;

// NEW: same fcmToken-sync pattern as main_hero.dart's
// _syncFcmTokenForHero — writes to admins/{uid}.fcmToken, which is
// exactly the field notifyAdminOnNewRide.ts / notifyAdminOnNewService
// Request.ts read to know which device(s) to push to. Without this,
// the Cloud Functions would always find zero tokens and no-op.
Future<void> _syncFcmTokenForAdmin(String uid) async {
  try {
    // FIX (same web-push root cause fixed for main_hero.dart): getToken()
    // on web needs a vapidKey or it fails silently. Admin PWA gets the
    // same fix for consistency across all 4 apps.
    final token = await FirebaseMessaging.instance.getToken(
      vapidKey: kIsWeb ? WebPushConfig.vapidKey : null,
    );
    if (token != null && token.trim().isNotEmpty) {
      await FirebaseFirestore.instance.collection('admins').doc(uid).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('[FCM] Token synced for admin $uid');
    }
  } catch (e) {
    debugPrint('[FCM] Token sync failed for admin $uid: $e');
  }

  _adminFcmTokenRefreshSub?.cancel();
  _adminFcmTokenRefreshSub =
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    unawaited(
      FirebaseFirestore.instance.collection('admins').doc(uid).set({
        'fcmToken': newToken,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((Object e) {
        debugPrint('[FCM] Token refresh write failed for admin $uid: $e');
      }),
    );
  }, onError: (Object e) {
    debugPrint('[FCM] onTokenRefresh listener error: $e');
  });
}

void _initAdminFcmAuthListener() {
  _adminAuthSub?.cancel();
  _adminAuthSub = FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user == null) {
      _adminFcmTokenRefreshSub?.cancel();
      _adminFcmTokenRefreshSub = null;
      // FIX (per Nizam's request — free alternative, no Blaze/billing):
      // the FCM-token sync above only matters if Cloud Functions ever
      // get deployed later; the actual FREE, working notification path
      // is this foreground-service + live-Firestore-listener pair
      // (admin_foreground_service.dart / admin_live_alert_service.dart)
      // — start it whenever an admin is signed in, stop it on logout so
      // a signed-out phone doesn't keep a persistent notification/
      // listener running for no reason.
      AdminLiveAlertService.instance.stop();
      unawaited(AdminForegroundService.stop());
      return;
    }
    unawaited(_syncFcmTokenForAdmin(user.uid));
    AdminLiveAlertService.instance.start();
    unawaited(AdminForegroundService.start());
  });
}

// FIX (Nizam's "video as natural visual buffer" request, task #108, same
// fix as main_customer.dart/main_hero.dart/main_seller.dart): paint
// app_splash.mp4 first, before Hive/Firebase even start, so Flutter's
// first frame fires in milliseconds instead of after a Firebase network
// round-trip, AND the video itself becomes the boot buffer while Hive/
// Firebase init in parallel behind it. Previously the video was shown
// AFTER Firebase, wrapped around AdminApp's StreamBuilder auth gate —
// moved here and removed there (see AdminApp.build for that change) so
// it's no longer a second screen stacked after this one.
// BrandedLoadingScreen is now only a rare fallback frame, shown only if
// Hive/Firebase init somehow outlasts the video.
class _BootLoadingApp extends StatelessWidget {
  const _BootLoadingApp({required this.onVideoFinished});

  final VoidCallback onVideoFinished;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AppSplashVideoScreen(
        nextScreen: const BrandedLoadingScreen(),
        onFinished: onVideoFinished,
      ),
    );
  }
}

void main() {
  FlutterError.onError = (details) {
    debugPrint('[main_admin] Flutter error: ${details.exceptionAsString()}');
  };

  // NOTE for whoever reads this next: this used to be a manual
  // runZonedGuarded(...) here, with WidgetsFlutterBinding.ensureInitialized()
  // as its first line — see the comment that used to sit there: binding
  // and runApp() must run in the SAME zone or cold start throws a "Zone
  // mismatch" assertion. SentryFlutter.init()'s appRunner ALSO creates its
  // own zone internally, so nesting the old runZonedGuarded inside it (or
  // vice versa) would split binding/runApp() back into two different
  // zones — the exact bug that comment was warning about. Fix: Sentry's
  // appRunner zone now IS the one zone; the old runZonedGuarded is gone
  // and WidgetsFlutterBinding.ensureInitialized() moved to be appRunner's
  // first line instead, preserving the same "same zone" invariant.
  SentryFlutter.init(
    (options) {
      options.dsn =
          'https://208217846f0b9708dc26f1d5d812eefc@o4511799785553920.ingest.us.sentry.io/4511799822843904';
      options.tracesSampleRate = 1.0;
    },
    appRunner: () async {
      WidgetsFlutterBinding.ensureInitialized();
      // FIX (audit finding — notifications_screen.dart hardcoded
      // 'customer' fallback): see lib/config/app_variant.dart.
      currentAppVariant = 'admin';

      // videoDone completes when app_splash.mp4 finishes playing; the
      // second runApp() below (AdminApp) awaits it so the video is never
      // cut short by a fast Hive/Firebase init.
      final videoDone = Completer<void>();
      runApp(_BootLoadingApp(onVideoFinished: () {
        if (!videoDone.isCompleted) videoDone.complete();
      }));

      // SessionService.saveSession() opens a Hive box directly (not via
      // HiveCache's guarded wrapper), which throws "You need to
      // initialize Hive..." if nothing primed it first. main_customer.dart
      // calls this eagerly at startup; admin never did, so Google
      // Sign-In's post-auth saveSession() call was crashing here.
      await Hive.initFlutter();

      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        }
        // Enable Firestore offline persistence on web (PWA). Mobile
        // (Android/iOS) already has persistence on by default, so this
        // is guarded to web only; a capped 50MB cache (CTO-specified)
        // keeps browser storage bounded instead of unlimited.
        if (kIsWeb) {
          FirebaseFirestore.instance.settings = const Settings(
            persistenceEnabled: true,
            cacheSizeBytes: 52428800, // 50MB
          );
        }
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      } on FirebaseException catch (e, stack) {
        if (e.code == 'duplicate-app') {
          debugPrint('[main_admin] Firebase already initialized, continuing.');
        } else {
          debugPrint('[main_admin] Firebase init failed: $e\n$stack');
          runApp(_InitErrorApp('Firebase initialization failed:\n$e'));
          return;
        }
      } catch (e, stack) {
        debugPrint('[main_admin] Firebase init failed: $e\n$stack');
        runApp(_InitErrorApp('Firebase initialization failed:\n$e'));
        return;
      }
      DbUsageTracker.instance.init('admin');

      // NEW (per Nizam's request — Admin "WhatsApp model" closed-app
      // alerts): registers the background handler + local-notification
      // channel BEFORE runApp, same ordering main_hero.dart uses, and
      // starts syncing this admin's FCM token the moment they're
      // signed in (works for both a fresh login and an already-warm
      // session restored from disk).
      FirebaseMessaging.onBackgroundMessage(_adminFirebaseMessagingBackgroundHandler);
      await AdminAlertNotificationService.initialize();
      AdminForegroundService.initialize();
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      _initAdminFcmAuthListener();
      // Foreground messages are NOT auto-displayed by Android/FCM (only
      // background/killed states get that for free from the
      // `notification` block) — this is the foreground-only path.
      FirebaseMessaging.onMessage.listen((message) {
        final notification = message.notification;
        if (notification == null) return;
        unawaited(AdminAlertNotificationService.showForegroundAlert(
          title: notification.title ?? 'Allin1 Admin',
          body: notification.body ?? 'New activity',
          payloadId: message.messageId ?? DateTime.now().toIso8601String(),
        ));
      });

      // Gate the real-app swap on the video having finished playing (it
      // almost always has, by now — Hive/Firebase init is the fast side
      // of this race) so the boot video is never truncated mid-playback.
      await videoDone.future;
      runApp(const AdminApp());
    },
  );
}

class _InitErrorApp extends StatelessWidget {
  final String message;
  const _InitErrorApp(this.message);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0A0A1A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('message', message));
  }
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    // LocalizationService (en/ta/tg) made available app-wide, same as
    // customer/hero apps — admin had zero language infrastructure
    // before this (see language-system audit).
    return ChangeNotifierProvider(
      create: (_) => LocalizationService(),
      child: MaterialApp(
      // NEW (CTO mandate — Admin App Autonomous Agent Support System):
      // wires the app's shared navigatorKey (app_navigator.dart) into
      // the Admin app's own MaterialApp, same as main_customer.dart and
      // main_hero.dart already do. AdminApp never had this before —
      // without it, AdminQuickTaskService (below) has no Overlay/
      // Navigator to insert its floating panel into or push admin
      // screens from.
      navigatorKey: navigatorKey,
      title: 'Allin1 Admin',
      debugShowCheckedModeBanner: false,
      // FIX (typography audit): this used to be a bare ThemeData.dark()
      // with no fontFamily set, so any bare TextStyle() in the admin
      // screens (which don't route through the customer/hero apps'
      // ThemeService) silently rendered in the platform default (Roboto)
      // while every GoogleFonts.outfit(...) call around it rendered in
      // Outfit -- same inconsistency as the customer app, just via a
      // different theme object. Reusing AppBrandTheme's shared
      // Outfit + NotoSansTamil-fallback text theme brings the admin
      // panel in line with the rest of the app.
      theme: ThemeData.dark().copyWith(
        // NOTE: ThemeData.copyWith() has no fontFamily/fontFamilyFallback
        // named params (those only exist on the ThemeData() constructor) --
        // textTheme below already carries Outfit + the Tamil fallback via
        // AppBrandTheme.brandTextTheme(), which is what actually matters
        // for text rendering.
        textTheme: AppBrandTheme.brandTextTheme(
          ThemeData.dark().textTheme,
          bodyColor: const Color(0xFFEEEEF5),
          displayColor: const Color(0xFFEEEEF5),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE05555),
          secondary: Color(0xFFF5C542),
        ),
      ),
      // FIX (boot-flicker root cause, mirrors main_customer.dart/
      // main_hero.dart's fix): no `initialData` here meant EVERY
      // relaunch — even for an already-signed-in admin — started at
      // ConnectionState.waiting and mounted a bare CircularProgressIndicator
      // scaffold (a THIRD, visually distinct loading design) right after
      // the boot sequence's second runApp(AdminApp()) had already torn
      // down _BootLoadingApp's BrandedLoadingScreen. Seeding
      // FirebaseAuth.instance.currentUser (available synchronously once
      // Firebase is initialized, no network wait) as initialData skips
      // this mount entirely for a returning admin, and the waiting-state
      // fallback now reuses BrandedLoadingScreen instead of a different-
      // looking bare spinner for the rare genuine cold-cache case.
      // FIX (video-as-natural-buffer, per Nizam's request): app_splash.mp4
      // now plays pre-Firebase/Hive as the very first boot frame (see
      // _BootLoadingApp above) instead of here — this used to wrap the
      // StreamBuilder auth gate in a second AppSplashVideoScreen play,
      // which would have shown the same video twice back to back on every
      // launch. Now goes straight to the (unchanged) StreamBuilder gate.
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        initialData: FirebaseAuth.instance.currentUser,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const BrandedLoadingScreen();
          }
          if (snap.hasData && snap.data != null) {
            return const SuperAdminHomeScreen();
          }
          return const LoginScreen(
             presetUserType: UserType.admin,
             lockUserType: true,
             title: '🔐 Admin Access',
             subtitle: 'Authorized personnel only',
             lockedUserLabel: 'Admin',
           );
        },
      ),
      // NEW (CTO mandate — Task 1: The Admin Confirmation Gate): the
      // "Quick Task Chatbox" FAB, laid over every admin screen exactly
      // like GlobalGuruFab is on the customer app. The actual panel is
      // a separate root-level OverlayEntry (see
      // AdminQuickTaskService.show()) inserted via `navigatorKey`, so
      // it survives Navigator.push/pop the same way this FAB does.
      builder: (context, child) => Stack(
        children: [
          if (child != null) child,
          const AdminQuickTaskFab(),
        ],
      ),
      routes: {
        '/admin-home':       (_) => const AdminDashboardScreen(),
        '/admin/ads': (_) => const AdsManagementScreen(),
        '/admin/credentials': (_) => const CredentialsAdminScreen(),
        '/admin/tasks': (_) => const TaskApprovalsScreen(),
        '/admin/fares': (_) => const FareManagementScreen(),
      },
      ),
    );
  }
}
