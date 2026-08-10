// lib/main_seller.dart
// Allin1 — SELLER App Entry Point (Food/E-commerce Pipeline)

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'config/app_variant.dart';
import 'firebase_options.dart';
import 'screens/app_splash_video_screen.dart';
import 'screens/login_screen.dart';
import 'screens/seller_dashboard_screen.dart';
import 'screens/seller_home_kitchen_menu_screen.dart';
import 'screens/seller_onboarding_screen.dart';
import 'screens/seller_screen.dart';
import 'services/db_usage_tracker.dart';
import 'services/localization_service.dart';
import 'services/session_service.dart';
import 'services/theme_service.dart';
import 'widgets/branded_loading_screen.dart';

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // FIX (audit finding — notifications_screen.dart hardcoded
  // 'customer' fallback): see lib/config/app_variant.dart.
  currentAppVariant = 'seller';

  await SentryFlutter.init(
    (options) {
      options.dsn =
          'https://208217846f0b9708dc26f1d5d812eefc@o4511799785553920.ingest.us.sentry.io/4511799822843904';
      options.tracesSampleRate = 1.0;
    },
    appRunner: () async {
      // videoDone completes when app_splash.mp4 finishes playing; the
      // second runApp() below (SellerApp) awaits it so the video is never
      // cut short by a fast Firebase init.
      final videoDone = Completer<void>();
      runApp(_BootLoadingApp(onVideoFinished: () {
        if (!videoDone.isCompleted) videoDone.complete();
      }));
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
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
      DbUsageTracker.instance.init('seller');
      // NOTE (boot-flicker audit, per Nizam's request to mirror the fix
      // across all 4 apps): unlike main_customer.dart/main_hero.dart/
      // main_admin.dart, SellerApp's root route goes straight to
      // LoginScreen ('/') with no auth-stream gate at the app root at
      // all — there's no second loading widget mounted after this
      // runApp() swap to collapse here. The only two screens painted
      // during a seller cold boot are the pre-Firebase _BootLoadingApp
      // (BrandedLoadingScreen) and then LoginScreen itself — already a
      // single continuous mount, nothing to fix structurally. (Separately
      // worth knowing: a seller with an existing Firebase Auth session
      // still sees the login FORM on every relaunch instead of skipping
      // straight to SellerDashboardScreen — a real UX gap, but a
      // different issue from the boot flicker asked about here.)
      //
      // Gate the real-app swap on the video having finished playing (it
      // almost always has, by now — Firebase init is the fast side of
      // this race) so the boot video is never truncated mid-playback.
      await videoDone.future;
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
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocalizationService()),
        // FIX (Nizam's request: same theme-switcher pattern as customer
        // and hero apps): seller app used to have a hardcoded dark
        // ThemeData with no way to change it, and no Settings screen to
        // change it from. Now shares the same ThemeService (5 selectable
        // themes), switchable from seller_settings_screen.dart.
        ChangeNotifierProvider(create: (_) => ThemeService()),
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
        // now plays pre-Firebase as the very first boot frame (see
        // _BootLoadingApp above) instead of here — this route used to wrap
        // LoginScreen in a second AppSplashVideoScreen play, which would
        // have shown the same video twice back to back on every launch.
        // Now goes straight to LoginScreen.
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
        ),
      ),
    );
  }
}
