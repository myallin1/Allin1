// ================================================================
// chitti_voice_service.dart — one owner of how Chitti SOUNDS.
// ================================================================
// WHY (Aug 28 2026 — Nizam: "namma Chitti voice innum girl voice ah
// iruku, atha yepdi naughty Chitti mari vara vekirathu").
//
// There were already two copies of a `_applyChittiMaleVoice()` helper
// — one in guru_chat_screen.dart, one in guru_overlay_service.dart —
// and both were failing for the same reason. They looked for a voice
// whose NAME contains "male":
//
//     lowerName.contains('male') && !lowerName.contains('female')
//
// On Android and on Chrome (this app ships as a PWA), Google's TTS
// voices are named by opaque code, not by gender:
//     ta-in-x-tac-local     en-in-x-ene-network     hi-in-x-hia-local
// None of those contain "male", so the check never matched, the code
// fell through to `setPitch(0.82)`, and the customer heard the SAME
// female voice pitched down slightly — which is exactly what "innum
// girl voice ah iruku" describes. The old comment in those files was
// honest that this was best-effort; it just was not good enough.
//
// THREE CHANGES MAKE IT ACTUALLY WORK:
//
// 1. A real voice table instead of one substring. Google, Microsoft
//    and Apple each name voices differently, and the male ones ARE
//    identifiable — Google by its per-locale voice codes, Microsoft
//    and Apple by given names (Prabhat, Madhur, Rishi, Daniel...).
//    Female names are listed too, as an explicit veto, because a
//    partial code match is otherwise easy to get backwards.
//
// 2. A saved override. Voice availability is per-device — it depends
//    on the TTS engine, the installed language packs, and the browser.
//    No heuristic can be right everywhere, so whatever this picks is a
//    DEFAULT, and AiSettingsScreen lets Nizam audition the voices that
//    actually exist on a device and pin one. A pinned voice always
//    wins over the heuristic.
//
// 3. Honest shaping. When a genuinely male voice is found, it is left
//    alone apart from the robot tuning. When one is NOT found, the
//    fallback drops pitch much further than the old 0.82 — at 0.82 a
//    female voice still reads as female; the robot profile pushes it
//    low and flat enough to read as a machine instead, which is closer
//    to Chitti than a slightly-deep girl voice is.
//
// The "naughty Chitti" character lives in TWO places and needs both:
// this file (how it sounds) and the persona text in guru_api_service
// (what it says). Neither alone is convincing.
import 'package:flutter/foundation.dart'
    show debugPrint, immutable, kIsWeb, visibleForTesting;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How robotic Chitti should sound.
enum ChittiVoiceTone {
  /// A normal human voice, male where one is available. For anyone who
  /// finds the robot effect tiring.
  natural,

  /// The default: recognisably Chitti — lower and a little slower than
  /// natural, without becoming hard to follow.
  chitti,

  /// Full Enthiran metallic robot. Deliberately available but not the
  /// default: it is fun for a few lines and tiring for a paragraph,
  /// and Chitti reads out order confirmations people need to catch.
  robot,
}

/// One tuning profile.
@immutable
class _ToneProfile {
  const _ToneProfile({
    required this.pitchWithMaleVoice,
    required this.pitchWithoutMaleVoice,
    required this.rate,
  });

  /// Pitch when a real male voice was selected — it already has the
  /// depth, so this only adds character.
  final double pitchWithMaleVoice;

  /// Pitch when we are stuck shaping a female voice. Pushed much
  /// further, because this is the case the old code got wrong.
  final double pitchWithoutMaleVoice;

  final double rate;
}

class ChittiVoiceService {
  ChittiVoiceService._();

  static const String _tonePrefsKey = 'chitti_voice_tone';
  static const String _voiceNamePrefsKey = 'chitti_voice_name';
  static const String _voiceLocalePrefsKey = 'chitti_voice_locale';

