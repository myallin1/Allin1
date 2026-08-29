// ================================================================
// chitti_conversation_controller.dart — the hands-free back-and-forth
// loop: listen → act → speak → listen again, until the job is done.
// ================================================================
// NEW (Aug 28 2026 — Nizam: "apdiye voice la continue va nammakuda
// communicate pannanum work mudiravaraiyum").
//
// Before this, voice was one shot. Tap the mic, say a thing, Chitti
// acts, the mic closes. If the request needed a follow-up ("which
// service — bike, auto or cab?") the customer had to reach over and
// tap the mic again to answer, which defeats the point of speaking in
// the first place — they are usually holding something, or riding.
//
// WHY THIS IS A SEPARATE CLASS
// The loop itself is a small state machine, but it has two genuinely
// tricky rules, and both are the kind of thing that silently rots when
// it lives inline in a 2000-line widget alongside setState calls. Kept
// here, with no Flutter, no plugins and no I/O, it is directly
// testable — which matters because the failure modes below are not
// things you notice by looking.
//
// ── RULE 1: THE ECHO PROBLEM ────────────────────────────────────────
// Nizam asked for barge-in — the customer must be able to cut Chitti
// off mid-sentence. That means the mic stays OPEN while Chitti is
// speaking, and on a phone speaker the mic will absolutely hear the
// TTS. Without a guard, Chitti says "Opening your wallet now", hears
// "opening your wallet now", treats it as a new request, and talks to
// itself forever. This is the single most likely way a hands-free mode
// ships broken.
//
// Proper acoustic echo cancellation is not reachable from Flutter's
// speech plugin, so the guard is textual: while speaking, we know
// exactly what Chitti is saying, and we discard anything the mic
// returns that substantially overlaps it. Real barge-in ("no, stop",
// "cancel it") shares almost no words with what Chitti was saying, so
// it passes straight through.
//
// It is not perfect — a customer who repeats Chitti's own words back
// will be ignored. That is a far better failure than an infinite
// self-conversation, and [ChittiConversationMode] gives them a way out
// either way.
//
// ── RULE 2: KNOWING WHEN TO STOP ────────────────────────────────────
// A mic that stays open forever is a battery and privacy problem, so
// the loop has three independent exits: an explicit stop word, a
// silence timeout, and task completion. Per Nizam, WHICH of these
// applies is the user's choice — see [ChittiConversationMode].
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the hands-free loop decides it is finished.
enum ChittiConversationMode {
  /// Ends on its own: after a completed task with nothing pending, or
  /// after the auto-stop silence window with nothing said. The safe default —
  /// nobody ever leaves the mic on by accident.
  autoStop,

  /// Stays open like a phone call until the user stops it. Better for
  /// a long back-and-forth; worse if they walk away and forget.
  call,
}

/// What the host should do next.
enum ChittiConversationStep {
  /// Open the mic.
  listen,

  /// Say something, then come back for the next step.
  speak,

  /// Loop is over — close the mic and reset the UI.
  stop,
}

/// The user's saved choice of [ChittiConversationMode].
///
/// Nizam asked for both modes with the user picking — auto-stop is the
/// default because a mic nobody remembered to close is a battery and
/// privacy problem, and that failure is silent.
class ChittiConversationPrefs {
  ChittiConversationPrefs._();

  static const String _key = 'chitti_conversation_mode';

  static ChittiConversationMode mode = ChittiConversationMode.autoStop;
  static bool _loaded = false;

  static Future<ChittiConversationMode> load() async {
    if (_loaded) return mode;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved != null) {
        mode = ChittiConversationMode.values.firstWhere(
          (m) => m.name == saved,
          orElse: () => ChittiConversationMode.autoStop,
        );
      }
    } catch (e) {
      debugPrint('[ChittiConversation] mode load failed: $e');
    }
    return mode;
  }

  static Future<void> save(ChittiConversationMode value) async {
    mode = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, value.name);
    } catch (e) {
      debugPrint('[ChittiConversation] mode save failed: $e');
    }
  }
}

/// The loop's state machine. No Flutter, no plugins, no I/O.
class ChittiConversationController {
  ChittiConversationController({
    this.mode = ChittiConversationMode.autoStop,
    this.autoStopSilence = const Duration(seconds: 8),
  });

  ChittiConversationMode mode;

  /// How long a silent gap ends an [ChittiConversationMode.autoStop]
  /// session. Long enough to think, short enough that a pocketed phone
  /// stops listening quickly.
  final Duration autoStopSilence;

  bool _active = false;
  bool _speaking = false;
  String _spokenNormalized = '';

  /// Consecutive turns where the mic returned nothing usable. Two in a
  /// row usually means the customer has walked away or is in a noisy
  /// place, and continuing just drains the battery.
  int _emptyTurns = 0;

