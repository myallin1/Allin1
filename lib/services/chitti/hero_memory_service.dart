// ================================================================
// HeroMemoryService — Chitti's offline-first memory of ONE hero.
// ================================================================
// NEW (Sep 1 2026 — Nizam: Chitti should evolve from a scripted bot
// into a genuine companion/business-advisor for the Hero, "like a CTO
// guiding a founder", but WITHOUT spending cloud cost or API tokens to
// get there).
//
// WHAT THIS FILE IS
// The "Local Memory Engine" + "Smart Prompt Injection Manager" in one
// place, on purpose — the manager's whole job is deciding what subset
// of the engine's data is worth a token, so splitting them would just
// mean two files that have to agree on the same data shape.
//
// WHY HIVE AND NOT FIRESTORE (same reasoning as ChittiOrderMemoryService)
// This is a per-device convenience memory, not a record of anything
// billable or disputable — the real earnings ledger stays in
// `wallet_transactions` on Firestore. Writing a rolling summary of it
// to Hive costs nothing and needs no network, which is also what makes
// [offlineInsight] possible: it reads numbers already sitting on the
// device, so it works with the hero's data connection fully off.
//
// WHY A COMPRESSED "PROFILE" AND NOT RAW HISTORY IN THE PROMPT
// The whole point of Nizam's ask is token cost. Fourteen days of raw
// earnings rows in a system prompt is the exact waste this exists to
// avoid. [heroProfileForPrompt] is the one place that turns the local
// history into three or four short lines — "yesterday vs today",
// "mood", "last remembered struggle" — and that block is ALL that gets
// injected. The full history never leaves this file.
//
// WHY IN-MEMORY CACHE + preload() (same contract as ChittiOrderMemoryService)
// [heroProfileForPrompt] is called from `_buildSystemPrompt()`, which is
// synchronous by contract (see guru_api_service.dart) — so this follows
// the same "warm cache at boot, keep it in sync on every write" pattern
// rather than making prompt-building async for one feature.
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class HeroMemoryService {
  HeroMemoryService._();

  static const String _boxName = 'chitti_hero_memory';
  static const String _earningsKey = 'earnings';
  static const String _moodsKey = 'moods';
  static const String _highlightsKey = 'highlights';

  /// How many days of earnings snapshots to keep. Enough for a real
  /// "this week vs last week" comparison later without the box (or the
  /// prompt) growing without bound.
  static const int kMaxEarningsDays = 14;

  /// Mood log — short on purpose, same reasoning as
  /// ChittiOrderMemoryService.kMaxEntries: this is read on every
  /// prompt build, not archived for its own sake.
  static const int kMaxMoods = 10;

  /// Remembered struggles/wins — the "CTO remembers your last blocker"
  /// half of the ask. Capped hard: this is the part most likely to
  /// grow unbounded if left uncapped, since every setback conversation
  /// is a candidate.
  static const int kMaxHighlights = 8;

  static List<Map<String, dynamic>> _earnings = <Map<String, dynamic>>[];
  static List<Map<String, dynamic>> _moods = <Map<String, dynamic>>[];
  static List<Map<String, dynamic>> _highlights = <Map<String, dynamic>>[];

  static Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    // Idempotent, same as every other Chitti Hive box in this codebase
    // — safe even if another entrypoint already called this.
    await Hive.initFlutter();
    return Hive.openBox(_boxName);
  }

  static List<Map<String, dynamic>> _readList(Box box, String key) {
    final raw = box.get(key);
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Call once at boot (after Hive.initFlutter()), same contract as
  /// ChittiOrderMemoryService.preload(). Safe to skip — callers just
  /// see no history until the next record*() call warms the cache.
  static Future<void> preload() async {
    try {
      final box = await _box();
      _earnings = _readList(box, _earningsKey);
      _moods = _readList(box, _moodsKey);
      _highlights = _readList(box, _highlightsKey);
    } catch (e) {
      debugPrint('[HeroMemoryService] preload failed: $e');
    }
  }

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ── EARNINGS ───────────────────────────────────────────────────

  /// Upserts TODAY's running earnings snapshot. Safe to call repeatedly
  /// through the day (every time the hero asks Chitti about earnings) —
  /// it replaces today's entry rather than appending a duplicate, so
  /// the box never grows past [kMaxEarningsDays] regardless of how many
  /// times the hero checks.
  ///
  /// Fire-and-forget from the caller (wrap in `unawaited(...)`) — a
  /// memory-write failure must never block the real answer it is
  /// describing.
  static Future<void> recordEarningsSnapshot(double total, int count) async {
    try {
      final today = _dateKey(DateTime.now());
      final box = await _box();
      final entries = _readList(box, _earningsKey);
      final idx = entries.indexWhere((e) => e['date'] == today);
      final entry = {'date': today, 'total': total, 'count': count};
      if (idx >= 0) {
        entries[idx] = entry;
      } else {
        entries.add(entry);
      }
      if (entries.length > kMaxEarningsDays) {
        entries.removeRange(0, entries.length - kMaxEarningsDays);
      }
      await box.put(_earningsKey, entries);
      _earnings = entries;
    } catch (e) {
      debugPrint('[HeroMemoryService] recordEarningsSnapshot failed: $e');
    }
  }

  /// Today's and yesterday's snapshot, or null for either if there is
  /// no data yet (new hero, or a day was skipped). Raw — for a caller
  /// that needs to make a decision off the numbers, unlike the
  /// formatted prompt/insight strings below.
  static ({double total, int count})? _snapshotFor(String dateKey) {
    final match = _earnings.where((e) => e['date'] == dateKey);
    if (match.isEmpty) return null;
    final e = match.first;
    return (
      total: (e['total'] as num?)?.toDouble() ?? 0.0,
      count: (e['count'] as num?)?.toInt() ?? 0,
    );
  }

  // ── MOOD ───────────────────────────────────────────────────────

  /// Very small, fully-offline keyword classifier — no model call.
  /// Deliberately narrow: it only ever moves the needle toward 'low',
  /// never invents a mood from a neutral factual sentence. A false
  /// "you seem down" is worse than staying silent (same principle as
  /// ChittiBuddy.isSafeMoment being pessimistic).
  static final RegExp _lowMoodWords = RegExp(
    r'\b(tired|exhausted|not feeling well|unmotivated|no rides|no ride|'
    r'no work|slow day|bad day|sad|frustrated|give up|giving up|fed up|'
    r'losing money|loss|struggling|difficult|hard day)\b|'
    '(கஷ்டமா|சோர்வா|வேலை இல்ல|மனசு இல்ல|நஷ்டம்|கஷ்டம்)',
    caseSensitive: false,
  );

  static final RegExp _goodMoodWords = RegExp(
    r'\b(great day|good day|happy|excellent|best day|feeling good|'
    r'earned well|good earning)\b|'
    '(நல்லா இருக்கு|சந்தோஷமா|நல்ல நாள்)',
    caseSensitive: false,
  );

  /// Looks at one message the hero typed/spoke and records a mood entry
  /// ONLY when the text is a clear enough signal — most messages ("go
  /// online", "my wallet balance") match neither pattern and this is a
  /// silent no-op for them, same as it should be.
  static Future<void> maybeInferMood(String text) async {
    if (_lowMoodWords.hasMatch(text)) {
      await recordMood('low');
    } else if (_goodMoodWords.hasMatch(text)) {
      await recordMood('good');
    }
  }

  static Future<void> recordMood(String mood, {String? note}) async {
    try {
      final box = await _box();
      final entries = _readList(box, _moodsKey)
        ..add({
          'mood': mood,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          'at': DateTime.now().millisecondsSinceEpoch,
        });
      if (entries.length > kMaxMoods) {
        entries.removeRange(0, entries.length - kMaxMoods);
      }
      await box.put(_moodsKey, entries);
      _moods = entries;
    } catch (e) {
      debugPrint('[HeroMemoryService] recordMood failed: $e');
    }
  }

  /// The most recent mood entry, or null if none recorded yet.
  static String? get lastMood =>
      _moods.isEmpty ? null : _moods.last['mood'] as String?;

  // ── HIGHLIGHTS (remembered struggles/wins) ──────────────────────

  /// Records one short, human-readable fact worth remembering across
  /// sessions — "vehicle broke down", "first ₹1000 day", "third late
  /// night in a row". Same rolling-window discipline as everything
  /// else here: this is a handful of reminders, not a diary.
  static Future<void> recordHighlight(String note) async {
    final trimmed = note.trim();
    if (trimmed.isEmpty) return;
    try {
      final box = await _box();
      final entries = _readList(box, _highlightsKey)
        ..add({'note': trimmed, 'at': DateTime.now().millisecondsSinceEpoch});
      if (entries.length > kMaxHighlights) {
        entries.removeRange(0, entries.length - kMaxHighlights);
      }
      await box.put(_highlightsKey, entries);
      _highlights = entries;
    } catch (e) {
      debugPrint('[HeroMemoryService] recordHighlight failed: $e');
    }
  }

  // ── TOKEN-OPTIMIZED PROMPT INJECTOR ─────────────────────────────

  /// The ONLY thing that reaches the model. Three or four short lines,
  /// never the raw history — this is the piece that keeps the "smart
  /// prompt injection" promise: Groq sees a compressed profile, not
  /// fourteen days of numbers.
  ///
  /// Empty string for a brand-new hero (nothing recorded yet) — callers
  /// should omit the section entirely rather than print an empty
  /// header, same contract as ChittiOrderMemoryService.recentSummary().
  static String heroProfileForPrompt() {
    if (_earnings.isEmpty && _moods.isEmpty && _highlights.isEmpty) {
      return '';
    }
    final lines = <String>[];

    final today = _snapshotFor(_dateKey(DateTime.now()));
    final yesterday =
        _snapshotFor(_dateKey(DateTime.now().subtract(const Duration(days: 1))));
    if (today != null || yesterday != null) {
      final todayText = today == null
          ? 'no earnings recorded yet today'
          : '₹${today.total.toStringAsFixed(0)} so far today across '
              '${today.count} payment${today.count == 1 ? '' : 's'}';
      final y = yesterday?.total;
      final trend = (y != null && today != null)
          ? (today.total > y
              ? ' (up from ₹${y.toStringAsFixed(0)} yesterday)'
              : today.total < y
                  ? ' (down from ₹${y.toStringAsFixed(0)} yesterday)'
                  : ' (same as yesterday)')
          : (y != null ? ' (yesterday was ₹${y.toStringAsFixed(0)})' : '');
      lines.add('Earnings: $todayText$trend.');
    }

    if (lastMood != null) {
      lines.add(
        lastMood == 'low'
            ? "Mood: the hero recently sounded discouraged or tired — "
                'lead with encouragement, not just numbers.'
            : 'Mood: the hero recently sounded upbeat.',
      );
    }

    if (_highlights.isNotEmpty) {
      lines.add('Remember: ${_highlights.last['note']}.');
    }

    if (lines.isEmpty) return '';
    return "Hero Profile (compact, local-only memory — use this to sound "
        "like someone who actually remembers this hero, not a generic "
        "assistant; never invent numbers beyond what is given here):\n"
        '${lines.join('\n')}';
  }

  // ── OFFLINE / NO-API-KEY FALLBACK ────────────────────────────────

  /// A dynamic, personalized line generated PURELY from local numbers
  /// — no model, no network, no API key. This is the fallback for a
  /// hero with no connectivity at all: still better than a static pep
  /// quote, because it is actually about THEM.
  ///
  /// Returns null when there isn't enough local data to say anything
  /// specific (brand-new hero) — callers should fall back to
  /// ChittiHeroVoice's generic pep lines in that case.
  static String? offlineInsight() {
    final today = _snapshotFor(_dateKey(DateTime.now()));
    final yesterday =
        _snapshotFor(_dateKey(DateTime.now().subtract(const Duration(days: 1))));

    final parts = <String>[];

    if (today != null && yesterday != null) {
      final diff = today.total - yesterday.total;
      if (diff > 0) {
        parts.add(
          'Boss, you are ₹${diff.toStringAsFixed(0)} ahead of yesterday '
          'already — keep this pace.',
        );
      } else if (diff < 0) {
        parts.add(
          'Boss, a bit slower than yesterday (₹${(-diff).toStringAsFixed(0)} '
          'less so far) — the day is not over, one more good ride turns '
          'this around.',
        );
      } else {
        parts.add('Boss, matching yesterday so far — steady.');
      }
    } else if (today != null && today.count > 0) {
      parts.add(
        'Boss, ₹${today.total.toStringAsFixed(0)} so far today across '
        '${today.count} payment${today.count == 1 ? '' : 's'}.',
      );
    }

    if (lastMood == 'low') {
      parts.add("I know it's been a tough stretch — I'm keeping an eye on "
          'your numbers so you don\'t have to.');
    }

    if (parts.isEmpty) return null;
    return parts.join(' ');
  }

  static void clearForTesting() {
    _earnings = <Map<String, dynamic>>[];
    _moods = <Map<String, dynamic>>[];
    _highlights = <Map<String, dynamic>>[];
  }
}
