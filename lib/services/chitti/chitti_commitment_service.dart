// ================================================================
// chitti_commitment_service.dart — the things Nizam said he'd do, and
// the things Chitti promised to come back about.
// ================================================================
// NEW (Sep 4 2026 — Nizam: "apopo adminoda daily schedule pottu
// vachutu itha mudichutingla boss athu mudichutingla boos nu kekekanum
// enkita ... enoda task ah folowup pannanum sollapona ennoda persnol
// secrotryavum irukanum").
//
// WHY THIS FILE HAD TO EXIST BEFORE ANY OF THAT COULD WORK
//   The persona work (PR #40) added follow-up INSTRUCTIONS to admin
//   Chitti, and its own audit flagged the hole it couldn't fill from a
//   prompt: there was nowhere to write down what was promised. A model
//   asked to "follow up on what the boss committed to" with no store
//   behind it has exactly two options — stay silent, or invent a
//   commitment. Inventing one is the same failure class as inventing a
//   balance, and this app already treats that as unacceptable. So the
//   record comes first, and the follow-up reads from it.
//
// LOCAL-FIRST, AND THAT IS DELIBERATE
//   Kept in SharedPreferences as JSON, not Firestore. Three reasons:
//   this is one person's private worklist on one phone, not shared
//   data; Firestore reads are a real budget on the Spark plan (see
//   AppKnowledgeBriefing.constraints); and Nizam asked specifically
//   for the secretary to work with no API and no network. A commitment
//   you can't read back on a train with no signal is not a secretary.
//
// WHAT THIS DELIBERATELY DOES NOT DO
//   It does not invent commitments on its own. Every entry comes from
//   Nizam typing it or telling Chitti. Chitti noticing things by
//   itself ("6 heroes are still pending approval — shall I add that?")
//   is a good idea and a separate one: an assistant that files its own
//   todos becomes noise fast, and this needs to earn trust while it is
//   still boring and predictable.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chitti_commitment_alarms.dart';

enum CommitmentStatus { open, done, snoozed }

/// Who put this on the list. Kept because "you told me to remind you"
/// and "I noticed this" need different wording when Chitti asks, and
/// because a wrong nudge is easier to forgive when it says where it
/// came from.
enum CommitmentSource { boss, chitti }

@immutable
class Commitment {
  const Commitment({
    required this.id,
    required this.what,
    required this.dueAt,
    required this.status,
    required this.source,
    required this.createdAt,
    this.note = '',
    this.timesAsked = 0,
    this.lastAskedAt,
  });

  final String id;

  /// One line, in Nizam's own words. Not summarised, not rewritten —
  /// he has to recognise it instantly when it comes back at him.
  final String what;

  final DateTime dueAt;
  final CommitmentStatus status;
  final CommitmentSource source;
  final DateTime createdAt;
  final String note;

  /// How many times Chitti has already asked about this one. The nudge
  /// logic uses it to back off instead of repeating forever — see
  /// [ChittiCommitmentService.dueForFollowUp].
  final int timesAsked;
  final DateTime? lastAskedAt;

  bool get isOpen => status == CommitmentStatus.open;
  bool get isOverdue => isOpen && DateTime.now().isAfter(dueAt);

  bool get isToday {
    final now = DateTime.now();
    return dueAt.year == now.year &&
        dueAt.month == now.month &&
        dueAt.day == now.day;
  }

  Commitment copyWith({
    String? what,
    DateTime? dueAt,
    CommitmentStatus? status,
    String? note,
    int? timesAsked,
    DateTime? lastAskedAt,
  }) =>
      Commitment(
        id: id,
        what: what ?? this.what,
        dueAt: dueAt ?? this.dueAt,
        status: status ?? this.status,
        source: source,
        createdAt: createdAt,
        note: note ?? this.note,
        timesAsked: timesAsked ?? this.timesAsked,
        lastAskedAt: lastAskedAt ?? this.lastAskedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'what': what,
        'dueAt': dueAt.millisecondsSinceEpoch,
        'status': status.name,
        'source': source.name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'note': note,
        'timesAsked': timesAsked,
        'lastAskedAt': lastAskedAt?.millisecondsSinceEpoch,
      };

