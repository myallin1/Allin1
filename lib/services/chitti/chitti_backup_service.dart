// ================================================================
// chitti_backup_service.dart — the customer's data, in the customer's
// own Google Drive.
// ================================================================
// NEW (Aug 28 2026 — Nizam's WhatsApp model: "customer data a to z, a
// theme, work, usage history yellame avanga offline local database la
// irunthu ... avanga G.Drive ku backup kuduthukattum ... mobile
// maathumbothu backup kuduthuttu new mobile la restore pannikalam,
// ithunala customer kum namaku database wastage agathu").
//
// ── WHY DRIVE AND NOT OUR DATABASE ──────────────────────────────────
// Because it is their data and their storage quota, not ours. Every
// megabyte of chat history, order memory and preferences kept in
// Firestore is a bill we pay forever for something only one person
// will ever read. Drive moves that cost to where the data belongs and
// removes it from ours entirely — which is the whole point of the
// model, and the reason WhatsApp does exactly this.
//
// ── THE APP DATA FOLDER ─────────────────────────────────────────────
// Uploads go to Drive's `appDataFolder`, a private space the customer
// never sees in their Drive listing and no other app can read. That
// keeps a machine-readable backup file out of their documents while
// still being unambiguously theirs — they can revoke our access or
// delete the app data at any time from Google's own settings.
//
// ── WHAT IS AND IS NOT BACKED UP ────────────────────────────────────
// In:  Chitti's chat history and memory of them, order memory, recent
//      places, completed requests, theme, language and voice settings.
//      Nizam: "chitti relationship yellame avangavanga backup G.Drive
//      la store panikanum" — the point is that a new phone gets the
//      same Chitti, not a stranger.
// Out: THE WALLET. Money stays server-authoritative
//      ("apo than hack panna mudiyathu"). A balance restored from a
//      file the customer controls is a balance the customer can edit.
//
// ── PLATFORM ────────────────────────────────────────────────────────
// Drive backup: Android and iOS only. On web, google_sign_in cannot
// mint the Drive scope the same way and this reports itself
// unsupported rather than failing halfway through a restore — see
// [isSupported].
//
// Local file backup (backupToLocalFile/restoreFromLocalFile, added per
// Nizam's request for an offline path that isn't tied to a Google
// account at all): every platform FilePicker supports, web included —
// gated only on [_hasRealAccount], not [isSupported].
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chitti_order_memory_service.dart';

/// Thrown when the file on Drive was written by a newer build.
///
/// An Exception rather than a StateError on purpose: this is an
/// expected, recoverable outcome the UI shows to the customer, not a
/// programming mistake — and catching Errors is a lint for good reason.
class ChittiBackupTooNewException implements Exception {
  const ChittiBackupTooNewException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What a backup or restore ended up doing.
@immutable
class ChittiBackupResult {
  const ChittiBackupResult({
    required this.ok,
    required this.message,
    this.at,
  });

  final bool ok;
  final String message;
  final DateTime? at;
}

class ChittiBackupService {
  ChittiBackupService._();

  static final ChittiBackupService instance = ChittiBackupService._();

  static const String _fileName = 'myallin1_backup.json';
  static const String _lastBackupKey = 'chitti_last_backup_at';

  /// Format version, so a future change can migrate rather than
  /// silently restoring fields that no longer mean the same thing.
  static const int schemaVersion = 1;

  /// The Hive boxes that hold the customer's own history.
  ///
  /// Named explicitly rather than "every open box": a cache box
  /// (catalogues, offers) would bloat the backup with data that is
  /// re-fetchable and stale by the time anyone restores it.
  static const List<String> backedUpBoxes = <String>[
    'chitti_chat_history',
    'chitti_order_memory',
    'completed_service_requests',
    'recent_places',
  ];

