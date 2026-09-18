// ================================================================
// app_error_log_service.dart — Allin1 On-Device Error Monitor
// ================================================================
// Pure Hive storage (box: 'app_error_log'). Zero Firestore writes, zero
// recurring cloud costs. Capped at 500 entries (oldest pruned) and
// deduplicated within a 5-minute window for identical errors on the
// same screen.
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
      );
}

class AppErrorLogService {
  AppErrorLogService._();

  static const String boxName = 'app_error_log';
  static const int maxEntries = 500;
  static const Duration dedupWindow = Duration(minutes: 5);
  static const int maxStackTraceChars = 2000;

  static String? _cachedVersion;

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
  static void recordFlutterError(FlutterErrorDetails details) {
    final isWarning = details.silent;
    final severity = isWarning ? 'WARNING' : 'ERROR';
    final message = details.exceptionAsString();
    final stack = details.stack?.toString();

    // Fire and forget, never crash the caller.
    logError(
      message: message,
      stack: stack,
      severity: severity,
    );
  }

  /// Hook for unhandled asynchronous errors from Dart / PlatformDispatcher.
  static void recordPlatformError(Object error, StackTrace stack) {
    logError(
      message: error.toString(),
      stack: stack.toString(),
      severity: 'CRITICAL',
    );
  }

  /// Logs an error into the local Hive store with automatic deduplication
  /// and capacity enforcement.
  static Future<AppErrorLogEntry?> logError({
    required String message,
    String? stack,
    String severity = 'ERROR',
    String? screen,
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
        await box.put(matchingKey, existingMatch.toMap());
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
      );

      await box.put(id, newEntry.toMap());
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

  static String _truncate(String? text, int max) {
    if (text == null || text.isEmpty) return '';
    if (text.length <= max) return text;
    return '${text.substring(0, max)}\n...[truncated]';
  }
}
