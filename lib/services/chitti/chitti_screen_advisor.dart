// ================================================================
// chitti_screen_advisor.dart — turns what Chitti can SEE on a screen
// into a question worth asking.
// ================================================================
// NEW (Aug 28 2026 — Nizam/CEO: "udane athu bot mari work pannama user
// intent purinjukutu avar kita avar sonna work ku knowledgable ah
// question kekkanum ... namma Chitti oda knowledge paathu customer
// viyanthuranum").
//
// The difference between a bot and an assistant is not vocabulary, it
// is whether the next question shows it was paying attention. "How can
// I help you?" is a bot. "Your drop location is still empty — where
// are you headed?" is someone who looked.
//
// ChittiScreenReader supplies the looking. This file decides what is
// worth saying about it, and the ranking is deliberate:
//
//   1. A BLANK FIELD the customer has to fill anyway. This is the
//      highest-value thing on any screen — it is the thing standing
//      between them and finishing, and Chitti can usually fill it.
//   2. The screen's OWN BUTTONS, offered as tappable chips. This is
//      the part that needs no teaching: whatever a new screen ships
//      with, Chitti can already offer it. A screen added next month
//      works on the day it ships, with nobody updating a table.
//   3. The section's description, when the registry knows the screen.
//
// WHY THIS IS NOT A PROMPT
// Every line here is produced on device, in microseconds, with no key
// and no network. The model, when there is one, gets the same snapshot
// as context and can do better — but the floor is a genuinely
// attentive reply rather than "I'm having a network pause".
import 'package:flutter/foundation.dart';

import '../../config/app_variant.dart';
import '../chitti_order_memory_service.dart';
import 'chitti_local_answer_service.dart';
import 'chitti_screen_reader.dart';
import 'chitti_section_registry.dart';

class ChittiScreenAdvisor {
  ChittiScreenAdvisor._();

  /// Field labels that are worth asking about, and the ones that are
  /// not. A search box being empty is not a problem to solve; a drop
  /// address being empty is the whole reason the customer is stuck.
  static final RegExp _ignorableField = RegExp(
    'search|filter|find|promo|coupon|referral|note|optional|comment',
    caseSensitive: false,
  );

  /// An opening line for a screen Chitti has just landed on with the
  /// customer, or a reply when they ask what to do here.
  ///
  /// Returns null when the screen has nothing worth remarking on —
  /// silence beats narrating a screen back to the person looking at it.
  static Future<ChittiLocalAnswer?> adviseOnCurrentScreen({
    String? variant,
  }) async {
    final v = variant ?? currentAppVariant;
    final snapshot = await ChittiScreenReader.read();
    if (snapshot.isEmpty) return null;
    return adviseFrom(snapshot, variant: v);
  }

  /// The pure half — no I/O, so it can be tested against a snapshot
  /// built by hand.
  @visibleForTesting
  static ChittiLocalAnswer? adviseFrom(
    ChittiScreenSnapshot snapshot, {
    String? variant,
  }) {
    final v = variant ?? currentAppVariant;
    final section = _sectionForTitle(snapshot.title, v);
    final chips = _chipsFromButtons(snapshot);

    // 1. A blank field the customer needs filled.
    final blank = snapshot.blankFields
        .where((f) => !_ignorableField.hasMatch(f.label))
        .toList(growable: false);
    if (blank.isNotEmpty) {
      final first = blank.first;
      final rest = blank.length - 1;
      final tail = rest > 0
          ? ' After that there ${rest == 1 ? 'is' : 'are'} $rest more to fill.'
          : '';
      return ChittiLocalAnswer(
        '"${first.label}" is still empty. Tell me what goes in it and I '
        'will fill it for you.$tail',
        suggestions: chips.isEmpty
            ? const <String>['What is this page?']
            : chips,
      );
    }

    // 2. The screen's own actions, which is the part that needs no
    //    maintenance as the app grows.
    if (chips.isNotEmpty) {
      final where = section?.label ?? snapshot.title;
      final lead = where != null
          ? "You're on $where."
          : 'Here on this page,';
      return ChittiLocalAnswer(
        '$lead I can do any of these for you — just say the word.',
        suggestions: chips,
      );
    }

    // 3. Fall back to what the registry knows.
    if (section != null) {
      return ChittiLocalAnswer(
        '${section.label}: ${section.description}',
        suggestions: const <String>['What can you do?'],
      );
    }
    return null;
  }

  /// A short, knowledgeable follow-up to something the customer just
  /// said, using the screen and their history.
  ///
  /// This is the "don't answer like a bot" path: the reply names
  /// something real — the field they still have to fill, or what they
  /// ordered last time — rather than asking an empty question.
  static Future<ChittiLocalAnswer?> followUpFor(
    String utterance, {
    String? variant,
  }) async {
    final snapshot = await ChittiScreenReader.read();
    if (snapshot.isEmpty) return null;

    final blank = snapshot.blankFields
        .where((f) => !_ignorableField.hasMatch(f.label))
        .toList(growable: false);

    // Their own last order is the single most impressive thing Chitti
    // can bring up unprompted — it is specific, it is theirs, and it
    // usually IS the answer to whatever is blank.
    final last = ChittiOrderMemoryService.mostRecentEntry();
    final lastSummary = (last?['summary'] as String?)?.trim();

    if (blank.isNotEmpty) {
      final label = blank.first.label;
      if (lastSummary != null && lastSummary.isNotEmpty) {
        return ChittiLocalAnswer(
          'Got it. "$label" is empty — last time you went with '
          '"$lastSummary". Same again, or something else?',
          suggestions: <String>[
            'Same as last time',
            'Something else',
            ..._chipsFromButtons(snapshot).take(1),
          ],
        );
      }
      return ChittiLocalAnswer(
        'Got it. I just need "$label" — tell me and I will fill it in.',
        suggestions: _chipsFromButtons(snapshot),
      );
    }
    return null;
  }

  // ── helpers ──────────────────────────────────────────────────────

  /// Buttons the screen actually offers, as chips.
  ///
  /// Filtered hard, because a raw semantics dump contains plenty that
  /// is not a real choice: navigation chrome, tab labels, and anything
  /// long enough to be a paragraph rather than an action.
  static List<String> _chipsFromButtons(ChittiScreenSnapshot snapshot) {
    final out = <String>[];
    for (final b in snapshot.buttons) {
      final label = b.label.trim();
      if (label.length < 3 || label.length > 28) continue;
      if (_chromeLabel.hasMatch(label)) continue;
      if (out.contains(label)) continue;
      out.add(label);
      if (out.length == 3) break;
    }
    return out;
  }

  static final RegExp _chromeLabel = RegExp(
    r'^(back|next|previous|ok|cancel|done|close|menu|home|tab \d+)$',
    caseSensitive: false,
  );

  static ChittiSection? _sectionForTitle(String? title, String variant) {
    if (title == null || title.isEmpty) return null;
    final needle = title.toLowerCase().trim();
    for (final s in chittiSectionsFor(variant)) {
      if (s.label.toLowerCase() == needle) return s;
      for (final alias in s.aliases) {
        if (alias.length > 3 && needle.contains(alias.toLowerCase())) return s;
      }
    }
    return null;
  }
}
