// ================================================================
// app_error_log_service.dart — Allin1 On-Device Error Monitor
// ================================================================
// Pure Hive storage (box: 'app_error_log'). Zero Firestore writes, zero
// recurring cloud costs. Capped at 500 entries (oldest pruned) and
// deduplicated within a 5-minute window for identical errors on the
// same screen.
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_variant.dart';
import 'chitti_memory_service.dart';

class AppErrorLogEntry {
  AppErrorLogEntry({
    required this.id,
    required this.date,
    required this.timestamp,
    required this.severity,
    required this.screen,
    required this.errorMessage,
    required this.stackTrace,
    required this.appVersion,
    required this.lastSeenAt,
    this.repeatCount = 1,
    this.authUid,
    this.authEmail,
    this.hasAdminClaim,
    this.appVariant = 'customer',
    this.category = 'crash',
    this.resolved = false,
    this.osPlatform,
  });

  final String id;
  final String date; // YYYY-MM-DD
  final String timestamp; // ISO-8601
  final String severity; // CRITICAL, ERROR, WARNING
  final String screen;
  final String errorMessage;
  final String stackTrace;
  final String appVersion;
  int repeatCount;
  String lastSeenAt;
  String? authUid;
  String? authEmail;
  bool? hasAdminClaim;
  final String appVariant; // customer, hero, seller, admin
  final String category; // crash, network, permission, ui, payment, location
  bool resolved;
  final String? osPlatform;

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date,
        'timestamp': timestamp,
        'severity': severity,
        'screen': screen,
        'errorMessage': errorMessage,
        'stackTrace': stackTrace,
        'appVersion': appVersion,
        'repeatCount': repeatCount,
        'lastSeenAt': lastSeenAt,
        'authUid': authUid,
        'authEmail': authEmail,
        'hasAdminClaim': hasAdminClaim,
        'appVariant': appVariant,
        'category': category,
        'resolved': resolved,
        'osPlatform': osPlatform,
      };

  factory AppErrorLogEntry.fromMap(Map<dynamic, dynamic> map) =>
      AppErrorLogEntry(
        id: map['id'] as String? ?? '',
        date: map['date'] as String? ?? '',
        timestamp: map['timestamp'] as String? ?? '',
        severity: map['severity'] as String? ?? 'ERROR',
        screen: map['screen'] as String? ?? 'Unknown',
        errorMessage: map['errorMessage'] as String? ?? '',
        stackTrace: map['stackTrace'] as String? ?? '',
        appVersion: map['appVersion'] as String? ?? '',
        repeatCount: (map['repeatCount'] as num?)?.toInt() ?? 1,
        lastSeenAt: map['lastSeenAt'] as String? ??
            (map['timestamp'] as String? ?? ''),
        authUid: map['authUid'] as String?,
        authEmail: map['authEmail'] as String?,
        hasAdminClaim: map['hasAdminClaim'] as bool?,
        appVariant: map['appVariant'] as String? ?? 'customer',
        category: map['category'] as String? ?? 'crash',
        resolved: map['resolved'] as bool? ?? false,
        osPlatform: map['osPlatform'] as String?,
      );
}

class AppErrorLogService {
  AppErrorLogService._();

  static const String boxName = 'app_error_log';
  static const int maxEntries = 500;
  static const Duration dedupWindow = Duration(minutes: 5);
  static const int maxStackTraceChars = 2000;

  static final Map<String, DateTime> _lastRemoteSyncedAt = {};
  static const Duration remoteSyncThrottle = Duration(minutes: 15);

  // Tester allowlist gate: only errors from an opted-in tester's email are
  // synced to the shared `app_error_reports` collection, so the admin cloud
  // monitor stays limited to test devices instead of filling up with every
  // production customer's crashes. Cached for `_testerAllowlistTtl` so this
  // never turns into a read on every logged error — same throttle pattern as
  // `remoteSyncThrottle` above.
  static Set<String>? _testerEmailsCache;
  static DateTime? _testerEmailsFetchedAt;
  static const Duration _testerAllowlistTtl = Duration(minutes: 15);
  static const String testerConfigDocPath = 'app_config/testers';

