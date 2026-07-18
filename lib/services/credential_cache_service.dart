// ================================================================
// Credential Cache Service - Allin1 Super App
// ================================================================
// Offline caching service for credentials with TTL support,
// offline queue management, and auto-sync capabilities.
//
// Author: NJ TECH
// Version: 1.0.0
// ================================================================

import 'dart:async';
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/credential.dart';
import '../models/credential_category.dart';
import 'session_service.dart';

/// Enum representing the type of offline operation
enum OfflineOperationType {
  create,
  update,
  delete,
}

/// Represents a queued offline operation
class OfflineOperation {
  final String id;
  final OfflineOperationType type;
  final String entityType; // 'credential' or 'category'
  final Map<String, dynamic> data;
  final DateTime timestamp;
  int retryCount;
  String? lastError;

  OfflineOperation({
    required this.id,
    required this.type,
    required this.entityType,
    required this.data,
    DateTime? timestamp,
    this.retryCount = 0,
    this.lastError,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'entityType': entityType,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
      'retryCount': retryCount,
      'lastError': lastError,
    };
  }

  factory OfflineOperation.fromJson(Map<String, dynamic> json) {
    return OfflineOperation(
      id: json['id'] as String,
      type: OfflineOperationType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => OfflineOperationType.create,
      ),
      entityType: json['entityType'] as String,
      data: json['data'] as Map<String, dynamic>,
      timestamp: DateTime.parse(json['timestamp'] as String),
      retryCount: json['retryCount'] as int? ?? 0,
      lastError: json['lastError'] as String?,
    );
  }
}

/// Cache metadata for TTL tracking
class CacheMetadata {
  final String key;
  final DateTime cachedAt;
  final Duration ttl;

  CacheMetadata({
    required this.key,
    required this.cachedAt,
    required this.ttl,
  });

  bool get isExpired => DateTime.now().difference(cachedAt) > ttl;

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'cachedAt': cachedAt.toIso8601String(),
      'ttl': ttl.inMinutes,
    };
  }

  factory CacheMetadata.fromJson(Map<String, dynamic> json) {
    return CacheMetadata(
      key: json['key'] as String,
      cachedAt: DateTime.parse(json['cachedAt'] as String),
      ttl: Duration(minutes: json['ttl'] as int? ?? 5),
    );
  }
}

/// Sync status for UI display
enum SyncStatus {
  idle,
  syncing,
  synced,
  error,
  offline,
}

/// Result class for cache operations
class CacheResult<T> {
  final bool success;
  final T? data;
  final String? error;
  final bool fromCache;

  CacheResult({
    required this.success,
    this.data,
    this.error,
    this.fromCache = false,
  });

  factory CacheResult.success({T? data, bool fromCache = false}) {
    return CacheResult(success: true, data: data, fromCache: fromCache);
  }

  factory CacheResult.failure(String error) {
    return CacheResult(success: false, error: error);
  }
}

/// Credential Cache Service - handles all caching operations
class CredentialCacheService {
  // ================================================================
  // Singleton Pattern
  // ================================================================
  static final CredentialCacheService _instance =
      CredentialCacheService._internal();
  factory CredentialCacheService() => _instance;
  CredentialCacheService._internal();

  // ================================================================
  // Constants
  // ================================================================
  static const String _credentialsCacheBox = 'credentials_cache';
  static const String _categoriesCacheBox = 'categories_cache';
  static const String _offlineQueueBox = 'offline_queue';
  static const String _cacheMetadataBox = 'cache_metadata';
  static const String _syncStatusBox = 'sync_status';

  static const Duration kDefaultTtl = Duration(minutes: 5);
  static const int maxRetryCount = 3;

  // ================================================================
  // Hive Boxes
  // ================================================================
  late Box<dynamic> _credentialsCacheBoxInstance;
  late Box<dynamic> _categoriesCacheBoxInstance;
  late Box<dynamic> _offlineQueueBoxInstance;
  late Box<dynamic> _cacheMetadataBoxInstance;
  late Box<dynamic> _syncStatusBoxInstance;

  // ================================================================
  // State
  // ================================================================
  final SessionService _sessionService = SessionService();
  bool _isInitialized = false;
  bool _isOnline = true;
  Duration _defaultTtl = kDefaultTtl;

  // Stream controllers for sync status
  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  final _connectivityController = StreamController<bool>.broadcast();

  // Timer for periodic cache cleanup
  Timer? _cleanupTimer;