  static Commitment? fromJson(Map<String, dynamic> m) {
    try {
      final id = m['id'] as String?;
      final what = m['what'] as String?;
      final dueMs = (m['dueAt'] as num?)?.toInt();
      if (id == null || what == null || dueMs == null) return null;
      final lastMs = (m['lastAskedAt'] as num?)?.toInt();
      return Commitment(
        id: id,
        what: what,
        dueAt: DateTime.fromMillisecondsSinceEpoch(dueMs),
        status: CommitmentStatus.values.firstWhere(
          (s) => s.name == m['status'],
          orElse: () => CommitmentStatus.open,
        ),
        source: CommitmentSource.values.firstWhere(
          (s) => s.name == m['source'],
          orElse: () => CommitmentSource.boss,
        ),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (m['createdAt'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch),
        note: (m['note'] as String?) ?? '',
        timesAsked: (m['timesAsked'] as num?)?.toInt() ?? 0,
        lastAskedAt:
            lastMs == null ? null : DateTime.fromMillisecondsSinceEpoch(lastMs),
      );
    } catch (_) {
      // One corrupt entry must not take the whole list down with it —
      // see load().
      return null;
    }
  }
}

class ChittiCommitmentService extends ChangeNotifier {
  ChittiCommitmentService._();
  static final ChittiCommitmentService instance = ChittiCommitmentService._();

  static const String _prefsKey = 'chitti_commitments_v1';

  /// After this many asks Chitti stops bringing it up on its own. It
  /// stays on the list and stays visible — it just stops being spoken.
  /// A secretary who asks a seventh time about the same thing is not
  /// being diligent, they are being ignored, and the honest response
  /// to being ignored is to write it down and stop talking.
  static const int kMaxAsksPerCommitment = 3;

  /// Minimum gap between two asks about the SAME commitment. The
  /// global anti-spam ceiling still applies on top of this via
  /// ChittiNudgeService — this is only the per-item floor.
  static const Duration kAskCooldown = Duration(hours: 3);

  List<Commitment> _items = [];
  bool _loaded = false;

  List<Commitment> get all => List.unmodifiable(_items);

  List<Commitment> get openItems =>
      _items.where((c) => c.isOpen).toList()
        ..sort((a, b) => a.dueAt.compareTo(b.dueAt));

  List<Commitment> get today =>
      openItems.where((c) => c.isToday || c.isOverdue).toList();

