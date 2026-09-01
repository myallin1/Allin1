// ================================================================
// daily_greeting_notification_service.dart
// ================================================================
// NEW (Aug 28 2026 — Nizam: "namma chitty daily morning ovvoru
// customer kum avanga notification la good morning boss nu solli, anga
// namma daily morning motivational quote kaatanum. But ithu app kulla
// inbuilt ah nadakanum — ithunala namma database and server yethume
// use agakudathu").
//
// ZERO SERVER, ZERO DATABASE — AND THAT IS THE DESIGN, NOT A SHORTCUT
// The obvious way to send a daily good-morning is FCM: a scheduled job
// fans a push out to every device. We are on the Spark plan, so there
// is no Cloud Functions to run that job, and even with one it would
// mean a server holding a list of every customer and waking up daily
// to message them — recurring cost and a moving part that can fail
// silently for everyone at once.
//
// Instead each phone schedules its OWN alarm. flutter_local_notifications
// hands the schedule to the OS (AlarmManager on Android, UNCalendar on
// iOS), which fires it whether or not the app is running, whether or
// not there is a network, and costs nothing. The quote is already
// compiled into the app and chosen deterministically from the date
// (DailyQuoteService), so every customer in Erode still sees the same
// line on the same morning WITHOUT anything coordinating them. That
// deterministic pick is what makes a serverless broadcast possible at
// all.
//
// WHY matchDateTimeComponents.time
// Without it the notification fires once and never again. With it the
// OS repeats it at the same wall-clock time daily, so there is nothing
// to re-arm and nothing to drift.
//
// WHY THE TIMEZONE IS PINNED TO ASIA/KOLKATA
// This app serves Erode. Reading the device timezone would need
// another plugin, and a customer whose phone is set to the wrong zone
// would get their good-morning at 3am. India has one timezone and no
// DST, so pinning it is both simpler and more correct here.
//
// LANGUAGE
// The notification is written in the language the customer chose, and
// a Thanglish reader gets Latin script — the notification is READ, not
// spoken, so the transliteration is exactly right here. See
// tamil_transliteration.dart.
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'chitti/chitti_welcome_service.dart';
import '../config/app_variant.dart';
import 'daily_quote_service.dart';

class DailyGreetingNotificationService {
  DailyGreetingNotificationService._();
  static final DailyGreetingNotificationService instance =
      DailyGreetingNotificationService._();

  static const int notificationId = 90210;
  static const String _channelId = 'chitti_daily_greeting';
  static const String _enabledKey = 'chitti_daily_greeting_enabled';
  static const String _hourKey = 'chitti_daily_greeting_hour';

  /// 7am. Early enough to be a good-morning, late enough not to wake
  /// anyone.
  static const int defaultHour = 7;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  /// Web has no OS-level scheduler this plugin can use.
  static bool get isSupported => !kIsWeb;

  Future<bool> get enabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  Future<int> get hour async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_hourKey) ?? defaultHour;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    if (value) {
      await scheduleNext();
    } else {
      await cancel();
    }
  }

  Future<void> setHour(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hourKey, value.clamp(0, 23));
    if (await enabled) await scheduleNext();
  }

  Future<void> _ensureReady() async {
    if (_ready || !isSupported) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        // Not requested here: asking for notification permission during
        // startup, before the customer has seen anything, is the
        // fastest way to get it denied permanently. requestPermission()
        // is called from a real moment instead.
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
        'Daily Good Morning',
        description: "Chitti's morning wish and the thought for the day.",
        importance: Importance.defaultImportance,
      ),
    );
    _ready = true;
  }

  /// Asks for permission at a moment the customer can understand.
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
    return granted;
  }

  /// Arms tomorrow morning's greeting (and every morning after).
  ///
  /// Safe to call on every app start: scheduling the same id twice
  /// replaces the pending one rather than stacking a second alarm.
  Future<void> scheduleNext({String? languageCode}) async {
    if (!isSupported) return;
    if (!await enabled) return;

    try {
      await _ensureReady();

      // Read the customer's own choice rather than taking it from the
      // caller. The alarm is armed at startup, before any provider is
      // necessarily built, and a greeting in the wrong language is
      // exactly the kind of thing nobody reports and everybody notices.
      final lang = languageCode ?? await _savedLanguage();

      final at = _nextOccurrence(await hour);
      final body = bodyFor(lang, at);

      await _plugin.zonedSchedule(
        id: notificationId,
        title: titleFor(lang),
        body: body,
        scheduledDate: at,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Daily Good Morning',
            channelDescription:
                "Chitti's morning wish and the thought for the day.",
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            // The quote is a sentence, not a label — without this
            // Android truncates it to one line and the whole point of
            // the notification is the part that got cut off.
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        // Repeat daily at this wall-clock time. Without it this fires
        // exactly once, ever.
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      // A greeting is decoration. It must never break app startup.
      debugPrint('[DailyGreeting] schedule failed: $e');
    }
  }

  Future<void> cancel() async {
    if (!isSupported) return;
    try {
      await _plugin.cancel(id: notificationId);
    } catch (e) {
      debugPrint('[DailyGreeting] cancel failed: $e');
    }
  }

  /// Whatever language the customer last chose, defaulting to English.
  ///
  /// Same SharedPreferences key LocalizationService persists to — read
  /// directly so this does not need a BuildContext or a provider.
  static Future<String> _savedLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('customer_language_code') ?? 'en';
    } catch (_) {
      return 'en';
    }
  }

  /// The next [hour]:00 that is still in the future.
  ///
  /// If it is already past this morning's slot, the alarm belongs to
  /// tomorrow — scheduling it in the past makes the OS either fire it
  /// immediately or drop it, and both look broken.
  static tz.TZDateTime _nextOccurrence(int hour) {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }

  // ── copy ────────────────────────────────────────────────────────
  // Pure functions so the wording is testable without a device.

  /// "Good morning, boss!" in the customer's language.
  @visibleForTesting
  static String titleFor(String languageCode) => switch (languageCode) {
        'ta' => 'காலை வணக்கம் பாஸ்!',
        'tg' => 'Kaalai vanakkam boss!',
        'hi' => 'सुप्रभात बॉस!',
        'ml' => 'സുപ്രഭാതം ബോസ്!',
        _ => 'Good morning, boss!',
      };

  /// Today's thought, in the customer's language.
  ///
  /// Derived from the SCHEDULED date, not from now(): the alarm is
  /// armed the evening before, so using now() would bake in yesterday's
  /// quote and every customer would read the wrong line.
  @visibleForTesting
  static String bodyFor(String languageCode, DateTime at) {
    final quote = DailyQuoteService.instance
        .forRole(currentAppVariant, languageCode, now: at);
    if (quote.trim().isEmpty) {
      return ChittiWelcomeService.greetingFor(languageCode);
    }
    return quote;
  }
}