  static const Map<ChittiVoiceTone, _ToneProfile> _profiles =
      <ChittiVoiceTone, _ToneProfile>{
    ChittiVoiceTone.natural: _ToneProfile(
      pitchWithMaleVoice: 1,
      // Even "natural" drops a female voice a little — Chitti is
      // written and personified as male throughout the app.
      pitchWithoutMaleVoice: 0.85,
      rate: 0.5,
    ),
    // RETUNED (Aug 28 2026 — Nizam: "voice romba ilaythu pesuthu").
    //
    // The complaint was that Chitti sounded thin and dragged out. The
    // proposal on the table was to RAISE pitch to 1.1-1.25. That would
    // have made it worse, and it is worth writing down why.
    //
    // Pitch shifting moves the fundamental frequency but not the
    // formants — the resonances that actually tell an ear "woman" or
    // "man". Pushing a female voice UP keeps every formant where it was
    // and just makes it childlike; the complaint is that it still
    // sounds like a girl, so that is the wrong direction outright.
    //
    // Pushing it too far DOWN, which is what these values did (0.52),
    // has its own artefact: same unmoved formants over a much lower
    // pitch reads as a slowed-down recording. Combined with rate 0.38
    // that is precisely "thin and dragging".
    //
    // So: moderate the pitch back toward where the voice still sounds
    // like a voice, and take the drag out with RATE instead. Energy is
    // what makes Chitti read as cheeky; depth was never doing that work
    // on a female voice, and no number here can.
    //
    // The real fix remains the picker in AiSettingsScreen — a genuinely
    // male voice needs none of this shaping. These numbers are the
    // fallback for a device that has none installed.
    ChittiVoiceTone.chitti: _ToneProfile(
      pitchWithMaleVoice: 0.92,
      pitchWithoutMaleVoice: 0.72,
      rate: 0.52,
    ),
    ChittiVoiceTone.robot: _ToneProfile(
      pitchWithMaleVoice: 0.8,
      pitchWithoutMaleVoice: 0.65,
      rate: 0.5,
    ),
  };

  // ── voice-name knowledge ────────────────────────────────────────
  //
  // Google Android/Chrome voices carry no gender field and no gender
  // word in the name — only a per-locale three-letter code. These are
  // the male codes for the four languages this app supports. They are
  // matched as substrings of the full voice name (e.g.
  // "en-in-x-ahp-local" contains "-x-ahp").
  static const List<String> _googleMaleCodes = <String>[
    // English (India)
    '-x-ahp', '-x-end', '-x-enb',
    // Tamil
    '-x-tag', '-x-tad',
    // Hindi
    '-x-hig', '-x-hie',
    // Malayalam
    '-x-mlg',
  ];

  // Explicit vetoes. Checked BEFORE the male list, because a wrong
  // positive here is the exact bug being fixed — and because Google's
  // female codes sit only one letter away from the male ones.
  static const List<String> _knownFemaleCodes = <String>[
    '-x-ene', '-x-enc', '-x-tac', '-x-taf', '-x-hia', '-x-hic', '-x-mlc',
  ];

  /// Male given names used by Microsoft (Edge/Windows) and Apple
  /// voices, which DO name their voices like people.
  static const List<String> _maleVoiceNames = <String>[
    'prabhat', 'madhur', 'rishi', 'valluvar', 'midhun', 'ravi', 'hemant',
    'aaron', 'alex', 'daniel', 'fred', 'oliver', 'rishabh', 'arjun',
    'gopal', 'kumar', 'thomas', 'george', 'james',
  ];

  static const List<String> _femaleVoiceNames = <String>[
    'swara', 'neerja', 'pallavi', 'sapna', 'kavya', 'sobhana', 'aarohi',
    'samantha', 'karen', 'moira', 'tessa', 'fiona', 'veena', 'rishika',
    'lekha', 'zira', 'heera', 'susan', 'catherine',
  ];

  static ChittiVoiceTone _tone = ChittiVoiceTone.chitti;
  static String? _pinnedVoiceName;
  static String? _pinnedVoiceLocale;
  static bool _loaded = false;

  static ChittiVoiceTone get tone => _tone;
  static String? get pinnedVoiceName => _pinnedVoiceName;