  List<Commitment> get overdue => openItems.where((c) => c.isOverdue).toList();

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        _items = list
            .whereType<Map<String, dynamic>>()
            .map(Commitment.fromJson)
            .whereType<Commitment>()
            .toList();
      }
    } catch (_) {
      // A decode failure means the stored blob is unreadable. Starting
      // empty is bad; crashing the admin's whole day view is worse.
      _items = [];
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(_items.map((c) => c.toJson()).toList()));
    } catch (_) {
      // Nothing useful to do here — the in-memory list is still right
      // for this session, and the next successful write re-syncs it.
    }
    notifyListeners();
  }

  Future<Commitment> add({
    required String what,
    required DateTime dueAt,
    CommitmentSource source = CommitmentSource.boss,
    String note = '',
  }) async {
    await load();
    final c = Commitment(
      id: 'c${DateTime.now().microsecondsSinceEpoch}',
      what: what.trim(),
      dueAt: dueAt,
      status: CommitmentStatus.open,
      source: source,
      createdAt: DateTime.now(),
      note: note.trim(),
    );
    _items = [..._items, c];
    await _persist();
    // Arm the background alarm as part of adding, not as a separate
    // step a caller could forget. See ChittiCommitmentAlarms for why
    // this is a local AlarmManager schedule and not a push.
    await ChittiCommitmentAlarms.instance.schedule(c);
    return c;
  }

  Future<void> markDone(String id) async {
    await _update(id, (c) => c.copyWith(status: CommitmentStatus.done));
    // A reminder for something already done is the fastest way to make
    // someone mute the whole feature.
    await ChittiCommitmentAlarms.instance.cancel(id);
  }

  Future<void> reopen(String id) async {
    await _update(id, (c) => c.copyWith(status: CommitmentStatus.open));
    await _rearm(id);
  }

  /// Pushes a commitment out and RESETS its ask counter — snoozing is
  /// the boss saying "not now, ask me later", which is a fresh start,
  /// not a strike against it.
  Future<void> snooze(String id, Duration by) async {
    await _update(
      id,
      (c) => c.copyWith(
        dueAt: DateTime.now().add(by),
        status: CommitmentStatus.open,
        timesAsked: 0,
      ),
    );
    await _rearm(id);
  }

  Future<void> remove(String id) async {
    await load();
    _items = _items.where((c) => c.id != id).toList();
    await _persist();
    await ChittiCommitmentAlarms.instance.cancel(id);
  }

  /// Re-points the alarm at whatever the commitment's due time is now.
  Future<void> _rearm(String id) async {
    final match = _items.where((c) => c.id == id);
    if (match.isEmpty) return;
    await ChittiCommitmentAlarms.instance.schedule(match.first);
  }

  Future<void> _update(
      String id, Commitment Function(Commitment) transform) async {
    await load();
    _items = _items.map((c) => c.id == id ? transform(c) : c).toList();
    await _persist();
  }

  /// The single commitment Chitti should ask about right now, or null
  /// when it should stay quiet.
  ///
  /// Returns ONE, never a list, on purpose: reading five overdue items
  /// at someone is a status report, not a question, and a person can
  /// only answer one thing at a time. The oldest overdue item wins,
  /// because that's the one most likely to have actually slipped.
  Future<Commitment?> dueForFollowUp() async {
    await load();
    final now = DateTime.now();
    final candidates = overdue.where((c) {
      if (c.timesAsked >= kMaxAsksPerCommitment) return false;
      final last = c.lastAskedAt;
      if (last != null && now.difference(last) < kAskCooldown) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return candidates.isEmpty ? null : candidates.first;
  }

  /// Call immediately after Chitti actually asks, so the back-off in
  /// [dueForFollowUp] is based on what was really said out loud.
  Future<void> recordAsked(String id) async {
    await _update(
      id,
      (c) => c.copyWith(
        timesAsked: c.timesAsked + 1,
        lastAskedAt: DateTime.now(),
      ),
    );
  }

  /// What Chitti says when following up. Names the commitment in
  /// Nizam's own words rather than paraphrasing — he should recognise
  /// it without having to think.
  static String followUpLine(Commitment c, {String languageCode = 'ta'}) {
    if (languageCode == 'ta') {
      return c.source == CommitmentSource.boss
          ? 'பாஸ், "${c.what}" — இதை முடிச்சிட்டீங்களா?'
          : 'பாஸ், "${c.what}" — இது இன்னும் பாக்கியிருக்கு.';
    }
    return c.source == CommitmentSource.boss
        ? 'Boss, "${c.what}" — did you finish that?'
        : 'Boss, "${c.what}" is still pending.';
  }

  /// The morning summary. Empty string when there is nothing worth
  /// saying — silence is a valid answer and better than "you have 0
  /// tasks today, boss".
  static String morningSummary(List<Commitment> items,
      {String languageCode = 'ta'}) {
    if (items.isEmpty) return '';
    final n = items.length;
    final first = items.first.what;
    if (languageCode == 'ta') {
      return n == 1
          ? 'காலை வணக்கம் பாஸ். இன்னைக்கு ஒரு விஷயம் இருக்கு — "$first".'
          : 'காலை வணக்கம் பாஸ். இன்னைக்கு $n விஷயம் இருக்கு. முதல்ல — "$first".';
    }
    return n == 1
        ? 'Good morning boss. One thing today — "$first".'
        : 'Good morning boss. $n things today. First up — "$first".';
  }
}
