// lib/main_seller.dart
// Allin1 — SELLER App Entry Point (Food/E-commerce Pipeline)

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/seller_dashboard_screen.dart';
import 'screens/seller_home_kitchen_menu_screen.dart';
import 'screens/seller_onboarding_screen.dart';
import 'screens/seller_screen.dart';
import 'services/db_usage_tracker.dart';
import 'services/localization_service.dart';
import 'services/session_service.dart';
import 'services/theme_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SentryFlutter.init(
    (options) {
      options.dsn =
          'https://208217846f0b9708dc26f1d5d812eefc@o4511799785553920.ingest.us.sentry.io/4511799822843904';
      options.tracesSampleRate = 1.0;
    },
    appRunner: () async {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      DbUsageTracker.instance.init('seller');
      runApp(const SellerApp());
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
    return ChangeNotifierProvider(
      create: (_) => LocalizationService(),
      child: MaterialApp(
      title: 'Allin1 Partner Dashboard',
      debugShowCheckedModeBanner: false,
      // FIX (typography audit): same fix as main_admin.dart -- this had
      // no fontFamily set, so bare TextStyle() calls in seller screens
      // rendered in the platform default instead of matching the
      // GoogleFonts.outfit(...) calls used everywhere else in the file.
      theme: ThemeData.dark().copyWith(
        fontFamily: AppBrandTheme.brandFontFamily,
        fontFamilyFallback: AppBrandTheme.brandFontFallback,
        textTheme: AppBrandTheme.brandTextTheme(
          ThemeData.dark().textTheme,
          bodyColor: const Color(0xFFEEEEF5),
          displayColor: const Color(0xFFEEEEF5),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF11998E),
          secondary: Color(0xFF38EF7D),
        ),
      ),
      initialRoute: '/',
      routes: {
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
          final sellerId = settings.arguments as String;
          // FIX (per Nizam's request): every seller authors their own
          // custom dishes now — see seller_dashboard_screen.dart and
          // seller_onboarding_screen.dart for the same change.
          return MaterialPageRoute(
            builder: (_) => SellerHomeKitchenMenuScreen(sellerId: sellerId, title: 'My Menu', categoryName: 'Menu'),
          );
        }
        return null;
      },
      ),
    );
  }
}