  // ================================================================
  // Properties
  // ================================================================

  /// Whether the cache service is initialized
  bool get isInitialized => _isInitialized;

  /// Current online status
  bool get isOnline => _isOnline;

  /// Stream of sync status changes
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  /// Stream of connectivity changes
  Stream<bool> get connectivityStream => _connectivityController.stream;

  /// Current sync status
  SyncStatus _currentSyncStatus = SyncStatus.idle;
  SyncStatus get currentSyncStatus => _currentSyncStatus;

  /// Default TTL for cache entries
  Duration get defaultTtl => _defaultTtl;

  // ================================================================
  // Initialization
  // ================================================================

  /// Initialize the cache service
  Future<void> init({Duration? ttl}) async {
    if (_isInitialized) {
      return;
    }

    try {
      _defaultTtl = ttl ?? kDefaultTtl;

      // Open Hive boxes
      _credentialsCacheBoxInstance = await Hive.openBox(_credentialsCacheBox);
      _categoriesCacheBoxInstance = await Hive.openBox(_categoriesCacheBox);
      _offlineQueueBoxInstance = await Hive.openBox(_offlineQueueBox);
      _cacheMetadataBoxInstance = await Hive.openBox(_cacheMetadataBox);
      _syncStatusBoxInstance = await Hive.openBox(_syncStatusBox);

      _isInitialized = true;

      // Start periodic cleanup timer
      _startCleanupTimer();

      // Check if there are pending operations to sync
      unawaited(_checkPendingOperations());
    } catch (e) {
      _isInitialized = false;
      rethrow;
    }
  }

