// ================================================================
// ChittiChatHistoryService — survives the customer leaving the app
// mid-conversation, Aug 25 2026
// ================================================================
// Nizam's report: customer chats with Chitti, switches to another app
// on their phone, comes back — and the conversation (at least the last
// message) is gone.
//
// ROOT CAUSE: GuruChatScreen's `_messages` was a plain in-memory Dart
// list with NO persistence anywhere — not Hive, not Firestore. On a
// budget Android phone (this app's own asset-size comments elsewhere
// call out ₹8,000-class devices explicitly), backgrounding an app is
// exactly when Android is most likely to kill the process to reclaim
// RAM. The next "return" is a full cold start, not a resume — the
// entire in-memory list is gone, not just the last line. What Nizam
// perceived as "last message deleted" is that cold-start symptom.
//
// FIX: persist the whole conversation to Hive whenever the app is
// about to leave the foreground (see GuruChatScreen's
// didChangeAppLifecycleState — WidgetsBindingObserver fires
// AppLifecycleState.paused/inactive reliably BEFORE the OS has a
// chance to kill the process, which `dispose()` alone cannot
// guarantee: a killed process never runs dispose()). On the next open,
// GuruChatScreen asks whether to continue or start fresh, exactly like
// Nizam described.
//
// WHY SAVE THE WHOLE LIST ON EVERY BACKGROUND EVENT, NOT INCREMENTALLY
// PER MESSAGE
// Simpler and touches far fewer call sites (GuruChatScreen adds a
// message via `setState` in ~20 different places for different reply
// types). A single list overwrite on backgrounding is cheap — chat
// history here is capped at a normal conversation's length, nowhere
// near the "unbounded growth" concern that governs the shorter-lived
// ChittiMemoryService/ChittiOrderMemoryService caches.
//
// WHY A SEPARATE BOX FROM ChittiOrderMemoryService
// Different lifetime and purpose: order memory is a small permanent
// rolling summary fed into every prompt; this is one full
// conversation's transcript, replaced wholesale each time, and
// cleared the moment the customer picks "start new chat".
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ChittiChatHistoryService {
  ChittiChatHistoryService._();

  static const String _boxName = 'chitti_chat_history';
  static const String _messagesKey = 'messages';

  /// How many messages survive a save.
  ///
  /// Roughly a fortnight of steady use, and a payload measured in tens
  /// of KB rather than megabytes. See [saveChat] for why there is a cap
  /// at all.
  static const int maxSavedMessages = 300;

  static Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    await Hive.initFlutter();
    return Hive.openBox(_boxName);
  }

  /// True when there's a non-empty saved conversation waiting — used to
  /// decide whether to show the "continue or start new?" prompt at all.
  static Future<bool> hasSavedChat() async {
    try {
      final box = await _box();
      final raw = box.get(_messagesKey);
      return raw is List && raw.isNotEmpty;
    } catch (e) {
      debugPrint('[ChittiChatHistoryService] hasSavedChat failed: $e');
      return false;
    }
  }

  /// Each entry is {role, text, suggestions} — deliberately NOT
  /// imageBytes (a saved screenshot could be several hundred KB; a
  /// restored message just loses its thumbnail, which is an acceptable
  /// trade for not writing large binaries to Hive on every background
  /// event).
  static Future<List<Map<String, dynamic>>> loadSavedChat() async {
    try {
      final box = await _box();
      final raw = box.get(_messagesKey);
      if (raw is! List) return <Map<String, dynamic>>[];
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      debugPrint('[ChittiChatHistoryService] loadSavedChat failed: $e');
      return <Map<String, dynamic>>[];
    }
  }

  /// Overwrites the saved conversation. Fire-and-forget by contract —
  /// wrap in `unawaited(...)`; a save failure must never block or
  /// crash the lifecycle callback that triggers it.
  static Future<void> saveChat(List<Map<String, dynamic>> messages) async {
    try {
      final box = await _box();
      // Keep only the recent tail (self-audit, Aug 28 2026).
      //
      // This used to store every message ever sent. Nothing read the
      // whole thing, so nothing broke visibly — but the box is now part
      // of the Drive backup, and an unbounded box means a backup that
      // grows forever, uploaded from a phone on mobile data into the
      // CUSTOMER's own Drive quota. A daily chatter would eventually be
      // paying, in bytes and battery, for messages from months ago that
      // no screen shows.
      //
      // The tail is kept, not the head: continuity is about what was
      // just said.
      final trimmed = messages.length > maxSavedMessages
          ? messages.sublist(messages.length - maxSavedMessages)
          : messages;
      await box.put(_messagesKey, trimmed);
    } catch (e) {
      debugPrint('[ChittiChatHistoryService] saveChat failed: $e');
    }
  }

  // ── PAST CHATS (Aug 28 2026 — Nizam: "all apps kum ithukumunnadi
  // chitti kita pannuna chat ah pakka history oru button ah new chat
  // la vei") ──────────────────────────────────────────────────────
  //
  // THE BUG THIS FIXES
  // "New chat" called clear(), which DELETED the conversation. Every
  // time anyone started a fresh chat, everything Chitti had been told
  // before was destroyed — and Chitti's whole premise is that it
  // remembers you. Somebody who explained their address once, then
  // tapped New chat, had simply lost it.
  //
  // Archiving instead of deleting is the entire change. Nothing else
  // about the live conversation moves.
  //
  // WHY A CAP ON SESSIONS TOO
  // Same reason single-chat messages are capped (see [saveChat]): this
  // box rides along in the Drive backup, into the CUSTOMER's own quota.
  // Twenty sessions is more than anyone scrolls back through and still
  // measures in tens of KB.

  static const String _sessionsKey = 'sessions';

  /// How many past conversations are kept.
  static const int maxSavedSessions = 20;

  /// Files the current conversation away and clears the live one.
  ///
  /// This is what "New chat" calls now. An empty conversation is not
  /// archived — a stray tap on New chat should not fill the history
  /// list with blanks.
  static Future<void> archiveCurrentAndStartNew() async {
    try {
      final box = await _box();
      final raw = box.get(_messagesKey);
      if (raw is List && raw.isNotEmpty) {
        final sessions = _readSessions(box);
        sessions.insert(0, <String, dynamic>{
          'savedAt': DateTime.now().toIso8601String(),
          'title': _titleFor(raw),
          'messages': raw,
        });
        // Newest first, so the trim drops the oldest.
        await box.put(
          _sessionsKey,
          sessions.take(maxSavedSessions).toList(),
        );
      }
      await box.delete(_messagesKey);
    } catch (e) {
      debugPrint('[ChittiChatHistoryService] archive failed: $e');
    }
  }

  /// Past conversations, newest first.
  static Future<List<ChittiChatSession>> pastSessions() async {
    try {
      final box = await _box();
      return _readSessions(box)
          .map(ChittiChatSession.fromMap)
          .where((s) => s.messages.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[ChittiChatHistoryService] pastSessions failed: $e');
      return <ChittiChatSession>[];
    }
  }

  /// Makes one past conversation the live one again.
  ///
  /// The conversation currently open is archived first, not discarded:
  /// reopening an old chat must never be a way to lose the one you
  /// were just having.
  static Future<List<Map<String, dynamic>>> resumeSession(int index) async {
    try {
      final box = await _box();
      final sessions = _readSessions(box);
      if (index < 0 || index >= sessions.length) {
        return <Map<String, dynamic>>[];
      }

      // Read the chosen session BEFORE archiving, not after.
      //
      // Archiving inserts at position 0, so every index shifts by one
      // — but ONLY when there was something to archive. Compensating
      // for that shift unconditionally opens the wrong conversation
      // whenever the live chat was empty, which is the common case:
      // tap New chat, then tap History. It fails silently and
      // confidently, which is the worst way for it to fail.
      final picked = Map<String, dynamic>.from(sessions[index]);
      await archiveCurrentAndStartNew();

      final msgs = (picked['messages'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          <Map<String, dynamic>>[];
      await saveChat(msgs);
      return msgs;
    } catch (e) {
      debugPrint('[ChittiChatHistoryService] resumeSession failed: $e');
      return <Map<String, dynamic>>[];
    }
  }

  /// Forgets every past conversation. The live one is untouched.
  static Future<void> clearHistory() async {
    try {
      final box = await _box();
      await box.delete(_sessionsKey);
    } catch (e) {
      debugPrint('[ChittiChatHistoryService] clearHistory failed: $e');
    }
  }

  static List<Map<String, dynamic>> _readSessions(Box box) {
    final raw = box.get(_sessionsKey);
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// A one-line label for the history list.
  ///
  /// The customer's FIRST message, not the last and not Chitti's
  /// greeting: what someone remembers about a conversation is what
  /// they came to ask.
  @visibleForTesting
  static String titleFor(List<dynamic> messages) => _titleFor(messages);

  static String _titleFor(List<dynamic> messages) {
    for (final m in messages) {
      if (m is! Map) continue;
      if ((m['role'] as String?) != 'user') continue;
      final t = (m['text'] as String?)?.trim() ?? '';
      if (t.isEmpty) continue;
      return t.length > 60 ? '${t.substring(0, 60)}…' : t;
    }
    return 'Chat with Chitti';
  }

  /// Called when the customer explicitly starts a new chat, or after
  /// they choose "start new" on the continue/new prompt.
  ///
  /// Prefer [archiveCurrentAndStartNew]. This still exists for the
  /// places that genuinely mean "forget this", and for the Drive
  /// restore path.
  static Future<void> clear() async {
    try {
      final box = await _box();
      await box.delete(_messagesKey);
    } catch (e) {
      debugPrint('[ChittiChatHistoryService] clear failed: $e');
    }
  }
}

/// One archived conversation, as the history list needs it.
@immutable
class ChittiChatSession {
  const ChittiChatSession({
    required this.title,
    required this.messages,
    this.savedAt,
  });

  factory ChittiChatSession.fromMap(Map<String, dynamic> m) {
    return ChittiChatSession(
      title: (m['title'] as String?) ?? 'Chat with Chitti',
      savedAt: DateTime.tryParse((m['savedAt'] as String?) ?? ''),
      messages: (m['messages'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          const <Map<String, dynamic>>[],
    );
  }

  final String title;
  final DateTime? savedAt;
  final List<Map<String, dynamic>> messages;

  /// "28/8 14:05" — enough to tell two conversations apart.
  String get whenLabel {
    final at = savedAt;
    if (at == null) return '';
    return '${at.day}/${at.month} '
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
  }
}
