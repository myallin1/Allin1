// ================================================================
// chitti_chat_history_cap_test.dart
// ================================================================
// NEW (Aug 28 2026, self-audit).
//
// Chat history was stored without a limit. On its own that was
// harmless — nothing read the whole box. It stopped being harmless
// when the box joined the Drive backup: an unbounded box means a
// backup that grows forever, uploaded from the customer's phone into
// the CUSTOMER's own 15GB Drive quota. A daily user would eventually
// spend bytes and battery re-uploading months of messages no screen
// ever shows.
//
// This pins the cap and, more importantly, pins WHICH end survives.
// Trimming the wrong end would leave Chitti "remembering" the oldest
// conversation and forgetting what was said a minute ago — which is
// the exact opposite of the continuity the feature exists for.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:erode_superapp/services/chitti_chat_history_service.dart';

void main() {
  // Hive needs a home in a unit test; it does not need a device.
  // Each test starts from an empty box so a cap assertion cannot pass
  // on leftovers from the test before it.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Hive.init(Directory.systemTemp.createTempSync('chitti_hist_test').path);
    // Open the box HERE so the service's own _box() takes its
    // isBoxOpen() short-circuit. Left closed, _box() falls through to
    // Hive.initFlutter(), which asks path_provider for the documents
    // directory — a plugin with no implementation in a unit test.
    await Hive.openBox<dynamic>('chitti_chat_history');
  });

  setUp(() async {
    await ChittiChatHistoryService.clear();
  });

  List<Map<String, dynamic>> messages(int n) => List.generate(
        n,
        (i) => <String, dynamic>{'role': 'user', 'text': 'm$i'},
      );

  test('a short conversation is stored whole', () async {
    await ChittiChatHistoryService.saveChat(messages(5));
    final loaded = await ChittiChatHistoryService.loadSavedChat();
    expect(loaded.length, 5);
    expect(loaded.first['text'], 'm0');
  });

  test('a long conversation is capped', () async {
    await ChittiChatHistoryService.saveChat(
      messages(ChittiChatHistoryService.maxSavedMessages + 250),
    );
    final loaded = await ChittiChatHistoryService.loadSavedChat();
    expect(loaded.length, ChittiChatHistoryService.maxSavedMessages);
  });

  test('the RECENT end survives, not the oldest', () async {
    const extra = 40;
    final total = ChittiChatHistoryService.maxSavedMessages + extra;
    await ChittiChatHistoryService.saveChat(messages(total));
    final loaded = await ChittiChatHistoryService.loadSavedChat();

    // The very last thing said must still be there — that is what
    // "continue where we left off" means.
    expect(loaded.last['text'], 'm${total - 1}');
    // And the oldest must be the one dropped.
    expect(loaded.first['text'], 'm$extra');
  });

  test('saving exactly at the cap changes nothing', () async {
    // Off-by-one guard: sublist() at the boundary is where a trim
    // silently loses one message every save, which would quietly erode
    // a long conversation over a day of use.
    await ChittiChatHistoryService.saveChat(
      messages(ChittiChatHistoryService.maxSavedMessages),
    );
    final loaded = await ChittiChatHistoryService.loadSavedChat();
    expect(loaded.length, ChittiChatHistoryService.maxSavedMessages);
    expect(loaded.first['text'], 'm0');
  });
}