  /// Start periodic cache cleanup timer
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _cleanupExpiredCache();
    });
  }

  // ================================================================
  // Connectivity Management
  // ================================================================

  /// Set online status (called by network listener)
  void setOnlineStatus(bool isOnline) {
    if (_isOnline != isOnline) {
      _isOnline = isOnline;
      _connectivityController.add(_isOnline);

      if (_isOnline) {
        // Auto-sync when back online
        _checkPendingOperations();
      } else {
        _updateSyncStatus(SyncStatus.offline);
      }
    }
  }

  // ================================================================
  // Credential Caching
  // ================================================================

  /// Cache credentials list
  Future<void> cacheCredentials(List<Credential> credentials) async {
    _ensureInitialized();
    final userId = _sessionService.getCurrentUid();
    if (userId == null) {
      return;
    }

    final key = 'user_$userId';
    final jsonList = credentials.map((c) => c.toJson()).toList();

    await _credentialsCacheBoxInstance.put(key, jsonEncode(jsonList));
    await _updateCacheMetadata(key, _defaultTtl);
  }

  /// Get cached credentials
  Future<CacheResult<List<Credential>>> getCachedCredentials() async {
    _ensureInitialized();
    final userId = _sessionService.getCurrentUid();
    if (userId == null) {
      return CacheResult.failure('User not logged in');
    }

    final key = 'user_$userId';

    // Check if cache is expired
    if (await _isCacheExpired(key)) {
      return CacheResult.failure('Cache expired');
    }

    final cachedData = _credentialsCacheBoxInstance.get(key);
    if (cachedData == null) {
      return CacheResult.failure('No cached data');
    }

    try {
      final jsonList = jsonDecode(cachedData as String) as List;
      final credentials = jsonList
          .map((json) => Credential.fromJson(json as Map<String, dynamic>))
          .toList();
      return CacheResult.success(data: credentials, fromCache: true);
    } catch (e) {
      return CacheResult.failure('Failed to parse cached data: $e');
    }
  }

  /// Cache a single credential
  Future<void> cacheCredential(Credential credential) async {
    _ensureInitialized();
    final key = credential.id;

    await _credentialsCacheBoxInstance.put(key, credential.toJsonString());
    await _updateCacheMetadata(key, _defaultTtl);
  }

  /// Get cached credential by ID
  Future<CacheResult<Credential>> getCachedCredential(
    String credentialId,
  ) async {
    _ensureInitialized();

    final cachedData = _credentialsCacheBoxInstance.get(credentialId);
    if (cachedData == null) {
      return CacheResult.failure('Credential not in cache');
    }

    try {
      final credential = Credential.fromJson(
        jsonDecode(cachedData as String) as Map<String, dynamic>,
      );
      return CacheResult.success(data: credential, fromCache: true);
    } catch (e) {
      return CacheResult.failure('Failed to parse cached credential: $e');
    }
  }

  /// Update cached credential
  Future<void> updateCachedCredential(Credential credential) async {
    _ensureInitialized();
    await cacheCredential(credential);
  }

  /// Remove credential from cache
  Future<void> removeCachedCredential(String credentialId) async {
    _ensureInitialized();
    await _credentialsCacheBoxInstance.delete(credentialId);
    await _removeCacheMetadata(credentialId);
  }

  // ================================================================
  // Category Caching
  // ================================================================

  /// Cache categories list
  Future<void> cacheCategories(List<CredentialCategory> categories) async {
    _ensureInitialized();
    final userId = _sessionService.getCurrentUid();
    if (userId == null) {
      return;
    }

    final key = 'categories_$userId';
    final jsonList = categories.map((c) => c.toJson()).toList();

    await _categoriesCacheBoxInstance.put(key, jsonEncode(jsonList));
    await _updateCacheMetadata(key, _defaultTtl);
  }

  /// Get cached categories
  Future<CacheResult<List<CredentialCategory>>> getCachedCategories() async {
    _ensureInitialized();
    final userId = _sessionService.getCurrentUid();
    if (userId == null) {
      return CacheResult.failure('User not logged in');
    }

    final key = 'categories_$userId';

    // Check if cache is expired
    if (await _isCacheExpired(key)) {
      return CacheResult.failure('Cache expired');
    }

    final cachedData = _categoriesCacheBoxInstance.get(key);
    if (cachedData == null) {
      return CacheResult.failure('No cached data');
    }

    try {
      final jsonList = jsonDecode(cachedData as String) as List;
      final categories = jsonList
          .map(
            (json) => CredentialCategory.fromJson(json as Map<String, dynamic>),
          )
          .toList();
      return CacheResult.success(data: categories, fromCache: true);
    } catch (e) {
      return CacheResult.failure('Failed to parse cached categories: $e');
    }
  }

  // ================================================================
  // Offline Queue Management
  // ================================================================

  /// Add operation to offline queue
  Future<void> addToOfflineQueue({
    required OfflineOperationType type,
    required String entityType,
    required Map<String, dynamic> data,
  }) async {
    _ensureInitialized();

    final operation = OfflineOperation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      entityType: entityType,
      data: data,
    );

    await _offlineQueueBoxInstance.put(
      operation.id,
      jsonEncode(operation.toJson()),
    );
  }

  /// Get all pending offline operations
  Future<List<OfflineOperation>> getPendingOperations() async {
    _ensureInitialized();

    final operations = <OfflineOperation>[];
    for (final key in _offlineQueueBoxInstance.keys) {
      try {
        final data = _offlineQueueBoxInstance.get(key);
        if (data != null) {
          operations.add(
            OfflineOperation.fromJson(
              jsonDecode(data as String) as Map<String, dynamic>,
            ),
          );
        }
      } catch (e) {
        // Skip malformed entries
      }
    }

    // Sort by timestamp
    operations.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return operations;
  }

  /// Remove operation from queue after successful sync
  Future<void> removeFromOfflineQueue(String operationId) async {
    _ensureInitialized();
    await _offlineQueueBoxInstance.delete(operationId);
  }

  /// Update operation retry count
  Future<void> updateOperationRetry(
    String operationId,
    String error,
    int retryCount,
  ) async {
    _ensureInitialized();

    final data = _offlineQueueBoxInstance.get(operationId);
    if (data != null) {
      final operation = OfflineOperation.fromJson(
        jsonDecode(data as String) as Map<String, dynamic>,
      )
        ..retryCount = retryCount
        ..lastError = error;

      await _offlineQueueBoxInstance.put(
        operationId,
        jsonEncode(operation.toJson()),
      );
    }
  }

  /// Get count of pending operations
  int get pendingOperationsCount {
    if (!_isInitialized) {
      return 0;
    }
    return _offlineQueueBoxInstance.length;
  }

  // ================================================================
  // Sync Operations
  // ================================================================

  /// Sync pending operations to server
  /// This method should be called with actual sync logic from CredentialService
  Future<bool> syncPendingOperations({
    required Future<dynamic> Function(OfflineOperation) syncCallback,
  }) async {
    if (!_isOnline) {
      _updateSyncStatus(SyncStatus.offline);
      return false;
    }

    _updateSyncStatus(SyncStatus.syncing);

    final operations = await getPendingOperations();
    if (operations.isEmpty) {
      _updateSyncStatus(SyncStatus.synced);
      return true;
    }

    bool hasErrors = false;

    for (final operation in operations) {
      try {
        await syncCallback(operation);
        await removeFromOfflineQueue(operation.id);
      } catch (e) {
        hasErrors = true;
        final newRetryCount = operation.retryCount + 1;

        if (newRetryCount >= maxRetryCount) {
          // Max retries reached, remove from queue
          await removeFromOfflineQueue(operation.id);
        } else {
          await updateOperationRetry(
            operation.id,
            e.toString(),
            newRetryCount,
          );
        }
      }
    }

    if (hasErrors) {
      _updateSyncStatus(SyncStatus.error);
    } else {
      _updateSyncStatus(SyncStatus.synced);
    }

    return !hasErrors;
  }

  /// Check and process pending operations
  Future<void> _checkPendingOperations() async {
    if (!_isOnline) {
      return;
    }

    final pendingCount = pendingOperationsCount;
    if (pendingCount > 0) {
      _updateSyncStatus(SyncStatus.syncing);
    }
  }

  // ================================================================
  // Cache Metadata Management
  // ================================================================

  /// Update cache metadata for a key
  Future<void> _updateCacheMetadata(String key, Duration ttl) async {
    final metadata = CacheMetadata(
      key: key,
      cachedAt: DateTime.now(),
      ttl: ttl,
    );
    await _cacheMetadataBoxInstance.put(
      key,
      jsonEncode(metadata.toJson()),
    );
  }

  /// Remove cache metadata
  Future<void> _removeCacheMetadata(String key) async {
    await _cacheMetadataBoxInstance.delete(key);
  }

  /// Check if cache is expired for a key
  Future<bool> _isCacheExpired(String key) async {
    final data = _cacheMetadataBoxInstance.get(key);
    if (data == null) {
      return true;
    }

    try {
      final metadata = CacheMetadata.fromJson(
        jsonDecode(data as String) as Map<String, dynamic>,
      );
      return metadata.isExpired;
    } catch (e) {
      return true;
    }
  }

  /// Cleanup expired cache entries
  Future<void> _cleanupExpiredCache() async {
    if (!_isInitialized) {
      return;
    }

    try {
      // Clean up credentials cache
      for (final key in _credentialsCacheBoxInstance.keys) {
        if (await _isCacheExpired(key as String)) {
          await _credentialsCacheBoxInstance.delete(key);
          await _removeCacheMetadata(key);
        }
      }

      // Clean up categories cache
      for (final key in _categoriesCacheBoxInstance.keys) {
        if (await _isCacheExpired(key as String)) {
          await _categoriesCacheBoxInstance.delete(key);
          await _removeCacheMetadata(key);
        }
      }
    } catch (e) {
      // Log error but don't crash
    }
  }

  // ================================================================
  // Clear Cache
  // ================================================================

  /// Clear all cached data (called on logout)
  Future<void> clearAllCache() async {
    _ensureInitialized();

    await _credentialsCacheBoxInstance.clear();
    await _categoriesCacheBoxInstance.clear();
    await _offlineQueueBoxInstance.clear();
    await _cacheMetadataBoxInstance.clear();
    await _syncStatusBoxInstance.clear();

    _updateSyncStatus(SyncStatus.idle);
  }

  /// Clear only credentials cache
  Future<void> clearCredentialsCache() async {
    _ensureInitialized();
    await _credentialsCacheBoxInstance.clear();
  }

  /// Clear only categories cache
  Future<void> clearCategoriesCache() async {
    _ensureInitialized();
    await _categoriesCacheBoxInstance.clear();
  }

  // ================================================================
  // Helper Methods
  // ================================================================

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError(
        'CredentialCacheService not initialized. Call init() first.',
      );
    }
  }

  void _updateSyncStatus(SyncStatus status) {
    _currentSyncStatus = status;
    _syncStatusController.add(status);
  }

  /// Get sync status text for display
  String getSyncStatusText() {
    switch (_currentSyncStatus) {
      case SyncStatus.idle:
        return 'Up to date';
      case SyncStatus.syncing:
        return 'Syncing...';
      case SyncStatus.synced:
        return 'Synced';
      case SyncStatus.error:
        return 'Sync error';
      case SyncStatus.offline:
        return 'Offline';
    }
  }

  // ================================================================
  // Dispose
  // ================================================================

  /// Dispose resources
  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    await _syncStatusController.close();
    await _connectivityController.close();
  }
}
