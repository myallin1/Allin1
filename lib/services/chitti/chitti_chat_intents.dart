// ================================================================
// chitti_chat_intents.dart — the conversational layer: replies that
// keep the conversation moving instead of ending it.
// ================================================================
// NEW (Aug 28 2026 — Nizam, with a screenshot: "Chitti innum
// yellathukum answer, next step ku pogamattingran ... customer question
// oda intent purinju work pannanuma ila answer pannanuma nu pirichu
// purinjukura knowledge namma Chitti ku venum").
//
// THE BUG THIS EXISTS TO FIX, EXACTLY
// Chitti offers chips after a booking — "Change destination", "Cancel
// this booking", "Ask something else". Tapping one sends that text
// back as a message. Nothing in the app handled those strings: not the
// intent engine (no rule), not the answerer (not a question about a
// section). So every tap fell through to the no-key reply, and the
// screenshot showed the same sentence three times in a row with no way
// forward. Chitti was offering doors that opened onto a wall.
//
// ANSWER vs ACT — the split Nizam asked for
// A message is one of three things, and they need different handling:
//   • ACT   — do something (book, cancel, open). ChittiLocalIntentEngine.
//   • ASK   — a question about the app. ChittiLocalAnswerService.
//   • TALK  — keeping the conversation going: a chip, an
//             acknowledgement, a "something else". Nothing owned that,
//             which is this file.
// TALK is checked FIRST, because its phrases are short and would
// otherwise be mis-read: "cancel this booking" contains "cancel" and
// would fire the real cancel_order tool on an order that does not
// exist yet.
//
// EVERY REPLY HERE CARRIES CHIPS. That is the actual rule being
// enforced: a dead end is a bug, so a turn that offers no next step
// does not ship. Bilingual, because the app switches language and a
// reply stuck in English mid-Tamil-conversation reads as broken.
import 'package:flutter/foundation.dart';

import '../../config/app_variant.dart';
import 'chitti_local_answer_service.dart';
import 'chitti_section_registry.dart';

/// What kind of turn this is.
enum ChittiTurnKind {
  /// Do something.
  act,

  /// Answer a question in words.
  ask,

  /// Keep the conversation moving.
  talk,
}

class ChittiChatIntents {
  ChittiChatIntents._();

  /// Handles a conversational turn, or returns null to let the ACT and
  /// ASK layers have it.
  static ChittiLocalAnswer? handle(
    String message, {
    String languageCode = 'en',
    String? variant,
  }) {
    final v = variant ?? currentAppVariant;
    final q = _normalize(message);
    if (q.isEmpty) return null;
    final ta = languageCode == 'ta' || languageCode == 'tg';

    if (_matches(q, _changeDestination)) {
      return ChittiLocalAnswer(
        ta
            ? 'சரிங்க பாஸ் — எங்க போகணும் சொல்லுங்க, நான் மாத்திடறேன்.'
            : 'Sure boss — tell me the new drop location and I will change it.',
        suggestions: _navChips(v, ta),
      );
    }

    if (_matches(q, _cancelBooking)) {
      // NOT the cancel_order tool. Nothing has been placed yet at this
      // point — this is the customer backing out of a booking screen,
      // which is a conversation, not a Firestore write.
      return ChittiLocalAnswer(
        ta
            ? 'சரி, அந்த புக்கிங் விட்டுட்டோம். வேற என்ன வேணும்?'
            : 'Dropped that booking. What else can I do for you?',
        suggestions: _openingChips(v, ta),
      );
    }

    if (_matches(q, _somethingElse)) {
      return ChittiLocalAnswer(
        ta
            ? 'சொல்லுங்க பாஸ், என்ன வேணும்?'
            : 'Go on then, boss — what do you need?',
        suggestions: _openingChips(v, ta),
      );
    }

    if (_matches(q, _thanks)) {
      return ChittiLocalAnswer(
        ta
            ? 'இதுக்கெல்லாம் என்ன பாஸ். வேற ஏதாவது?'
            : 'Any time, boss. Anything else?',
        suggestions: _openingChips(v, ta),
      );
    }

    if (_matches(q, _greeting)) {
      return ChittiLocalAnswer(
        ta
            ? 'வணக்கம் பாஸ்! சொல்லுங்க, என்ன பண்ணனும்?'
            : "Hello boss! Tell me what you need — I'll handle it.",
        suggestions: _openingChips(v, ta),
      );
    }

    return null;
  }

  /// Classifies a message, for callers that want to route rather than
  /// reply. Exposed mainly so the split is testable and visible.
  static ChittiTurnKind classify(String message) {
    final q = _normalize(message);
    if (_matches(q, _changeDestination) ||
        _matches(q, _cancelBooking) ||
        _matches(q, _somethingElse) ||
        _matches(q, _thanks) ||
        _matches(q, _greeting)) {
      return ChittiTurnKind.talk;
    }
    return _questionShaped.hasMatch(q) ? ChittiTurnKind.ask : ChittiTurnKind.act;
  }

