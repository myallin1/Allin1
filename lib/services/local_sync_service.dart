// ================================================================
// LocalSyncService — Local-First Delta Sync Engine
// Allin1 Super App v2.0
//
// Architecture:
//   - Hive as the universal local store (mobile + web PWA)
//   - TrailBase HTTP endpoints as the edge data source
//   - Delta syncs: only fetch records changed after lastSyncTime
//   - Firebase stays untouched (rides, auth, live tracking)
//
// Usage:
//   await LocalSyncService.instance.initialize();
//   await LocalSyncService.instance.syncAll(userId: uid, city: 'Erode');
//   final stores = LocalSyncService.instance.getStores('Erode');
// ================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import '../models/reward_model.dart';
import '../models/store_model.dart';
import '../models/user_balance_model.dart';

// ── Box key constants ─────────────────────────────────────────────────────────
const String _kStoresBox = 'tb_stores';
const String _kRewardsBox = 'tb_rewards';
const String _kBalanceBox = 'tb_user_balance';
const String _kMetaBox = 'tb_sync_meta';

// Meta keys inside _kMetaBox
const String _kStoresSyncKey = 'stores_last_sync';
const String _kRewardsSyncKey = 'rewards_last_sync';
const String _kBalanceSyncKey = 'balance_last_sync';

// ── TrailBase Configuration ───────────────────────────────────────────────────
// Set TRAILBASE_URL in your .env file once your backend is deployed.
// Format: 'http://<VM_PUBLIC_IP>:4000/api/v1'  (no trailing slash)
// Example: 'http://34.100.200.50:4000/api/v1'
// Leave blank or omit to disable sync (app runs on cached/empty data).
final String _kTrailBaseUrl = (dotenv.env['TRAILBASE_URL'] ?? '').trim();

// Delta sync window: max age before forcing a full re-sync (24 hours)
const Duration _kMaxSyncAge = Duration(hours: 24);

// Sync cooldown: minimum gap between syncs (30 minutes)
const Duration _kSyncCooldown = Duration(minutes: 30);

class LocalSyncService {
  LocalSyncService._();
  static final LocalSyncService instance = LocalSyncService._();

  bool _initialized = false;

  late Box<StoreModel> _storesBox;
  late Box<RewardModel> _rewardsBox;
  late Box<UserBalanceModel> _balanceBox;
  late Box<dynamic> _metaBox;

