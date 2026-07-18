// ================================================================
// Admin Credential Service - Allin1 Super App
// ================================================================
// Administrative credential management service for managing
// admin-created credentials and user assignments.
// Uses Firebase Firestore for storage.
//
// Author: NJ TECH
// Version: 1.0.0
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/credential.dart' hide Timestamp;
import 'encryption_service.dart';
import 'session_service.dart';

// ================================================================
// Admin Credential Result Class
// ================================================================
class AdminCredentialResult {
  final bool success;
  final String? error;
  final Map<String, dynamic>? data;

  AdminCredentialResult({
    required this.success,
    this.error,
    this.data,
  });

  factory AdminCredentialResult.success({Map<String, dynamic>? data}) {
    return AdminCredentialResult(success: true, data: data);
  }

  factory AdminCredentialResult.failure(String error) {
    return AdminCredentialResult(success: false, error: error);
  }
}

// ================================================================
// Admin Credential Model (for Firestore storage)
// ================================================================
class AdminCredential {
  final String id;
  final String title;
  final CredentialType type;
  final String encryptedUsername;
  final String encryptedPassword;
  final String? encryptedUrl;
  final String? encryptedNotes;
  final String? encryptedExtra;
  final List<String> assignedUserIds;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  AdminCredential({
    required this.id,
    required this.title,
    required this.type,
    required this.encryptedUsername,
    required this.encryptedPassword,
    required this.assignedUserIds,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.encryptedUrl,
    this.encryptedNotes,
    this.encryptedExtra,
  });

