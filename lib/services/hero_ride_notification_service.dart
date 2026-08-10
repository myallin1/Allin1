import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hive_cache.dart';

const String kPendingHeroRideIdKey = 'pending_hero_ride_id';
const String kPendingHeroAcceptRideIdKey = 'pending_hero_accept_ride_id';
// TASK 39 (Aug 8 2026 — unified View/Accept/Minimize notification popup):
// same string as hero_home_screen.dart's private
// _pendingHeroServiceRequestIdKey and main_hero.dart's
// kPendingHeroServiceRequestIdKey — duplicated (not imported) on purpose,
// same pattern already used across those two files, since it's just a
// SharedPreferences key literal, not a shared object.
const String kPendingHeroServiceRequestIdKey = 'pending_hero_service_request_id';

@pragma('vm:entry-point')
void heroRideNotificationResponseBackground(NotificationResponse response) {
  unawaited(HeroRideNotificationService.handleNotificationResponse(response));
}

class HeroRideNotificationService {
  // FIX T2: Bumped to v5 — forces Android to recreate channel with
  // ride_alert.mp3 sound + full-screen-intent settings + alarm volume + vibration baked in.
  static const String rideAlertChannelId = 'hero_ride_alerts_v5';
  static const String acceptRideActionId = 'accept_ride';
  // TASK 39 (Aug 8 2026): the standard 3-button notification contract —
  // View / Accept / Minimize — used by every request type (ride, hero
  // booking, grocery, food). VIEW and tapping the notification body do
  // the same thing (open the existing accept dialog wherever the hero
  // currently is); ACCEPT additionally fast-accepts a ride the way it
  // always has; MINIMIZE dismisses the notification WITHOUT opening
  // anything — the request stays valid, same "close but don't touch the
  // ping" contract as the in-app dialog's own MINIMIZE button (see
  // hero_home_screen.dart's _PingCountdownDialog / _doShowServiceDialog).
  static const String viewRideActionId = 'view_ride';
  static const String minimizeRideActionId = 'minimize_ride';
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static int _notificationIdForRide(String rideId) =>
      rideId.hashCode & 0x7fffffff;

  // ── De-duplication guards ──────────────────────────────────
  // Persisted via HiveCache (not a static in-memory field) so the
  // dedup check survives the FCM background-isolate / main-isolate
  // boundary — a plain static var only dedups within one isolate's
  // lifetime, which is why background + foreground paths could both
  // fire for the same ride. Window widened from 3s to 18s to cover
  // realistic "hero unlocks phone and opens app" delay after a
  // background push already showed a (quiet) system notification.
  static const Duration _deduplicationWindow = Duration(seconds: 18);
  static String _dedupKey(String rideId) => 'hero_ride_notified_$rideId';

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

