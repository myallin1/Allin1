// lib/main_admin.dart
// Allin1 — ADMIN Panel Entry Point
// HIDDEN — Not for public!

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/admin/ads_management_screen.dart';
import 'screens/admin/credentials_admin_screen.dart';
import 'screens/admin/fare_management_screen.dart';
import 'screens/admin/super_admin_home_screen.dart';
import 'screens/admin/task_approvals_screen.dart';
import 'screens/login_screen.dart';
import 'services/localization_service.dart';
import 'services/session_service.dart';

void main() {
  FlutterError.onError = (details) {
    debugPrint('[main_admin] Flutter error: ${details.exceptionAsString()}');
  };

  runZonedGuarded(() async {
    // WidgetsFlutterBinding must be created inside the same zone that
    // runApp() executes in — creating it before runZonedGuarded() puts
    // the binding in the root zone while runApp() runs in a child zone,
    // which triggers a "Zone mismatch" framework assertion on cold start.
    WidgetsFlutterBinding.ensureInitialized();

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
    runApp(const AdminApp());
  }, (error, stack) {
    debugPrint('[main_admin] Unhandled zone error: $error\n$stack');
  });
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
      title: 'Allin1 Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE05555),
          secondary: Color(0xFFF5C542),
        ),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
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