  /// Preference keys worth carrying to a new phone.
  ///
  /// Deliberately a list and not "all prefs": prefs also hold one-shot
  /// flags (splash seen, migration gates) that must re-evaluate on new
  /// hardware, and API keys, which should never leave the device.
  static const List<String> backedUpPrefs = <String>[
    'chitti_voice_tone',
    'chitti_voice_name',
    'chitti_voice_locale',
    'chitti_welcome_enabled',
    'chitti_conversation_mode',
    'app_language',
    'theme_mode',
  ];

  static final GoogleSignIn _signIn = GoogleSignIn(
    scopes: <String>[drive.DriveApi.driveAppdataScope],
  );

  /// Drive backup needs a scope google_sign_in cannot mint on web.
  static bool get isSupported => !kIsWeb;

  /// The signed-in uid, or empty.
  ///
  /// Guarded: building a payload must never fail because Firebase is
  /// unavailable. An empty owner simply means the file cannot be
  /// ownership-checked on restore, which is the pre-marker behaviour
  /// and still better than no backup at all.
  static String _currentUid() {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (e) {
      debugPrint('[ChittiBackup] uid unavailable: $e');
      return '';
    }
  }

  /// A signed-in, non-anonymous account.
  ///
  /// Guests are excluded on both sides: a guest's backup has no account
  /// to restore into, and restoring INTO a guest session would hand one
  /// person's history to whoever picks the phone up next.
  static bool get _hasRealAccount {
    try {
      final user = FirebaseAuth.instance.currentUser;
      return user != null && !user.isAnonymous;
    } catch (e) {
      debugPrint('[ChittiBackup] auth unavailable: $e');
      return false;
    }
  }

  // ── the payload ──────────────────────────────────────────────────

  /// Collects everything worth keeping into one JSON map.
  ///
  /// Public and pure so it can be tested without Drive or Google
  /// sign-in anywhere near it.
  @visibleForTesting
  static Future<Map<String, dynamic>> buildPayload() async {
    final boxes = <String, dynamic>{};
    for (final name in backedUpBoxes) {
      try {
        final box = Hive.isBoxOpen(name)
            ? Hive.box<dynamic>(name)
            : await Hive.openBox<dynamic>(name);
        // toMap() keys can be ints (auto-increment boxes), and JSON
        // needs strings — encoded here rather than at restore so a
        // malformed box fails at backup time, where it is recoverable.
        boxes[name] = box.toMap().map(
              (k, v) => MapEntry(k.toString(), v),
            );
      } catch (e) {
        debugPrint('[ChittiBackup] skipped box $name: $e');
      }
    }

    final prefsOut = <String, dynamic>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in backedUpPrefs) {
        final value = prefs.get(key);
        if (value != null) prefsOut[key] = value;
      }
    } catch (e) {
      debugPrint('[ChittiBackup] prefs read failed: $e');
    }

