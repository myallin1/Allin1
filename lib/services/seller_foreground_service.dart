// ================================================================
// seller_foreground_service.dart — Android "Seller Monitoring Active"
// persistent foreground service.
// ================================================================
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
class _SellerKeepAliveTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[SellerForegroundService] Keep-alive service started');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[SellerForegroundService] Keep-alive service stopped');
  }
}

@pragma('vm:entry-point')
void _sellerForegroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_SellerKeepAliveTaskHandler());
}

class SellerForegroundService {
  SellerForegroundService._();

  static bool _initialized = false;

  static void initialize() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        FlutterForegroundTask.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'seller_online_status',
            channelName: 'Seller Monitoring Active',
            channelDescription:
                'Keeps the Seller app watching for new orders in the background.',
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
        debugPrint('[SellerForegroundService] init failed (non-fatal): $e');
      }
    }
  }

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
        notificationTitle: 'MyAllin1 Seller — Monitoring Active',
        notificationText: 'Watching for new orders...',
        callback: _sellerForegroundTaskCallback,
      );
      debugPrint('[SellerForegroundService] Started');
    } catch (e) {
      debugPrint('[SellerForegroundService] start failed: $e');
    }
  }

  static Future<void> stop() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final alreadyRunning = await FlutterForegroundTask.isRunningService;
      if (!alreadyRunning) return;
      await FlutterForegroundTask.stopService();
      debugPrint('[SellerForegroundService] Stopped');
    } catch (e) {
      debugPrint('[SellerForegroundService] stop failed: $e');
    }
  }
}
