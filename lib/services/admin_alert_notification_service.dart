// ================================================================
// admin_alert_notification_service.dart — Admin "WhatsApp model"
// closed-app alerts.
// ================================================================
// NEW (per Nizam's request — "admin app whatsapp model ku innum full
// update agala"): the Admin app previously had ZERO Firebase Messaging
// wiring at all (no onBackgroundMessage handler, no local-notification
// channel, no FCM token ever saved) — meaning it was structurally
// impossible for a closed/locked admin phone to ever be alerted about
// a new ride or service request, no matter what happened server-side.
// Free-tier build (no Blaze/Cloud Functions) — paired with
// admin_foreground_service.dart + admin_live_alert_service.dart.
//
// FIX (2nd pass, per Nizam's follow-up bug report): two gaps found —
// (1) tapping the notification did nothing (no onDidReceiveNotification
// Response registered), so the admin app just opened to whatever
// screen it last had, with zero way to find the new ride. Now
// navigates straight to the right live-monitoring screen using the
// payload's `type`. (2) the alert used a generic system sound instead
// of a loud, DND-bypassing custom tone — reuses the exact same
// ride_alert.mp3-through-the-alarm-stream approach already proven for
// Hero (hero_ride_notification_service.dart), so admin gets an
// equally-unmissable alert, single sound source (no duplicate-sound
// bug — see the fix applied to Hero's own notification for why that
// matters).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../app_navigator.dart';
import '../screens/admin/admin_new_orders_screen.dart';
import '../screens/admin/admin_taxi_rides_screen.dart';

@pragma('vm:entry-point')
void adminAlertResponseBackground(NotificationResponse response) {
  unawaited(AdminAlertNotificationService.handleNotificationResponse(response));
}

class AdminAlertNotificationService {
  static const String alertChannelId = 'admin_alerts_v2';
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (kIsWeb || _initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: adminAlertResponseBackground,
    );

    // Same loud, alarm-stream approach as Hero's ride alert channel —
    // bypasses silent mode/DND, single sound source (no separate
    // FlutterRingtonePlayer call here, avoiding the double-sound bug).
    const channel = AndroidNotificationChannel(
      alertChannelId,
      'Admin Alerts',
      description: 'New ride and service request alerts for the Admin app.',
      importance: Importance.max,
      sound: RawResourceAndroidNotificationSound('ride_alert'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableLights: true,
      playSound: true,
    );
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(channel);
    await androidPlugin?.requestNotificationsPermission();
    _initialized = true;
  }

  /// Shows a local notification. `type` drives where a tap navigates —
  /// 'admin_new_ride' -> AdminTaxiRidesScreen, everything else ->
  /// AdminNewOrdersScreen (service requests).
  static Future<void> showForegroundAlert({
    required String title,
    required String body,
    required String payloadId,
    String type = 'admin_new_ride',
  }) async {
    if (kIsWeb) return;
    try {
      await _plugin.show(
        id: payloadId.hashCode & 0x7fffffff,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            alertChannelId,
            'Admin Alerts',
            channelDescription:
                'New ride and service request alerts for the Admin app.',
            importance: Importance.max,
            priority: Priority.max,
            sound: RawResourceAndroidNotificationSound('ride_alert'),
            audioAttributesUsage: AudioAttributesUsage.alarm,
            fullScreenIntent: false,
          ),
        ),
        payload: jsonEncode(<String, String>{'type': type}),
      );
    } catch (e) {
      debugPrint('[AdminAlertNotificationService] show failed: $e');
    }
  }

  static Future<void> handleNotificationResponse(
    NotificationResponse response,
  ) async {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final type = data['type'] as String? ?? '';
      final navigator = navigatorKey.currentState;
      if (navigator == null) return;
      if (type == 'admin_new_ride') {
        await navigator.push(
          MaterialPageRoute<void>(builder: (_) => const AdminTaxiRidesScreen()),
        );
      } else {
        await navigator.push(
          MaterialPageRoute<void>(builder: (_) => const AdminNewOrdersScreen()),
        );
      }
    } catch (e) {
      debugPrint('[AdminAlertNotificationService] tap navigation failed: $e');
    }
  }
}
