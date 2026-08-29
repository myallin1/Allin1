// ================================================================
// chitti_welcome_service.dart — Chitti greets the user out loud, once
// per app session, on their FIRST touch.
// ================================================================
// WHY IT IS TAP-GATED AND NOT ON-OPEN (Aug 28 2026).
//
// The obvious implementation — speak from initState when the app
// launches — does not work on this app's most important surface. The
// customer build ships primarily as a PWA, and browsers apply their
// autoplay policy to speech synthesis: a `speak()` call before the
// user has interacted with the page is discarded. No exception, no
// error the app can catch, no sound. It would have looked like a
// working feature in a native APK test and silently done nothing for
// most real customers.
//
// So the greeting waits for the first pointer-down anywhere in the
// app, which is a user gesture by definition and satisfies the policy
// on every platform. In practice this costs nothing: the first thing
// anyone does after opening the app is touch it.
//
// SESSION-SCOPED, NOT DAILY. `_greeted` is a plain field with no
// persistence, so a greeting happens once per app run. Making it
// per-day would need a stored timestamp and would still greet someone
// who reopened the app for the fourth time that morning — this is a
// nice touch, and a nice touch that repeats is an annoyance.
//
// SILENT UNTIL EARNED. It respects the user's own mute setting, and
// says nothing at all when speech is off. Chitti talking over someone
// who muted it would be a bug, not a feature.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tamil_transliteration.dart';
import 'chitti_buddy.dart';
import 'chitti_voice_service.dart';

class ChittiWelcomeService {
  ChittiWelcomeService._();

  static const String _enabledPrefsKey = 'chitti_welcome_enabled';

  static final FlutterTts _tts = FlutterTts();

  static bool _greeted = false;
  static bool _enabled = true;
  static bool _loaded = false;

  static bool get enabled => _enabled;

  /// True once the greeting for this app run has been spoken (or
  /// deliberately skipped), so the root gesture listener can detach
  /// itself instead of checking on every touch.
  static bool get done => _greeted;