  factory AdminCredential.fromJson(Map<String, dynamic> json) {
    return AdminCredential(
      id: json['id'] as String,
      title: json['title'] as String,
      type: CredentialType.fromString(json['type'] as String),
      encryptedUsername: json['encryptedUsername'] as String,
      encryptedPassword: json['encryptedPassword'] as String,
      encryptedUrl: json['encryptedUrl'] as String?,
      encryptedNotes: json['encryptedNotes'] as String?,
      encryptedExtra: json['encryptedExtra'] as String?,
      assignedUserIds: (json['assignedUserIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      createdBy: json['createdBy'] as String,
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.parse(
            json['createdAt'] as String? ?? DateTime.now().toIso8601String(),
          ),
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate() ??
          DateTime.parse(
            json['updatedAt'] as String? ?? DateTime.now().toIso8601String(),
          ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'type': type.toJson(),
      'encryptedUsername': encryptedUsername,
      'encryptedPassword': encryptedPassword,
      if (encryptedUrl != null) 'encryptedUrl': encryptedUrl,
      if (encryptedNotes != null) 'encryptedNotes': encryptedNotes,
      if (encryptedExtra != null) 'encryptedExtra': encryptedExtra,
      'assignedUserIds': assignedUserIds,
      'createdBy': createdBy,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  AdminCredential copyWith({
    String? id,
    String? title,
    CredentialType? type,
    String? encryptedUsername,
    String? encryptedPassword,
    String? encryptedUrl,
    String? encryptedNotes,
    String? encryptedExtra,
    List<String>? assignedUserIds,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AdminCredential(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      encryptedUsername: encryptedUsername ?? this.encryptedUsername,
      encryptedPassword: encryptedPassword ?? this.encryptedPassword,
      encryptedUrl: encryptedUrl ?? this.encryptedUrl,
      encryptedNotes: encryptedNotes ?? this.encryptedNotes,
      encryptedExtra: encryptedExtra ?? this.encryptedExtra,
      assignedUserIds: assignedUserIds ?? this.assignedUserIds,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// ================================================================
// Admin Credential Service
// ================================================================
class AdminCredentialService {
  // ================================================================
  // Singleton Pattern
  // ================================================================
  static final AdminCredentialService _instance =
      AdminCredentialService._internal();
  factory AdminCredentialService() => _instance;
  AdminCredentialService._internal();

  // ================================================================
  // Dependencies
  // ================================================================
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final EncryptionService _encryption = EncryptionService();
  final SessionService _sessionService = SessionService();

  // ================================================================
  // Collection References
  // ================================================================
  CollectionReference get _adminCredentialsCollection =>
      _firestore.collection('adminCredentials');

  CollectionReference get _usersCollection => _firestore.collection('users');

  // ================================================================
  // User Context
  // ================================================================

  /// Get current user ID
  String? get currentUserId => _auth.currentUser?.uid;

  /// Check if user is admin
  bool get isAdmin => _sessionService.isAdmin();

  /// Check if encryption service is initialized
  bool get isEncryptionReady => _encryption.isInitialized;

  // ================================================================
  // Admin Operations - Create
  // ================================================================

  /// Create admin credential (for user assignment)
  Future<AdminCredentialResult> createAdminCredential({
    required String title,
    required CredentialType type,
    required String username,
    required String password,
    String? url,
    String? notes,
    String? extra,
    List<String>? assignedUserIds,
  }) async {
    try {
      // Validate admin access
      if (!isAdmin) {
        return AdminCredentialResult.failure('Admin access required');
      }

      if (title.isEmpty) {
        return AdminCredentialResult.failure('Title is required');
      }

      if (title.length > 100) {
        return AdminCredentialResult.failure(
          'Title must be less than 100 characters',
        );
      }

      if (!isEncryptionReady) {
        return AdminCredentialResult.failure(
          'Encryption service not initialized',
        );
      }

      final adminId = currentUserId!;
      final credentialId = _adminCredentialsCollection.doc().id;
      final now = DateTime.now();

      // Encrypt sensitive fields
      final encryptedFields = _encryption.encryptCredentialFields(
        username: username,
        password: password,
        url: url,
        notes: notes,
        extra: extra,
      );

      // Create admin credential
      final credential = AdminCredential(
        id: credentialId,
        title: title.trim(),
        type: type,
        encryptedUsername: encryptedFields['encryptedUsername'] ?? '',
        encryptedPassword: encryptedFields['encryptedPassword'] ?? '',
        encryptedUrl: encryptedFields['encryptedUrl'],
        encryptedNotes: encryptedFields['encryptedNotes'],
        encryptedExtra: encryptedFields['encryptedExtra'],
        assignedUserIds: assignedUserIds ?? [],
        createdBy: adminId,
        createdAt: now,
        updatedAt: now,
      );

      // Save to Firestore
      await _adminCredentialsCollection
          .doc(credentialId)
          .set(credential.toJson());

      return AdminCredentialResult.success(data: {'id': credentialId});
    } on FirebaseException catch (e) {
      return AdminCredentialResult.failure(
        'Failed to create admin credential: ${e.message}',
      );
    } catch (e) {
      return AdminCredentialResult.failure(
        'Failed to create admin credential: $e',
      );
    }
  }

  // ================================================================
  // Admin Operations - Read
  // ================================================================

  /// Get all admin credentials (admin only)
  Future<List<AdminCredential>> getAllCredentials() async {
    try {
      if (!isAdmin) {
        return [];
      }

      final querySnapshot = await _adminCredentialsCollection
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map(
            (doc) =>
                AdminCredential.fromJson(doc.data()! as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Watch all admin credentials (admin only)
  Stream<List<AdminCredential>> watchAllCredentials() {
    if (!isAdmin) {
      return Stream.value([]);
    }

    return _adminCredentialsCollection
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => AdminCredential.fromJson(
                  doc.data()! as Map<String, dynamic>,
                ),
              )
              .toList(),
        );
  }

  /// Get admin credential by ID
  Future<AdminCredential?> getAdminCredential(String credentialId) async {
    try {
      if (!isAdmin) {
        return null;
      }

      final doc = await _adminCredentialsCollection.doc(credentialId).get();
      if (!doc.exists) {
        return null;
      }

      return AdminCredential.fromJson(doc.data()! as Map<String, dynamic>);
    } catch (e) {
      return null;
    }
  }

  /// Get decrypted admin credential
  Future<Map<String, String?>?> getDecryptedAdminCredential(
    String credentialId,
  ) async {
    final credential = await getAdminCredential(credentialId);
    if (credential == null) {
      return null;
    }

    if (!isEncryptionReady) {
      return null;
    }

    return _encryption.decryptCredentialFields(
      encryptedUsername: credential.encryptedUsername,
      encryptedPassword: credential.encryptedPassword,
      encryptedUrl: credential.encryptedUrl,
      encryptedNotes: credential.encryptedNotes,
      encryptedExtra: credential.encryptedExtra,
    );
  }

  // ================================================================
  // Admin Operations - Update
  // ================================================================

  /// Update admin credential
  Future<AdminCredentialResult> updateAdminCredential({
    required String credentialId,
    String? title,
    CredentialType? type,
    String? username,
    String? password,
    String? url,
    String? notes,
    String? extra,
  }) async {
    try {
      if (!isAdmin) {
        return AdminCredentialResult.failure('Admin access required');
      }

      if (!isEncryptionReady) {
        return AdminCredentialResult.failure(
          'Encryption service not initialized',
        );
      }

      final existing = await getAdminCredential(credentialId);
      if (existing == null) {
        return AdminCredentialResult.failure('Credential not found');
      }

      final now = DateTime.now();

      // Encrypt new sensitive fields if provided
      String encryptedUsername = existing.encryptedUsername;
      String encryptedPassword = existing.encryptedPassword;
      String? encryptedUrl = existing.encryptedUrl;
      String? encryptedNotes = existing.encryptedNotes;
      String? encryptedExtra = existing.encryptedExtra;

      if (username != null ||
          password != null ||
          url != null ||
          notes != null ||
          extra != null) {
        final decrypted = _encryption.decryptCredentialFields(
          encryptedUsername: existing.encryptedUsername,
          encryptedPassword: existing.encryptedPassword,
          encryptedUrl: existing.encryptedUrl,
          encryptedNotes: existing.encryptedNotes,
          encryptedExtra: existing.encryptedExtra,
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

        encryptedUsername =
            encryptedFields['encryptedUsername'] ?? encryptedUsername;
        encryptedPassword =
            encryptedFields['encryptedPassword'] ?? encryptedPassword;
        encryptedUrl = encryptedFields['encryptedUrl'] ?? encryptedUrl;
        encryptedNotes = encryptedFields['encryptedNotes'] ?? encryptedNotes;
        encryptedExtra = encryptedFields['encryptedExtra'] ?? encryptedExtra;
      }

      final updated = existing.copyWith(
        title: title?.trim() ?? existing.title,
        type: type ?? existing.type,
        encryptedUsername: encryptedUsername,
        encryptedPassword: encryptedPassword,
        encryptedUrl: encryptedUrl,
        encryptedNotes: encryptedNotes,
        encryptedExtra: encryptedExtra,
        updatedAt: now,
      );

      await _adminCredentialsCollection
          .doc(credentialId)
          .update(updated.toJson());

      return AdminCredentialResult.success();
    } on FirebaseException catch (e) {
      return AdminCredentialResult.failure(
        'Failed to update credential: ${e.message}',
      );
    } catch (e) {
      return AdminCredentialResult.failure('Failed to update credential: $e');
    }
  }

  /// Assign credential to user(s)
  Future<AdminCredentialResult> assignCredentialToUser({
    required String credentialId,
    required List<String> userIds,
  }) async {
    try {
      if (!isAdmin) {
        return AdminCredentialResult.failure('Admin access required');
      }

      final existing = await getAdminCredential(credentialId);
      if (existing == null) {
        return AdminCredentialResult.failure('Credential not found');
      }

      // Merge existing and new user IDs
      final updatedUserIds = {...existing.assignedUserIds, ...userIds}.toList();

      await _adminCredentialsCollection.doc(credentialId).update({
        'assignedUserIds': updatedUserIds,
        'updatedAt': DateTime.now(),
      });

      return AdminCredentialResult.success();
    } on FirebaseException catch (e) {
      return AdminCredentialResult.failure(
        'Failed to assign credential: ${e.message}',
      );
    } catch (e) {
      return AdminCredentialResult.failure('Failed to assign credential: $e');
    }
  }

  /// Remove user assignment
  Future<AdminCredentialResult> removeUserAssignment({
    required String credentialId,
    required String userId,
  }) async {
    try {
      if (!isAdmin) {
        return AdminCredentialResult.failure('Admin access required');
      }

      final existing = await getAdminCredential(credentialId);
      if (existing == null) {
        return AdminCredentialResult.failure('Credential not found');
      }

      final updatedUserIds =
          existing.assignedUserIds.where((id) => id != userId).toList();

      await _adminCredentialsCollection.doc(credentialId).update({
        'assignedUserIds': updatedUserIds,
        'updatedAt': DateTime.now(),
      });

      return AdminCredentialResult.success();
    } on FirebaseException catch (e) {
      return AdminCredentialResult.failure(
        'Failed to remove assignment: ${e.message}',
      );
    } catch (e) {
      return AdminCredentialResult.failure('Failed to remove assignment: $e');
    }
  }

  // ================================================================
  // Admin Operations - Delete
  // ================================================================

  /// Delete admin credential
  Future<AdminCredentialResult> deleteAdminCredential(
    String credentialId,
  ) async {
    try {
      if (!isAdmin) {
        return AdminCredentialResult.failure('Admin access required');
      }

      final doc = await _adminCredentialsCollection.doc(credentialId).get();
      if (!doc.exists) {
        return AdminCredentialResult.failure('Credential not found');
      }

      await _adminCredentialsCollection.doc(credentialId).delete();

      return AdminCredentialResult.success();
    } on FirebaseException catch (e) {
      return AdminCredentialResult.failure(
        'Failed to delete credential: ${e.message}',
      );
    } catch (e) {
      return AdminCredentialResult.failure('Failed to delete credential: $e');
    }
  }

  // ================================================================
  // User Operations (for non-admin users)
  // ================================================================

  /// Get credentials assigned to current user
  Future<List<AdminCredential>> getAssignedCredentials() async {
    try {
      if (!isLoggedIn) {
        return [];
      }

      final userId = currentUserId!;

      // Query for credentials assigned to current user
      final querySnapshot = await _adminCredentialsCollection
          .where('assignedUserIds', arrayContains: userId)
          .orderBy('updatedAt', descending: true)
          .get();

      return querySnapshot.docs
          .map(
            (doc) =>
                AdminCredential.fromJson(doc.data()! as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Watch assigned credentials stream
  Stream<List<AdminCredential>> watchAssignedCredentials() {
    if (!isLoggedIn) {
      return Stream.value([]);
    }

    final userId = currentUserId!;

    return _adminCredentialsCollection
        .where('assignedUserIds', arrayContains: userId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => AdminCredential.fromJson(
                  doc.data()! as Map<String, dynamic>,
                ),
              )
              .toList(),
        );
  }

  /// Get decrypted assigned credential
  Future<Map<String, String?>?> getDecryptedAssignedCredential(
    String credentialId,
  ) async {
    try {
      if (!isLoggedIn) {
        return null;
      }

      final userId = currentUserId!;

      final doc = await _adminCredentialsCollection.doc(credentialId).get();
      if (!doc.exists) {
        return null;
      }

      final credential =
          AdminCredential.fromJson(doc.data()! as Map<String, dynamic>);

      // Check if user is assigned
      if (!credential.assignedUserIds.contains(userId)) {
        return null;
      }

      if (!isEncryptionReady) {
        return null;
      }

      return _encryption.decryptCredentialFields(
        encryptedUsername: credential.encryptedUsername,
        encryptedPassword: credential.encryptedPassword,
        encryptedUrl: credential.encryptedUrl,
        encryptedNotes: credential.encryptedNotes,
        encryptedExtra: credential.encryptedExtra,
      );
    } catch (e) {
      return null;
    }
  }

  // ================================================================
  // User Lookup
  // ================================================================

  /// Get user details by ID
  Future<Map<String, dynamic>?> getUserDetails(String userId) async {
    try {
      final doc = await _usersCollection.doc(userId).get();
      if (!doc.exists) {
        return null;
      }
      return doc.data()! as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Search users by username or email
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      if (query.isEmpty) {
        return [];
      }

      final queryLower = query.toLowerCase();

      // Search by username
      final usernameSnapshot = await _usersCollection
          .where('usernameLower', isGreaterThanOrEqualTo: queryLower)
          .where('usernameLower', isLessThanOrEqualTo: '$queryLower\uf8ff')
          .limit(10)
          .get();

      final users = <Map<String, dynamic>>[];

      for (final doc in usernameSnapshot.docs) {
        final data = doc.data()! as Map<String, dynamic>;
        data['uid'] = doc.id;
        users.add(data);
      }

      return users;
    } catch (e) {
      return [];
    }
  }

  /// Get all users (for admin selection)
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      if (!isAdmin) {
        return [];
      }

      final querySnapshot =
          await _usersCollection.orderBy('username').limit(100).get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data()! as Map<String, dynamic>;
        data['uid'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  // ================================================================
  // Statistics
  // ================================================================

  /// Get admin credentials statistics
  Future<Map<String, int>> getCredentialsStats() async {
    try {
      if (!isAdmin) {
        return {
          'total': 0,
          'assigned': 0,
        };
      }

      final allCredentials = await getAllCredentials();

      int assignedCount = 0;
      for (final cred in allCredentials) {
        assignedCount += cred.assignedUserIds.length;
      }

      return {
        'total': allCredentials.length,
        'assigned': assignedCount,
      };
    } catch (e) {
      return {
        'total': 0,
        'assigned': 0,
      };
    }
  }

  /// Get user's assigned credentials count
  Future<int> getAssignedCredentialsCount() async {
    try {
      if (!isLoggedIn) {
        return 0;
      }

      final userId = currentUserId!;

      final querySnapshot = await _adminCredentialsCollection
          .where('assignedUserIds', arrayContains: userId)
          .get();

      return querySnapshot.docs.length;
    } catch (e) {
      return 0;
    }
  }

  // ================================================================
  // Helper Methods
  // ================================================================

  /// Check if user is logged in
  bool get isLoggedIn => _auth.currentUser != null;
}
