// ================================================================
// Credential Provider - Allin1 Super App
// ================================================================
// Provider for credential management with offline caching support.
// Wraps CredentialService and uses CredentialCacheService for caching.
//
// Author: NJ TECH
// Version: 1.0.0
// ================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/credential.dart';
import '../models/credential_category.dart';
import '../services/credential_cache_service.dart';
import '../services/credential_service.dart';
import '../services/session_service.dart';

/// State for credential operations
enum CredentialState {
  initial,
  loading,
  loaded,
  error,
}

/// Provider for managing credentials with offline support
class CredentialProvider extends ChangeNotifier {
  // ================================================================
  // Dependencies
  // ================================================================
  final CredentialService _credentialService = CredentialService();
  final CredentialCacheService _cacheService = CredentialCacheService();
  final SessionService _sessionService = SessionService();

  // ================================================================
  // State
  // ================================================================
  CredentialState _state = CredentialState.initial;
  List<Credential> _credentials = [];
  List<CredentialCategory> _categories = [];
  String? _errorMessage;
  bool _isOnline = true;
  SyncStatus _syncStatus = SyncStatus.idle;

  // Stream subscriptions
  StreamSubscription<SyncStatus>? _syncStatusSubscription;
  StreamSubscription<bool>? _connectivitySubscription;

  // ================================================================
  // Constructor
  // ================================================================
  CredentialProvider() {
    _init();
  }

  // ================================================================
  // Properties
  // ================================================================

  /// Current state
  CredentialState get state => _state;

  /// List of credentials
  List<Credential> get credentials => _credentials;

  /// List of categories
  List<CredentialCategory> get categories => _categories;

  /// Error message if any
  String? get errorMessage => _errorMessage;

  /// Whether device is online
  bool get isOnline => _isOnline;

  /// Current sync status
  SyncStatus get syncStatus => _syncStatus;

  /// Sync status text for display
  String get syncStatusText => _cacheService.getSyncStatusText();

  /// Whether data is currently loading
  bool get isLoading => _state == CredentialState.loading;

  /// Number of pending offline operations
  int get pendingOperationsCount => _cacheService.pendingOperationsCount;

  /// Whether credentials are loaded from cache
  bool _isFromCache = false;
  bool get isFromCache => _isFromCache;

  // ================================================================
  // Initialization
  // ================================================================

  Future<void> _init() async {
    try {
      // Initialize cache service
      await _cacheService.init();

      // Listen to sync status changes
      _syncStatusSubscription = _cacheService.syncStatusStream.listen((status) {
        _syncStatus = status;
        notifyListeners();
      });

      // Listen to connectivity changes
      _connectivitySubscription =
          _cacheService.connectivityStream.listen((isOnline) {
        _isOnline = isOnline;
        notifyListeners();
      });

      // Initial connectivity check
      _isOnline = _sessionService.isLoggedIn();
    } catch (e) {
      _errorMessage = 'Failed to initialize: $e';
      notifyListeners();
    }
  }

  // ================================================================
  // Load Credentials
  // ================================================================

  /// Load user credentials with caching
  Future<void> loadCredentials({bool forceRefresh = false}) async {
    _state = CredentialState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      // If online and not forcing refresh, try cache first
      if (_isOnline && !forceRefresh) {
        final cachedResult = await _cacheService.getCachedCredentials();
        if (cachedResult.success && cachedResult.data != null) {
          _credentials = cachedResult.data!;
          _isFromCache = true;
          _state = CredentialState.loaded;
          notifyListeners();
        }
      }

      // Fetch from server
      final serverCredentials = await _credentialService.getUserCredentials();

      if (serverCredentials.isNotEmpty) {
        _credentials = serverCredentials;
        _isFromCache = false;

        // Update cache
        await _cacheService.cacheCredentials(serverCredentials);
      }

      _state = CredentialState.loaded;
    } catch (e) {
      // Try to get from cache on error
      final cachedResult = await _cacheService.getCachedCredentials();
      if (cachedResult.success && cachedResult.data != null) {
        _credentials = cachedResult.data!;
        _isFromCache = true;
        _errorMessage = 'Showing cached data. Server error: $e';
        _state = CredentialState.loaded;
      } else {
        _errorMessage = 'Failed to load credentials: $e';
        _state = CredentialState.error;
      }
    }

