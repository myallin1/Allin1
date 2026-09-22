// ================================================================
// order_tracking_foreground_service.dart — Phase 2 of the live-order-
// tracking-notification feature (branch: feature/live-order-tracking-
// notification)
// ================================================================
// Low-level Android foreground-service wrapper for the customer app's
// live order-tracking notification. Deliberately mirrors
// hero_foreground_service.dart's exact shape (init/start/update/stop,
// same Android-only guard, same best-effort/never-block-the-caller
// error handling) rather than inventing a new pattern — that file is
// the proven, already-shipped precedent for exactly this kind of
// persistent notification in this codebase.
//
// WHAT'S DIFFERENT FROM hero_foreground_service.dart
// The hero version's notification content is STATIC ("You are
// Online") — its whole job is process-keep-alive, nothing more. This
// one's content needs to change live as an order moves through
// pending -> assigned -> en route -> arriving (Phase 3 layers an
// animated icon on top of this; this file only owns the plumbing:
// starting, updating title/text/progress, and stopping). update()
// below is the new method this file adds beyond the hero pattern.
//
// BATTERY NOTE (per Nizam's explicit ask — "battery theeratha maari"):
// this file does NOT poll anything on a timer. It only ever pushes an
// update when OrderTrackingNotificationController hands it one, which
// only happens when the underlying Firestore/RTDB streams (Phase 1)
// actually emit a change — i.e. the exact same event-driven model
// hero_foreground_service.dart already uses for its own listeners.
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
class _OrderTrackingTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[OrderTrackingForegroundService] Started');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Intentionally empty — same reasoning as HeroForegroundService's
    // handler: the notification's own existence is what protects the
    // process; content updates arrive via update() from the main
    // isolate, not from this repeat callback.
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[OrderTrackingForegroundService] Stopped');
  }
}

@pragma('vm:entry-point')
void _orderTrackingForegroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_OrderTrackingTaskHandler());
}

class OrderTrackingForegroundService {
  OrderTrackingForegroundService._();

  static bool _initialized = false;

  /// Call once at customer app boot (main_customer.dart) — cheap,
  /// idempotent, registers the notification channel without starting
  /// the service or showing anything yet.
  static void initialize() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        FlutterForegroundTask.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'order_tracking',
            channelName: 'Order Tracking',
            channelDescription:
                'Shows the live status of your active order or ride — '
                'lets you know the moment it\'s on the way.',
          ),
          iosNotificationOptions: const IOSNotificationOptions(),
          // No repeat event needed — see onRepeatEvent's own comment.
          // A long interval here is just the plugin's minimum
          // keep-alive heartbeat, not something this feature reacts to.
          foregroundTaskOptions: ForegroundTaskOptions(
            eventAction: ForegroundTaskEventAction.repeat(60000),
          ),
        );
        _initialized = true;
      } catch (e) {
        debugPrint('[OrderTrackingForegroundService] init failed (non-fatal): $e');
      }
    }
  }

  /// Starts the notification with initial content. Idempotent — if a
  /// tracking notification is already running (e.g. a second order
  /// placed while one is still active, or a hot-restart), this updates
  /// the existing one instead of trying to start a duplicate.
  static Future<void> start({
    required String title,
    required String text,
  }) async {
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
        await update(title: title, text: text);
        return;
      }

      await FlutterForegroundTask.startService(
        notificationTitle: title,
        notificationText: text,
        callback: _orderTrackingForegroundTaskCallback,
      );
      debugPrint('[OrderTrackingForegroundService] Started: $title / $text');
    } catch (e) {
      debugPrint('[OrderTrackingForegroundService] start() failed (non-fatal): $e');
    }
  }

  /// Pushes new content onto an already-running notification. Called
  /// by OrderTrackingNotificationController on every TrackingSnapshot
  /// change — never on a timer (see this file's battery note above).
  /// Safe to call even if the service isn't running (silently returns).
  static Future<void> update({
    required String title,
    required String text,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      final running = await FlutterForegroundTask.isRunningService;
      if (!running) return;
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    } catch (e) {
      debugPrint('[OrderTrackingForegroundService] update() failed (non-fatal): $e');
    }
  }

  /// Stops the notification. Call when the tracked order reaches a
  /// terminal phase (completed/cancelled) or when tracking is
  /// otherwise abandoned (e.g. customer signs out).
  static Future<void> stop() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      final running = await FlutterForegroundTask.isRunningService;
      if (!running) return;
      await FlutterForegroundTask.stopService();
      debugPrint('[OrderTrackingForegroundService] Stopped');
    } catch (e) {
      debugPrint('[OrderTrackingForegroundService] stop() failed (non-fatal): $e');
    }
  }
}