    return <String, dynamic>{
      'schemaVersion': schemaVersion,
      'createdAt': DateTime.now().toIso8601String(),
      // WHOSE data this is (self-audit, Aug 28 2026).
      //
      // Without it a restore is unverifiable. A phone can be shared, and
      // the Google account signed into the device is not necessarily the
      // account signed into this app — so a file found in Drive is not
      // proof it belongs to whoever is using the app right now.
      // restoreNow() checks this before writing anything.
      'ownerUid': _currentUid(),
      'boxes': boxes,
      'prefs': prefsOut,
    };
  }

  /// Writes a payload back onto this device.
  @visibleForTesting
  static Future<void> applyPayload(Map<String, dynamic> payload) async {
    final version = (payload['schemaVersion'] as num?)?.toInt() ?? 0;
    if (version > schemaVersion) {
      // Written by a newer app. Restoring fields this build does not
      // understand is how you corrupt a customer's history.
      throw const ChittiBackupTooNewException(
        'This backup was made by a newer version of the app. '
        'Update MyAllin1 and try again.',
      );
    }

    final boxes = payload['boxes'];
    if (boxes is Map) {
      for (final entry in boxes.entries) {
        final name = entry.key.toString();
        if (!backedUpBoxes.contains(name)) continue;
        final data = entry.value;
        if (data is! Map) continue;
        try {
          final box = Hive.isBoxOpen(name)
              ? Hive.box<dynamic>(name)
              : await Hive.openBox<dynamic>(name);
          // Replace, not merge: a half-merged history would interleave
          // two phones' worth of conversation out of order.
          await box.clear();
          await box.putAll(data.map((k, v) => MapEntry(k.toString(), v)));
        } catch (e) {
          debugPrint('[ChittiBackup] restore of box $name failed: $e');
        }
      }
    }

    final prefs = payload['prefs'];
    if (prefs is Map) {
      try {
        final store = await SharedPreferences.getInstance();
        for (final entry in prefs.entries) {
          final key = entry.key.toString();
          if (!backedUpPrefs.contains(key)) continue;
          final value = entry.value;
          if (value is String) await store.setString(key, value);
          if (value is bool) await store.setBool(key, value);
          if (value is int) await store.setInt(key, value);
          if (value is double) await store.setDouble(key, value);
        }
      } catch (e) {
        debugPrint('[ChittiBackup] prefs restore failed: $e');
      }
    }

    // Rehydrate what is held in memory (self-audit, Aug 28 2026).
    //
    // Writing the Hive boxes is not enough: ChittiOrderMemoryService
    // keeps a static cache read once at boot, so without this the
    // customer restores their history and Chitti still does not
    // remember them until the app is killed and reopened — which is
    // precisely the moment the feature is supposed to prove itself.
    try {
      await ChittiOrderMemoryService.preload();
    } catch (e) {
      debugPrint('[ChittiBackup] memory reload failed: $e');
    }
  }

  // ── Drive ────────────────────────────────────────────────────────

  Future<drive.DriveApi?> _api({bool interactive = true}) async {
    if (!isSupported) return null;
    try {
      final account = interactive
          ? (await _signIn.signInSilently() ?? await _signIn.signIn())
          : await _signIn.signInSilently();
      if (account == null) return null;
      final client = await _signIn.authenticatedClient();
      if (client == null) return null;
      return drive.DriveApi(client);
    } catch (e) {
      debugPrint('[ChittiBackup] Drive auth failed: $e');
      return null;
    }
  }

  Future<String?> _findBackupId(drive.DriveApi api) async {
    try {
      final list = await api.files.list(
        q: "name = '$_fileName'",
        spaces: 'appDataFolder',
        $fields: 'files(id, modifiedTime)',
      );
      final files = list.files;
      if (files == null || files.isEmpty) return null;
      return files.first.id;
    } catch (e) {
      debugPrint('[ChittiBackup] lookup failed: $e');
      return null;
    }
  }

  /// Uploads a fresh backup, replacing any previous one.
  Future<ChittiBackupResult> backupNow() async {
    if (!isSupported) {
      return const ChittiBackupResult(
        ok: false,
        message: 'Backup works on the installed app, not in the browser.',
      );
    }
    if (!_hasRealAccount) {
      return const ChittiBackupResult(
        ok: false,
        message: 'Sign in first so the backup is saved under your account.',
      );
    }
    final api = await _api();
    if (api == null) {
      return const ChittiBackupResult(
        ok: false,
        message: 'Google sign-in was needed and did not complete.',
      );
    }

    try {
      final payload = await buildPayload();
      final bytes = utf8.encode(jsonEncode(payload));
      final media = drive.Media(Stream.value(bytes), bytes.length);

      final existingId = await _findBackupId(api);
      if (existingId == null) {
        await api.files.create(
          drive.File()
            ..name = _fileName
            ..parents = <String>['appDataFolder'],
          uploadMedia: media,
        );
      } else {
        // Update in place so the customer accumulates one backup, not
        // one per day forever inside their quota.
        await api.files.update(drive.File(), existingId, uploadMedia: media);
      }

      final now = DateTime.now();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastBackupKey, now.toIso8601String());
      } catch (_) {
        // A missing timestamp only affects what the settings screen
        // shows, never whether the backup happened.
      }
      return ChittiBackupResult(
        ok: true,
        message: 'Backed up to your Google Drive.',
        at: now,
      );
    } catch (e) {
      debugPrint('[ChittiBackup] backup failed: $e');
      return const ChittiBackupResult(
        ok: false,
        message: 'Could not back up just now. Please try again.',
      );
    }
  }

  /// Pulls the backup down and applies it.
  Future<ChittiBackupResult> restoreNow() async {
    if (!isSupported) {
      return const ChittiBackupResult(
        ok: false,
        message: 'Restore works on the installed app, not in the browser.',
      );
    }
    if (!_hasRealAccount) {
      return const ChittiBackupResult(
        ok: false,
        message: 'Sign in first so I know whose backup to restore.',
      );
    }
    final api = await _api();
    if (api == null) {
      return const ChittiBackupResult(
        ok: false,
        message: 'Google sign-in was needed and did not complete.',
      );
    }

    try {
      final id = await _findBackupId(api);
      if (id == null) {
        return const ChittiBackupResult(
          ok: false,
          message: 'No backup found in your Google Drive yet.',
        );
      }

      final media = await api.files.get(
        id,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final chunks = <int>[];
      await for (final chunk in media.stream) {
        chunks.addAll(chunk);
      }
      final payload = jsonDecode(utf8.decode(chunks)) as Map<String, dynamic>;

      // Whose backup is this? A shared phone, or a Google account that
      // is not the one signed into the app, can put someone else's file
      // in reach. Restoring it would overwrite this customer's history
      // with a stranger's — checked BEFORE anything is written.
      final owner = (payload['ownerUid'] as String?) ?? '';
      final me = _currentUid();
      if (owner.isNotEmpty && me.isNotEmpty && owner != me) {
        return const ChittiBackupResult(
          ok: false,
          message: 'That backup belongs to a different MyAllin1 account. '
              'Sign in with that account to restore it.',
        );
      }

      await applyPayload(payload);

      return ChittiBackupResult(
        ok: true,
        message: 'Restored. Chitti remembers you again.',
        at: DateTime.now(),
      );
    } on ChittiBackupTooNewException catch (e) {
      return ChittiBackupResult(ok: false, message: e.message);
    } catch (e) {
      debugPrint('[ChittiBackup] restore failed: $e');
      return const ChittiBackupResult(
        ok: false,
        message: 'Could not restore just now. Please try again.',
      );
    }
  }

  // ── Local file (file manager) ───────────────────────────────────
  //
  // NEW (per Nizam's request): a second, independent backup path — a
  // plain .json file the customer saves wherever they like (Downloads,
  // an SD card, WhatsApp to themselves, their own cloud drive app) via
  // the OS's own file picker, instead of only ours. Same payload,
  // same applyPayload() restore path as the Drive flow above; the only
  // difference is WHERE the bytes end up. Works on every platform
  // FilePicker supports, including web — unlike the Drive path, this
  // needs no Google sign-in at all.

  static String _localFileName() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'myallin1_backup_${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}.json';
  }

  /// Lets the customer save a backup file wherever they choose via the
  /// OS file picker (Downloads, SD card, another app via "Save to...").
  Future<ChittiBackupResult> backupToLocalFile() async {
    if (!_hasRealAccount) {
      return const ChittiBackupResult(
        ok: false,
        message: 'Sign in first so the backup is tied to your account.',
      );
    }
    try {
      final payload = await buildPayload();
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));

      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save MyAllin1 backup',
        fileName: _localFileName(),
        type: FileType.custom,
        allowedExtensions: <String>['json'],
        bytes: bytes,
      );

      // A null path/result means the customer backed out of the picker
      // — not a failure, just nothing to report as success either.
      if (savedPath == null) {
        return const ChittiBackupResult(
          ok: false,
          message: 'Backup cancelled.',
        );
      }

      final now = DateTime.now();
      try {
        final prefs = await SharedPreferences.getInstance();
        // Deliberately the SAME key the Drive path stamps — from the
        // customer's point of view there is one "backup", not two;
        // Settings should show whichever happened most recently
        // regardless of which button made it happen.
        await prefs.setString(_lastBackupKey, now.toIso8601String());
      } catch (_) {
        // A missing timestamp only affects what Settings displays.
      }

      return ChittiBackupResult(
        ok: true,
        message: 'Backup saved to your device.',
        at: now,
      );
    } catch (e) {
      debugPrint('[ChittiBackup] local backup failed: $e');
      return const ChittiBackupResult(
        ok: false,
        message: 'Could not save the backup file. Please try again.',
      );
    }
  }

  /// Lets the customer pick a previously saved backup file and restores
  /// from it — same ownership check and schema-version guard as the
  /// Drive restore, since this file can just as easily have come from
  /// someone else's phone (forwarded, shared folder, etc.).
  Future<ChittiBackupResult> restoreFromLocalFile() async {
    if (!_hasRealAccount) {
      return const ChittiBackupResult(
        ok: false,
        message: 'Sign in first so I know whose backup to restore.',
      );
    }
    try {
      // withData: true is required on mobile/web to get the bytes back
      // directly — without it, PlatformFile.bytes is null on platforms
      // that only hand back a content:// URI, not a real file path.
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose a MyAllin1 backup file',
        type: FileType.custom,
        allowedExtensions: <String>['json'],
        withData: true,
      );
      final file = picked?.files.singleOrNull;
      if (file == null) {
        return const ChittiBackupResult(
          ok: false,
          message: 'Restore cancelled.',
        );
      }

      final bytes = file.bytes;
      if (bytes == null) {
        return const ChittiBackupResult(
          ok: false,
          message: 'Could not read that file.',
        );
      }

      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        return const ChittiBackupResult(
          ok: false,
          message: 'That file is not a MyAllin1 backup.',
        );
      }

      final owner = (decoded['ownerUid'] as String?) ?? '';
      final me = _currentUid();
      if (owner.isNotEmpty && me.isNotEmpty && owner != me) {
        return const ChittiBackupResult(
          ok: false,
          message: 'That backup belongs to a different MyAllin1 account. '
              'Sign in with that account to restore it.',
        );
      }

      await applyPayload(decoded);

      return ChittiBackupResult(
        ok: true,
        message: 'Restored. Chitti remembers you again.',
        at: DateTime.now(),
      );
    } on ChittiBackupTooNewException catch (e) {
      return ChittiBackupResult(ok: false, message: e.message);
    } on FormatException {
      return const ChittiBackupResult(
        ok: false,
        message: 'That file is not a valid MyAllin1 backup.',
      );
    } catch (e) {
      debugPrint('[ChittiBackup] local restore failed: $e');
      return const ChittiBackupResult(
        ok: false,
        message: 'Could not restore from that file. Please try again.',
      );
    }
  }

  /// When the last successful backup happened, or null.
  Future<DateTime?> lastBackupAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lastBackupKey);
      return raw == null ? null : DateTime.tryParse(raw);
    } catch (e) {
      debugPrint('[ChittiBackup] lastBackupAt failed: $e');
      return null;
    }
  }

  /// Backs up at most once a day, silently.
  ///
  /// Called when the app goes to the background — the moment the
  /// customer is done and the device is least busy. Never blocks and
  /// never shows anything: a backup the customer had to think about is
  /// a backup that does not happen.
  Future<void> maybeAutoBackup() async {
    if (!isSupported) return;
    // No account, no backup (self-audit, Aug 28 2026). Without this a
    // guest session would upload whatever Chitti history was on the
    // phone to whichever Google account happened to be signed into the
    // device — on a shared phone, somebody else's Drive.
    if (!_hasRealAccount) return;
    try {
      final last = await lastBackupAt();
      if (last != null && DateTime.now().difference(last) < const Duration(days: 1)) {
        return;
      }
      // Silent: no sign-in prompt. If the customer has never granted
      // Drive access, this does nothing until they tap Back Up in
      // Settings once.
      final api = await _api(interactive: false);
      if (api == null) return;
      await backupNow();
    } catch (e) {
      debugPrint('[ChittiBackup] auto-backup failed: $e');
    }
  }
}
