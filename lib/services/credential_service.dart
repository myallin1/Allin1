// ================================================================
// Credential Service - Allin1 Super App
// ================================================================
// Comprehensive credential management service with CRUD operations,
// encryption, search, filtering, and sharing capabilities.
// Uses Firebase Firestore for storage and encryption for sensitive data.
//
// Author: NJ TECH
// Version: 1.0.0
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/credential.dart' hide Timestamp;
import '../models/credential_category.dart' hide Timestamp;
import 'credential_cache_service.dart';
import 'encryption_service.dart';
import 'session_service.dart';
import './firestore_usage_tracking.dart';

// ================================================================
// Credential Result Class
// ================================================================
class CredentialResult {
  final bool success;
  final String? error;
  final Credential? credential;

  CredentialResult({
    required this.success,
    this.error,
    this.credential,
  });

  factory CredentialResult.success({Credential? credential}) {
    return CredentialResult(success: true, credential: credential);
  }

  factory CredentialResult.failure(String error) {
    return CredentialResult(success: false, error: error);
  }
}

// ================================================================
// Credential Service
// ================================================================
class CredentialService {
  // ================================================================
  // Singleton Pattern
  // ================================================================
  static final CredentialService _instance = CredentialService._internal();
  factory CredentialService() => _instance;
  CredentialService._internal();

  // ================================================================
  // Dependencies
  // ================================================================
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final EncryptionService _encryption = EncryptionService();
  final SessionService _sessionService = SessionService();
  final CredentialCacheService _cacheService = CredentialCacheService();

  // Caching enabled flag
  bool _cachingEnabled = false;

  // ================================================================
  // Cache Control
  // ================================================================

  /// Enable caching for this service
  Future<void> enableCaching() async {
    if (!_cacheService.isInitialized) {
      await _cacheService.init();
    }
    _cachingEnabled = true;
  }

  /// Disable caching for this service
  void disableCaching() {
    _cachingEnabled = false;
  }

  /// Check if caching is enabled
  bool get isCachingEnabled => _cachingEnabled;

  /// Get cache service instance
  CredentialCacheService get cacheService => _cacheService;

  // ================================================================
  // Collection References
  // ================================================================
  CollectionReference get _credentialsCollection =>
      _firestore.collection('credentials');

  CollectionReference get _categoriesCollection =>
      _firestore.collection('credentialCategories');

  CollectionReference get _accessCollection =>
      _firestore.collection('credentialAccess');

  // ================================================================
  // User Context
  // ================================================================

  /// Get current user ID
  String? get currentUserId => _auth.currentUser?.uid;

  /// Check if user is logged in
  bool get isLoggedIn => _auth.currentUser != null;

  /// Check if encryption service is initialized
  bool get isEncryptionReady => _encryption.isInitialized;

  // ================================================================
  // Cache Operations
  // ================================================================

  /// Clear all cached credentials (call on logout)
  Future<void> clearCache() async {
    await _cacheService.clearAllCache();
    _cachingEnabled = false;
  }

  /// Clear only credentials cache
  Future<void> clearCredentialsCache() async {
    await _cacheService.clearCredentialsCache();
  }

  /// Clear only categories cache
  Future<void> clearCategoriesCache() async {
    await _cacheService.clearCategoriesCache();
  }

  /// Get sync status
  SyncStatus get syncStatus => _cacheService.currentSyncStatus;

  /// Get sync status text
  String get syncStatusText => _cacheService.getSyncStatusText();

  /// Get pending operations count
  int get pendingOperationsCount => _cacheService.pendingOperationsCount;

  // ================================================================
  // CRUD Operations - Create
  // ================================================================

