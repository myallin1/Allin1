// ================================================================
// dynamic_app_layout_service.dart — Allin1 Universal Layout Engine
// ================================================================
// Provides persistent, reactive order management for customizable
// screens and sections across the Allin1 Super App.
//
// Key Features:
// 1. Zero-latency memory cache backed by SharedPreferences.
// 2. ValueNotifier `layoutNotifier` emits section key changes for live UI reordering.
// 3. Graceful fallback: new tiles not in saved order automatically append at end.
// 4. Programmatic reordering for Chitti autonomous voice/intent commands.
// 5. One-tap layout reset per section or globally.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DynamicAppLayoutService {
  DynamicAppLayoutService._();

  static final DynamicAppLayoutService instance = DynamicAppLayoutService._();

  static const String _prefsPrefix = 'app_layout_order::';

  /// In-memory cache of section orders: {sectionKey: [tileId1, tileId2, ...]}
  final Map<String, List<String>> _cache = {};

  /// ValueNotifier that increments / notifies listeners whenever a section order changes.
  final ValueNotifier<int> layoutNotifier = ValueNotifier<int>(0);

  /// Synchronously or asynchronously resolves the ordered list of IDs for a [sectionKey].
  /// If a saved order exists, it applies it while appending any new IDs from [defaultIds].
  Future<List<String>> getOrderedIds({
    required String sectionKey,
    required List<String> defaultIds,
  }) async {
    if (_cache.containsKey(sectionKey)) {
      return _applyOrder(defaultIds, _cache[sectionKey]!);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      var raw = prefs.getString('$_prefsPrefix$sectionKey');
      // Backward compatibility with legacy admin tile order prefix
      raw ??= prefs.getString('admin_home_tile_order::$sectionKey');

      if (raw != null) {
        final saved = (jsonDecode(raw) as List<dynamic>).cast<String>();
        _cache[sectionKey] = saved;
        return _applyOrder(defaultIds, saved);
      }
    } catch (e) {
      debugPrint('[DynamicAppLayoutService] Error reading order for $sectionKey: $e');
    }

    _cache[sectionKey] = List<String>.from(defaultIds);
    return List<String>.from(defaultIds);
  }

  /// Synchronous retrieval from in-memory cache if already loaded, else returns default.
  List<String> getCachedOrderedIds({
    required String sectionKey,
    required List<String> defaultIds,
  }) {
    final cached = _cache[sectionKey];
    if (cached != null) {
      return _applyOrder(defaultIds, cached);
    }
    return List<String>.from(defaultIds);
  }

  /// Persists a new ordered list of tile IDs for [sectionKey].
  Future<void> saveSectionOrder({
    required String sectionKey,
    required List<String> orderedIds,
  }) async {
    _cache[sectionKey] = List<String>.from(orderedIds);
    layoutNotifier.value++;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefsPrefix$sectionKey', jsonEncode(orderedIds));
    } catch (e) {
      debugPrint('[DynamicAppLayoutService] Error saving order for $sectionKey: $e');
    }
  }

  /// Moves the specified [tileIds] to the front of the list for [sectionKey].
  /// Unmentioned tiles preserve their relative order behind the prioritized tiles.
  Future<List<String>> moveTilesToFront({
    required String sectionKey,
    required List<String> tileIds,
    required List<String> defaultIds,
  }) async {
    final current = await getOrderedIds(
      sectionKey: sectionKey,
      defaultIds: defaultIds,
    );

    final validPriorityIds = tileIds.where(current.contains).toList();
    final remainingIds = current.where((id) => !validPriorityIds.contains(id)).toList();
    final updated = [...validPriorityIds, ...remainingIds];

    await saveSectionOrder(sectionKey: sectionKey, orderedIds: updated);
    return updated;
  }

  /// Moves a single tile to a specific target index.
  Future<List<String>> reorderTile({
    required String sectionKey,
    required String tileId,
    required int targetIndex,
    required List<String> defaultIds,
  }) async {
    final current = await getOrderedIds(
      sectionKey: sectionKey,
      defaultIds: defaultIds,
    );

    if (!current.contains(tileId)) return current;

    final updated = List<String>.from(current);
    updated.remove(tileId);
    final clampedIndex = targetIndex.clamp(0, updated.length);
    updated.insert(clampedIndex, tileId);

    await saveSectionOrder(sectionKey: sectionKey, orderedIds: updated);
    return updated;
  }

  /// Resets a section back to its original default arrangement.
  Future<void> resetSectionOrder(String sectionKey) async {
    _cache.remove(sectionKey);
    layoutNotifier.value++;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefsPrefix$sectionKey');
      await prefs.remove('admin_home_tile_order::$sectionKey');
    } catch (e) {
      debugPrint('[DynamicAppLayoutService] Error resetting order for $sectionKey: $e');
    }
  }

  /// Resets all customizable section layouts across the app.
  Future<void> resetAllSections() async {
    _cache.clear();
    layoutNotifier.value++;

    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefsPrefix) || k.startsWith('admin_home_tile_order::')).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (e) {
      debugPrint('[DynamicAppLayoutService] Error resetting all sections: $e');
    }
  }

  /// Clears in-memory cache. Used in tests to reset state between test cases.
  @visibleForTesting
  void clearMemoryCacheForTesting() {
    _cache.clear();
  }

  /// Reconciles [defaultIds] with [savedOrder].
  /// Items in [savedOrder] present in [defaultIds] come first in saved order;
  /// any new [defaultIds] not in [savedOrder] are gracefully appended to the end.
  static List<String> _applyOrder(
    List<String> defaultIds,
    List<String> savedOrder,
  ) {
    final result = <String>[];
    final defaultSet = defaultIds.toSet();

    for (final id in savedOrder) {
      if (defaultSet.contains(id)) {
        result.add(id);
      }
    }

    for (final id in defaultIds) {
      if (!result.contains(id)) {
        result.add(id);
      }
    }

    return result;
  }
}
