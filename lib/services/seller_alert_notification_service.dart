// ================================================================
// seller_alert_notification_service.dart — Seller loud order alerts.
// ================================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../app_navigator.dart';

@pragma('vm:entry-point')
void sellerAlertResponseBackground(NotificationResponse response) {
  unawaited(SellerAlertNotificationService.handleNotificationResponse(response));
}

class SellerAlertNotificationService {
  static const String alertChannelId = 'seller_alerts_v1';
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
      onDidReceiveBackgroundNotificationResponse: sellerAlertResponseBackground,
    );

    const channel = AndroidNotificationChannel(
      alertChannelId,
      'Seller Order Alerts',
      description: 'Loud alarm for incoming food orders.',
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

  static Future<void> showForegroundAlert({
    required String title,
    required String body,
    required String payloadId,
    String type = 'seller_new_order',
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
            'Seller Order Alerts',
            channelDescription: 'Loud alarm for incoming food orders.',
            importance: Importance.max,
            priority: Priority.max,
            fullScreenIntent: true,
            icon: '@mipmap/ic_launcher',
            sound: RawResourceAndroidNotificationSound('ride_alert'),
            audioAttributesUsage: AudioAttributesUsage.alarm,
            enableVibration: true,
            playSound: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        payload: jsonEncode({'type': type, 'id': payloadId}),
      );
    } catch (e) {
      debugPrint('[SellerAlertNotificationService] show alert failed: $e');
    }
  }

  static Future<void> handleNotificationResponse(
      NotificationResponse response) async {
    try {
      if (response.payload == null) return;
      final context = navigatorKey.currentContext;
      if (context != null) {
         Navigator.pushNamedAndRemoveUntil(context, '/seller-home', (route) => false);
      }
    } catch (e) {
      debugPrint('[SellerAlertNotificationService] handle response failed: $e');
    }
  }
}
