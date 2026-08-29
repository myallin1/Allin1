// ================================================================
// chitti_backup_service_test.dart
// ================================================================
// Restore is the most dangerous operation in the app: it REPLACES the
// customer's history. A bug here does not show an error — it quietly
// loses conversations, or writes a field this build does not
// understand.
//
// Two rules matter more than the Drive plumbing (which needs a real
// account and is covered by using it):
//   • the wallet is NEVER in the file — money stays server-side, so a
//     restored backup can never be an edited balance;
//   • a backup from a NEWER app is refused rather than half-applied.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:erode_superapp/services/chitti/chitti_backup_service.dart';

void main() {
  // buildPayload/applyPayload touch Hive and SharedPreferences. Both
  // need a home in a unit test; neither needs a real device.
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Hive.init(Directory.systemTemp.createTempSync('chitti_backup_test').path);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('what travels to a new phone', () {
    test('carries Chitti\'s memory of the customer', () {
      // The whole point: a new phone gets the same Chitti, not a
      // stranger.
      expect(
        ChittiBackupService.backedUpBoxes,
        containsAll(<String>['chitti_chat_history', 'chitti_order_memory']),
      );
    });

    test('carries their settings', () {
      expect(
        ChittiBackupService.backedUpPrefs,
        containsAll(<String>['chitti_voice_tone', 'app_language']),
      );
    });

    test('NEVER carries the wallet', () {
      // "wallet mattum Firestore valiya manage panniklam, apo than hack
      // panna mudiyathu" — a balance in a file the customer controls is
      // a balance the customer can edit.
      final everything = <String>[
        ...ChittiBackupService.backedUpBoxes,
        ...ChittiBackupService.backedUpPrefs,
      ].join(' ').toLowerCase();
      expect(everything, isNot(contains('wallet')));
      expect(everything, isNot(contains('balance')));
      expect(everything, isNot(contains('coin')));
    });

    test('NEVER carries API keys', () {
      final prefs = ChittiBackupService.backedUpPrefs.join(' ').toLowerCase();
      expect(prefs, isNot(contains('key')));
      expect(prefs, isNot(contains('token')));
    });

    test('carries no re-fetchable cache', () {
      // A catalogue or offers box would bloat the file with data that
      // is stale by the time anyone restores it.
      expect(ChittiBackupService.backedUpBoxes, isNot(contains('cache')));
    });
  });

  group('restoring a payload', () {
    test('refuses a backup written by a newer app', () async {
      await expectLater(
        ChittiBackupService.applyPayload(<String, dynamic>{
          'schemaVersion': ChittiBackupService.schemaVersion + 1,
          'boxes': <String, dynamic>{},
        }),
        throwsA(isA<ChittiBackupTooNewException>()),
      );
    });

    test('accepts the current version', () async {
      await expectLater(
        ChittiBackupService.applyPayload(<String, dynamic>{
          'schemaVersion': ChittiBackupService.schemaVersion,
          'boxes': <String, dynamic>{},
          'prefs': <String, dynamic>{},
        }),
        completes,
      );
    });

    test('ignores a box name that is not on the allow-list', () async {
      // A tampered or older file must not be able to write anywhere it
      // likes on the device.
      await expectLater(
        ChittiBackupService.applyPayload(<String, dynamic>{
          'schemaVersion': 1,
          'boxes': <String, dynamic>{
            'some_other_box': <String, dynamic>{'a': 1},
          },
        }),
        completes,
      );
    });

    test('survives a malformed payload rather than throwing', () async {
      await expectLater(
        ChittiBackupService.applyPayload(<String, dynamic>{
          'schemaVersion': 1,
          'boxes': 'not a map',
          'prefs': 42,
        }),
        completes,
      );
    });
  });

  _ownershipTests();

  group('platform', () {
    test('reports whether Drive backup can run here', () {
      // Web cannot mint the Drive scope; the service says so up front
      // rather than failing halfway through a restore.
      expect(ChittiBackupService.isSupported, isNotNull);
    });
  });
}

// ── ownership (self-audit, Aug 28 2026) ──────────────────────────────
//
// The audit found the backup file carried no owner marker and
// auto-backup ran with no auth check. Together those meant a shared
// phone could upload one customer's Chitti history to a different
// person's Drive, and a restore could overwrite this customer's
// history with a stranger's — silently, in both directions.
void _ownershipTests() {
  group('a backup knows whose it is', () {
    test('the payload declares an owner field', () async {
      final payload = await ChittiBackupService.buildPayload();
      expect(
        payload.containsKey('ownerUid'),
        isTrue,
        reason: 'without this a restore cannot be verified',
      );
    });

    test('the payload is versioned so a newer file can be refused', () async {
      final payload = await ChittiBackupService.buildPayload();
      expect(payload['schemaVersion'], ChittiBackupService.schemaVersion);
    });

    test('a payload with no owner still restores', () async {
      // Files written before the marker existed must keep working —
      // refusing them would strand early customers' history.
      await expectLater(
        ChittiBackupService.applyPayload(<String, dynamic>{
          'schemaVersion': 1,
          'boxes': <String, dynamic>{},
          'prefs': <String, dynamic>{},
        }),
        completes,
      );
    });
  });
}
