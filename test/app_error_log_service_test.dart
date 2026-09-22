// ================================================================
// app_error_log_service_test.dart
// ================================================================
import 'dart:io';

import 'package:erode_superapp/services/app_error_log_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('app_error_log_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>(AppErrorLogService.boxName);
    await AppErrorLogService.clearAll();
  });

  tearDown(() async {
    if (Hive.isBoxOpen(AppErrorLogService.boxName)) {
      await Hive.box<dynamic>(AppErrorLogService.boxName).close();
    }
    await Hive.deleteBoxFromDisk(AppErrorLogService.boxName);
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('AppErrorLogService core recording', () {
    test('records a new error entry into local Hive store', () async {
      final entry = await AppErrorLogService.logError(
        message: 'Null check operator used on null',
        stack: 'package:erode_superapp/billing_screen.dart:42',
        screen: 'Billing Screen',
      );

      expect(entry, isNotNull);
      expect(entry!.errorMessage, 'Null check operator used on null');
      expect(entry.screen, 'Billing Screen');
      expect(entry.severity, 'ERROR');
      expect(entry.repeatCount, 1);

      final stored = await AppErrorLogService.getLogById(entry.id);
      expect(stored, isNotNull);
      expect(stored!.id, entry.id);
    });

    test('deduplicates identical error on same screen within 5 minutes',
        () async {
      final first = await AppErrorLogService.logError(
        message: 'Network timeout during checkout',
        screen: 'Order Screen',
      );
      expect(first, isNotNull);
      expect(first!.repeatCount, 1);

      // Same error and screen immediately after
      final second = await AppErrorLogService.logError(
        message: 'Network timeout during checkout',
        screen: 'Order Screen',
      );

      expect(second, isNotNull);
      expect(second!.id, first.id); // Reuses the same entry
      expect(second.repeatCount, 2); // Increments counter

      final box = Hive.box<dynamic>(AppErrorLogService.boxName);
      expect(box.length, 1); // Only 1 entry stored, no bloat
    });

    test('creates separate entries for different screens or errors',
        () async {
      final e1 = await AppErrorLogService.logError(
        message: 'Error A',
        screen: 'Screen 1',
      );
      final e2 = await AppErrorLogService.logError(
        message: 'Error B',
        screen: 'Screen 1',
      );
      final e3 = await AppErrorLogService.logError(
        message: 'Error A',
        screen: 'Screen 2',
      );

      expect(e1!.id, isNot(e2!.id));
      expect(e1.id, isNot(e3!.id));

      final box = Hive.box<dynamic>(AppErrorLogService.boxName);
      expect(box.length, 3);
    });
  });

  group('Capacity and size discipline', () {
    test('truncates oversized stack traces to maxStackTraceChars', () async {
      final longStack = 'a' * 5000;
      final entry = await AppErrorLogService.logError(
        message: 'Stack test',
        stack: longStack,
        screen: 'Test Screen',
      );

      expect(entry, isNotNull);
      expect(
        entry!.stackTrace.length,
        lessThanOrEqualTo(AppErrorLogService.maxStackTraceChars + 30),
      );
      expect(entry.stackTrace, contains('[truncated]'));
    });

    test('prunes oldest entries when capacity exceeds maxEntries', () async {
      final box = Hive.box<dynamic>(AppErrorLogService.boxName);

      // Pre-fill box with fake older entries
      final now = DateTime.now();
      for (int i = 0; i < 505; i++) {
        final date = now.subtract(Duration(minutes: 600 - i));
        final id = 'err_old_$i';
        await box.put(id, {
          'id': id,
          'date': '2026-09-18',
          'timestamp': date.toIso8601String(),
          'severity': 'ERROR',
          'screen': 'Screen_$i',
          'errorMessage': 'Error_$i',
          'stackTrace': '',
          'appVersion': '1.0.0',
          'repeatCount': 1,
          'lastSeenAt': date.toIso8601String(),
        });
      }

      expect(box.length, 505);

      // Log a new error; capacity pruning should trigger
      await AppErrorLogService.logError(
        message: 'Trigger pruning',
        screen: 'New Screen',
      );

      // Must be capped at maxEntries
      expect(box.length, lessThanOrEqualTo(AppErrorLogService.maxEntries));
    });
  });

  group('Queries and daily summaries', () {
    test('computes accurate daily summary with counts and screen stats',
        () async {
      final now = DateTime.now();
      final todayStr =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      await AppErrorLogService.logError(
        message: 'Null error',
        severity: 'CRITICAL',
        screen: 'Billing',
      );
      await AppErrorLogService.logError(
        message: 'Timeout error',
        screen: 'Orders',
      );
      await AppErrorLogService.logError(
        message: 'Timeout error',
        screen: 'Orders',
      ); // Will dedupe to 2x
      await AppErrorLogService.logError(
        message: 'Render warning',
        severity: 'WARNING',
        screen: 'Home',
      );

      final summary = await AppErrorLogService.getDailySummary(todayStr);

      expect(summary.total, 4); // 1 critical + 2 errors + 1 warning
      expect(summary.criticalCount, 1);
      expect(summary.errorCount, 2);
      expect(summary.warningCount, 1);
      expect(summary.screenCounts['Orders'], 2);
      expect(summary.screenCounts['Billing'], 1);
      expect(summary.screenCounts['Home'], 1);
    });

    test('getLogsForDate filters correctly and ignores other dates', () async {
      final box = Hive.box<dynamic>(AppErrorLogService.boxName);

      // Insert an entry for yesterday
      await box.put('yesterday_1', {
        'id': 'yesterday_1',
        'date': '2026-09-17',
        'timestamp': '2026-09-17T10:00:00.000',
        'severity': 'ERROR',
        'screen': 'Old Screen',
        'errorMessage': 'Old error',
        'stackTrace': '',
        'appVersion': '1.0.0',
        'repeatCount': 1,
        'lastSeenAt': '2026-09-17T10:00:00.000',
      });

      // Insert an entry for today
      await box.put('today_1', {
        'id': 'today_1',
        'date': '2026-09-18',
        'timestamp': '2026-09-18T10:00:00.000',
        'severity': 'ERROR',
        'screen': 'Today Screen',
        'errorMessage': 'Today error',
        'stackTrace': '',
        'appVersion': '1.0.0',
        'repeatCount': 1,
        'lastSeenAt': '2026-09-18T10:00:00.000',
      });

      final todayLogs = await AppErrorLogService.getLogsForDate('2026-09-18');
      expect(todayLogs.length, 1);
      expect(todayLogs.first.id, 'today_1');

      final yesterdayLogs =
          await AppErrorLogService.getLogsForDate('2026-09-17');
      expect(yesterdayLogs.length, 1);
      expect(yesterdayLogs.first.id, 'yesterday_1');
    });
  });

  group('Auth context tracking', () {
    test('AppErrorLogEntry serializes and deserializes auth fields', () {
      final entry = AppErrorLogEntry(
        id: 'test_auth_1',
        date: '2026-09-19',
        timestamp: '2026-09-19T00:00:00.000',
        severity: 'ERROR',
        screen: 'Admin Screen',
        errorMessage: 'Permission denied',
        stackTrace: '',
        appVersion: '1.0.9+284',
        lastSeenAt: '2026-09-19T00:00:00.000',
        authUid: 'admin_uid_123',
        authEmail: 'admin@allin1.com',
        hasAdminClaim: true,
      );

      final map = entry.toMap();
      expect(map['authUid'], 'admin_uid_123');
      expect(map['authEmail'], 'admin@allin1.com');
      expect(map['hasAdminClaim'], true);

      final reconstructed = AppErrorLogEntry.fromMap(map);
      expect(reconstructed.authUid, 'admin_uid_123');
      expect(reconstructed.authEmail, 'admin@allin1.com');
      expect(reconstructed.hasAdminClaim, true);
    });

    test('logError records auth fields into Hive and retrieves them', () async {
      final entry = await AppErrorLogService.logError(
        message: 'Permission denied in dispatch',
        screen: 'Hero Dispatch',
        authUid: 'admin_xyz',
        authEmail: 'admin_xyz@allin1.com',
        hasAdminClaim: false,
      );

      expect(entry, isNotNull);
      expect(entry!.authUid, 'admin_xyz');
      expect(entry.authEmail, 'admin_xyz@allin1.com');
      expect(entry.hasAdminClaim, false);

      final stored = await AppErrorLogService.getLogById(entry.id);
      expect(stored, isNotNull);
      expect(stored!.authUid, 'admin_xyz');
      expect(stored.authEmail, 'admin_xyz@allin1.com');
      expect(stored.hasAdminClaim, false);
    });

    test('logError defaults auth fields to null without failing when unauthenticated/uninitialized', () async {
      final entry = await AppErrorLogService.logError(
        message: 'Generic unauthenticated error',
        screen: 'Splash',
      );

      expect(entry, isNotNull);
      expect(entry!.authUid, isNull);
      expect(entry.authEmail, isNull);
      expect(entry.hasAdminClaim, isNull);
    });
  });

  group('Cross-app variant, category and resolution tracking', () {
    test('AppErrorLogEntry serializes and deserializes variant, category and resolved', () {
      final entry = AppErrorLogEntry(
        id: 'err_variant_test',
        date: '2026-09-19',
        timestamp: '2026-09-19T10:00:00.000',
        severity: 'ERROR',
        screen: 'Seller Menu Screen',
        errorMessage: 'Failed to update item price',
        stackTrace: 'stack...',
        appVersion: '1.0.0',
        lastSeenAt: '2026-09-19T10:00:00.000',
        appVariant: 'seller',
        category: 'network',
        resolved: true,
        osPlatform: 'android',
      );

      final map = entry.toMap();
      expect(map['appVariant'], 'seller');
      expect(map['category'], 'network');
      expect(map['resolved'], true);
      expect(map['osPlatform'], 'android');

      final reconstructed = AppErrorLogEntry.fromMap(map);
      expect(reconstructed.appVariant, 'seller');
      expect(reconstructed.category, 'network');
      expect(reconstructed.resolved, true);
      expect(reconstructed.osPlatform, 'android');
    });

    test('inferCategory correctly categorizes various error patterns', () {
      expect(
        AppErrorLogService.inferCategory(message: 'SocketException: Connection refused'),
        'network',
      );
      expect(
        AppErrorLogService.inferCategory(message: 'Cloud Firestore error: permission-denied'),
        'permission',
      );
      expect(
        AppErrorLogService.inferCategory(message: 'A RenderFlex overflowed by 24 pixels on the bottom.'),
        'ui',
      );
      expect(
        AppErrorLogService.inferCategory(message: 'PhonePe payment checkout cancelled'),
        'payment',
      );
      expect(
        AppErrorLogService.inferCategory(message: 'Geolocator location permission denied'),
        'location',
      );
      expect(
        AppErrorLogService.inferCategory(message: 'Unhandled Exception: Null check operator used on null value'),
        'crash',
      );
    });

    test('logError records custom appVariant and category into local store', () async {
      final entry = await AppErrorLogService.logError(
        message: 'SocketException during hero accept',
        screen: 'Hero Accept Dialog',
        appVariant: 'hero',
        category: 'network',
      );

      expect(entry, isNotNull);
      expect(entry!.appVariant, 'hero');
      expect(entry.category, 'network');

      final stored = await AppErrorLogService.getLogById(entry.id);
      expect(stored, isNotNull);
      expect(stored!.appVariant, 'hero');
      expect(stored.category, 'network');
    });
  });
}