  /// Reads the saved preferences once per app run.
  ///
  /// Cheap enough to call before every utterance, but the `_loaded`
  /// guard keeps it off the SharedPreferences channel on the hot path —
  /// Chitti speaks after every reply, and this runs inside that.
  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_tonePrefsKey);
      if (saved != null) {
        _tone = ChittiVoiceTone.values.firstWhere(
          (t) => t.name == saved,
          orElse: () => ChittiVoiceTone.chitti,
        );
      }
      _pinnedVoiceName = prefs.getString(_voiceNamePrefsKey);
      _pinnedVoiceLocale = prefs.getString(_voiceLocalePrefsKey);
    } catch (e) {
      debugPrint('[ChittiVoiceService] prefs load failed: $e');
    }
  }

  static Future<void> setTone(ChittiVoiceTone value) async {
    _tone = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tonePrefsKey, value.name);
    } catch (e) {
      debugPrint('[ChittiVoiceService] tone save failed: $e');
    }
  }

  /// Pins a specific device voice, or clears the pin when [name] is
  /// null so the heuristic takes over again.
  static Future<void> pinVoice({String? name, String? locale}) async {
    _pinnedVoiceName = name;
    _pinnedVoiceLocale = locale;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (name == null || name.isEmpty) {
        await prefs.remove(_voiceNamePrefsKey);
        await prefs.remove(_voiceLocalePrefsKey);
      } else {
        await prefs.setString(_voiceNamePrefsKey, name);
        await prefs.setString(_voiceLocalePrefsKey, locale ?? '');
      }
    } catch (e) {
      debugPrint('[ChittiVoiceService] voice pin save failed: $e');
    }
  }

  /// Converts a profile rate into what THIS platform means by it.
  ///
  /// FIX (Aug 28 2026 — Nizam: "male voice vanthuruchu but romba
  /// iluththu iluththu pesuran").
  ///
  /// flutter_tts documents setSpeechRate as "0.0 (slowest) to 1.0
  /// (fastest)", and two of its three platforms honour that. Web does
  /// not — it assigns the value straight to
  /// SpeechSynthesisUtterance.rate, where the scale is different:
  ///
  ///   Android  rate * 2.0 -> native (1.0 = normal)  => normal at 0.5
  ///   iOS      passthrough -> AVSpeechUtterance      => normal at 0.5
  ///   Web      passthrough -> utterance.rate         => normal at 1.0
  ///
  /// So every rate in [_profiles] — written on the documented 0.5-is-
  /// normal scale — was running at roughly HALF SPEED on the PWA. That
  /// is the dragging. It was invisible until a real male voice was
  /// selected, because before that the complaint was the voice itself.
  ///
  /// Pitch needs no such treatment: all three platforms pass it through
  /// to a scale where 1.0 is normal.
  @visibleForTesting
  static double platformRate(double profileRate, {required bool isWeb}) {
    if (!isWeb) return profileRate;
    // Doubling puts web on the same footing as the other two. Clamped
    // to the range browsers actually accept.
    return (profileRate * 2).clamp(0.1, 2.0);
  }

  /// The engine that spoke last.
  ///
  /// FIX (Aug 28 2026 re-audit). There are five FlutterTts instances in
  /// this app — the chat screen, the overlay bubble, the welcome
  /// greeting, the settings preview and the admin co-pilot. Nothing
  /// coordinated them, so two could talk at once: the most likely pair
  /// being the first-touch welcome and whatever the customer's first
  /// touch actually opened. Two Chittis over each other is worse than
  /// either one alone.
  ///
  /// A weak reference is deliberate — this must never be the reason a
  /// disposed screen's engine stays alive.
  static FlutterTts? _speaking;

  /// Claims the speech channel for [tts], silencing whoever had it.
  ///
  /// Called from [apply], so every Chitti surface gets this for free
  /// just by configuring its voice before it speaks.
  static Future<void> _claimSpeechChannel(FlutterTts tts) async {
    final previous = _speaking;
    _speaking = tts;
    if (previous == null || identical(previous, tts)) return;
    try {
      await previous.stop();
    } catch (e) {
      debugPrint('[ChittiVoiceService] could not stop previous engine: $e');
    }
  }

  /// Configures [tts] for [locale]. Call before every `speak()` — the
  /// engine can reset between utterances on web, and on Android a
  /// language switch silently drops the selected voice.
  static Future<void> apply(FlutterTts tts, String locale) async {
    await _ensureLoaded();
    await _claimSpeechChannel(tts);
    final profile = _profiles[_tone] ?? _profiles[ChittiVoiceTone.chitti]!;

    try {
      await tts.setLanguage(locale);
    } catch (e) {
      debugPrint('[ChittiVoiceService] setLanguage failed: $e');
    }

    var usingMaleVoice = false;
    try {
      final chosen = await _selectVoice(tts, locale);
      if (chosen != null) {
        await tts.setVoice(<String, String>{
          'name': chosen.name,
          'locale': chosen.locale,
        });
        usingMaleVoice = chosen.isMale;
      }
    } catch (e) {
      debugPrint('[ChittiVoiceService] voice selection failed: $e');
    }

    if (!usingMaleVoice) {
      // Worth a log line: every complaint about Chitti "still sounding
      // like a girl" comes back to this branch. If it fires, no male
      // voice is installed for this language and no amount of pitch
      // tuning will fix it — the answer is the picker in AI Settings,
      // or installing a voice.
      debugPrint(
        '[ChittiVoiceService] no male voice for "$locale" on this device — '
        'shaping the default instead. Pin one in AI Settings if the list '
        'shows a "(male)" option.',
      );
    }

    try {
      await tts.setSpeechRate(platformRate(profile.rate, isWeb: kIsWeb));
      await tts.setPitch(
        usingMaleVoice
            ? profile.pitchWithMaleVoice
            : profile.pitchWithoutMaleVoice,
      );
    } catch (e) {
      debugPrint('[ChittiVoiceService] shaping failed: $e');
    }
  }

  /// Every voice on this device for [locale], male-looking ones first.
  ///
  /// Used by the settings picker. The ordering matters: it puts the
  /// candidates worth auditioning at the top of a list that can run to
  /// dozens of entries on a well-stocked Android device.
  static Future<List<ChittiVoiceOption>> availableVoices(
    FlutterTts tts,
    String locale,
  ) async {
    final out = <ChittiVoiceOption>[];
    try {
      final voices = await tts.getVoices;
      if (voices is! List) return out;
      final prefix = locale.split('-').first.toLowerCase();
      for (final entry in voices) {
        if (entry is! Map) continue;
        final name = (entry['name'] ?? '').toString();
        final voiceLocale = (entry['locale'] ?? '').toString();
        if (name.isEmpty) continue;
        if (!voiceLocale.toLowerCase().startsWith(prefix)) continue;
        out.add(
          ChittiVoiceOption(
            name: name,
            locale: voiceLocale,
            isMale: _looksMale(name, (entry['gender'] ?? '').toString()),
          ),
        );
      }
    } catch (e) {
      debugPrint('[ChittiVoiceService] availableVoices failed: $e');
    }
    out.sort((a, b) {
      if (a.isMale != b.isMale) return a.isMale ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return out;
  }

  static Future<ChittiVoiceOption?> _selectVoice(
    FlutterTts tts,
    String locale,
  ) async {
    final options = await availableVoices(tts, locale);
    if (options.isEmpty) return null;

    // A pinned voice wins outright — the whole point of pinning is that
    // the person listening knows better than the heuristic. Only honour
    // it for the language it was pinned in, so switching to Tamil does
    // not keep speaking through an English voice.
    final pinned = _pinnedVoiceName;
    if (pinned != null && pinned.isNotEmpty) {
      for (final option in options) {
        if (option.name != pinned) continue;
        final pinnedLocale = _pinnedVoiceLocale;
        if (pinnedLocale == null ||
            pinnedLocale.isEmpty ||
            pinnedLocale.toLowerCase().startsWith(
                  locale.split('-').first.toLowerCase(),
                )) {
          return option;
        }
      }
    }

    for (final option in options) {
      if (option.isMale) return option;
    }
    // No male voice on this device for this language. Returning null
    // rather than an arbitrary pick leaves the engine on its own
    // default, and `apply()` then shapes it hard via the tone profile.
    return null;
  }

  static bool _looksMale(String name, String gender) {
    final lower = name.toLowerCase();

    // iOS is the one platform that reports gender honestly.
    if (gender.toLowerCase() == 'male') return true;
    if (gender.toLowerCase() == 'female') return false;

    // Vetoes first — see the comment on _knownFemaleCodes.
    for (final code in _knownFemaleCodes) {
      if (lower.contains(code)) return false;
    }
    for (final female in _femaleVoiceNames) {
      if (lower.contains(female)) return false;
    }
    // "female" contains "male", so the explicit word check has to come
    // after the female vetoes above, not before.
    if (lower.contains('female')) return false;

    for (final code in _googleMaleCodes) {
      if (lower.contains(code)) return true;
    }
    for (final male in _maleVoiceNames) {
      if (lower.contains(male)) return true;
    }
    return lower.contains('male') || lower.contains('#male');
  }

  /// Which locale to hand `speech_to_text` for LISTENING.
  ///
  /// This is speech INPUT, not the TTS output the rest of this class
  /// deals with — it lives here so both Chitti surfaces share one
  /// answer instead of the copy-pasted pair they had before.
  ///
  /// THE `tg` SPLIT IS THE WHOLE POINT (Aug 28 2026).
  ///
  /// Both surfaces used to do `if (code == 'ta' || code == 'tg')` and
  /// force a Tamil recogniser. But this app has TWO Tamil-ish language
  /// codes, and they mean different things: `ta` is Tamil, `tg` is
  /// Tanglish. Someone who picked Tanglish has explicitly told us they
  /// mix English into their speech — "Bike book pannu", "Wallet balance
  /// evlo" — and a pure-Tamil recogniser mangles exactly those English
  /// words, because it is constrained to produce Tamil.
  ///
  /// The fix is a split, NOT a flip. Sending everyone to en-IN would
  /// re-open the bug that made `ta-IN` get forced in the first place:
  /// English recognition applied to genuinely Tamil speech produces the
  /// fragmented "ErodeErode busErode bus stand" stutter documented in
  /// guru_chat_screen.dart. So: `ta` keeps Tamil, `tg` gets Indian
  /// English, and everyone else keeps the device default.
  ///
  /// [availableLocales] comes from `SpeechToText.locales()`. It is
  /// consulted rather than hardcoding an id because the exact string
  /// ("ta-IN", "ta_IN", "ta-in") varies by OEM.
  static String? speechLocaleFor(
    String languageCode,
    List<String> availableLocales,
  ) {
    String? firstStartingWith(String prefix) {
      for (final id in availableLocales) {
        if (id.toLowerCase().startsWith(prefix)) return id;
      }
      return null;
    }

    switch (languageCode) {
      case 'ta':
        return firstStartingWith('ta') ?? 'ta-IN';
      case 'tg':
        // Indian English handles code-switched Tanglish far better than
        // a Tamil-only model does, and it is what the recogniser is
        // actually good at for "book pannu" style speech.
        return firstStartingWith('en-in') ??
            firstStartingWith('en') ??
            'en-IN';
      case 'hi':
        return firstStartingWith('hi') ?? 'hi-IN';
      case 'ml':
        return firstStartingWith('ml') ?? 'ml-IN';
      default:
        // Null means "use the device default", which is correct for
        // English users and avoids overriding a deliberate OS setting.
        return null;
    }
  }

  /// A line for the settings screen's preview button, in the tone being
  /// auditioned. Written in Chitti's own voice so what you hear is what
  /// you will get.
  static String previewLine(String languageCode) => switch (languageCode) {
        'ta' || 'tg' => 'வணக்கம் பாஸ், நான் தான் சிட்டி. சொல்லுங்க, '
            'என்ன பண்ணனும்?',
        'hi' => 'नमस्ते बॉस, मैं चिट्टी हूँ। बताइए, क्या करना है?',
        'ml' => 'ഹലോ ബോസ്, ഞാൻ ചിട്ടിയാണ്. പറയൂ, എന്ത് വേണം?',
        _ => "Hello boss, Chitti here. Tell me what you need — I'll handle it.",
      };
}

/// One selectable device voice.
@immutable
class ChittiVoiceOption {
  const ChittiVoiceOption({
    required this.name,
    required this.locale,
    required this.isMale,
  });

  final String name;
  final String locale;

  /// Best-effort. On iOS this is the engine's own answer; elsewhere it
  /// is the name/code heuristic, which is why the picker exists.
  final bool isMale;

  /// Something a person can actually choose between. Raw Google codes
  /// ("ta-in-x-tag-local") tell the listener nothing, so the label
  /// leads with the useful part.
  String get label {
    final cleaned = name.replaceAll('_', ' ').trim();
    return isMale ? '$cleaned  (male)' : cleaned;
  }
}
