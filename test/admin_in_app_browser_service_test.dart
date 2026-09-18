// ================================================================
// admin_in_app_browser_service_test.dart
// ================================================================
import 'dart:io';

import 'package:erode_superapp/services/admin_in_app_browser_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('admin_browser_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>(AdminInAppBrowserService.boxName);
    await AdminInAppBrowserService.clearAll();
  });

  tearDown(() async {
    if (Hive.isBoxOpen(AdminInAppBrowserService.boxName)) {
      await Hive.box<dynamic>(AdminInAppBrowserService.boxName).close();
    }
    await Hive.deleteBoxFromDisk(AdminInAppBrowserService.boxName);
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('AdminBrowserHistoryEntry serialization', () {
    test('serializes and deserializes correctly', () {
      final entry = AdminBrowserHistoryEntry(
        id: 'hist_1',
        url: 'https://github.com/myallin1/Allin1/actions/runs/12345',
        title: 'CI Workflow #12345',
        timestamp: '2026-09-19T02:00:00.000',
        date: '2026-09-19',
        textContent: 'Run completed with status: SUCCESS\nLogs: all passed.',
        visitCount: 3,
        lastVisitedAt: '2026-09-19T02:30:00.000',
      );

      final map = entry.toMap();
      expect(map['id'], 'hist_1');
      expect(map['url'], contains('runs/12345'));
      expect(map['visitCount'], 3);
      expect(map['hasSnapshot'], isNull); // not in map, getter only

      final reconstructed = AdminBrowserHistoryEntry.fromMap(map);
      expect(reconstructed.id, 'hist_1');
      expect(reconstructed.url, entry.url);
      expect(reconstructed.title, entry.title);
      expect(reconstructed.textContent, entry.textContent);
      expect(reconstructed.visitCount, 3);
      expect(reconstructed.hasSnapshot, true);
    });
  });

  group('AdminInAppBrowserService core recording', () {
    test('records a new page visit with title and text snapshot', () async {
      final entry = await AdminInAppBrowserService.recordVisit(
        url: 'https://github.com/myallin1/Allin1/issues/42',
        title: 'Fix permission denied on hero dispatch',
        textContent: 'Issue description: Dispatch throws permission-denied.',
      );

      expect(entry, isNotNull);
      expect(entry!.url, 'https://github.com/myallin1/Allin1/issues/42');
      expect(entry.title, 'Fix permission denied on hero dispatch');
      expect(entry.textContent, contains('Dispatch throws'));
      expect(entry.visitCount, 1);

      final retrieved = await AdminInAppBrowserService.getEntryByUrl(
        'https://github.com/myallin1/Allin1/issues/42',
      );
      expect(retrieved, isNotNull);
      expect(retrieved!.id, entry.id);
    });

    test('re-visiting existing URL increments count and updates snapshot',
        () async {
      final first = await AdminInAppBrowserService.recordVisit(
        url: 'https://github.com/myallin1/Allin1/actions/runs/99',
        title: 'Running Build',
        textContent: 'Workflow running in step 2...',
      );
      expect(first, isNotNull);
      expect(first!.visitCount, 1);

      final second = await AdminInAppBrowserService.recordVisit(
        url: 'https://github.com/myallin1/Allin1/actions/runs/99',
        title: 'Passed Build #99',
        textContent: 'Workflow completed successfully.',
      );

      expect(second, isNotNull);
      expect(second!.id, first.id); // Reuses the same entry
      expect(second.visitCount, 2);
      expect(second.title, 'Passed Build #99');
      expect(second.textContent, contains('completed successfully'));

      final box = Hive.box<dynamic>(AdminInAppBrowserService.boxName);
      expect(box.length, 1); // No bloat, single entry kept
    });

    test('ignores empty URLs', () async {
      final entry = await AdminInAppBrowserService.recordVisit(url: '   ');
      expect(entry, isNull);
    });
  });

  group('Capacity and snapshot discipline', () {
    test('truncates oversized text snapshots to maxSnapshotChars', () async {
      final longText = 'x' * 60000;
      final entry = await AdminInAppBrowserService.recordVisit(
        url: 'https://github.com/huge-log',
        title: 'Huge Log',
        textContent: longText,
      );

      expect(entry, isNotNull);
      expect(
        entry!.textContent.length,
        lessThanOrEqualTo(AdminInAppBrowserService.maxSnapshotChars + 30),
      );
      expect(entry.textContent, contains('[snapshot truncated]'));
    });

    test('prunes oldest records when capacity exceeds maxEntries', () async {
      final box = Hive.box<dynamic>(AdminInAppBrowserService.boxName);

      // Pre-fill box with fake older entries
      final now = DateTime.now();
      for (int i = 0; i < 205; i++) {
        final date = now.subtract(Duration(minutes: 300 - i));
        final id = 'hist_old_$i';
        await box.put(id, {
          'id': id,
          'url': 'https://example.com/page_$i',
          'title': 'Page $i',
          'timestamp': date.toIso8601String(),
          'date': '2026-09-19',
          'textContent': 'Content $i',
          'visitCount': 1,
          'lastVisitedAt': date.toIso8601String(),
        });
      }

      expect(box.length, 205);

      // Record a new visit to trigger pruning
      await AdminInAppBrowserService.recordVisit(
        url: 'https://example.com/new_page',
        title: 'New Page',
      );

      // Must be capped at maxEntries
      expect(box.length, lessThanOrEqualTo(AdminInAppBrowserService.maxEntries));
    });
  });

  group('Queries and offline reading', () {
    test('getHistory returns entries sorted newest-first', () async {
      await AdminInAppBrowserService.recordVisit(
        url: 'https://example.com/page1',
        title: 'Page 1',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await AdminInAppBrowserService.recordVisit(
        url: 'https://example.com/page2',
        title: 'Page 2',
      );

      final history = await AdminInAppBrowserService.getHistory();
      expect(history.length, 2);
      expect(history[0].url, 'https://example.com/page2');
      expect(history[1].url, 'https://example.com/page1');
    });

    test('searchHistory matches title, url, and content', () async {
      await AdminInAppBrowserService.recordVisit(
        url: 'https://github.com/myallin1/Allin1/pulls/10',
        title: 'PR #10: Offline Browser',
        textContent: 'Implements tabs and reader view.',
      );
      await AdminInAppBrowserService.recordVisit(
        url: 'https://github.com/myallin1/Allin1/issues/50',
        title: 'Bug: Crash on back press',
        textContent: 'Null safety in navigation delegate.',
      );

      final searchTitle =
          await AdminInAppBrowserService.searchHistory('Offline Browser');
      expect(searchTitle.length, 1);
      expect(searchTitle.first.title, contains('Offline Browser'));

      final searchContent =
          await AdminInAppBrowserService.searchHistory('Null safety');
      expect(searchContent.length, 1);
      expect(searchContent.first.url, contains('issues/50'));
    });

    test('deleteEntry and clearAll remove records properly', () async {
      final entry = await AdminInAppBrowserService.recordVisit(
        url: 'https://example.com/delete_me',
        title: 'To be deleted',
      );

      expect(entry, isNotNull);
      await AdminInAppBrowserService.deleteEntry(entry!.id);
      final fetched = await AdminInAppBrowserService.getEntryById(entry.id);
      expect(fetched, isNull);

      await AdminInAppBrowserService.recordVisit(
        url: 'https://example.com/remain',
        title: 'Remain',
      );
      await AdminInAppBrowserService.clearAll();

      final all = await AdminInAppBrowserService.getHistory();
      expect(all, isEmpty);
    });
  });
}
