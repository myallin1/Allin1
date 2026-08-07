// ================================================================
// hero_foreground_service.dart — Android "You are Online" persistent
// foreground service.
// ================================================================
// CTO mandate — FCM Data Push Layer 2 alternative, Option D: rather
// than paying for Cloud Functions (Blaze-only) to wake a KILLED Hero
// app via FCM, this sidesteps the problem by keeping the app process
// from being killed in the first place while a hero is Online. A
// foreground service with a persistent, low-priority notification
// ("NJ TECH — You are Online / Waiting for tasks") tells Android's
// process manager this app is doing user-visible, ongoing work and
// should not be OOM-killed the way an ordinary backgrounded app would
// be. Every RTDB listener already running in the Hero app's main
// isolate (main_hero.dart's _initGlobalHeroPingListener,
// hero_home_screen.dart's _listenForHeroPings/_listenForServicePings)
// benefits automatically — this file does NOT duplicate that listening
// logic into a separate isolate; its only job is keeping the process
// that already runs it alive.
//
// Deliberately Android-only. iOS has no equivalent concept (a
// long-running foreground service isn't a thing there — iOS's own
// background execution model is entirely different and out of scope
// for this change) and the PWA/web build has no OS process to protect
// at all. Every public method here is a no-op (not an error) on any
// non-Android platform, so callers never need their own kIsWeb/
// Platform.isAndroid guards.
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Minimal task handler — deliberately does nothing itself. The
/// foreground service's entire value here is process-keep-alive; the
/// actual ping listening already happens in the main Flutter isolate
/// via the app's normal RTDB listeners, which is exactly what staying
/// alive protects. Re-implementing that logic inside this handler's
/// separate isolate would be a much larger, riskier duplication for no
/// benefit — the notification callback below only exists because the
/// plugin requires SOME TaskHandler to be registered to start a
/// foreground service at all.
@pragma('vm:entry-point')
class _HeroKeepAliveTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[HeroForegroundService] Keep-alive service started');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Intentionally empty — no periodic work needed. The service's
    // mere existence (and its notification) is what protects the
    // process; onRepeatEvent firing is just the plugin's own internal
    // heartbeat, not something this app needs to react to.
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[HeroForegroundService] Keep-alive service stopped');
  }
}

@pragma('vm:entry-point')
void _heroForegroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_HeroKeepAliveTaskHandler());
}

class HeroForegroundService {
  HeroForegroundService._();

  static bool _initialized = false;

  /// Call once at Hero app boot (main_hero.dart) — cheap, idempotent,
  /// does not itself start the service or show any notification. Only
  /// registers the notification channel/options so start() later is
  /// fast. Best-effort: a failure here must never block app boot.
  static void initialize() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        FlutterForegroundTask.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'hero_online_status',
            channelName: 'Hero Online Status',
            channelDescription:
                'Shows while you are Online and available for tasks. '
                'Keeps the app responsive to new ride/task requests in '
                'the background.',
            // LOW, no sound/vibration — this is a persistent status
            // indicator, not an alert. The loud ringtone/notification
            // for an actual incoming ride/task is a completely
            // separate channel (see hero_ride_notification_service.dart)
            // and is unaffected by this.
            channelImportance: NotificationChannelImportance.LOW,
            priority: NotificationPriority.LOW,
          ),
          iosNotificationOptions: const IOSNotificationOptions(),
          foregroundTaskOptions: ForegroundTaskOptions(
            eventAction: ForegroundTaskEventAction.repeat(60000),
            autoRunOnBoot: false,
            allowWifiLock: false,
          ),
        );
        _initialized = true;
      } catch (e) {
        debugPrint('[HeroForegroundService] init failed (non-fatal): $e');
      }
    }
  }

  /// Starts (or restarts, if already running — idempotent) the
  /// persistent "You are Online" foreground service. Call this exactly
  /// where hero_home_screen.dart's _syncOnlineStatus() transitions a
  /// hero to Online. Best-effort: a failure here must never block the
  /// hero from actually going online — RTDB presence (onDisconnect +
  /// .info/connected) already works independently of this.
  static Future<void> start() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    if (!_initialized) {
      initialize();
    }
    try {
      final permission = await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }

      final alreadyRunning = await FlutterForegroundTask.isRunningService;
      if (alreadyRunning) {
        debugPrint('[HeroForegroundService] Already running — skipping restart');
        return;
      }

      await FlutterForegroundTask.startService(
        notificationTitle: 'NJ TECH — You are Online',
        notificationText: 'Waiting for tasks...',
        callback: _heroForegroundTaskCallback,
      );
      debugPrint('[HeroForegroundService] Started');
    } catch (e) {
      debugPrint('[HeroForegroundService] start() failed (non-fatal): $e');
    }
  }

  /// Stops the foreground service. Call wherever a hero goes Offline
  /// (including the logout flow, which already calls
  /// _syncOnlineStatus(false) before signing out — see
  /// hero_home_screen.dart's _showLogoutDialog) or on any error path
  /// that forces _isOnline back to false. Best-effort/idempotent: safe
  /// to call even if the service was never started.
  static Future<void> stop() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      final running = await FlutterForegroundTask.isRunningService;
      if (!running) {
        return;
      }
      await FlutterForegroundTask.stopService();
      debugPrint('[HeroForegroundService] Stopped');
    } catch (e) {
      debugPrint('[HeroForegroundService] stop() failed (non-fatal): $e');
    }
  }
}
