// ================================================================
// chitti_followup_service.dart — Chitti asking "boss, did you finish
// that?" out loud, and only when it has earned the right to.
// ================================================================
// NEW (Sep 4 2026 — Nizam: "itha mudichutingla boss athu mudichutingla
// boss nu kekekanum enkita ... enoda task ah folowup pannanum").
//
// TWO GATES, AND BOTH MATTER
//
//   ChittiCommitmentService decides whether a given commitment is worth
//   asking about at all: overdue, not asked in the last 3 hours, and
//   asked fewer than 3 times total. Past that it stays on the list and
//   stops being spoken — a secretary who asks a seventh time about the
//   same thing is not being diligent, they are being ignored.
//
//   ChittiNudgeService then decides whether Chitti may speak AT ALL
//   right now: 6 unprompted messages a day across every feature, 3
//   minutes between any two, and a global mute. Its header is explicit
//   that no trigger site may call the overlay directly — every one must
//   pass through tryFire() — because the failure mode of unprompted AI
//   is always the same: each new trigger gets added independently, none
//   of them knows what the others already said today, and within a week
//   it is spam and the whole thing gets muted.
//
//   So this file adds a feature that CAN be silenced by features it has
//   never heard of. That is the design working, not a limitation.
//
// NO API, NO NETWORK. The question is built from the commitment's own
// words and spoken through the same native TTS Chitti uses on calls.
import 'package:flutter/foundation.dart';

import '../chitti_nudge_service.dart';
import 'chitti_accessibility_bridge.dart';
import 'chitti_commitment_service.dart';

class ChittiFollowUpService {
  ChittiFollowUpService._();
  static final ChittiFollowUpService instance = ChittiFollowUpService._();

  /// Nudge id for the shared anti-spam gate. One id for all follow-ups
  /// on purpose: two different overdue tasks asked about back to back
  /// is the same annoyance as one asked twice.
  static const String _nudgeId = 'commitment_followup';

  /// Long on purpose. This is the "boss, did you finish that?" voice,
  /// and it competes for the same daily budget as every other proactive
  /// message. Ninety minutes means at most a handful a day even before
  /// the global cap applies.
  static const Duration _perTypeCooldown = Duration(minutes: 90);

  bool _running = false;

  /// Checks whether anything is due and, if the gates allow, speaks ONE
  /// follow-up. Safe to call on app resume, on a timer, or after a call
  /// ends — it self-checks and does nothing the vast majority of times.
  ///
  /// Returns the commitment asked about, or null when it stayed quiet.
  Future<Commitment?> maybeAskOne({String languageCode = 'ta'}) async {
    if (_running) return null;
    _running = true;
    try {
      // Cheapest check first: is there anything to say? Asking the nudge
      // gate before knowing that would burn a slot from the daily
      // budget on a question that was never going to be asked -- tryFire
      // RECORDS the fire as a side effect, by design.
      final due = await ChittiCommitmentService.instance.dueForFollowUp();
      if (due == null) return null;

      final allowed = await ChittiNudgeService.instance.tryFire(
        _nudgeId,
        perTypeCooldown: _perTypeCooldown,
      );
      if (!allowed) return null;

      final line = ChittiCommitmentService.followUpLine(
        due,
        languageCode: languageCode,
      );
      await ChittiAccessibilityBridge.instance.speakOnCallStream(
        line,
        languageCode == 'ta' ? 'ta-IN' : 'en-US',
      );
      // Recorded only after it was actually spoken, so a TTS failure
      // doesn't burn one of the three asks this commitment gets.
      await ChittiCommitmentService.instance.recordAsked(due.id);
      return due;
    } catch (e) {
      debugPrint('[ChittiFollowUp] skipped: $e');
      return null;
    } finally {
      _running = false;
    }
  }

  /// The morning line: what today looks like, said once.
  ///
  /// Separate from [maybeAskOne] because it is a different act — a
  /// briefing, not a chase — and it should not consume the follow-up
  /// cooldown. It still passes the shared gate, so a muted Chitti stays
  /// muted at 8am too.
  Future<bool> maybeGreetWithToday({String languageCode = 'ta'}) async {
    try {
      await ChittiCommitmentService.instance.load();
      final items = ChittiCommitmentService.instance.today;
      final summary = ChittiCommitmentService.morningSummary(
        items,
        languageCode: languageCode,
      );
      // Empty means nothing worth saying. Silence beats "you have 0
      // tasks today, boss".
      if (summary.isEmpty) return false;

      final allowed = await ChittiNudgeService.instance.tryFire(
        'commitment_morning',
        // Once a day, and only in the morning by virtue of when the
        // caller invokes it.
        perTypeCooldown: const Duration(hours: 20),
      );
      if (!allowed) return false;

      await ChittiAccessibilityBridge.instance.speakOnCallStream(
        summary,
        languageCode == 'ta' ? 'ta-IN' : 'en-US',
      );
      return true;
    } catch (e) {
      debugPrint('[ChittiFollowUp] morning summary skipped: $e');
      return false;
    }
  }
}
