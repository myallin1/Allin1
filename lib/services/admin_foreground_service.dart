// ================================================================
// admin_foreground_service.dart — Android "Admin Monitoring Active"
// persistent foreground service.
// ================================================================
// NEW (per Nizam's request — free alternative to Cloud Functions,
// since Blaze/billing is off the table): exact same "Option D" pattern
// already proven for Hero (see hero_foreground_service.dart's own
// comment block) — instead of paying for a Cloud Function to wake a
// KILLED Admin app via FCM, this keeps the Admin app process from
// being killed by Android in the first place whenever an admin is
// logged in, via a persistent low-priority notification. The app's own
// Firestore listeners (see admin_live_alert_service.dart) then keep
// running continuously in the same process and can fire a LOUD local
// notification the instant a new ride/service request document is
// created — no server, no billing, no Cloud Functions involved.
//
// Deliberately Android-only, same reasoning as HeroForegroundService:
// iOS has no equivalent, and the Admin PWA/web build has no OS process
// to protect (a closed browser tab genuinely cannot run code without a
// service worker + push subscription, which is its own separate, much
// larger project — out of scope for this free-tier fix).
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
class _AdminKeepAliveTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[AdminForegroundService] Keep-alive service started');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Intentionally empty — see HeroForegroundService's identical note.
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[AdminForegroundService] Keep-alive service stopped');
  }
}

@pragma('vm:entry-point')
void _adminForegroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_AdminKeepAliveTaskHandler());
}

class AdminForegroundService {
  AdminForegroundService._();

  static bool _initialized = false;

  static void initialize() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        FlutterForegroundTask.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'admin_online_status',
            channelName: 'Admin Monitoring Active',
            channelDescription:
                'Keeps the Admin app watching for new rides and service '
                'requests in the background so alerts still arrive with '
                'the app closed.',
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
        debugPrint('[AdminForegroundService] init failed (non-fatal): $e');
      }
    }
  }

  /// Call once the admin is signed in — keeps running for the whole
  /// session (unlike Hero's start/stop-per-online-toggle, an admin
  /// should always be reachable while logged in).
  static Future<void> start() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (!_initialized) initialize();
    try {
      final permission = await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      final alreadyRunning = await FlutterForegroundTask.isRunningService;
      if (alreadyRunning) return;
      await FlutterForegroundTask.startService(
        notificationTitle: 'NJ TECH Admin — Monitoring Active',
        notificationText: 'Watching for new rides and service requests...',
        callback: _adminForegroundTaskCallback,
      );
      debugPrint('[AdminForegroundService] Started');
    } catch (e) {
      debugPrint('[AdminForegroundService] start() failed (non-fatal): $e');
    }
  }

  /// Call on logout.
  static Future<void> stop() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final running = await FlutterForegroundTask.isRunningService;
      if (!running) return;
      await FlutterForegroundTask.stopService();
      debugPrint('[AdminForegroundService] Stopped');
    } catch (e) {
      debugPrint('[AdminForegroundService] stop() failed (non-fatal): $e');
    }
  }
}
