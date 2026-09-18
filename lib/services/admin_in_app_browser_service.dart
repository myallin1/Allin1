// ================================================================
// admin_in_app_browser_service.dart — Allin1 In-App Browser History
// ================================================================
// Pure Hive storage (box: 'admin_browser_history'). Zero Firestore writes,
// zero cloud costs. Capped at 200 entries (oldest pruned automatically).
// Stores URL, title, visit timestamps, and a lightweight rendered text
// snapshot (reader view) so the admin can review build logs and dev task
// status offline with zero connectivity.
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class AdminBrowserHistoryEntry {
  AdminBrowserHistoryEntry({
    required this.id,
    required this.url,
    required this.title,
    required this.timestamp,
    required this.date,
    required this.textContent,
    this.visitCount = 1,
    String? lastVisitedAt,
  }) : lastVisitedAt = lastVisitedAt ?? timestamp;

  final String id;
  final String url;
  final String title;
  final String timestamp; // ISO-8601
  final String date; // YYYY-MM-DD
  final String textContent;
  int visitCount;
  String lastVisitedAt;

  bool get hasSnapshot => textContent.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'id': id,
        'url': url,
        'title': title,
        'timestamp': timestamp,
        'date': date,
        'textContent': textContent,
        'visitCount': visitCount,
        'lastVisitedAt': lastVisitedAt,
      };

  factory AdminBrowserHistoryEntry.fromMap(Map<dynamic, dynamic> map) =>
      AdminBrowserHistoryEntry(
        id: map['id'] as String? ?? '',
        url: map['url'] as String? ?? '',
        title: map['title'] as String? ?? '',
        timestamp: map['timestamp'] as String? ?? '',
        date: map['date'] as String? ?? '',
        textContent: map['textContent'] as String? ?? '',
        visitCount: (map['visitCount'] as num?)?.toInt() ?? 1,
        lastVisitedAt: map['lastVisitedAt'] as String? ??
            (map['timestamp'] as String? ?? ''),
      );
}

class AdminInAppBrowserService {
  AdminInAppBrowserService._();

  static const String boxName = 'admin_browser_history';
  static const int maxEntries = 200;
  static const int maxSnapshotChars = 40000;