  bool get isActive => _active;

  bool get isSpeaking => _speaking;

  /// Words that end the loop immediately, in the four languages the
  /// app supports plus the Tanglish people actually speak.
  ///
  /// Matched as whole words against normalised text, because "stop" is
  /// a substring of nothing useful but "podhum" appears inside longer
  /// words in Tamil.
  static final RegExp _stopWords = RegExp(
    r'\b(stop|cancel it|quit|exit|enough|bye|thanks bye|shut up|'
    'podhum|pothum|sari podhum|vendam|vendaam|venaam|mudinjidhu|'
    r'nirutu|niruthu)\b|'
    '(போதும்|நிறுத்து|வேண்டாம்|சரி போதும்)',
    caseSensitive: false,
  );

  /// Starts a hands-free session.
  void start() {
    _active = true;
    _speaking = false;
    _emptyTurns = 0;
    _spokenNormalized = '';
  }

  /// Ends it. Idempotent.
  void stop() {
    _active = false;
    _speaking = false;
    _spokenNormalized = '';
  }

  /// Call immediately before handing [text] to the TTS engine.
  ///
  /// Storing what Chitti is about to say is what makes the echo guard
  /// possible — see RULE 1 in this file's header.
  void markSpeaking(String text) {
    _speaking = true;
    _spokenNormalized = _normalize(text);
  }

  /// Call when the TTS engine reports it has finished.
  void markSpokenDone() {
    _speaking = false;
    _spokenNormalized = '';
  }

  /// True when [heard] is almost certainly Chitti's own voice coming
  /// back through the mic, rather than the customer speaking.
  ///
  /// Only ever returns true while Chitti is actually speaking, so a
  /// customer who happens to repeat a phrase later is unaffected.
  bool isSelfEcho(String heard) {
    if (!_speaking || _spokenNormalized.isEmpty) return false;
    final words = _normalize(heard)
        .split(' ')
        .where((w) => w.length > 2)
        .toList(growable: false);
    if (words.isEmpty) return false;

    final spoken = _spokenNormalized.split(' ').toSet();
    var overlap = 0;
    for (final word in words) {
      if (spoken.contains(word)) overlap++;
    }
    // Over half the meaningful words coming straight back is echo. A
    // genuine interruption ("no, cancel that") shares almost nothing
    // with whatever sentence Chitti was in the middle of.
    return overlap / words.length > 0.5;
  }

  /// True when [text] is the customer telling Chitti to stop.
  bool isStopRequest(String text) => _stopWords.hasMatch(_normalize(text));

  /// What to do after the customer said [heard].
  ///
  /// [resolvedAnIntent] is whether the utterance produced a real action;
  /// [awaitingReply] is whether Chitti asked something back and is
  /// waiting on an answer (a confirmation, or a clarifying question).
  ChittiConversationStep onUserSaid(
    String heard, {
    required bool resolvedAnIntent,
    required bool awaitingReply,
  }) {
    if (!_active) return ChittiConversationStep.stop;

    if (isStopRequest(heard)) {
      stop();
      return ChittiConversationStep.stop;
    }

    if (heard.trim().length < 2) {
      _emptyTurns++;
      // Two silent turns in a row: they have walked away, or the room
      // is too noisy for this to work. Either way, keeping the mic open
      // helps nobody.
      if (_emptyTurns >= 2 && mode == ChittiConversationMode.autoStop) {
        stop();
        return ChittiConversationStep.stop;
      }
      return ChittiConversationStep.listen;
    }

    _emptyTurns = 0;

    // Chitti is waiting on an answer, so the loop must continue no
    // matter the mode — hanging up mid-question is the one thing a
    // hands-free assistant must never do.
    if (awaitingReply) return ChittiConversationStep.speak;

    // Task done and nothing pending. In autoStop that is the natural
    // end; in call mode the customer stays connected.
    if (resolvedAnIntent && mode == ChittiConversationMode.autoStop) {
      stop();
      return ChittiConversationStep.stop;
    }

    return ChittiConversationStep.speak;
  }

  /// What to do once Chitti has finished speaking.
  ChittiConversationStep afterSpeaking() {
    markSpokenDone();
    return _active ? ChittiConversationStep.listen : ChittiConversationStep.stop;
  }

  /// The silence gap that ends the session, or null in call mode where
  /// only an explicit stop ends it.
  Duration? get idleTimeout =>
      mode == ChittiConversationMode.autoStop ? autoStopSilence : null;

  static String _normalize(String input) => input
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s஀-௿ऀ-ॿഀ-ൿ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  @visibleForTesting
  int get emptyTurns => _emptyTurns;
}
