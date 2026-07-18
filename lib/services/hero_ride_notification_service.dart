import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kPendingHeroRideIdKey = 'pending_hero_ride_id';
const String kPendingHeroAcceptRideIdKey = 'pending_hero_accept_ride_id';

@pragma('vm:entry-point')
void heroRideNotificationResponseBackground(NotificationResponse response) {
  unawaited(HeroRideNotificationService.handleNotificationResponse(response));
}

class HeroRideNotificationService {
  // FIX T2: Bumped to v5 — forces Android to recreate channel with
  // ride_alert.mp3 sound + full-screen-intent settings + alarm volume + vibration baked in.
  static const String rideAlertChannelId = 'hero_ride_alerts_v5';
  static const String acceptRideActionId = 'accept_ride';
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static int _notificationIdForRide(String rideId) =>
      rideId.hashCode & 0x7fffffff;

  // ── De-duplication guards ──────────────────────────────────
  static String? lastProcessedRideId;
  static DateTime? lastProcessedAt;

  static Future<void> initialize() async {
    if (kIsWeb || _initialized) {
      return;
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: DarwinInitializationSettings(),
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          heroRideNotificationResponseBackground,
    );

    const channel = AndroidNotificationChannel(
      rideAlertChannelId,
      'Hero Ride Alerts',
      description:
          'Lock-screen ride request alerts with ACCEPT action and ringtone.',
      importance: Importance.max,
      sound: RawResourceAndroidNotificationSound('ride_alert'),
      enableLights: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(channel);
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestFullScreenIntentPermission();
    _initialized = true;
  }

  static Future<void> handleNotificationResponse(
    NotificationResponse response,
  ) async {
    final rideId = _rideIdFromPayload(response.payload);
    if (rideId == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPendingHeroRideIdKey, rideId);
    if (response.actionId == acceptRideActionId) {
      await prefs.setString(kPendingHeroAcceptRideIdKey, rideId);
    }
    await stopWakeAlertRingtone();
    await _plugin.cancel(id: _notificationIdForRide(rideId));
  }

  static Future<void> playWakeAlertRingtone({bool looping = true}) async {
    if (kIsWeb) {
      return;
    }
    try {
      // 🚀 FIX: Switched from AndroidSounds.ringtone to AndroidSounds.alarm.
      // This forces the sound through the ALARM stream (bypassing silent mode)
      // and plays at maximum alarm volume, ensuring the driver never misses a ride.
      FlutterRingtonePlayer().play(
        android: AndroidSounds.alarm,
        ios: IosSounds.alarm,
        looping: looping,
        volume: 1,
        asAlarm: true,
      );
    } catch (e) {
      debugPrint('[HeroRideNotificationService] Ringtone play failed: $e');
    }
  }

  static Future<void> stopWakeAlertRingtone() async {
    if (kIsWeb) {
      return;
    }
    try {
      FlutterRingtonePlayer().stop();
    } catch (e) {
      debugPrint('[HeroRideNotificationService] Ringtone stop failed: $e');
    }
  }

  static Future<void> showRideAssigned({
    required String rideId,
    required Map<String, dynamic> data,
    bool playAlertTone = true,
    // ── Generic-text overrides ──────────────────────────────────
    // Defaults preserve the exact ride-alert text/behavior for every
    // existing call site. Passing overrides (e.g. from the broadcast
    // order system) reuses the identical full-screen-intent + alarm-
    // stream ringtone mechanism with different wording.
    String title = 'New Ride Assigned',
    String channelName = 'Hero Ride Alerts',
    String channelDescription =
        'Lock-screen ride request alerts with ACCEPT action and ringtone.',
    String ticker = 'New ride assigned',
    String emptyBodyFallback = 'Tap ACCEPT to open the ride request.',
  }) async {
    if (kIsWeb || rideId.trim().isEmpty) {
      return;
    }

    await initialize();
    final pickup = _stringValue(data, const [
      'pickupAddress',
      'pickup',
      'fromAddress',
    ]);
    final drop = _stringValue(data, const [
      'dropAddress',
      'drop',
      'toAddress',
    ]);
    final fare = _fareText(data);
    final body = [
      if (pickup.isNotEmpty) 'Pickup: $pickup',
      if (drop.isNotEmpty) 'Drop: $drop',
      if (fare.isNotEmpty) 'Fare: $fare',
    ].join('\n');

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        rideAlertChannelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.call,
        visibility: NotificationVisibility.public,
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: false,
        // 0ms delay, vibrate 1sec, pause 0.5sec, vibrate 1sec, pause 0.5sec, vibrate 1sec
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
        ticker: ticker,
        timeoutAfter: 15000,
        sound: const RawResourceAndroidNotificationSound('ride_alert'),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        actions: const [
          AndroidNotificationAction(
            acceptRideActionId,
            'ACCEPT',
            icon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
            showsUserInterface: true,
            contextual: true,
          ),
        ],
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        sound: 'ride_alert.mp3',
      ),
    );

    await _plugin.show(
      id: _notificationIdForRide(rideId),
      title: title,
      body: body.isEmpty ? emptyBodyFallback : body,
      notificationDetails: details,
      payload: jsonEncode(<String, String>{'rideId': rideId}),
    );
    if (playAlertTone) {
      await playWakeAlertRingtone();
    }
  }

  // ── Cancel Ride Notification (Kill Signal) ────────────────
  static Future<void> cancelRideNotification(String rideId) async {
    try {
      // Use hashCode instead of hex parsing — works for any Firestore doc ID
      final notificationId = rideId.hashCode.abs() & 0x7FFFFFFF;

      await _plugin.cancel(id: notificationId);
      debugPrint(
        '[NotificationService] ✅ Cancelled notification for ride: $rideId (ID: $notificationId)',
      );

      // Clear de-duplication flag
      if (lastProcessedRideId == rideId) {
        lastProcessedRideId = null;
        lastProcessedAt = null;
      }
    } catch (e) {
      debugPrint('[NotificationService] ❌ Cancel failed for $rideId: $e');
    }
  }

  // ── Check if notification already processing (De-duplication) ──
  static bool shouldProcessRideNotification(String rideId) {
    final now = DateTime.now();

    // If same ride pinged within 3 seconds — skip
    if (lastProcessedRideId == rideId &&
        lastProcessedAt != null &&
        now.difference(lastProcessedAt!).inSeconds < 3) {
      debugPrint(
        '[NotificationService] ⏭️ Skipping duplicate notification for $rideId',
      );
      return false;
    }

    // New ride or 3s+ passed — process it
    lastProcessedRideId = rideId;
    lastProcessedAt = now;
    return true;
  }

  static String? _rideIdFromPayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        final rideId = decoded['rideId'];
        if (rideId is String && rideId.trim().isNotEmpty) {
          return rideId.trim();
        }
      }
    } catch (_) {
      if (payload.trim().isNotEmpty) {
        return payload.trim();
      }
    }
    return null;
  }

  static String _stringValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }

  static String _fareText(Map<String, dynamic> data) {
    for (final key in const [
      'totalFare',
      'actualFare',
      'estimatedFare',
      'fare',
    ]) {
      final value = data[key];
      if (value is num && value > 0) {
        return '₹${value.toStringAsFixed(0)}';
      }
    }
    return '';
  }
}