  // ignore: avoid_positional_boolean_parameters
  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledPrefsKey, value);
    } catch (e) {
      debugPrint('[ChittiWelcome] save failed: $e');
    }
  }

  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledPrefsKey) ?? true;
    } catch (e) {
      debugPrint('[ChittiWelcome] load failed: $e');
    }
  }

  /// Call on the first user gesture of the app run.
  ///
  /// [languageCode] comes from LocalizationService — passed in rather
  /// than read here, because this service has no BuildContext and
  /// greeting someone in the wrong language is worse than not greeting
  /// them at all.
  ///
  /// Safe to call repeatedly; only the first call does anything.
  static Future<void> greetOnFirstTouch(String languageCode) async {
    if (_greeted) return;
    // Set before the awaits below, not after — two pointer-downs can
    // land in the same frame, and without this both would pass the
    // guard and Chitti would greet twice, over itself.
    _greeted = true;

    await _ensureLoaded();
    if (!_enabled) return;

    try {
      await ChittiVoiceService.apply(_tts, _ttsLocaleFor(languageCode));
      // spokenOpeningLineFor, NOT openingLineFor: for a Thanglish
      // customer the two differ, and only this one is pronounceable.
      await _tts.speak(spokenOpeningLineFor(languageCode));
    } catch (e) {
      // A greeting is decoration. It must never be able to interfere
      // with app startup.
      debugPrint('[ChittiWelcome] speak failed: $e');
    }
  }

  /// Greeting plus the day's motivational line.
  ///
  /// CEO's ask (Aug 28 2026): "daily um customer app open pannunathum
  /// namma daily yenna motivational quote vachurukkomo atha read
  /// pannanum customer ku". The quote comes from DailyQuoteService —
  /// the same one the app already displays, so what Chitti reads out
  /// and what the customer sees on screen are the same line. Two
  /// different quotes in the same minute would be worse than none.
  ///
  /// Kept as one utterance rather than two speak() calls: on web the
  /// second would frequently be swallowed by the first still playing.
  /// The greeting as it should be SPOKEN, which is not always what is
  /// shown.
  ///
  /// Thanglish is a way of READING Tamil, not of pronouncing it. Handed
  /// "Kaalai vanakkam boss" a ta-IN engine sounds the Latin letters out
  /// as English and the result is unintelligible; handed the Tamil
  /// original it is perfect. So a Thanglish customer reads Latin on
  /// screen and hears correct Tamil — which is what "pronounciation
  /// perfecta irukanum" actually requires.
  static String spokenGreetingFor(String languageCode) =>
      languageCode == 'tg' ? _tamil(DateTime.now().hour, _firstName())
          : greetingFor(languageCode);

  /// The full opening line — greeting plus today's quote — as it should
  /// be SPOKEN. Same reasoning as [spokenGreetingFor].
  static String spokenOpeningLineFor(String languageCode) {
    final greeting = spokenGreetingFor(languageCode);
    final quote = ChittiBuddy.spokenDailyQuote(languageCode);
    if (quote == null || quote.isEmpty) return greeting;
    return '$greeting  $quote';
  }

  static String openingLineFor(String languageCode) {
    final greeting = greetingFor(languageCode);
    final quote = ChittiBuddy.dailyQuote(languageCode);
    if (quote == null || quote.isEmpty) return greeting;
    return '$greeting  $quote';
  }

  /// The line Chitti says, in Chitti's own voice — time-aware, and
  /// using the customer's first name when Firebase has one.
  ///
  /// Kept public so the settings screen can preview the real line
  /// rather than a stand-in.
  static String greetingFor(String languageCode) {
    final name = _firstName();
    final hour = DateTime.now().hour;

    return switch (languageCode) {
      'ta' => _tamil(hour, name),
      // CHANGED (Aug 28 2026 — Nizam: "thanglish vachurukanvangaluku
      // thanglish layum welcome and guidance pannanum"). 'tg' used to
      // share the Tamil branch, so a Thanglish reader was shown Tamil
      // SCRIPT — unreadable to the exact person who chose Thanglish
      // because they cannot read it. They now get the same sentence in
      // Latin. What is SPOKEN stays Tamil: see spokenGreetingFor().
      'tg' => TamilTransliteration.toLatin(_tamil(hour, name)),
      'hi' => name.isEmpty
          ? 'नमस्ते बॉस, मैं चिट्टी। बताइए, क्या करना है?'
          : 'नमस्ते $name, मैं चिट्टी। बताइए, क्या करना है?',
      'ml' => name.isEmpty
          ? 'ഹലോ ബോസ്, ഞാൻ ചിട്ടി. എന്ത് വേണം?'
          : 'ഹലോ $name, ഞാൻ ചിട്ടി. എന്ത് വേണം?',
      _ => _english(hour, name),
    };
  }

  static String _tamil(int hour, String name) {
    final who = name.isEmpty ? 'பாஸ்' : name;
    if (hour >= 5 && hour < 12) {
      return 'காலை வணக்கம் $who! நான் தான் சிட்டி. சொல்லுங்க, என்ன பண்ணனும்?';
    }
    if (hour >= 12 && hour < 17) {
      return 'வணக்கம் $who! சிட்டி ரெடி. என்ன வேணும் சொல்லுங்க.';
    }
    if (hour >= 17 && hour < 21) {
      return 'மாலை வணக்கம் $who! சொல்லுங்க, நான் பார்த்துக்கறேன்.';
    }
    return 'வணக்கம் $who! இந்த நேரத்துலயும் நான் ரெடி. என்ன வேணும்?';
  }

  static String _english(int hour, String name) {
    final who = name.isEmpty ? 'boss' : name;
    if (hour >= 5 && hour < 12) {
      return 'Good morning $who! Chitti here — tell me what you need.';
    }
    if (hour >= 12 && hour < 17) {
      return 'Hello $who! Chitti reporting. What can I do for you?';
    }
    if (hour >= 17 && hour < 21) {
      return 'Good evening $who! Chitti here, ready when you are.';
    }
    return 'Still awake, $who? Chitti never sleeps. What do you need?';
  }

  static String _firstName() {
    // Guarded (Aug 28 2026): FirebaseAuth.instance THROWS when Firebase
    // has not been initialised, and this sits on the greeting path —
    // which now also runs from the notification scheduler at startup,
    // before initialisation is guaranteed. A greeting is decoration; it
    // must degrade to "boss" rather than take the caller down with it.
    String raw;
    try {
      raw = FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
    } catch (_) {
      return '';
    }
    if (raw.isEmpty) return '';
    final first = raw.split(RegExp(r'\s+')).first;
    // A name long enough to be a sentence is almost always junk data
    // from a social sign-in, and Chitti reading it aloud sounds broken.
    return first.length > 14 ? '' : first;
  }

  static String _ttsLocaleFor(String code) => switch (code) {
        'ta' || 'tg' => 'ta-IN',
        'hi' => 'hi-IN',
        'ml' => 'ml-IN',
        _ => 'en-IN',
      };

  @visibleForTesting
  static void resetForTesting() {
    _greeted = false;
    _loaded = false;
    _enabled = true;
  }
}