    notifyListeners();
  }

  /// Get a single credential
  Future<Credential?> getCredential(String credentialId) async {
    try {
      // Try cache first
      final cachedResult =
          await _cacheService.getCachedCredential(credentialId);
      if (cachedResult.success && cachedResult.data != null) {
        return cachedResult.data;
      }

      // Fetch from server
      final credential = await _credentialService.getCredential(credentialId);
      if (credential != null) {
        await _cacheService.cacheCredential(credential);
      }
      return credential;
    } catch (e) {
      // Try cache on error
      final cachedResult =
          await _cacheService.getCachedCredential(credentialId);
      return cachedResult.data;
    }
  }

  // ================================================================
  // Load Categories
  // ================================================================

  /// Load categories with caching
  Future<void> loadCategories({bool forceRefresh = false}) async {
    try {
      // If online and not forcing refresh, try cache first
      if (_isOnline && !forceRefresh) {
        final cachedResult = await _cacheService.getCachedCategories();
        if (cachedResult.success && cachedResult.data != null) {
          _categories = cachedResult.data!;
          notifyListeners();
        }
      }

      // Fetch from server
      final serverCategories = await _credentialService.getCategories();

      if (serverCategories.isNotEmpty) {
        _categories = serverCategories;

        // Update cache
        await _cacheService.cacheCategories(serverCategories);
      }
    } catch (e) {
      // Try to get from cache on error
      final cachedResult = await _cacheService.getCachedCategories();
      if (cachedResult.success && cachedResult.data != null) {
        _categories = cachedResult.data!;
      }
    }

    notifyListeners();
  }

  // ================================================================
  // CRUD Operations
  // ================================================================

  /// Create a new credential
  Future<CredentialResult> createCredential({
    required String title,
    required CredentialType type,
    required String username,
    required String password,
    String? url,
    String? notes,
    String? extra,
    String? categoryId,
  }) async {
    if (!_isOnline) {
      // Queue for offline
      await _cacheService.addToOfflineQueue(
        type: OfflineOperationType.create,
        entityType: 'credential',
        data: {
          'title': title,
          'type': type.name,
          'username': username,
          'password': password,
          'url': url,
          'notes': notes,
          'extra': extra,
          'categoryId': categoryId,
        },
      );

      // Optimistically add to local list
      final tempCredential = Credential(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: _sessionService.getCurrentUid() ?? '',
        title: title,
        type: type,
        encryptedUsername: '',
        encryptedPassword: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _credentials.insert(0, tempCredential);
      notifyListeners();

      return CredentialResult.success(credential: tempCredential);
    }

    final result = await _credentialService.createCredential(
      title: title,
      type: type,
      username: username,
      password: password,
      url: url,
      notes: notes,
      extra: extra,
      categoryId: categoryId,
    );

    if (result.success && result.credential != null) {
      _credentials.insert(0, result.credential!);
      await _cacheService.cacheCredential(result.credential!);
      await _cacheService.cacheCredentials(_credentials);
    }

    notifyListeners();
    return result;
  }

  /// Update an existing credential
  Future<CredentialResult> updateCredential({
    required String credentialId,
    String? title,
    CredentialType? type,
    String? username,
    String? password,
    String? url,
    String? notes,
    String? extra,
    String? categoryId,
    bool? isFavorite,
    bool? isPinned,
  }) async {
    if (!_isOnline) {
      // Queue for offline
      await _cacheService.addToOfflineQueue(
        type: OfflineOperationType.update,
        entityType: 'credential',
        data: {
          'credentialId': credentialId,
          'title': title,
          'type': type?.name,
          'username': username,
          'password': password,
          'url': url,
          'notes': notes,
          'extra': extra,
          'categoryId': categoryId,
          'isFavorite': isFavorite,
          'isPinned': isPinned,
        },
      );

      // Optimistically update local list
      final index = _credentials.indexWhere((c) => c.id == credentialId);
      if (index != -1) {
        final updated = _credentials[index].copyWith(
          title: title ?? _credentials[index].title,
          type: type ?? _credentials[index].type,
          categoryId: categoryId ?? _credentials[index].categoryId,
          isFavorite: isFavorite ?? _credentials[index].isFavorite,
          isPinned: isPinned ?? _credentials[index].isPinned,
          updatedAt: DateTime.now(),
        );
        _credentials[index] = updated;
      }
      notifyListeners();

      return CredentialResult.success();
    }

    final result = await _credentialService.updateCredential(
      credentialId: credentialId,
      title: title,
      type: type,
      username: username,
      password: password,
      url: url,
      notes: notes,
      extra: extra,
      categoryId: categoryId,
      isFavorite: isFavorite,
      isPinned: isPinned,
    );

    if (result.success && result.credential != null) {
      final index = _credentials.indexWhere((c) => c.id == credentialId);
      if (index != -1) {
        _credentials[index] = result.credential!;
      }
      await _cacheService.updateCachedCredential(result.credential!);
      await _cacheService.cacheCredentials(_credentials);
    }

    notifyListeners();
    return result;
  }

  /// Delete a credential
  Future<CredentialResult> deleteCredential(String credentialId) async {
    if (!_isOnline) {
      // Queue for offline
      await _cacheService.addToOfflineQueue(
        type: OfflineOperationType.delete,
        entityType: 'credential',
        data: {'credentialId': credentialId},
      );

      // Optimistically remove from local list
      _credentials.removeWhere((c) => c.id == credentialId);
      notifyListeners();

      return CredentialResult.success();
    }

    final result = await _credentialService.deleteCredential(credentialId);

    if (result.success) {
      _credentials.removeWhere((c) => c.id == credentialId);
      await _cacheService.removeCachedCredential(credentialId);
      await _cacheService.cacheCredentials(_credentials);
    }

    notifyListeners();
    return result;
  }

  /// Toggle favorite status
  Future<CredentialResult> toggleFavorite(String credentialId) async {
    final credential = _credentials.firstWhere(
      (c) => c.id == credentialId,
      orElse: () {
        throw Exception('Credential not found');
      },
    );

    return updateCredential(
      credentialId: credentialId,
      isFavorite: !credential.isFavorite,
    );
  }

  /// Toggle pin status
  Future<CredentialResult> togglePin(String credentialId) async {
    final credential = _credentials.firstWhere(
      (c) => c.id == credentialId,
      orElse: () {
        throw Exception('Credential not found');
      },
    );

    return updateCredential(
      credentialId: credentialId,
      isPinned: !credential.isPinned,
    );
  }

  // ================================================================
  // Search & Filter
  // ================================================================

  /// Search credentials by title
  List<Credential> searchCredentials(String query) {
    if (query.isEmpty) {
      return _credentials;
    }

    final lowerQuery = query.toLowerCase();
    return _credentials.where((credential) {
      return credential.title.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// Get credentials by category
  List<Credential> getCredentialsByCategory(String categoryId) {
    return _credentials.where((credential) {
      return credential.categoryId == categoryId;
    }).toList();
  }

  /// Get favorite credentials
  List<Credential> get favoriteCredentials {
    return _credentials.where((credential) => credential.isFavorite).toList();
  }

  /// Get pinned credentials
  List<Credential> get pinnedCredentials {
    return _credentials.where((credential) => credential.isPinned).toList();
  }

  // ================================================================
  // Sync Operations
  // ================================================================

  /// Manually trigger sync
  Future<void> syncNow() async {
    if (!_isOnline) {
      _errorMessage = 'Cannot sync while offline';
      notifyListeners();
      return;
    }

    await _cacheService.syncPendingOperations(
      syncCallback: _syncOperation,
    );

    // Reload data after sync
    await loadCredentials(forceRefresh: true);
    await loadCategories(forceRefresh: true);
  }

  /// Sync a single offline operation
  Future<dynamic> _syncOperation(OfflineOperation operation) async {
    switch (operation.entityType) {
      case 'credential':
        return _syncCredentialOperation(operation);
      case 'category':
        return _syncCategoryOperation(operation);
      default:
        throw Exception('Unknown entity type: ${operation.entityType}');
    }
  }

  /// Sync credential operation
  Future<dynamic> _syncCredentialOperation(OfflineOperation operation) async {
    final data = operation.data;

    switch (operation.type) {
      case OfflineOperationType.create:
        return _credentialService.createCredential(
          title: data['title'] as String,
          type: CredentialType.fromString(data['type'] as String),
          username: data['username'] as String,
          password: data['password'] as String,
          url: data['url'] as String?,
          notes: data['notes'] as String?,
          extra: data['extra'] as String?,
          categoryId: data['categoryId'] as String?,
        );
      case OfflineOperationType.update:
        return _credentialService.updateCredential(
          credentialId: data['credentialId'] as String,
          title: data['title'] as String?,
          type: data['type'] != null
              ? CredentialType.fromString(data['type'] as String)
              : null,
          username: data['username'] as String?,
          password: data['password'] as String?,
          url: data['url'] as String?,
          notes: data['notes'] as String?,
          extra: data['extra'] as String?,
          categoryId: data['categoryId'] as String?,
          isFavorite: data['isFavorite'] as bool?,
          isPinned: data['isPinned'] as bool?,
        );
      case OfflineOperationType.delete:
        return _credentialService.deleteCredential(
          data['credentialId'] as String,
        );
    }
  }

  /// Sync category operation
  Future<dynamic> _syncCategoryOperation(OfflineOperation operation) async {
    final data = operation.data;

    switch (operation.type) {
      case OfflineOperationType.create:
        return _credentialService.createCategory(
          name: data['name'] as String,
          icon: data['icon'] as String?,
          color: data['color'] as String?,
        );
      case OfflineOperationType.update:
        return _credentialService.updateCategory(
          categoryId: data['categoryId'] as String,
          name: data['name'] as String?,
          icon: data['icon'] as String?,
          color: data['color'] as String?,
        );
      case OfflineOperationType.delete:
        return _credentialService.deleteCategory(
          data['categoryId'] as String,
        );
    }
  }

  /// Set online status (for external network monitoring)
  void setOnlineStatus({required bool isOnline}) {
    _isOnline = isOnline;
    _cacheService.setOnlineStatus(isOnline: isOnline);
    notifyListeners();
  }

  // ================================================================
  // Clear Cache
  // ================================================================

  /// Clear all cached data (call on logout)
  Future<void> clearCache() async {
    await _cacheService.clearAllCache();
    _credentials = [];
    _categories = [];
    _state = CredentialState.initial;
    notifyListeners();
  }

  // ================================================================
  // Refresh
  // ================================================================

  /// Refresh all data
  Future<void> refresh() async {
    await loadCredentials(forceRefresh: true);
    await loadCategories(forceRefresh: true);
  }

  // ================================================================
  // Dispose
  // ================================================================

  @override
  void dispose() {
    _syncStatusSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _cacheService.dispose();
    super.dispose();
  }
}
