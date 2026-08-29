// ================================================================
// ChittiOrderMemoryService — "what did this customer recently order"
// Allin1 (Aug 25 2026 — Super Chitti Phase 1, Step 2)
// ================================================================
// Deliberately separate from ChittiMemoryService (which is SESSION-
// scoped — cleared the moment a service ends, see that file's header).
// This one is the opposite on purpose: a small ROLLING HISTORY that
// survives app restarts, so Chitti can open a brand-new session and
// still say "should I book your usual bike ride to the shop?".
//
// WHY HIVE AND NOT FIRESTORE
// Same Spark-plan-budget reasoning HiveCache documents: this is a
// tiny, purely-local convenience cache, not a durable record (the
// real order/ride documents already live in Firestore). Writing it
// to Hive costs nothing and needs no network.
//
// WHY A ROLLING WINDOW OF 5, NOT THE FULL HISTORY
// Same reasoning as ChittiMemoryService.kMaxTurns: this is injected
// into EVERY prompt, so it must stay a handful of short lines, not an
// ever-growing order log. Oldest entries are dropped, not kept.
//
// WHY AN IN-MEMORY CACHE ON TOP OF THE HIVE BOX
// buildPromptContext()-style callers need this synchronously (system
// prompt construction is not async in guru_api_service.dart), so this
// follows the exact "warm in-memory index, refreshed off the message
// path" contract chitti_memory_service.dart already documents for its
// knowledgeLookup hook: preload() once at boot (see main_customer.dart
// boot phase 1, right after Hive.initFlutter()), then record() keeps
// both the box and the cache in sync on every write.
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ChittiOrderMemoryService {
  ChittiOrderMemoryService._();

  static const String _boxName = 'chitti_order_memory';
  static const String _entriesKey = 'entries';

  /// Hard ceiling on remembered orders — see file header for why.
  static const int kMaxEntries = 5;

  static List<Map<String, dynamic>> _cache = <Map<String, dynamic>>[];

  static Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    // Idempotent, same as HiveCache._box() — safe even if another
    // entrypoint (hero/seller) already called this.
    await Hive.initFlutter();
    return Hive.openBox(_boxName);
  }

  static List<Map<String, dynamic>> _readEntries(Box box) {
    final raw = box.get(_entriesKey);
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Call once at boot (after Hive.initFlutter()) so recentSummary()
  /// can stay synchronous. Safe to skip — callers just see no history
  /// until the next record() call warms the cache anyway.
  static Future<void> preload() async {
    try {
      final box = await _box();
      _cache = _readEntries(box);
    } catch (e) {
      debugPrint('[ChittiOrderMemoryService] preload failed: $e');
    }
  }

  /// Records one completed transaction. Fire-and-forget from a
  /// completion flow (wrap in `unawaited(...)`) — a memory-write
  /// failure must never block the real order/ride completion it's
  /// describing.
  ///
  /// [service] is a short key like 'bike', 'auto', 'cab', 'food',
  /// 'grocery' — matches the vocabulary already used elsewhere
  /// (VoiceService, book_transport's tool enum) so Chitti doesn't have
  /// to reconcile two different naming schemes.
  /// [summary] is a short human-readable phrase, e.g. "to Chamunda
  /// Spares" or "2 plate chicken biryani from Annapoorna Hotel".
  static Future<void> record({
    required String service,
    required String summary,
  }) async {
    final trimmedService = service.trim();
    final trimmedSummary = summary.trim();
    if (trimmedService.isEmpty || trimmedSummary.isEmpty) return;
    try {
      final box = await _box();
      final entries = _readEntries(box)
        ..add({
          'service': trimmedService,
          'summary': trimmedSummary,
          'at': DateTime.now().millisecondsSinceEpoch,
        });
      if (entries.length > kMaxEntries) {
        entries.removeRange(0, entries.length - kMaxEntries);
      }
      await box.put(_entriesKey, entries);
      _cache = entries;
    } catch (e) {
      debugPrint('[ChittiOrderMemoryService] record failed: $e');
    }
  }

  /// Compact, most-recent-first block ready to drop into a system
  /// prompt. Empty string when nothing has been recorded yet (new
  /// customer, or cache not warmed) — callers should omit the section
  /// entirely rather than print an empty header.
  static String recentSummary() {
    if (_cache.isEmpty) return '';
    final lines = _cache.reversed
        .map((e) => '- ${e['service']}: ${e['summary']}')
        .join('\n');
    return "Customer's recent orders (most recent first, use this to "
        'greet them personally or suggest a repeat booking — never '
        'claim one of these is happening again unless they ask):\n'
        '$lines';
  }

  /// The single most recent recorded order, or null if there's none
  /// yet. Raw (unformatted) — for a caller that needs to make a
  /// DECISION off it (e.g. "is this recent enough to suggest a
  /// repeat?"), unlike recentSummary()'s prompt-ready text block.
  static Map<String, dynamic>? mostRecentEntry() {
    if (_cache.isEmpty) return null;
    return _cache.last;
  }

  static void clearForTesting() {
    _cache = <Map<String, dynamic>>[];
  }
}
