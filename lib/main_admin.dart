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
import 'package:shared_preferences/shared_preferences.dart';

import 'app_navigator.dart';
import 'config/app_variant.dart';
import 'config/web_push_config.dart';
import 'firebase_options.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/admin/admin_dialer_screen.dart';
import 'screens/admin/admin_incoming_call_screen.dart';
import 'screens/admin/admin_post_call_sheet.dart';
import 'screens/admin/admin_in_call_screen.dart';
import 'screens/admin/ads_management_screen.dart';
import 'screens/admin/credentials_admin_screen.dart';
import 'screens/admin/fare_management_screen.dart';
import 'screens/admin/super_admin_home_screen.dart';
import 'screens/admin/task_approvals_screen.dart';
import 'screens/login_screen.dart';
import 'services/admin_alert_notification_service.dart';
import 'services/admin_foreground_service.dart';
import 'services/admin_live_alert_service.dart';
import 'services/guru_overlay_service.dart';
import 'services/db_usage_tracker.dart';
import 'services/localization_service.dart';
import 'services/migration_gate_service.dart';
import 'services/chitti/chitti_accessibility_bridge.dart';
import 'services/session_service.dart';
import 'services/theme_service.dart';
import 'widgets/branded_loading_screen.dart';
import 'widgets/migration_notice_overlay.dart';

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