  /// Create a new credential with encryption
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
    try {
      // Validate inputs
      if (!isLoggedIn) {
        return CredentialResult.failure('User not logged in');
      }

      if (title.isEmpty) {
        return CredentialResult.failure('Title is required');
      }

      if (title.length > 100) {
        return CredentialResult.failure(
          'Title must be less than 100 characters',
        );
      }

      if (username.isEmpty) {
        return CredentialResult.failure('Username is required');
      }

      if (password.isEmpty) {
        return CredentialResult.failure('Password is required');
      }

      if (!isEncryptionReady) {
        return CredentialResult.failure('Encryption service not initialized');
      }

      final userId = currentUserId!;
      final credentialId = _credentialsCollection.doc().id;
      final now = DateTime.now();

      // Encrypt sensitive fields
      final encryptedFields = _encryption.encryptCredentialFields(
        username: username,
        password: password,
        url: url,
        notes: notes,
        extra: extra,
      );

      // Create credential object
      final credential = Credential(
        id: credentialId,
        userId: userId,
        title: title.trim(),
        type: type,
        encryptedUsername: encryptedFields['encryptedUsername'] ?? '',
        encryptedPassword: encryptedFields['encryptedPassword'] ?? '',
        encryptedUrl: encryptedFields['encryptedUrl'],
        encryptedNotes: encryptedFields['encryptedNotes'],
        encryptedExtra: encryptedFields['encryptedExtra'],
        categoryId: categoryId,
        createdAt: now,
        updatedAt: now,
        sharedWith: [],
      );

      // Generate checksum for data integrity
      final checksum = _generateChecksum(credential);

      // Save to Firestore
      await _credentialsCollection.doc(credentialId).set({
        ...credential.toJson(),
        'checksum': checksum,
      });

      // Update cache
      if (_cachingEnabled) {
        await _cacheService.cacheCredential(credential);
        final credentials = await getUserCredentials();
        await _cacheService.cacheCredentials(credentials);
      }

      return CredentialResult.success(credential: credential);
    } on FirebaseException catch (e) {
      return CredentialResult.failure(
        'Failed to create credential: ${e.message}',
      );
    } catch (e) {
      return CredentialResult.failure('Failed to create credential: $e');
    }
  }

  // ================================================================
  // CRUD Operations - Read
  // ================================================================

  /// Get a single credential by ID
  Future<Credential?> getCredential(String credentialId) async {
    try {
      if (!isLoggedIn) {
        return null;
      }

      // Try cache first if caching is enabled
      if (_cachingEnabled) {
        final cachedResult =
            await _cacheService.getCachedCredential(credentialId);
        if (cachedResult.success && cachedResult.data != null) {
          return cachedResult.data;
        }
      }

      final doc = await _credentialsCollection.doc(credentialId).trackedGet();
      if (!doc.exists) {
        return null;
      }

      final data = doc.data()! as Map<String, dynamic>;

      // Check access permission
      final userId = currentUserId!;
      final credential = Credential.fromJson(data);

      // Allow if owner, shared with, or admin
      if (credential.userId != userId &&
          !credential.sharedWith.contains(userId) &&
          !_sessionService.isAdmin()) {
        return null;
      }

      // Don't return soft-deleted credentials to regular users
      if (credential.isDeleted && !_sessionService.isAdmin()) {
        return null;
      }

      // Update cache
      if (_cachingEnabled) {
        await _cacheService.cacheCredential(credential);
      }

      return credential;
    } catch (e) {
      // Try to return cached data on error
      if (_cachingEnabled) {
        final cachedResult =
            await _cacheService.getCachedCredential(credentialId);
        return cachedResult.data;
      }
      return null;
    }
  }

  /// Get decrypted credential with all fields
  Future<Map<String, String?>?> getDecryptedCredential(
    String credentialId,
  ) async {
    final credential = await getCredential(credentialId);
    if (credential == null) {
      return null;
    }

    if (!isEncryptionReady) {
      return null;
    }

    // Update last accessed time
    await _updateLastAccessed(credentialId);

    return _encryption.decryptCredentialFields(
      encryptedUsername: credential.encryptedUsername,
      encryptedPassword: credential.encryptedPassword,
      encryptedUrl: credential.encryptedUrl,
      encryptedNotes: credential.encryptedNotes,
      encryptedExtra: credential.encryptedExtra,
    );
  }

  /// Get all credentials for current user
  Future<List<Credential>> getUserCredentials({
    bool includeDeleted = false,
    bool forceRefresh = false,
  }) async {
    try {
      if (!isLoggedIn) {
        return [];
      }

      // Try cache first if caching is enabled and not forcing refresh
      if (_cachingEnabled && !forceRefresh) {
        final cachedResult = await _cacheService.getCachedCredentials();
        if (cachedResult.success && cachedResult.data != null) {
          return cachedResult.data!;
        }
      }

      final userId = currentUserId!;

      QuerySnapshot querySnapshot;

      if (includeDeleted && _sessionService.isAdmin()) {
        // Admin can see all including deleted
        querySnapshot = await _credentialsCollection
            .where('userId', isEqualTo: userId)
            .orderBy('updatedAt', descending: true)
            .get();
      } else {
        // Regular users see non-deleted only
        querySnapshot = await _credentialsCollection
            .where('userId', isEqualTo: userId)
            .where('isDeleted', isEqualTo: false)
            .orderBy('isPinned', descending: true)
            .orderBy('updatedAt', descending: true)
            .get();
      }

      final credentials = querySnapshot.docs
          .map(
            (doc) => Credential.fromJson(doc.data()! as Map<String, dynamic>),
          )
          .toList();

      // Update cache
      if (_cachingEnabled && credentials.isNotEmpty) {
        await _cacheService.cacheCredentials(credentials);
      }

      return credentials;
    } catch (e) {
      // Try to return cached data on error
      if (_cachingEnabled) {
        final cachedResult = await _cacheService.getCachedCredentials();
        if (cachedResult.success && cachedResult.data != null) {
          return cachedResult.data!;
        }
      }
      return [];
    }
  }

  /// Watch credentials stream for real-time updates
  Stream<List<Credential>> watchCredentials() {
    if (!isLoggedIn) {
      return Stream.value([]);
    }

    final userId = currentUserId!;

    return _credentialsCollection
        .where('userId', isEqualTo: userId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('isPinned', descending: true)
        .orderBy('updatedAt', descending: true)
        .trackedSnapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) =>
                    Credential.fromJson(doc.data()! as Map<String, dynamic>),
              )
              .toList(),
        );
  }

  // ================================================================
  // CRUD Operations - Update
  // ================================================================

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
    try {
      if (!isLoggedIn) {
        return CredentialResult.failure('User not logged in');
      }

      if (!isEncryptionReady) {
        return CredentialResult.failure('Encryption service not initialized');
      }

      // Get existing credential
      final existingCredential = await getCredential(credentialId);
      if (existingCredential == null) {
        return CredentialResult.failure('Credential not found');
      }

      // Check ownership
      if (existingCredential.userId != currentUserId) {
        return CredentialResult.failure(
          'Not authorized to update this credential',
        );
      }

      final now = DateTime.now();

      // Encrypt new sensitive fields if provided
      String? encryptedUsername;
      String? encryptedPassword;
      String? encryptedUrl;
      String? encryptedNotes;
      String? encryptedExtra;

      if (username != null ||
          password != null ||
          url != null ||
          notes != null ||
          extra != null) {
        final decrypted = _encryption.decryptCredentialFields(
          encryptedUsername: existingCredential.encryptedUsername,
          encryptedPassword: existingCredential.encryptedPassword,
          encryptedUrl: existingCredential.encryptedUrl,
          encryptedNotes: existingCredential.encryptedNotes,
          encryptedExtra: existingCredential.encryptedExtra,
        );

        final newUsername = username ?? decrypted['username'] ?? '';
        final newPassword = password ?? decrypted['password'] ?? '';
        final newUrl = url ?? decrypted['url'];
        final newNotes = notes ?? decrypted['notes'];
        final newExtra = extra ?? decrypted['extra'];

        final encryptedFields = _encryption.encryptCredentialFields(
          username: newUsername,
          password: newPassword,
          url: newUrl,
          notes: newNotes,
          extra: newExtra,
        );

        encryptedUsername = encryptedFields['encryptedUsername'];
        encryptedPassword = encryptedFields['encryptedPassword'];
        encryptedUrl = encryptedFields['encryptedUrl'];
        encryptedNotes = encryptedFields['encryptedNotes'];
        encryptedExtra = encryptedFields['encryptedExtra'];
      }

      // Build updated credential
      final updatedCredential = existingCredential.copyWith(
        title: title?.trim() ?? existingCredential.title,
        type: type ?? existingCredential.type,
        encryptedUsername:
            encryptedUsername ?? existingCredential.encryptedUsername,
        encryptedPassword:
            encryptedPassword ?? existingCredential.encryptedPassword,
        encryptedUrl: encryptedUrl ?? existingCredential.encryptedUrl,
        encryptedNotes: encryptedNotes ?? existingCredential.encryptedNotes,
        encryptedExtra: encryptedExtra ?? existingCredential.encryptedExtra,
        categoryId: categoryId ?? existingCredential.categoryId,
        isFavorite: isFavorite ?? existingCredential.isFavorite,
        isPinned: isPinned ?? existingCredential.isPinned,
        updatedAt: now,
      );

      // Generate new checksum
      final checksum = _generateChecksum(updatedCredential);

      // Update in Firestore
      await _credentialsCollection.doc(credentialId).update({
        ...updatedCredential.toJson(),
        'checksum': checksum,
      });

      // Update cache
      if (_cachingEnabled) {
        await _cacheService.updateCachedCredential(updatedCredential);
        final credentials = await getUserCredentials();
        await _cacheService.cacheCredentials(credentials);
      }

      return CredentialResult.success(credential: updatedCredential);
    } on FirebaseException catch (e) {
      return CredentialResult.failure(
        'Failed to update credential: ${e.message}',
      );
    } catch (e) {
      return CredentialResult.failure('Failed to update credential: $e');
    }
  }

  /// Toggle favorite status
  Future<CredentialResult> toggleFavorite(String credentialId) async {
    final credential = await getCredential(credentialId);
    if (credential == null) {
      return CredentialResult.failure('Credential not found');
    }

    return updateCredential(
      credentialId: credentialId,
      isFavorite: !credential.isFavorite,
    );
  }

  /// Toggle pin status
  Future<CredentialResult> togglePin(String credentialId) async {
    final credential = await getCredential(credentialId);
    if (credential == null) {
      return CredentialResult.failure('Credential not found');
    }

    return updateCredential(
      credentialId: credentialId,
      isPinned: !credential.isPinned,
    );
  }

  // ================================================================
  // CRUD Operations - Delete
  // ================================================================

  /// Soft delete - mark as deleted
  Future<CredentialResult> deleteCredential(String credentialId) async {
    try {
      if (!isLoggedIn) {
        return CredentialResult.failure('User not logged in');
      }

      final credential = await getCredential(credentialId);
      if (credential == null) {
        return CredentialResult.failure('Credential not found');
      }

      // Check ownership or admin
      if (credential.userId != currentUserId && !_sessionService.isAdmin()) {
        return CredentialResult.failure(
          'Not authorized to delete this credential',
        );
      }

      await _credentialsCollection.doc(credentialId).update({
        'isDeleted': true,
        'updatedAt': DateTime.now(),
      });

      // Update cache
      if (_cachingEnabled) {
        await _cacheService.removeCachedCredential(credentialId);
        final credentials = await getUserCredentials();
        await _cacheService.cacheCredentials(credentials);
      }

      return CredentialResult.success();
    } on FirebaseException catch (e) {
      return CredentialResult.failure(
        'Failed to delete credential: ${e.message}',
      );
    } catch (e) {
      return CredentialResult.failure('Failed to delete credential: $e');
    }
  }

  /// Restore soft-deleted credential
  Future<CredentialResult> restoreCredential(String credentialId) async {
    try {
      if (!isLoggedIn) {
        return CredentialResult.failure('User not logged in');
      }

      final doc = await _credentialsCollection.doc(credentialId).trackedGet();
      if (!doc.exists) {
        return CredentialResult.failure('Credential not found');
      }

      final data = doc.data()! as Map<String, dynamic>;
      final credential = Credential.fromJson(data);

      // Check ownership
      if (credential.userId != currentUserId && !_sessionService.isAdmin()) {
        return CredentialResult.failure(
          'Not authorized to restore this credential',
        );
      }

      await _credentialsCollection.doc(credentialId).update({
        'isDeleted': false,
        'updatedAt': DateTime.now(),
      });

      return CredentialResult.success();
    } on FirebaseException catch (e) {
      return CredentialResult.failure(
        'Failed to restore credential: ${e.message}',
      );
    } catch (e) {
      return CredentialResult.failure('Failed to restore credential: $e');
    }
  }

  /// Permanent delete - hard delete
  Future<CredentialResult> permanentDeleteCredential(
    String credentialId,
  ) async {
    try {
      if (!isLoggedIn) {
        return CredentialResult.failure('User not logged in');
      }

      // Only admins can permanently delete
      if (!_sessionService.isAdmin()) {
        return CredentialResult.failure('Not authorized to permanently delete');
      }

      // Get credential to verify
      final doc = await _credentialsCollection.doc(credentialId).trackedGet();
      if (!doc.exists) {
        return CredentialResult.failure('Credential not found');
      }

      // Delete from Firestore
      await _credentialsCollection.doc(credentialId).trackedDelete();

      // Also delete any access records
      await _deleteAccessRecords(credentialId);

      return CredentialResult.success();
    } on FirebaseException catch (e) {
      return CredentialResult.failure(
        'Failed to permanently delete: ${e.message}',
      );
    } catch (e) {
      return CredentialResult.failure('Failed to permanently delete: $e');
    }
  }

  // ================================================================
  // Category Operations
  // ================================================================

  /// Create a new category
  Future<CredentialResult> createCategory({
    required String name,
    String? icon,
    String? color,
    int sortOrder = 0,
  }) async {
    try {
      if (!isLoggedIn) {
        return CredentialResult.failure('User not logged in');
      }

      if (name.isEmpty) {
        return CredentialResult.failure('Category name is required');
      }

      if (name.length > 50) {
        return CredentialResult.failure(
          'Category name must be less than 50 characters',
        );
      }

      final userId = currentUserId!;
      final categoryId = _categoriesCollection.doc().id;
      final now = DateTime.now();

      final category = CredentialCategory(
        id: categoryId,
        userId: userId,
        name: name.trim(),
        icon: icon,
        color: color,
        sortOrder: sortOrder,
        createdAt: now,
      );

      await _categoriesCollection.doc(categoryId).trackedSet(category.toJson());

      return CredentialResult.success();
    } on FirebaseException catch (e) {
      return CredentialResult.failure(
        'Failed to create category: ${e.message}',
      );
    } catch (e) {
      return CredentialResult.failure('Failed to create category: $e');
    }
  }

  /// Get all categories for current user
  Future<List<CredentialCategory>> getCategories({
    bool forceRefresh = false,
  }) async {
    try {
      if (!isLoggedIn) {
        return [];
      }

      // Try cache first if caching is enabled and not forcing refresh
      if (_cachingEnabled && !forceRefresh) {
        final cachedResult = await _cacheService.getCachedCategories();
        if (cachedResult.success && cachedResult.data != null) {
          return cachedResult.data!;
        }
      }

      final userId = currentUserId!;

      final querySnapshot = await _categoriesCollection
          .where('userId', isEqualTo: userId)
          .orderBy('sortOrder')
          .get();

      final categories = querySnapshot.docs
          .map(
            (doc) => CredentialCategory.fromJson(
              doc.data()! as Map<String, dynamic>,
            ),
          )
          .toList();

      // Update cache
      if (_cachingEnabled && categories.isNotEmpty) {
        await _cacheService.cacheCategories(categories);
      }

      return categories;
    } catch (e) {
      // Try to return cached data on error
      if (_cachingEnabled) {
        final cachedResult = await _cacheService.getCachedCategories();
        if (cachedResult.success && cachedResult.data != null) {
          return cachedResult.data!;
        }
      }
      return [];
    }
  }

  /// Watch categories stream
  Stream<List<CredentialCategory>> watchCategories() {
    if (!isLoggedIn) {
      return Stream.value([]);
    }

    final userId = currentUserId!;

    return _categoriesCollection
        .where('userId', isEqualTo: userId)
        .orderBy('sortOrder')
        .trackedSnapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => CredentialCategory.fromJson(
                  doc.data()! as Map<String, dynamic>,
                ),
              )
              .toList(),
        );
  }

  /// Update a category
  Future<CredentialResult> updateCategory({
    required String categoryId,
    String? name,
    String? icon,
    String? color,
    int? sortOrder,
  }) async {
    try {
      if (!isLoggedIn) {
        return CredentialResult.failure('User not logged in');
      }

      final doc = await _categoriesCollection.doc(categoryId).trackedGet();
      if (!doc.exists) {
        return CredentialResult.failure('Category not found');
      }

      final data = doc.data()! as Map<String, dynamic>;
      final category = CredentialCategory.fromJson(data);

      // Check ownership
      if (category.userId != currentUserId) {
        return CredentialResult.failure(
          'Not authorized to update this category',
        );
      }

      await _categoriesCollection.doc(categoryId).update({
        if (name != null) 'name': name.trim(),
        if (icon != null) 'icon': icon,
        if (color != null) 'color': color,
        if (sortOrder != null) 'sortOrder': sortOrder,
      });

      return CredentialResult.success();
    } on FirebaseException catch (e) {
      return CredentialResult.failure(
        'Failed to update category: ${e.message}',
      );
    } catch (e) {
      return CredentialResult.failure('Failed to update category: $e');
    }
  }

  /// Delete a category
  Future<CredentialResult> deleteCategory(String categoryId) async {
    try {
      if (!isLoggedIn) {
        return CredentialResult.failure('User not logged in');
      }

      final doc = await _categoriesCollection.doc(categoryId).trackedGet();
      if (!doc.exists) {
        return CredentialResult.failure('Category not found');
      }

      final data = doc.data()! as Map<String, dynamic>;
      final category = CredentialCategory.fromJson(data);

      // Check ownership
      if (category.userId != currentUserId) {
        return CredentialResult.failure(
          'Not authorized to delete this category',
        );
      }

      await _categoriesCollection.doc(categoryId).trackedDelete();

      return CredentialResult.success();
    } on FirebaseException catch (e) {
      return CredentialResult.failure(
        'Failed to delete category: ${e.message}',
      );
    } catch (e) {
      return CredentialResult.failure('Failed to delete category: $e');
    }
  }

  // ================================================================
  // Search & Filter Operations
  // ================================================================

  /// Search credentials by title
  Future<List<Credential>> searchCredentials(String query) async {
    try {
      if (!isLoggedIn || query.isEmpty) {
        return [];
      }

      final userId = currentUserId!;
      final queryLower = query.toLowerCase();

      // Get all credentials and filter locally (Firestore doesn't support text search)
      final querySnapshot = await _credentialsCollection
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .get();

      final credentials = querySnapshot.docs
          .map(
            (doc) => Credential.fromJson(doc.data()! as Map<String, dynamic>),
          )
          .where(
            (credential) => credential.title.toLowerCase().contains(queryLower),
          )
          .toList();

      return credentials;
    } catch (e) {
      return [];
    }
  }

  /// Get credentials by category
  Future<List<Credential>> getCredentialsByCategory(String categoryId) async {
    try {
      if (!isLoggedIn) {
        return [];
      }

      final userId = currentUserId!;

      final querySnapshot = await _credentialsCollection
          .where('userId', isEqualTo: userId)
          .where('categoryId', isEqualTo: categoryId)
          .where('isDeleted', isEqualTo: false)
          .orderBy('isPinned', descending: true)
          .orderBy('updatedAt', descending: true)
          .get();

      return querySnapshot.docs
          .map(
            (doc) => Credential.fromJson(doc.data()! as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Get favorite credentials
  Future<List<Credential>> getFavoriteCredentials() async {
    try {
      if (!isLoggedIn) {
        return [];
      }

      final userId = currentUserId!;

      final querySnapshot = await _credentialsCollection
          .where('userId', isEqualTo: userId)
          .where('isFavorite', isEqualTo: true)
          .where('isDeleted', isEqualTo: false)
          .orderBy('updatedAt', descending: true)
          .get();

      return querySnapshot.docs
          .map(
            (doc) => Credential.fromJson(doc.data()! as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Get credentials by type
  Future<List<Credential>> getCredentialsByType(CredentialType type) async {
    try {
      if (!isLoggedIn) {
        return [];
      }

      final userId = currentUserId!;

      final querySnapshot = await _credentialsCollection
          .where('userId', isEqualTo: userId)
          .where('type', isEqualTo: type.name)
          .where('isDeleted', isEqualTo: false)
          .orderBy('updatedAt', descending: true)
          .get();

      return querySnapshot.docs
          .map(
            (doc) => Credential.fromJson(doc.data()! as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Get deleted credentials (trash)
  Future<List<Credential>> getDeletedCredentials() async {
    try {
      if (!isLoggedIn) {
        return [];
      }

      final userId = currentUserId!;

      final querySnapshot = await _credentialsCollection
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: true)
          .orderBy('updatedAt', descending: true)
          .get();

      return querySnapshot.docs
          .map(
            (doc) => Credential.fromJson(doc.data()! as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      return [];
    }
  }

  // ================================================================
  // Sharing Operations
  // ================================================================

  /// Share credential with another user
  Future<CredentialResult> shareCredential({
    required String credentialId,
    required String targetUserId,
  }) async {
    try {
      if (!isLoggedIn) {
        return CredentialResult.failure('User not logged in');
      }

      final credential = await getCredential(credentialId);
      if (credential == null) {
        return CredentialResult.failure('Credential not found');
      }

      // Check ownership
      if (credential.userId != currentUserId) {
        return CredentialResult.failure(
          'Not authorized to share this credential',
        );
      }

      // Don't share if already shared with this user
      if (credential.sharedWith.contains(targetUserId)) {
        return CredentialResult.failure('Already shared with this user');
      }

      // Add to sharedWith list
      final updatedSharedWith = [...credential.sharedWith, targetUserId];

      await _credentialsCollection.doc(credentialId).update({
        'sharedWith': updatedSharedWith,
        'updatedAt': DateTime.now(),
      });

      // Create access record
      await _createAccessRecord(
        ownerId: currentUserId!,
        accessorId: targetUserId,
        credentialId: credentialId,
        accessLevel: 'read',
      );

      return CredentialResult.success();
    } on FirebaseException catch (e) {
      return CredentialResult.failure(
        'Failed to share credential: ${e.message}',
      );
    } catch (e) {
      return CredentialResult.failure('Failed to share credential: $e');
    }
  }

  /// Revoke sharing access
  Future<CredentialResult> revokeAccess({
    required String credentialId,
    required String targetUserId,
  }) async {
    try {
      if (!isLoggedIn) {
        return CredentialResult.failure('User not logged in');
      }

      final credential = await getCredential(credentialId);
      if (credential == null) {
        return CredentialResult.failure('Credential not found');
      }

      // Check ownership
      if (credential.userId != currentUserId) {
        return CredentialResult.failure('Not authorized to revoke access');
      }

      // Remove from sharedWith list
      final updatedSharedWith = credential.sharedWith
          .where((userId) => userId != targetUserId)
          .toList();

      await _credentialsCollection.doc(credentialId).update({
        'sharedWith': updatedSharedWith,
        'updatedAt': DateTime.now(),
      });

      // Delete access record
      await _deleteAccessRecord(targetUserId, credentialId);

      return CredentialResult.success();
    } on FirebaseException catch (e) {
      return CredentialResult.failure('Failed to revoke access: ${e.message}');
    } catch (e) {
      return CredentialResult.failure('Failed to revoke access: $e');
    }
  }

  /// Get credentials shared with current user
  Future<List<Credential>> getSharedWithMe() async {
    try {
      if (!isLoggedIn) {
        return [];
      }

      final userId = currentUserId!;

      // Get credentials where userId matches (owned by user)
      final ownedQuery = await _credentialsCollection
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .get();

      final ownedCredentials = ownedQuery.docs
          .map(
            (doc) => Credential.fromJson(doc.data()! as Map<String, dynamic>),
          )
          .toList();

      // Get credentials shared with user
      final sharedQuery = await _credentialsCollection
          .where('sharedWith', arrayContains: userId)
          .where('isDeleted', isEqualTo: false)
          .get();

      final sharedCredentials = sharedQuery.docs
          .map(
            (doc) => Credential.fromJson(doc.data()! as Map<String, dynamic>),
          )
          .toList();

      // Combine and return
      final allCredentials = [...ownedCredentials, ...sharedCredentials];

      // Remove duplicates by ID
      final uniqueCredentials = <String, Credential>{};
      for (final cred in allCredentials) {
        uniqueCredentials[cred.id] = cred;
      }

      return uniqueCredentials.values.toList();
    } catch (e) {
      return [];
    }
  }

  /// Get list of users who have access to a credential
  Future<List<String>> getSharedUsers(String credentialId) async {
    try {
      final credential = await getCredential(credentialId);
      if (credential == null) {
        return [];
      }

      // Only owner can see shared users
      if (credential.userId != currentUserId) {
        return [];
      }

      return credential.sharedWith;
    } catch (e) {
      return [];
    }
  }

  // ================================================================
  // Helper Methods
  // ================================================================

  /// Generate checksum for data integrity
  String _generateChecksum(Credential credential) {
    final data =
        '${credential.title}${credential.encryptedUsername}${credential.encryptedPassword}';
    return _encryption.generateChecksum(data);
  }

  /// Update last accessed timestamp
  Future<void> _updateLastAccessed(String credentialId) async {
    try {
      await _credentialsCollection.doc(credentialId).update({
        'lastAccessedAt': DateTime.now(),
      });
    } catch (e) {
      // Silent failure - last accessed is optional
    }
  }

  /// Create access record for sharing
  Future<void> _createAccessRecord({
    required String ownerId,
    required String accessorId,
    required String credentialId,
    required String accessLevel,
  }) async {
    try {
      final accessId = _accessCollection.doc().id;
      await _accessCollection.doc(accessId).set({
        'id': accessId,
        'ownerId': ownerId,
        'accessorId': accessorId,
        'credentialId': credentialId,
        'accessLevel': accessLevel,
        'grantedAt': DateTime.now(),
      });
    } catch (e) {
      // Silent failure - access record is optional
    }
  }

  /// Delete access records for a credential
  Future<void> _deleteAccessRecords(String credentialId) async {
    try {
      final querySnapshot = await _accessCollection
          .where('credentialId', isEqualTo: credentialId)
          .get();

      for (final doc in querySnapshot.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      // Silent failure
    }
  }

  /// Delete specific access record
  Future<void> _deleteAccessRecord(
    String accessorId,
    String credentialId,
  ) async {
    try {
      final querySnapshot = await _accessCollection
          .where('accessorId', isEqualTo: accessorId)
          .where('credentialId', isEqualTo: credentialId)
          .get();

      for (final doc in querySnapshot.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      // Silent failure
    }
  }

  // ================================================================
  // Initialization & Cleanup
  // ================================================================

  /// Initialize default categories for new users
  Future<void> initializeDefaultCategories() async {
    try {
      if (!isLoggedIn) {
        return;
      }

      final userId = currentUserId!;
      final existingCategories = await getCategories();

      // Only create defaults if no categories exist
      if (existingCategories.isEmpty) {
        final defaults = CredentialCategory.getDefaultCategories(userId);
        for (final category in defaults) {
          await _categoriesCollection.doc(category.id).trackedSet(category.toJson());
        }
      }
    } catch (e) {
      // Silent failure
    }
  }
}
