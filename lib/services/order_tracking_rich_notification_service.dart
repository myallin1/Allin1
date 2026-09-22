// ================================================================
// order_tracking_rich_notification_service.dart — Phase 3 of the
// live-order-tracking-notification feature (branch: feature/live-
// order-tracking-notification)
// ================================================================
// Pushes the Blinkit-style animated-icon-on-a-path notification via
// flutter_local_notifications' Android BigPictureStyle — already a
// dependency in this app (hero_ride_notification_service.dart uses
// the same plugin), so this needs no new package and no native
// Kotlin/RemoteViews code (see order_tracking_bitmap_painter.dart's
// header for the full reasoning).
//
// RELATIONSHIP TO Phase 2's OrderTrackingForegroundService
// Only one of the two is ever showing a notification at a time for a
// given order — see OrderTrackingNotificationController, which is the
// only caller of either service and owns that hand-off: the plain
// text/progress notification (Phase 2) covers `waiting`/`assigned`
// (nothing to animate yet, no hero location exists), and this rich
// one takes over the instant a hero's live location is available.
// Never both at once — a customer seeing two ongoing notifications
// for the same order would be confusing, not reassuring.
//
// STABLE NOTIFICATION ID (not a per-order hash): this feature tracks
// at most one order at a time (see OrderTrackingNotificationController's
// own header), so re-using one fixed id for every update is correct —
// each show() call replaces the previous content in place rather than
// stacking a new notification.
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/tracking_snapshot.dart';
import '../utils/order_tracking_bitmap_painter.dart';
import '../utils/service_request_labels.dart';

class OrderTrackingRichNotificationService {
  OrderTrackingRichNotificationService._();

  static const int _notificationId = 918273; // fixed, see header
  static const String _channelId = 'order_tracking_rich';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> _ensureInitialized() async {
    if (kIsWeb || _initialized) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _plugin.initialize(settings: initSettings);
      // FIX (grep re-audit, Sep 2026 — real gap): without requesting this,
      // show() silently does nothing on Android 13+ until some OTHER
      // notification path (e.g. OrderTrackingForegroundService.start())
      // happens to have asked first. That's not guaranteed here — a
      // customer resuming an already-en-route order right at app boot
      // (OrderTrackingNotificationController.resumeIfActive finding a
      // snapshot that already has a live location) jumps straight into
      // this service without Phase 2's plain-text path ever running
      // first. Matches the same call hero_ride_notification_service.dart
      // already makes during its own initialize().
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      _initialized = true;
    } catch (e) {
      debugPrint('[OrderTrackingRichNotificationService] init failed (non-fatal): $e');
    }
  }

  /// Renders the current snapshot as a bitmap and shows/updates the
  /// ongoing rich notification. Best-effort: any failure (render or
  /// plugin call) is swallowed — the caller (OrderTrackingForegroundService's
  /// plain-text path, via the controller) is the fallback a customer
  /// still sees if this fails, so a failure here is never silent to
  /// the customer, just less pretty.
  static Future<void> show(TrackingSnapshot snapshot) async {
    if (kIsWeb) return;
    await _ensureInitialized();
    try {
      final bytes = await OrderTrackingBitmapPainter.render(snapshot);
      if (bytes == null) return;

      final title = _titleFor(snapshot);
      final text = _textFor(snapshot);

      final androidDetails = AndroidNotificationDetails(
        _channelId,
        'Order Tracking',
        channelDescription: 'Live status of your active order or ride.',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        showWhen: false,
        styleInformation: BigPictureStyleInformation(
          ByteArrayAndroidBitmap(Uint8List.fromList(bytes)),
          largeIcon: null,
          contentTitle: title,
          summaryText: text,
          htmlFormatContentTitle: false,
          htmlFormatSummaryText: false,
        ),
      );

      await _plugin.show(
        id: _notificationId,
        title: title,
        body: text,
        notificationDetails: NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('[OrderTrackingRichNotificationService] show() failed (non-fatal): $e');
    }
  }

  static Future<void> cancel() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancel(id: _notificationId);
    } catch (e) {
      debugPrint('[OrderTrackingRichNotificationService] cancel() failed (non-fatal): $e');
    }
  }

  static String _titleFor(TrackingSnapshot snapshot) {
    switch (snapshot.requestType) {
      case 'catalog_food_order':
      case 'custom_hotel_order':
        return 'Your food order';
      case 'grocery_order':
        return 'Your grocery order';
      case 'bike_taxi':
        return 'Your bike ride';
      case 'car_taxi':
        return 'Your car ride';
      default:
        return 'Your order';
    }
  }

  static String _textFor(TrackingSnapshot snapshot) {
    if (snapshot.collection == TrackingCollection.serviceRequests) {
      return serviceRequestStatusLabel(snapshot.requestType, snapshot.rawStatus);
    }
    switch (snapshot.phase) {
      case TrackingPhase.enRoute:
        return 'On the way';
      case TrackingPhase.nearingCompletion:
        return 'Arriving now';
      default:
        return 'Tracking your ride';
    }
  }
}