  /// A reply that is never a dead end.
  ///
  /// Used wherever Chitti has to say "I could not do that" — the whole
  /// point of the screenshot Nizam sent was three such replies in a row
  /// with no chips under any of them.
  static ChittiLocalAnswer fallback({
    required String text,
    String languageCode = 'en',
    String? variant,
  }) {
    final ta = languageCode == 'ta' || languageCode == 'tg';
    return ChittiLocalAnswer(
      text,
      suggestions: _openingChips(variant ?? currentAppVariant, ta),
    );
  }

  // ── chip sets ────────────────────────────────────────────────────

  /// Three things worth doing next, per app variant. Kept short — these
  /// render as chips, and a chip that wraps to two lines looks broken.
  static List<String> _openingChips(String variant, bool ta) {
    switch (variant) {
      case 'hero':
        return ta
            ? <String>['இன்னைக்கு எவ்வளவு?', 'என்ன வேலை இருக்கு?', 'ஆன்லைன் பண்ணு']
            : <String>['Today earnings', 'My current job', 'Go online'];
      case 'seller':
        return ta
            ? <String>['புது ஆர்டர்', 'இன்னைக்கு சேல்ஸ்', 'கடையை மூடு']
            : <String>['Pending orders', 'Today sales', 'Close the shop'];
      case 'admin':
        return ta
            ? <String>['புது ஆர்டர்', 'பக் ரிப்போர்ட்', 'டாஷ்போர்டு']
            : <String>['New orders', 'Bug reports', 'Open dashboard'];
      default:
        return ta
            ? <String>['ஆட்டோ புக் பண்ணு', 'என் ஆர்டர்', 'பணம் எவ்வளவு?']
            : <String>['Book a ride', 'My orders', 'My wallet balance'];
    }
  }

  /// Where-to-next chips, drawn from the registry so they stay true as
  /// sections are added.
  static List<String> _navChips(String variant, bool ta) {
    final sections = chittiSectionsFor(variant);
    if (sections.isEmpty) return _openingChips(variant, ta);
    return <String>[
      if (ta) 'ரத்து பண்ணு' else 'Cancel this booking',
      if (ta) 'வேற ஏதாவது' else 'Ask something else',
    ];
  }

  // ── phrase tables ────────────────────────────────────────────────
  //
  // Written as whole phrases rather than keywords on purpose. "cancel"
  // alone would collide with the real cancel_order tool; "change
  // destination" cannot.

  static const List<String> _changeDestination = [
    'change destination', 'change the destination', 'change drop',
    'different destination', 'wrong destination', 'edit destination',
    'இடம் மாத்து', 'எங்க போகணும் மாத்து',
  ];

  static const List<String> _cancelBooking = [
    'cancel this booking', 'cancel booking', 'cancel the booking',
    'dont book', 'do not book', 'leave the booking',
    'புக்கிங் ரத்து', 'புக்கிங் வேண்டாம்',
  ];

  static const List<String> _somethingElse = [
    'ask something else', 'something else', 'show me something else',
    'take me somewhere else', 'go somewhere else', 'go back to chat',
    'anything else', 'what else', 'report something else',
    'order something else', 'add another item',
    'வேற ஏதாவது', 'வேற எதுவும்',
  ];

  static const List<String> _thanks = [
    'thanks', 'thank you', 'thanks da', 'nandri', 'super', 'nice',
    'நன்றி', 'சூப்பர்',
  ];

  static const List<String> _greeting = [
    'hi', 'hello', 'hey', 'vanakkam', 'good morning', 'good evening',
    'வணக்கம்',
  ];

  static final RegExp _questionShaped = RegExp(
    r'\?|\b(what|which|how|why|when|where|who|can|does|is|are)\b|'
    '(என்ன|எப்படி|ஏன்|எங்க|எவ்வளவு|யாரு)',
    caseSensitive: false,
  );

  /// Whole-phrase match: the message IS the phrase, or contains it as a
  /// complete thought. A chip tap gives us the exact string, so an
  /// equality check catches the case this file was written for, and the
  /// contains() covers someone typing it themselves.
  static bool _matches(String q, List<String> phrases) {
    for (final p in phrases) {
      final n = _normalize(p);
      if (n.isEmpty) continue;
      if (q == n) return true;
      // Guarded by length so a short phrase cannot match inside a long
      // sentence that means something else entirely.
      if (q.length <= n.length + 12 && q.contains(n)) return true;
    }
    return false;
  }

  static String _normalize(String input) => input
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s஀-௿ऀ-ॿഀ-ൿ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  @visibleForTesting
  static List<String> openingChipsFor(String variant, {bool tamil = false}) =>
      _openingChips(variant, tamil);
}