  // ── Initialization ────────────────────────────────────────────────────────
  /// Call once at app startup (in main() after Hive.initFlutter())
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    // Register Hive adapters — generated via build_runner
    // Run: `flutter pub run build_runner build --delete-conflicting-outputs`
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(StoreModelAdapter());
    }
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(RewardModelAdapter());
    }
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(UserBalanceModelAdapter());
    }

    // Open Hive boxes IN PARALLEL. These used to be four sequential
    // awaits — each Hive.openBox() is a local storage round-trip
    // (IndexedDB on web), so waiting for one before starting the next
    // paid the cost four times over for no reason.
    final results = await Future.wait<Object>([
      Hive.openBox<StoreModel>(_kStoresBox),
      Hive.openBox<RewardModel>(_kRewardsBox),
      Hive.openBox<UserBalanceModel>(_kBalanceBox),
      Hive.openBox<dynamic>(_kMetaBox),
    ]);
    _storesBox = results[0] as Box<StoreModel>;
    _rewardsBox = results[1] as Box<RewardModel>;
    _balanceBox = results[2] as Box<UserBalanceModel>;
    _metaBox = results[3] as Box<dynamic>;

    _initialized = true;
    debugPrint('[LocalSync] Initialized. '
        'Stores: ${_storesBox.length}, '
        'Rewards: ${_rewardsBox.length}, '
        'Balances: ${_balanceBox.length}');
  }

  // ── Master Sync ───────────────────────────────────────────────────────────
  /// Convenience method — call on app foreground or pull-to-refresh
  Future<SyncResult> syncAll({
    required String userId,
    required String city,
  }) async {
    // initialize() now runs AFTER runApp() (see main_customer.dart), so
    // this can theoretically be reached before it finishes. It's
    // idempotent and near-free once done, so just await it here rather
    // than asserting and crashing.
    await initialize();
    final results = await Future.wait([
      syncStores(city),
      syncRewards(userId),
      syncUserBalance(userId),
    ]);
    return SyncResult(
      storesSynced: results[0].recordsSynced,
      rewardsSynced: results[1].recordsSynced,
      balanceUpdated: results[2].recordsSynced > 0,
      errors: results.expand((r) => r.errors).toList(),
    );
  }

  // ── Store Sync ────────────────────────────────────────────────────────────
  /// Delta-fetches stores for a city from TrailBase.
  /// Returns stores from cache immediately if within cooldown window.
  Future<_BoxSyncResult> syncStores(String city) async {
    _assertInitialized();

    if (_kTrailBaseUrl.isEmpty) {
      debugPrint('[LocalSync] TrailBase URL not configured — skipping store sync.');
      return const _BoxSyncResult(recordsSynced: 0);
    }

    final lastSync = _getLastSync(_kStoresSyncKey);

    // Respect cooldown — don't hammer the server
    if (lastSync != null && _withinCooldown(lastSync)) {
      debugPrint('[LocalSync] Stores within cooldown, using cache.');
      return const _BoxSyncResult(recordsSynced: 0);
    }

    try {
      final endpoint = '$_kTrailBaseUrl/stores'
          '?city=${Uri.encodeComponent(city)}'
          '&limit=500'
          '${_deltaParam(lastSync)}';

      final records = await _deltaFetch(endpoint);
      if (records == null) {
        return const _BoxSyncResult(recordsSynced: 0);
      }

      int synced = 0;
      for (final json in records) {
        try {
          final store = StoreModel.fromJson(json as Map<String, dynamic>);
          await _storesBox.put(store.id, store);
          synced++;
        } catch (e) {
          debugPrint('[LocalSync] Store parse error: $e');
        }
      }

      await _setLastSync(_kStoresSyncKey);
      debugPrint('[LocalSync] Stores synced: $synced records for $city');
      return _BoxSyncResult(recordsSynced: synced);
    } catch (e) {
      debugPrint('[LocalSync] Store sync failed: $e');
      return _BoxSyncResult(recordsSynced: 0, errors: ['Store sync: $e']);
    }
  }

  // ── Rewards Sync ──────────────────────────────────────────────────────────
  /// Delta-fetches reward tasks (global + user-specific) from TrailBase.
  Future<_BoxSyncResult> syncRewards(String userId) async {
    _assertInitialized();

    if (_kTrailBaseUrl.isEmpty) {
      debugPrint('[LocalSync] TrailBase URL not configured — skipping reward sync.');
      return const _BoxSyncResult(recordsSynced: 0);
    }

    final lastSync = _getLastSync(_kRewardsSyncKey);
    if (lastSync != null && _withinCooldown(lastSync)) {
      debugPrint('[LocalSync] Rewards within cooldown, using cache.');
      return const _BoxSyncResult(recordsSynced: 0);
    }

    try {
      final endpoint = '$_kTrailBaseUrl/rewards'
          '?user_id=${Uri.encodeComponent(userId)}'
          '&limit=200'
          '${_deltaParam(lastSync)}';

      final records = await _deltaFetch(endpoint);
      if (records == null) {
        return const _BoxSyncResult(recordsSynced: 0);
      }

      int synced = 0;
      for (final json in records) {
        try {
          final reward = RewardModel.fromJson(json as Map<String, dynamic>);
          await _rewardsBox.put(reward.id, reward);
          synced++;
        } catch (e) {
          debugPrint('[LocalSync] Reward parse error: $e');
        }
      }

      await _setLastSync(_kRewardsSyncKey);
      debugPrint('[LocalSync] Rewards synced: $synced records');
      return _BoxSyncResult(recordsSynced: synced);
    } catch (e) {
      debugPrint('[LocalSync] Reward sync failed: $e');
      return _BoxSyncResult(recordsSynced: 0, errors: ['Reward sync: $e']);
    }
  }

  // ── User Balance Sync ─────────────────────────────────────────────────────
  /// Fetches the user's latest coin balance snapshot from TrailBase.
  Future<_BoxSyncResult> syncUserBalance(String userId) async {
    _assertInitialized();

    if (_kTrailBaseUrl.isEmpty) {
      debugPrint('[LocalSync] TrailBase URL not configured — skipping balance sync.');
      return const _BoxSyncResult(recordsSynced: 0);
    }

    final lastSync = _getLastSync('${_kBalanceSyncKey}_$userId');
    if (lastSync != null && _withinCooldown(lastSync)) {
      debugPrint('[LocalSync] Balance within cooldown, using cache.');
      return const _BoxSyncResult(recordsSynced: 0);
    }

    try {
      final endpoint =
          '$_kTrailBaseUrl/user-balance/${Uri.encodeComponent(userId)}';

      final response = await http
          .get(Uri.parse(endpoint), headers: _headers())
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final balance = UserBalanceModel.fromJson(json);
        await _balanceBox.put(userId, balance);
        await _setLastSync('${_kBalanceSyncKey}_$userId');
        debugPrint('[LocalSync] Balance synced for $userId');
        return const _BoxSyncResult(recordsSynced: 1);
      } else if (response.statusCode == 404) {
        // User not in TrailBase yet — seed with empty balance
        final empty = UserBalanceModel.empty(userId);
        await _balanceBox.put(userId, empty);
        return const _BoxSyncResult(recordsSynced: 1);
      } else {
        return _BoxSyncResult(
          recordsSynced: 0,
          errors: ['Balance HTTP ${response.statusCode}'],
        );
      }
    } catch (e) {
      debugPrint('[LocalSync] Balance sync failed: $e');
      return _BoxSyncResult(recordsSynced: 0, errors: ['Balance sync: $e']);
    }
  }

  // ── Local Read APIs (zero-network, instant) ───────────────────────────────

  /// Returns all cached stores for a city. No network call.
  List<StoreModel> getStores(String city) {
    // Boxes now open after runApp(), so a very early caller gets an
    // empty list (== "nothing cached yet") instead of an exception.
    if (!_initialized) return const [];
    return _storesBox.values
        .where((s) => s.city.toLowerCase() == city.toLowerCase())
        .toList()
      ..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
  }

  /// Returns cached stores filtered by category.
  List<StoreModel> getStoresByCategory(String city, String category) {
    return getStores(city)
        .where((s) => s.category.toLowerCase() == category.toLowerCase())
        .toList();
  }

  /// Returns all cached rewards.
  List<RewardModel> getRewards() {
    if (!_initialized) return const [];
    return _rewardsBox.values.toList()
      ..sort((a, b) => b.coins.compareTo(a.coins));
  }

  /// Returns rewards filtered by status.
  List<RewardModel> getAvailableRewards() =>
      getRewards().where((r) => r.status == 'available').toList();

  /// Returns the cached balance for a user (or null if not yet synced).
  UserBalanceModel? getUserBalance(String userId) {
    if (!_initialized) return null;
    return _balanceBox.get(userId);
  }

  // ── Freshness Checks ──────────────────────────────────────────────────────

  /// Whether the store cache for a city is fresh enough to use
  bool isStoreCacheFresh() {
    final last = _getLastSync(_kStoresSyncKey);
    if (last == null) {
      return false;
    }
    return DateTime.now().difference(last) < _kMaxSyncAge;
  }

  /// Overall freshness check
  bool get isCacheFresh => isStoreCacheFresh();

  /// When stores were last synced (null if never)
  DateTime? get storesLastSynced => _getLastSync(_kStoresSyncKey);

  // ── Cache Management ──────────────────────────────────────────────────────

  /// Wipe all local caches (useful on logout)
  Future<void> clearAll() async {
    await initialize();
    await Future.wait([
      _storesBox.clear(),
      _rewardsBox.clear(),
      _balanceBox.clear(),
      _metaBox.clear(),
    ]);
    debugPrint('[LocalSync] All caches cleared.');
  }

  /// Force a full re-sync on next call (bypasses cooldown)
  Future<void> invalidateAll() async {
    await initialize();
    await _metaBox.clear();
    debugPrint(
        '[LocalSync] Sync timestamps invalidated — full sync on next call.',);
  }

  // ── Internal Helpers ──────────────────────────────────────────────────────

  /// Generic delta-fetch: GETs endpoint, returns list of records or null.
  Future<List<dynamic>?> _deltaFetch(String endpoint) async {
    try {
      final response = await http
          .get(Uri.parse(endpoint), headers: _headers())
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        // TrailBase returns either {"data": [...]} or a raw list
        if (body is Map<String, dynamic> && body.containsKey('data')) {
          return body['data'] as List<dynamic>;
        } else if (body is List<dynamic>) {
          return body;
        }
      } else {
        debugPrint('[LocalSync] HTTP ${response.statusCode} for $endpoint');
      }
    } on TimeoutException {
      debugPrint('[LocalSync] Timeout for $endpoint — using cache.');
    } catch (e) {
      debugPrint('[LocalSync] Fetch error for $endpoint: $e');
    }
    return null;
  }

  /// Builds the `?updated_after=` delta param string
  String _deltaParam(DateTime? lastSync) {
    if (lastSync == null) {
      return '';
    }
    // Force full re-sync if cache is older than max age
    if (DateTime.now().difference(lastSync) > _kMaxSyncAge) {
      return '';
    }
    return '&updated_after=${Uri.encodeComponent(lastSync.toUtc().toIso8601String())}';
  }

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        // Add auth header when TrailBase API keys are available:
        // 'Authorization': 'Bearer $apiKey',
      };

  DateTime? _getLastSync(String key) {
    if (!_initialized) return null;
    final stored = _metaBox.get(key) as String?;
    if (stored == null) {
      return null;
    }
    try {
      return DateTime.parse(stored);
    } catch (_) {
      return null;
    }
  }

  Future<void> _setLastSync(String key) async {
    await _metaBox.put(key, DateTime.now().toUtc().toIso8601String());
  }

  bool _withinCooldown(DateTime lastSync) =>
      DateTime.now().difference(lastSync) < _kSyncCooldown;

  void _assertInitialized() {
    if (!_initialized) {
      throw StateError(
        'LocalSyncService not initialized. '
        'Call LocalSyncService.instance.initialize() in main() first.',
      );
    }
  }
}

// ── Result types ──────────────────────────────────────────────────────────────

class _BoxSyncResult {
  final int recordsSynced;
  final List<String> errors;
  const _BoxSyncResult({required this.recordsSynced, this.errors = const []});
}

/// Public result returned by syncAll()
class SyncResult {
  final int storesSynced;
  final int rewardsSynced;
  final bool balanceUpdated;
  final List<String> errors;

  const SyncResult({
    required this.storesSynced,
    required this.rewardsSynced,
    required this.balanceUpdated,
    required this.errors,
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get isFullSuccess => !hasErrors;

  @override
  String toString() => 'SyncResult('
      'stores: $storesSynced, '
      'rewards: $rewardsSynced, '
      'balance: $balanceUpdated, '
      'errors: $errors)';
}