// FIX (Aug 10 2026 — Nizam's "video every launch is too slow / disturbs
// repeat users" report, same pattern as main_customer.dart/main_hero.dart/
// main_seller.dart): gates whether the splash video plays at all. Set
// (once) only after the video has actually finished playing on a
// first-ever launch — see the branch in main() below. Every launch after
// that reads this as true and skips straight past the video AND past any
// blocking loading screen.
const String _kSplashVideoSeenEverKey = 'admin_splash_video_seen_ever_v1';

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
//
// FIX (Aug 10 2026 — first-launch-only video): this class itself is
// UNCHANGED — still the video screen described above. What changed is
// main() no longer runApp()s it unconditionally: it now only does so the
// very first time this device/browser ever opens the admin app (see
// _kSplashVideoSeenEverKey above). Every later launch skips this widget
// entirely and goes straight to AdminApp — see the branch in main() below.
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

      // SessionService.saveSession() opens a Hive box directly (not via
      // HiveCache's guarded wrapper), which throws "You need to
      // initialize Hive..." if nothing primed it first. main_customer.dart
      // calls this eagerly at startup; admin never did, so Google
      // Sign-In's post-auth saveSession() call was crashing here.
      //
      // FIX (Aug 10 2026 — rocket-speed repeat opens): first-ever launch
      // still awaits this (unchanged timing, still finishes long before
      // the video does); a repeat launch has no video to hide behind, so
      // this now runs unawaited in the background instead — nothing on
      // the very first AdminApp frame reads Hive directly, only
      // SessionService.saveSession() does, and that only fires later, on
      // an actual login action.
      if (!hasSeenSplashVideoEver) {
        await Hive.initFlutter();
      } else {
        unawaited(Hive.initFlutter().catchError((Object e) {
          debugPrint('[main_admin] Background Hive.initFlutter() error: $e');
        }));
      }

      try {
        if (Firebase.apps.isEmpty) {
          try {
            await Firebase.initializeApp(
              options: DefaultFirebaseOptions.currentPlatform,
            );
          } catch (initErr) {
            debugPrint('[main_admin] Options init error: $initErr, attempting native fallback');
            if (Firebase.apps.isEmpty) {
              await Firebase.initializeApp();
            }
          }
        }
        // Enable Firestore offline persistence on web (PWA). Mobile
        // (Android/iOS) already has persistence on by default, so this
        // is guarded to web only; a capped 50MB cache (CTO-specified)
        // keeps browser storage bounded instead of unlimited.
        if (kIsWeb) {
          FirebaseFirestore.instance.settings = const Settings(
            persistenceEnabled: true,
            cacheSizeBytes: 52428800, // 50MB
            webExperimentalForceLongPolling: true,
          );
        }
        if (kIsWeb) {
          try {
            await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
          } catch (e) {
            debugPrint('[main_admin] setPersistence(LOCAL) failed: $e');
          }
        }
      } on FirebaseException catch (e, stack) {
        if (e.code == 'duplicate-app') {
          debugPrint('[main_admin] Firebase already initialized, continuing.');
        } else {
          debugPrint('[main_admin] Firebase init failed: $e\n$stack');
          if (Firebase.apps.isEmpty) {
            runApp(_InitErrorApp('[BUILD-FINGERPRINT-31AUG-1348] Firebase initialization failed:\n$e\n\nSTACK:\n$stack'));
            return;
          }
        }
      } catch (e, stack) {
        debugPrint('[main_admin] Firebase init failed: $e\n$stack');
        if (Firebase.apps.isEmpty) {
          runApp(_InitErrorApp('[BUILD-FINGERPRINT-31AUG-1348] Firebase initialization failed:\n$e\n\nSTACK:\n$stack'));
          return;
        }
      }
      DbUsageTracker.instance.init('admin');

      // NEW (per Nizam's request — Admin "WhatsApp model" closed-app
      // alerts): registers the background handler + local-notification
      // channel BEFORE runApp, same ordering main_hero.dart uses, and
      // starts syncing this admin's FCM token the moment they're
      // signed in (works for both a fresh login and an already-warm
      // session restored from disk).
      FirebaseMessaging.onBackgroundMessage(_adminFirebaseMessagingBackgroundHandler);
      // FIX (Aug 10 2026 — rocket-speed repeat opens): same treatment as
      // Hive.initFlutter() above — first-ever launch still awaits these
      // (unchanged timing, hidden behind the video), a repeat launch fires
      // them unawaited so notification-channel setup doesn't stand between
      // "app opens" and runApp(AdminApp()) below.
      if (!hasSeenSplashVideoEver) {
        await AdminAlertNotificationService.initialize();
      } else {
        unawaited(AdminAlertNotificationService.initialize());
      }
      AdminForegroundService.initialize();
      ChittiAccessibilityBridge.instance.initialize();
      ChittiAccessibilityBridge.instance.onVoiceCommandReceived = (command) {
        if (!GuruOverlayService.instance.isShowing) {
          GuruOverlayService.instance.show();
        }
        unawaited(GuruOverlayService.instance.sendMessage(command));
      };
      // Assistant-gesture path (power button / home swipe, ChittiVoiceInteractionSession) —
      // no spoken text yet, just open the panel with the mic already
      // listening, same as tapping the FAB with voice intent.
      ChittiAccessibilityBridge.instance.onAssistTriggered = () {
        GuruOverlayService.instance.show(autoStartMic: true);
      };
      // NEW (Sep 1 2026 — in-call screen): tapping the ongoing-call
      // notification opens the live call UI. Routed through the shared
      // navigatorKey because this fires from a native intent, with no
      // BuildContext of its own.
      ChittiAccessibilityBridge.instance.onOpenInCallScreen = () {
        final nav = navigatorKey.currentState;
        if (nav == null) return;
        nav.push(MaterialPageRoute<void>(
          builder: (_) => const AdminInCallScreen(),
        ));
      };
      // NEW (Sep 2 2026 — launcher "Dialer" shortcut): long-pressing the
      // app icon and tapping "Dialer" jumps straight here instead of
      // the app's normal home screen first.
      ChittiAccessibilityBridge.instance.onOpenDialerScreen = () {
        final nav = navigatorKey.currentState;
        if (nav == null) return;
        nav.push(MaterialPageRoute<void>(
          builder: (_) => const AdminDialerScreen(),
        ));
      };
      // NEW (Sep 2 2026 — Nizam: "incoming call vantha attend panna
      // screen ila"). Fires as soon as a call starts ringing (see
      // PhoneCallService.onCallRinging), including a cold start where
      // the ringing call itself launched this app.
      ChittiAccessibilityBridge.instance.onIncomingCallRinging = (number) {
        final nav = navigatorKey.currentState;
        if (nav == null) return;
        nav.push(MaterialPageRoute<void>(
          builder: (_) => AdminIncomingCallScreen(number: number),
        ));
      };
      // NEW (Sep 3 2026 — Nizam: "call atten pannitu line cut anathum 3
      // popup shortcuts....1.messege, 2.redial to same person,
      // 3.whatsapp button"). Only fires when the admin app has a live
      // navigator context (i.e. it is in the foreground) — see
      // admin_post_call_sheet.dart's header for why this is not a
      // system-wide overlay.
      ChittiAccessibilityBridge.instance.onCallEndedWithNumber = (number) {
        final ctx = navigatorKey.currentContext;
        if (ctx == null) return;
        showAdminPostCallSheet(ctx, number);
      };
      if (!hasSeenSplashVideoEver) {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      } else {
        unawaited(FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        ));
      }
      _initAdminFcmAuthListener();
      // NEW (Sep 1 2026 — automation pipeline notification): CI sends a
      // push to this topic when a new test APK finishes building
      // (.github/workflows/ci-cd.yml's publish_admin_test_build job),
      // so the admin doesn't have to keep opening Development Monitor
      // to find out. Uses the SAME foreground-alert path as every other
      // admin notification above/below — no new UI needed.
      unawaited(FirebaseMessaging.instance.subscribeToTopic('chitti_dev_builds'));
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
      // On a repeat launch videoDone was already completed above (no
      // video was ever shown), so this resolves instantly and adds no
      // wait — Firebase init above (a local-session restore, not a fresh
      // network call in the common case) is the only thing standing
      // between "app opens" and runApp(AdminApp()) on a repeat launch.
      await videoDone.future;
      runApp(const AdminApp());
      // NEW (Aug 12 2026 — "Zero-Budget Escape Hatch"): fire-and-forget,
      // fails open on any error — see MigrationGateService's own header.
      // Also doubles as the source of truth admin writes migrationUrl
      // FROM (Admin QR Generator screen), so it's especially important
      // this app instance always has the listener running.
      MigrationGateService.instance.start();

      // Mark the video as seen only now that it has actually finished
      // playing (videoDone is only completed by AppSplashVideoScreen's
      // own onFinished/safety-timer, or immediately above if it was
      // already skipped) — every launch from here on takes the
      // "skip video" branch above.
      if (!hasSeenSplashVideoEver) {
        unawaited(earlyPrefs.setBool(_kSplashVideoSeenEverKey, true));
      }
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
        // NEW (Aug 31 2026): scrollable + selectable, and the caller now
        // passes the STACK TRACE too. A boot failure that only shows its
        // message ("RangeError 0..13: 14") gives nothing to act on — it
        // cost three rebuild-and-guess cycles on a real device before
        // this was added. One screenshot of the frame below names the
        // exact package and line instead.
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: SelectableText(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
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
      // plays pre-Firebase/Hive as the very first boot frame (see
      // _BootLoadingApp above) instead of here — this used to wrap the
      // StreamBuilder auth gate in a second AppSplashVideoScreen play,
      // which would have shown the same video twice back to back on every
      // launch. Now goes straight to the (unchanged) StreamBuilder gate.
      // UPDATED (Aug 10 2026): the pre-Firebase video itself is now
      // first-ever-launch-only (see _kSplashVideoSeenEverKey in main())
      // — on every later launch nothing plays before this route at all,
      // and this StreamBuilder's existing initialData fast-path is what
      // the admin actually sees appear almost instantly.
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
      // NEW (Aug 12 2026 — "Zero-Budget Escape Hatch"): MigrationGate
      // wraps EVERYTHING else here, including the Quick Task FAB — a
      // migration lock must hide the whole app, not sit under a
      // still-interactive overlay.
      builder: (context, child) => MigrationGate(
        child: Stack(
          children: [
            if (child != null) child,
            const GlobalGuruFab(),
          ],
        ),
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
