// ================================================================
// chitti_commitment_alarms.dart — the reminder that fires whether or
// not the app is open.
// ================================================================
// NEW (Sep 4 2026 — Nizam: "Chitti only reminds me if I open the app.
// But as a busy founder, I might forget to open it. I need Chitti to
// proactively ring ... exactly when the 1 hour is up, even if the Admin
// app is completely closed, killed, or running in the background").
//
// He is right, and it was the honest limit of the first version:
// ChittiFollowUpService checks on app open, which only helps someone
// who was already opening the app. A reminder you have to remember to
// go and collect is not a reminder.
//
// ZERO SERVER, AND THAT IS THE DESIGN
// The obvious answer is a scheduled push. This project is on the
// Firebase Spark plan — no Cloud Functions — and even with them it
// would mean a server holding everyone's todo times and waking up to
// message them: recurring cost, and one moving part that fails
// silently for everybody at once. Instead the phone schedules its OWN
// alarm through AlarmManager, which fires whether or not the app is
// running, whether or not there is a network, and costs nothing. This
// is the same mechanism DailyGreetingNotificationService already uses
// for the morning wish — see that file's header for the full argument.
//
// EXACT vs INEXACT
// Android 12+ gates exact alarms behind a permission the user can
// revoke at any time. This asks for exact (the manifest already
// declares SCHEDULE_EXACT_ALARM) and falls back to
// inexactAllowWhileIdle when the OS refuses. Inexact can drift by a
// few minutes under Doze. That tradeoff is the right way round for a
// "did you finish that?" nudge: a reminder that arrives at 3:04 is
// useful, a reminder that never arrives because a permission was
// revoked is not.
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'chitti_commitment_service.dart';

class ChittiCommitmentAlarms {
  ChittiCommitmentAlarms._();
  static final ChittiCommitmentAlarms instance = ChittiCommitmentAlarms._();

  static const String _channelId = 'chitti_commitments';
  static const String _channelName = 'Task reminders';

  /// Notification ids for commitments live in their own numeric band so
  /// they can never collide with DailyGreetingNotificationService's id
  /// (or anything added later) and cancel each other's alarms.
  static const int _idBase = 900000;
  static const int _idSpan = 90000;

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Stable id for a commitment, derived from its own id so scheduling
  /// twice REPLACES the pending alarm rather than stacking a second
  /// one — which is what makes [rescheduleAll] safe to call on every
  /// app start.
  static int notificationIdFor(String commitmentId) =>
      _idBase + (commitmentId.hashCode.abs() % _idSpan);

  Future<void> _ensureReady() async {
    if (_ready || !isSupported) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings: settings);

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Chitti reminding you about something you said you would do.',
        // Deliberately higher than the morning greeting's channel: this
        // one is a commitment coming due, not decoration, so it earns a
        // heads-up notification and a sound.
        importance: Importance.high,
      ),
    );
    _ready = true;
  }

  /// Asks for notification permission. Call it from a moment the admin
  /// understands — the first time he adds something to My Day — not at
  /// startup, where an unexplained prompt is the fastest way to get a
  /// permanent denial.
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    await _ensureReady();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission() ??
        await ios?.requestPermissions(alert: true, sound: true) ??
        false;
    // Exact alarms are a SEPARATE grant on Android 12+, and asking is
    // cheap. schedule() still works without it, just less precisely.
    try {
      await android?.requestExactAlarmsPermission();
    } catch (_) {
      // Older Android has no such prompt — not an error.
    }
    return granted;
  }

  /// Arms (or re-arms) the reminder for one commitment.
  ///
  /// Never throws: a scheduling failure must not stop the commitment
  /// itself from being saved. The in-app follow-up on next open is
  /// still there as the backstop.
  Future<void> schedule(Commitment c) async {
    if (!isSupported) return;
    if (!c.isOpen) return;
    // A due time already in the past would fire immediately (or be
    // rejected). The app-open follow-up covers those.
    if (c.dueAt.isBefore(DateTime.now())) return;

    try {
      await _ensureReady();
      final when = tz.TZDateTime.from(c.dueAt, tz.local);
      final body = ChittiCommitmentService.followUpLine(c);

      await _plugin.zonedSchedule(
        id: notificationIdFor(c.id),
        title: 'Chitti',
        body: body,
        scheduledDate: when,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription:
                'Chitti reminding you about something you said you would do.',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            // The commitment is a sentence in his own words. Without
            // this Android clips it to one line, and the clipped part
            // is the part that says which task it is.
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        // Exact where the OS allows it; AlarmManager falls back on its
        // own when the permission is absent. See the header for why
        // inexact is an acceptable outcome and a missing alarm is not.
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('[CommitmentAlarms] schedule failed for ${c.id}: $e');
      // Retry once as inexact — the usual cause is the exact-alarm
      // permission being revoked, and an approximate reminder beats
      // none.
      try {
        await _plugin.zonedSchedule(
          id: notificationIdFor(c.id),
          title: 'Chitti',
          body: ChittiCommitmentService.followUpLine(c),
          scheduledDate: tz.TZDateTime.from(c.dueAt, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } catch (e2) {
        debugPrint('[CommitmentAlarms] inexact fallback also failed: $e2');
      }
    }
  }

  Future<void> cancel(String commitmentId) async {
    if (!isSupported) return;
    try {
      await _ensureReady();
      await _plugin.cancel(id: notificationIdFor(commitmentId));
    } catch (e) {
      debugPrint('[CommitmentAlarms] cancel failed for $commitmentId: $e');
    }
  }

  /// Re-arms every open commitment.
  ///
  /// Call on app start. Android drops all scheduled alarms when the
  /// device reboots, and the OS can clear them when an app is
  /// force-stopped — the manifest's boot receiver restores what
  /// flutter_local_notifications knows about, and this covers the rest.
  /// Cheap and idempotent: same ids, so it replaces rather than stacks.
  Future<void> rescheduleAll() async {
    if (!isSupported) return;
    try {
      await ChittiCommitmentService.instance.load();
      for (final c in ChittiCommitmentService.instance.openItems) {
        await schedule(c);
      }
    } catch (e) {
      debugPrint('[CommitmentAlarms] rescheduleAll failed: $e');
    }
  }
}