  static Future<Box<dynamic>> _openBox() async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box<dynamic>(boxName);
    }
    try {
      await Hive.initFlutter();
    } catch (_) {}
    return await Hive.openBox<dynamic>(boxName);
  }

  /// Records or updates a page visit in Hive. If the URL has been visited
  /// previously, its title and text snapshot are refreshed, visit counter is
  /// incremented, and lastVisitedAt is touched. If capacity exceeds maxEntries,
  /// oldest records are pruned.
  static Future<AdminBrowserHistoryEntry?> recordVisit({
    required String url,
    String? title,
    String? textContent,
  }) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return null;

    try {
      final box = await _openBox();
      final now = DateTime.now();
      final dateStr =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final cleanTitle = (title != null && title.trim().isNotEmpty)
          ? title.trim()
          : cleanUrl;
      final cleanText = _truncate(textContent?.trim(), maxSnapshotChars);

      // Check if this URL is already recorded
      dynamic existingKey;
      AdminBrowserHistoryEntry? existingEntry;

      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is Map) {
          final entry = AdminBrowserHistoryEntry.fromMap(raw);
          if (entry.url == cleanUrl) {
            existingKey = key;
            existingEntry = entry;
            break;
          }
        }
      }

      if (existingEntry != null && existingKey != null) {
        existingEntry.visitCount += 1;
        existingEntry.lastVisitedAt = now.toIso8601String();
        // Update title if new non-empty title provided
        if (cleanTitle != cleanUrl || existingEntry.title.isEmpty) {
          // If the new title is more descriptive than a raw URL, update it
          final updated = AdminBrowserHistoryEntry(
            id: existingEntry.id,
            url: existingEntry.url,
            title: cleanTitle.isNotEmpty ? cleanTitle : existingEntry.title,
            timestamp: existingEntry.timestamp,
            date: existingEntry.date,
            textContent: cleanText.isNotEmpty
                ? cleanText
                : existingEntry.textContent,
            visitCount: existingEntry.visitCount,
            lastVisitedAt: now.toIso8601String(),
          );
          await box.put(existingKey, updated.toMap());
          return updated;
        } else {
          final updated = AdminBrowserHistoryEntry(
            id: existingEntry.id,
            url: existingEntry.url,
            title: existingEntry.title,
            timestamp: existingEntry.timestamp,
            date: existingEntry.date,
            textContent: cleanText.isNotEmpty
                ? cleanText
                : existingEntry.textContent,
            visitCount: existingEntry.visitCount,
            lastVisitedAt: now.toIso8601String(),
          );
          await box.put(existingKey, updated.toMap());
          return updated;
        }
      }

      // If at capacity, prune oldest entries
      if (box.length >= maxEntries) {
        await _pruneOldest(box, (box.length - maxEntries) + 1);
      }

      final id =
          'hist_${now.millisecondsSinceEpoch}_${Random().nextInt(9999).toString().padLeft(4, '0')}';
      final newEntry = AdminBrowserHistoryEntry(
        id: id,
        url: cleanUrl,
        title: cleanTitle,
        timestamp: now.toIso8601String(),
        date: dateStr,
        textContent: cleanText,
        lastVisitedAt: now.toIso8601String(),
      );

      await box.put(id, newEntry.toMap());
      return newEntry;
    } catch (e) {
      debugPrint('[AdminInAppBrowserService] Failed to record visit: $e');
      return null;
    }
  }

  /// Prunes oldest history entries based on lastVisitedAt/timestamp.
  static Future<void> _pruneOldest(Box<dynamic> box, int countToRemove) async {
    if (countToRemove <= 0 || box.isEmpty) return;
    final entries = <({dynamic key, DateTime time})>[];

    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is Map) {
        final timeStr =
            (raw['lastVisitedAt'] ?? raw['timestamp']) as String?;
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

  /// Returns recent history entries up to [limit], ordered newest-to-oldest.
  static Future<List<AdminBrowserHistoryEntry>> getHistory({
    int limit = 100,
  }) async {
    try {
      final box = await _openBox();
      final results = <AdminBrowserHistoryEntry>[];

      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is Map) {
          results.add(AdminBrowserHistoryEntry.fromMap(raw));
        }
      }

      results.sort((a, b) {
        final tb = DateTime.tryParse(b.lastVisitedAt) ?? DateTime(1970);
        final ta = DateTime.tryParse(a.lastVisitedAt) ?? DateTime(1970);
        return tb.compareTo(ta);
      });

      if (results.length > limit) {
        return results.sublist(0, limit);
      }
      return results;
    } catch (e) {
      debugPrint('[AdminInAppBrowserService] getHistory error: $e');
      return <AdminBrowserHistoryEntry>[];
    }
  }

  /// Finds an existing history entry by its exact [url].
  static Future<AdminBrowserHistoryEntry?> getEntryByUrl(String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return null;

    try {
      final box = await _openBox();
      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is Map) {
          final entry = AdminBrowserHistoryEntry.fromMap(raw);
          if (entry.url == cleanUrl) {
            return entry;
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('[AdminInAppBrowserService] getEntryByUrl error: $e');
      return null;
    }
  }

  /// Finds a specific history entry by its [id].
  static Future<AdminBrowserHistoryEntry?> getEntryById(String id) async {
    try {
      final box = await _openBox();
      final raw = box.get(id);
      if (raw is Map) {
        return AdminBrowserHistoryEntry.fromMap(raw);
      }
      return null;
    } catch (e) {
      debugPrint('[AdminInAppBrowserService] getEntryById error: $e');
      return null;
    }
  }

  /// Searches history entries by [query] matching title, URL, or rendered text.
  static Future<List<AdminBrowserHistoryEntry>> searchHistory(
    String query,
  ) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return getHistory();

    try {
      final all = await getHistory(limit: maxEntries);
      return all.where((e) {
        return e.title.toLowerCase().contains(q) ||
            e.url.toLowerCase().contains(q) ||
            e.textContent.toLowerCase().contains(q);
      }).toList();
    } catch (e) {
      debugPrint('[AdminInAppBrowserService] searchHistory error: $e');
      return <AdminBrowserHistoryEntry>[];
    }
  }

  /// Deletes a specific history record.
  static Future<void> deleteEntry(String id) async {
    try {
      final box = await _openBox();
      await box.delete(id);
    } catch (e) {
      debugPrint('[AdminInAppBrowserService] deleteEntry error: $e');
    }
  }

  /// Deletes all browser history records from local storage.
  static Future<void> clearAll() async {
    try {
      final box = await _openBox();
      await box.clear();
    } catch (e) {
      debugPrint('[AdminInAppBrowserService] clearAll error: $e');
    }
  }

  static String _truncate(String? text, int max) {
    if (text == null || text.isEmpty) return '';
    if (text.length <= max) return text;
    return '${text.substring(0, max)}\n...[snapshot truncated]';
  }
}
