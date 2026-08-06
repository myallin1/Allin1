// lib/main_admin.dart
// Allin1 — ADMIN Panel Entry Point
// HIDDEN — Not for public!

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app_navigator.dart';
import 'firebase_options.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/admin/ads_management_screen.dart';
import 'screens/admin/credentials_admin_screen.dart';
import 'screens/admin/fare_management_screen.dart';
import 'screens/admin/super_admin_home_screen.dart';
import 'screens/admin/task_approvals_screen.dart';
import 'screens/login_screen.dart';
import 'services/admin_quick_task_service.dart';
import 'services/db_usage_tracker.dart';
import 'services/localization_service.dart';
import 'services/session_service.dart';
import 'services/theme_service.dart';
import 'widgets/branded_loading_screen.dart';

// FIX (Nizam's "jet-speed startup" request, task #108, same fix as
// main_customer.dart/main_hero.dart/main_seller.dart): paint this
// instantly, before Hive/Firebase even start, so Flutter's first frame
// fires in milliseconds instead of after a Firebase network round-trip.
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

      runApp(const _BootLoadingApp());

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