    // BUG B3 FIX (Aug 8 2026): flutter_local_notifications' response
    // callbacks (onDidReceiveNotificationResponse /
    // onDidReceiveBackgroundNotificationResponse, registered above) only
    // fire for a tap that happens AFTER the plugin is initialized — they
    // never fire for the tap that COLD-LAUNCHED a fully-killed app,
    // because nothing was listening yet at the moment of that tap.
    // getNotificationAppLaunchDetails() is the documented way to recover
    // that specific tap after the fact. This codebase never called it
    // before today. Consequence: on a genuine cold launch, the pending-*
    // SharedPreferences key still gets set (main_hero.dart's FCM
    // background handler writes it independently, before any tap), so
    // the accept dialog itself wasn't silently lost — but the ACCEPT
    // fast-path (kPendingHeroAcceptRideIdKey, only ever set inside
    // handleNotificationResponse) was, since that callback never ran.
    // A hero tapping ACCEPT directly from the lock screen on a killed
    // app got downgraded to "just open the dialog" with no visible
    // error. This call closes that gap by routing the launch tap
    // through the exact same handleNotificationResponse() logic used
    // for a live tap.
    try {
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true &&
          launchDetails?.notificationResponse != null) {
        await handleNotificationResponse(launchDetails!.notificationResponse!);
      }
    } catch (e) {
      debugPrint('[HeroRideNotificationService] getNotificationAppLaunchDetails failed: $e');
    }

    // TASK 1 (Aug 8 2026, live-test bug: ringtone played but Accept UI
    // never appeared while the app was backgrounded with the screen
    // off). Every code-level prerequisite for full-screen-intent
    // (manifest permission, showWhenLocked/turnScreenOn on
    // MainActivity, fullScreenIntent:true + max importance/priority on
    // this channel, requestFullScreenIntentPermission() above) was
    // already correct — the remaining, very common real-world cause on
    // Chinese/OEM-skinned Android (MIUI, ColorOS, EMUI, One UI
    // aggressive mode, etc.) is the OS killing/freezing the app process
    // in the background before the FCM push + full-screen-intent can
    // even fire, regardless of notification-channel config. Requesting
    // battery-optimization exemption is the standard mitigation. This
    // is a one-time system dialog; if the hero denies it, we don't
    // re-prompt every launch (see the `status.isDenied` check) to avoid
    // being naggy — degrade gracefully rather than block anything.
    unawaited(requestBatteryOptimizationExemption());
  }

  /// TASK 1: asks the OS to stop battery-optimizing this app so
  /// backgrounded/killed-app full-screen-intent ride alerts can still
  /// wake the screen. Safe to call repeatedly — a no-op once granted.
  static Future<void> requestBatteryOptimizationExemption() async {
    if (kIsWeb) return;
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (status.isGranted) {
        debugPrint('[HeroRideNotificationService] Battery optimization already exempted.');
        return;
      }
      final result = await Permission.ignoreBatteryOptimizations.request();
      debugPrint('[HeroRideNotificationService] Battery optimization exemption result: $result');
    } catch (e) {
      // permission_handler throws on some OEMs/emulators that don't
      // expose this intent at all — never let this block app startup.
      debugPrint('[HeroRideNotificationService] Battery optimization request failed: $e');
    }
  }

  static Future<void> handleNotificationResponse(
    NotificationResponse response,
  ) async {
    final rideId = _rideIdFromPayload(response.payload);
    if (rideId == null) {
      return;
    }

    // MINIMIZE (TASK 39): dismiss only. Deliberately does NOT write any
    // pending-* key — that's what stops _consumePendingRidePush()/
    // _consumePendingServiceRequestPush() from opening the accept dialog.
    // The request itself is untouched (no reject write), matching the
    // in-app dialog's own MINIMIZE contract.
    if (response.actionId == minimizeRideActionId) {
      await stopWakeAlertRingtone();
      await _plugin.cancel(id: _notificationIdForRide(rideId));
      return;
    }

    // bug B1 fix: route into the correct pending-* key based on the
    // notification's real type — before this, every tap (ride OR
    // service-request) wrote into the ride-only keys, so tapping a
    // grocery/food/hero-booking notification silently failed to open
    // its accept dialog (the id was looked up in the wrong Firestore
    // collection by the ride-only consumer and just no-opped).
    final pushType = _pushTypeFromPayload(response.payload);
    final prefs = await SharedPreferences.getInstance();
    if (pushType == 'service_request') {
      await prefs.setString(kPendingHeroServiceRequestIdKey, rideId);
    } else {
      await prefs.setString(kPendingHeroRideIdKey, rideId);
      // Fast-accept only exists for rides today — service-request
      // accept still goes through the dialog's own ACCEPT button.
      if (response.actionId == acceptRideActionId) {
        await prefs.setString(kPendingHeroAcceptRideIdKey, rideId);
      }
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
    // TASK 39 / bug B1 fix (Aug 8 2026): callers passing a service-request
    // id in as `rideId` (hero_home_screen.dart, main_hero.dart — every
    // grocery/food/hero_booking push already reuses this same method) now
    // MUST say so via pushType, so handleNotificationResponse() can route
    // the tapped id into the correct pending-* SharedPreferences key.
    // Before this param existed, EVERY notification tap wrote into the
    // ride keys regardless of real type, so tapping a service-request
    // notification silently never opened its accept dialog — the id was
    // looked up in the wrong collection (`rides`) and just no-opped.
    String pushType = 'ride',
    // ── Simplified/background mode ──────────────────────────────
    // When false (used only by the quiet background/killed-app paths
    // in main_hero.dart), the notification shows a generic,
    // non-alarming message with no fare/pickup/drop details and no
    // action buttons — full details + Accept/Reject are shown by the
    // existing in-app dialog once the hero taps the notification and
    // opens the app. Also made dismissible (not "ongoing"), since a
    // swipe-dismiss here is not a reject — the existing ping-expiry /
    // broadcast system already routes an unanswered request to the
    // next hero on its own.
    bool showDetails = true,
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

    String body;
    if (showDetails) {
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
      body = [
        if (pickup.isNotEmpty) 'Pickup: $pickup',
        if (drop.isNotEmpty) 'Drop: $drop',
        if (fare.isNotEmpty) 'Fare: $fare',
      ].join('\n');
    } else {
      // Generic, non-alarming — no ride specifics on the lock screen.
      body = 'Someone needs your help! Tap to view request details.';
    }

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
        ongoing: showDetails,
        autoCancel: !showDetails,
        // 0ms delay, vibrate 1sec, pause 0.5sec, vibrate 1sec, pause 0.5sec, vibrate 1sec
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
        ticker: ticker,
        timeoutAfter: 15000,
        sound: const RawResourceAndroidNotificationSound('ride_alert'),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        // TASK 39: standard View/Accept/Minimize 3-button contract on
        // every request-type notification, matching the in-app dialogs.
        actions: showDetails
            ? const [
                AndroidNotificationAction(
                  viewRideActionId,
                  'VIEW',
                  icon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
                  showsUserInterface: true,
                  contextual: true,
                ),
                AndroidNotificationAction(
                  acceptRideActionId,
                  'ACCEPT',
                  icon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
                  showsUserInterface: true,
                  contextual: true,
                ),
                AndroidNotificationAction(
                  minimizeRideActionId,
                  'MINIMIZE',
                  // No showsUserInterface — this must NOT bring the app
                  // forward, it's a pure dismiss.
                ),
              ]
            : const [],
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
      payload: jsonEncode(<String, String>{'rideId': rideId, 'type': pushType}),
    );
    // FIX (root cause of "our own ringtone AND the phone's stock alarm
    // tone both play at once", per Nizam's bug report): the
    // AndroidNotificationDetails above already plays our custom
    // ride_alert.mp3 through the ALARM audio stream
    // (audioAttributesUsage: AudioAttributesUsage.alarm), which alone
    // already bypasses silent mode/DND and plays loud on the lock
    // screen — that's the "namma app kulla vachurukka ringtone" the
    // user wants to keep. playWakeAlertRingtone() below used to ALSO
    // fire FlutterRingtonePlayer's separate AndroidSounds.alarm (the
    // phone's own stock system alarm tone) on top of it — two
    // independent sounds playing simultaneously. Removed; the
    // `playAlertTone` param is kept (unused here now) so every call
    // site elsewhere in the codebase keeps compiling unchanged.
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

      // Clear de-duplication flag (Hive-backed — see shouldProcessRideNotification)
      await HiveCache.evict(_dedupKey(rideId));
    } catch (e) {
      debugPrint('[NotificationService] ❌ Cancel failed for $rideId: $e');
    }
  }

  // ── Check if notification already processing (De-duplication) ──
  // Async + Hive-backed: this must be checked (and awaited) from BOTH
  // the FCM background isolate (main_hero.dart) and the main-isolate
  // in-app RTDB listeners (hero_home_screen.dart) for the SAME ride,
  // so the dedup record has to live somewhere both can see — a static
  // Dart field does not cross that isolate boundary, Hive does.
  static Future<bool> shouldProcessRideNotification(String rideId) async {
    final alreadyProcessed = await HiveCache.isFresh(_dedupKey(rideId));
    if (alreadyProcessed) {
      debugPrint(
        '[NotificationService] ⏭️ Skipping duplicate notification for $rideId',
      );
      return false;
    }

    await HiveCache.put(_dedupKey(rideId), true, ttl: _deduplicationWindow);
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

  // TASK 39 / bug B1 fix: old payloads (or a plain non-JSON legacy
  // payload from before this fix) have no 'type' field — default to
  // 'ride' so every pre-existing ride notification keeps behaving
  // exactly as before.
  static String _pushTypeFromPayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) return 'ride';
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        final type = decoded['type'];
        if (type is String && type.trim().isNotEmpty) {
          return type.trim();
        }
      }
    } catch (_) {
      // Legacy plain-string payload — no type info, assume ride.
    }
    return 'ride';
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