  static String? _cachedVersion;

  /// Fetches (and caches) the tester email allowlist from
  /// `app_config/testers` (field `emails`, lower-cased on read/write).
  static Future<Set<String>> _getTesterEmails() async {
    final now = DateTime.now();
    if (_testerEmailsCache != null &&
        _testerEmailsFetchedAt != null &&
        now.difference(_testerEmailsFetchedAt!) < _testerAllowlistTtl) {
      return _testerEmailsCache!;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .doc(testerConfigDocPath)
          .get();
      final raw = (doc.data()?['emails'] as List<dynamic>?) ?? const [];
      final emails = raw
          .map((e) => e.toString().trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
      _testerEmailsCache = emails;
      _testerEmailsFetchedAt = now;
      return emails;
    } catch (e) {
      debugPrint('[AppErrorLogService] tester allowlist fetch failed: $e');
      // Keep serving the last known-good cache rather than treating a
      // transient read failure as "no testers configured".
      return _testerEmailsCache ?? <String>{};
    }
  }

  /// Adds an email to the tester allowlist (one on-demand write).
  static Future<void> addTesterEmail(String email) async {
    final clean = email.trim().toLowerCase();
    if (clean.isEmpty) return;
    await FirebaseFirestore.instance.doc(testerConfigDocPath).set(
      {
        'emails': FieldValue.arrayUnion([clean]),
      },
      SetOptions(merge: true),
    );
    _testerEmailsCache = null; // force a fresh read next time
  }

  /// Removes an email from the tester allowlist (one on-demand write).
  static Future<void> removeTesterEmail(String email) async {
    final clean = email.trim().toLowerCase();
    await FirebaseFirestore.instance.doc(testerConfigDocPath).set(
      {
        'emails': FieldValue.arrayRemove([clean]),
      },
      SetOptions(merge: true),
    );
    _testerEmailsCache = null;
  }

  /// Returns the current tester allowlist, bypassing the cache (admin UI
  /// "manage testers" screen calls this on open, not on every rebuild).
  static Future<Set<String>> getTesterEmails() async {
    _testerEmailsFetchedAt = null;
    return _getTesterEmails();
  }

  static String _resolvePlatform() {
    if (kIsWeb) return 'web';
    try {
      return Platform.operatingSystem;
    } catch (_) {
      return 'unknown';
    }
  }

  static String inferCategory({
    required String message,
    String? stack,
    String severity = 'ERROR',
  }) {
    final combined = '${message.toLowerCase()} ${(stack ?? '').toLowerCase()}';
    // NEW (Sep 22 2026 — Nizam's Chitti error-log request): an
    // uncaught throw from anywhere in Chitti's own send/tool-call path
    // already reaches this method via the global FlutterError.onError/
    // PlatformDispatcher.onError handlers (see main_admin.dart etc.) —
    // no new call sites needed, just teach the EXISTING classifier to
    // recognise Chitti's own code by stack frame, same as the
    // network/location/payment checks below already do for theirs.
    // 'chitti_behavior' (not just 'crash') is what lets the new
    // in-chat error-log viewer filter to Chitti-specific issues.
    if (combined.contains('guruapiservice') ||
        combined.contains('guru_api_service') ||
        combined.contains('chitti_action_executor') ||
        combined.contains('chitti_local_intent_engine') ||
        combined.contains('guru_chat_screen') ||
        combined.contains('guru_overlay_service')) {
      return 'chitti_behavior';
    }
    if (combined.contains('socketexception') ||
        combined.contains('timeoutexception') ||
        combined.contains('connection refused') ||
        combined.contains('clientexception') ||
        combined.contains('network is unreachable') ||
        combined.contains('failed host lookup') ||
        combined.contains('http')) {
      return 'network';
    }
    if (combined.contains('location') ||
        combined.contains('geolocator') ||
        combined.contains('gps') ||
        combined.contains('latlong')) {
      return 'location';
    }
    if (combined.contains('payment') ||
        combined.contains('phonepe') ||
        combined.contains('upi') ||
        combined.contains('transaction') ||
        combined.contains('wallet')) {
      return 'payment';
    }
    if (combined.contains('permission-denied') ||
        combined.contains('permission_denied') ||
        combined.contains('permission denied') ||
        combined.contains('unauthorized') ||
        combined.contains('accessdenied')) {
      return 'permission';
    }
    if (combined.contains('renderflex') ||
        combined.contains('overflowed') ||
        combined.contains('boxconstraints') ||
        combined.contains('viewport') ||
        combined.contains('layout') ||
        combined.contains('renderbox') ||
        combined.contains('setstate()')) {
      return 'ui';
    }
    return 'crash';
  }

  static Future<String> _getAppVersion() async {
    if (_cachedVersion != null) return _cachedVersion!;
    try {
      final info = await PackageInfo.fromPlatform();
      _cachedVersion = '${info.version}+${info.buildNumber}';
      return _cachedVersion!;
    } catch (_) {
      return '1.0.0';
    }
  }

  static Future<Box<dynamic>> _openBox() async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box<dynamic>(boxName);
    }
    try {
      await Hive.initFlutter();
    } catch (_) {}
    return await Hive.openBox<dynamic>(boxName);
  }

  /// Hook for Flutter framework errors (rendering, layout, widget lifecycle).
  static void recordFlutterError(
    FlutterErrorDetails details, {
    String? appVariant,
    String? category,
  }) {
    final isWarning = details.silent;
    final severity = isWarning ? 'WARNING' : 'ERROR';
    final message = details.exceptionAsString();
    final stack = details.stack?.toString();

    // Fire and forget, never crash the caller.
    logError(
      message: message,
      stack: stack,
      severity: severity,
      appVariant: appVariant,
      category: category,
    );
  }

  /// Hook for unhandled asynchronous errors from Dart / PlatformDispatcher.
  static void recordPlatformError(
    Object error,
    StackTrace stack, {
    String? appVariant,
    String? category,
  }) {
    logError(
      message: error.toString(),
      stack: stack.toString(),
      severity: 'CRITICAL',
      appVariant: appVariant,
      category: category,
    );
  }

  static void _maybeSyncToFirestore(AppErrorLogEntry entry) {
    try {
      final sig =
          '${entry.appVariant}_${entry.screen}_${entry.errorMessage.hashCode}';
      final now = DateTime.now();
      final last = _lastRemoteSyncedAt[sig];
      if (last != null && now.difference(last) < remoteSyncThrottle) {
        return;
      }
      _lastRemoteSyncedAt[sig] = now;

      unawaited(
        Future<void>(() async {
          try {
            final email = entry.authEmail?.trim().toLowerCase();
            if (email == null || email.isEmpty) return;
            final allowlist = await _getTesterEmails();
            if (!allowlist.contains(email)) return;

            final col =
                FirebaseFirestore.instance.collection('app_error_reports');
            await col.doc(entry.id).set({
              ...entry.toMap(),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true),);
          } catch (e) {
            debugPrint('[AppErrorLogService] Firestore sync skipped: $e');
          }
        }),
      );
    } catch (_) {}
  }

  /// Logs an error into the local Hive store with automatic deduplication
  /// and capacity enforcement.
  static Future<AppErrorLogEntry?> logError({
    required String message,
    String? stack,
    String severity = 'ERROR',
    String? screen,
    String? authUid,
    String? authEmail,
    bool? hasAdminClaim,
    String? appVariant,
    String? category,
  }) async {
    try {
      final box = await _openBox();
      final now = DateTime.now();
      final dateStr =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final currentScreen = screen ??
          ChittiMemoryService.instance.currentScreen ??
          'Unknown';
      final cleanMessage = message.trim();
      final cleanStack = _truncate(stack?.trim(), maxStackTraceChars);
      final version = await _getAppVersion();

      // Best-effort auth context resolution
      String? resolvedUid = authUid;
      String? resolvedEmail = authEmail;
      bool? resolvedAdminClaim = hasAdminClaim;

      if (resolvedUid == null &&
          resolvedEmail == null &&
          resolvedAdminClaim == null) {
        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            resolvedUid = user.uid;
            resolvedEmail = user.email;
            try {
              final idToken = await user.getIdTokenResult();
              resolvedAdminClaim = idToken.claims?['admin'] as bool?;
            } catch (_) {}
          }
        } catch (_) {}
      }

      final resolvedVariant = appVariant ?? currentAppVariant;
      final resolvedCategory = category ??
          inferCategory(
            message: cleanMessage,
            stack: cleanStack,
            severity: severity,
          );

      // Deduplication check within dedupWindow:
      // Scan recent entries to see if the same error occurred on the same screen.
      dynamic matchingKey;
      AppErrorLogEntry? existingMatch;

      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is Map) {
          final entry = AppErrorLogEntry.fromMap(raw);
          if (entry.screen == currentScreen &&
              entry.errorMessage == cleanMessage) {
            final lastSeen = DateTime.tryParse(entry.lastSeenAt);
            if (lastSeen != null && now.difference(lastSeen) <= dedupWindow) {
              matchingKey = key;
              existingMatch = entry;
              break;
            }
          }
        }
      }

      if (existingMatch != null && matchingKey != null) {
        // Increment repeat count and touch lastSeenAt
        existingMatch.repeatCount += 1;
        existingMatch.lastSeenAt = now.toIso8601String();
        if (existingMatch.authUid == null && resolvedUid != null) {
          existingMatch.authUid = resolvedUid;
          existingMatch.authEmail = resolvedEmail;
          existingMatch.hasAdminClaim = resolvedAdminClaim;
        }
        await box.put(matchingKey, existingMatch.toMap());
        _maybeSyncToFirestore(existingMatch);
        return existingMatch;
      }

      // If at or exceeding capacity, prune oldest entries.
      if (box.length >= maxEntries) {
        await _pruneOldest(box, (box.length - maxEntries) + 1);
      }

      final id =
          'err_${now.millisecondsSinceEpoch}_${Random().nextInt(9999).toString().padLeft(4, '0')}';
      final newEntry = AppErrorLogEntry(
        id: id,
        date: dateStr,
        timestamp: now.toIso8601String(),
        severity: severity,
        screen: currentScreen,
        errorMessage: cleanMessage,
        stackTrace: cleanStack,
        appVersion: version,
        lastSeenAt: now.toIso8601String(),
        authUid: resolvedUid,
        authEmail: resolvedEmail,
        hasAdminClaim: resolvedAdminClaim,
        appVariant: resolvedVariant,
        category: resolvedCategory,
        osPlatform: _resolvePlatform(),
      );

      await box.put(id, newEntry.toMap());
      _maybeSyncToFirestore(newEntry);
      return newEntry;
    } catch (e) {
      debugPrint('[AppErrorLogService] Failed to record error log: $e');
      return null;
    }
  }

  static Future<void> _pruneOldest(Box<dynamic> box, int countToRemove) async {
    if (countToRemove <= 0 || box.isEmpty) return;
    final entries = <({dynamic key, DateTime time})>[];

    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is Map) {
        final timeStr = raw['timestamp'] as String?;
        final time = DateTime.tryParse(timeStr ?? '') ?? DateTime(1970);
        entries.add((key: key, time: time));
      } else {
        entries.add((key: key, time: DateTime(1970)));
      }
    }

    entries.sort((a, b) => a.time.compareTo(b.time)); // oldest first
    final keysToDelete = entries.take(countToRemove).map((e) => e.key).toList();
    await box.deleteAll(keysToDelete);
  }

  /// Returns all log entries for a given date (YYYY-MM-DD), ordered
  /// newest-to-oldest.
  static Future<List<AppErrorLogEntry>> getLogsForDate(String dateStr) async {
    try {
      final box = await _openBox();
      final results = <AppErrorLogEntry>[];

      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is Map) {
          final entry = AppErrorLogEntry.fromMap(raw);
          if (entry.date == dateStr) {
            results.add(entry);
          }
        }
      }

      results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return results;
    } catch (e) {
      debugPrint('[AppErrorLogService] getLogsForDate error: $e');
      return <AppErrorLogEntry>[];
    }
  }

  /// Returns recent log entries up to [limit], ordered newest-to-oldest.
  static Future<List<AppErrorLogEntry>> getRecentLogs({int limit = 50}) async {
    try {
      final box = await _openBox();
      final results = <AppErrorLogEntry>[];

      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is Map) {
          results.add(AppErrorLogEntry.fromMap(raw));
        }
      }

      results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (results.length > limit) {
        return results.sublist(0, limit);
      }
      return results;
    } catch (e) {
      debugPrint('[AppErrorLogService] getRecentLogs error: $e');
      return <AppErrorLogEntry>[];
    }
  }

  /// Finds a specific log entry by its [id].
  static Future<AppErrorLogEntry?> getLogById(String id) async {
    try {
      final box = await _openBox();
      final raw = box.get(id);
      if (raw is Map) {
        return AppErrorLogEntry.fromMap(raw);
      }
      return null;
    } catch (e) {
      debugPrint('[AppErrorLogService] getLogById error: $e');
      return null;
    }
  }

  /// Deletes all error logs from local storage.
  static Future<void> clearAll() async {
    try {
      final box = await _openBox();
      await box.clear();
    } catch (e) {
      debugPrint('[AppErrorLogService] clearAll error: $e');
    }
  }

  /// Generates a daily summary map for UI or Chitti spoken reports.
  static Future<({
    int total,
    int criticalCount,
    int errorCount,
    int warningCount,
    Map<String, int> screenCounts,
    List<AppErrorLogEntry> topErrors,
  })> getDailySummary(String dateStr) async {
    final logs = await getLogsForDate(dateStr);
    int critical = 0;
    int error = 0;
    int warning = 0;
    final screenMap = <String, int>{};

    for (final entry in logs) {
      if (entry.severity == 'CRITICAL') {
        critical += entry.repeatCount;
      } else if (entry.severity == 'WARNING') {
        warning += entry.repeatCount;
      } else {
        error += entry.repeatCount;
      }

      screenMap[entry.screen] =
          (screenMap[entry.screen] ?? 0) + entry.repeatCount;
    }

    return (
      total: critical + error + warning,
      criticalCount: critical,
      errorCount: error,
      warningCount: warning,
      screenCounts: screenMap,
      topErrors: logs.take(5).toList(),
    );
  }

  /// Fetches remote cross-app errors from Firestore with local filtering
  /// to prevent missing-index errors on Firebase Spark tier.
  static Future<List<AppErrorLogEntry>> fetchRemoteErrors({
    String? appVariant,
    String? category,
    bool? resolved,
    int limit = 100,
  }) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('app_error_reports')
          .limit(limit)
          .get();

      var list = snapshot.docs
          .map((d) => AppErrorLogEntry.fromMap(d.data()))
          .toList();

      if (appVariant != null && appVariant.isNotEmpty && appVariant != 'all') {
        list = list
            .where(
              (e) => e.appVariant.toLowerCase() == appVariant.toLowerCase(),
            )
            .toList();
      }
      if (category != null && category.isNotEmpty && category != 'all') {
        list = list
            .where((e) => e.category.toLowerCase() == category.toLowerCase())
            .toList();
      }
      if (resolved != null) {
        list = list.where((e) => e.resolved == resolved).toList();
      }

      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return list;
    } catch (e) {
      debugPrint('[AppErrorLogService] fetchRemoteErrors error: $e');
      return <AppErrorLogEntry>[];
    }
  }

  /// Marks an error report as resolved or active in Firestore.
  static Future<void> markRemoteResolved(
    String errorId, {
    required bool resolved,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('app_error_reports')
          .doc(errorId)
          .update({
        'resolved': resolved,
        'resolvedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[AppErrorLogService] markRemoteResolved error: $e');
    }
  }

  /// Deletes an error report doc from Firestore.
  static Future<void> deleteRemoteError(String errorId) async {
    try {
      await FirebaseFirestore.instance
          .collection('app_error_reports')
          .doc(errorId)
          .delete();
    } catch (e) {
      debugPrint('[AppErrorLogService] deleteRemoteError error: $e');
    }
  }

  static String _truncate(String? text, int max) {
    if (text == null || text.isEmpty) return '';
    if (text.length <= max) return text;
    return '${text.substring(0, max)}\n...[truncated]';
  }
}
