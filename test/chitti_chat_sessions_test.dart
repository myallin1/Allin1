// ================================================================
// chitti_chat_sessions_test.dart
// ================================================================
// NEW (Aug 28 2026 — Nizam: "all apps kum ithukumunnadi chitti kita
// pannuna chat ah pakka history oru button ah new chat la vei").
//
// THE BUG THIS PINS SHUT
// "New chat" called clear(), which DELETED the conversation. The app
// whose entire premise is that Chitti remembers you destroyed that
// memory every time anyone tapped New chat, with no way back. These
// tests exist so nobody quietly restores that behaviour while tidying.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:erode_superapp/services/chitti_chat_history_service.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Hive.init(Directory.systemTemp.createTempSync('chitti_sessions').path);
    // Opened here so the service's _box() takes its isBoxOpen()
    // short-circuit instead of falling through to Hive.initFlutter(),
    // which needs path_provider.
    await Hive.openBox<dynamic>('chitti_chat_history');
  });

  setUp(() async {
    await ChittiChatHistoryService.clear();
    await ChittiChatHistoryService.clearHistory();
  });

  List<Map<String, dynamic>> chat(String ask) => [
        {'role': 'user', 'text': ask, 'suggestions': <String>[]},
        {'role': 'assistant', 'text': 'Sure.', 'suggestions': <String>[]},
      ];

  group('new chat archives instead of deleting', () {
    test('the old conversation survives', () async {
      await ChittiChatHistoryService.saveChat(chat('where is my order'));
      await ChittiChatHistoryService.archiveCurrentAndStartNew();

      // The live chat is empty...
      expect(await ChittiChatHistoryService.hasSavedChat(), isFalse);
      // ...but nothing was lost.
      final past = await ChittiChatHistoryService.pastSessions();
      expect(past, hasLength(1));
      expect(past.first.messages, hasLength(2));
    });

    test('archiving an EMPTY chat files nothing', () async {
      // A stray tap on New chat must not fill the list with blanks.
      await ChittiChatHistoryService.archiveCurrentAndStartNew();
      expect(await ChittiChatHistoryService.pastSessions(), isEmpty);
    });

    test('sessions come back newest first', () async {
      await ChittiChatHistoryService.saveChat(chat('first thing'));
      await ChittiChatHistoryService.archiveCurrentAndStartNew();
      await ChittiChatHistoryService.saveChat(chat('second thing'));
      await ChittiChatHistoryService.archiveCurrentAndStartNew();

      final past = await ChittiChatHistoryService.pastSessions();
      expect(past, hasLength(2));
      expect(past.first.title, contains('second'));
    });

    test('old sessions are capped so the backup cannot grow forever', () async {
      // This box rides along in the customer's own Drive quota — same
      // reason single-chat messages are capped.
      for (var i = 0; i < ChittiChatHistoryService.maxSavedSessions + 6; i++) {
        await ChittiChatHistoryService.saveChat(chat('question $i'));
        await ChittiChatHistoryService.archiveCurrentAndStartNew();
      }
      final past = await ChittiChatHistoryService.pastSessions();
      expect(past, hasLength(ChittiChatHistoryService.maxSavedSessions));
      // The NEWEST survive, not the oldest.
      expect(past.first.title, contains('${ChittiChatHistoryService.maxSavedSessions + 5}'));
    });
  });

  group('reopening a past chat', () {
    test('brings its messages back', () async {
      await ChittiChatHistoryService.saveChat(chat('book an auto'));
      await ChittiChatHistoryService.archiveCurrentAndStartNew();

      final resumed = await ChittiChatHistoryService.resumeSession(0);
      expect(resumed, hasLength(2));
      expect(resumed.first['text'], 'book an auto');
      // And it is now the live conversation.
      expect(await ChittiChatHistoryService.hasSavedChat(), isTrue);
    });

    test('does not throw away the chat you were just having', () async {
      await ChittiChatHistoryService.saveChat(chat('old one'));
      await ChittiChatHistoryService.archiveCurrentAndStartNew();
      await ChittiChatHistoryService.saveChat(chat('the live one'));

      await ChittiChatHistoryService.resumeSession(0);

      // Opening an old chat must never be a way to lose the current
      // one — it is archived, not discarded.
      final past = await ChittiChatHistoryService.pastSessions();
      expect(
        past.any((s) => s.title.contains('the live one')),
        isTrue,
        reason: 'the in-progress chat was destroyed by opening an old one',
      );
    });

    test('opens the RIGHT one when the live chat is empty', () async {
      // The index shift trap: resuming archives the live chat first,
      // which pushes every past session down by one. If the live chat
      // was EMPTY nothing is archived and nothing shifts — so an
      // implementation that always compensates opens the wrong
      // conversation, silently and confidently.
      await ChittiChatHistoryService.saveChat(chat('alpha'));
      await ChittiChatHistoryService.archiveCurrentAndStartNew();
      await ChittiChatHistoryService.saveChat(chat('beta'));
      await ChittiChatHistoryService.archiveCurrentAndStartNew();
      // Live chat is now empty. past = [beta, alpha].

      final resumed = await ChittiChatHistoryService.resumeSession(0);
      expect(resumed.first['text'], 'beta');
    });

    test('an out-of-range index is a no-op, not a crash', () async {
      expect(await ChittiChatHistoryService.resumeSession(99), isEmpty);
      expect(await ChittiChatHistoryService.resumeSession(-1), isEmpty);
    });
  });

  group('the history list is readable', () {
    test('a session is titled by what the USER asked', () {
      // Not Chitti's greeting and not the last line: what someone
      // remembers about a conversation is what they came to ask.
      expect(
        ChittiChatHistoryService.titleFor([
          {'role': 'assistant', 'text': 'Good morning boss!'},
          {'role': 'user', 'text': 'where is my parcel'},
        ]),
        'where is my parcel',
      );
    });

    test('a long question is trimmed rather than wrapped forever', () {
      final t = ChittiChatHistoryService.titleFor([
        {'role': 'user', 'text': 'a' * 200},
      ]);
      expect(t.length, lessThanOrEqualTo(61));
      expect(t, endsWith('…'));
    });

    test('a chat with no user text still gets a name', () {
      expect(
        ChittiChatHistoryService.titleFor([
          {'role': 'assistant', 'text': 'Hello'},
        ]),
        'Chat with Chitti',
      );
    });
  });

  group('clearing history', () {
    test('removes the past but keeps the live chat', () async {
      await ChittiChatHistoryService.saveChat(chat('old'));
      await ChittiChatHistoryService.archiveCurrentAndStartNew();
      await ChittiChatHistoryService.saveChat(chat('current'));

      await ChittiChatHistoryService.clearHistory();

      expect(await ChittiChatHistoryService.pastSessions(), isEmpty);
      expect(await ChittiChatHistoryService.hasSavedChat(), isTrue);
    });
  });
}
