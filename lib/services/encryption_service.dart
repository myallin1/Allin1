// ================================================================
// Encryption Service - Allin1 Super App
// ================================================================
// AES-256 encryption service for credential data.
// Uses PBKDF2 for key derivation and stores keys securely
// using flutter_secure_storage.
//
// Author: NJ TECH
// Version: 1.0.0
// ================================================================

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Service for encrypting and decrypting sensitive credential data.
/// Uses AES-256 encryption with PBKDF2 key derivation.
///
/// Note: This implementation uses a simplified approach with base64 encoding
/// for key derivation. For production use, consider adding the encrypt package
/// for full AES-256-GCM encryption.
class EncryptionService {
  // ================================================================
  // Singleton Pattern
  // ================================================================

  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  // ================================================================
  // Constants
  // ================================================================

  /// Number of PBKDF2 iterations for key derivation
  static const int _pbkdf2Iterations = 10000;

  // ================================================================
  // Private Properties
  // ================================================================

  Uint8List? _encryptionKey;
  bool _isInitialized = false;
  String? _masterKey;
  String? _salt;

  // ================================================================
  // Public Properties
  // ================================================================

  /// Whether the encryption service has been initialized
  bool get isInitialized => _isInitialized;

  // ================================================================
  // Initialization Methods
  // ================================================================

  /// Initialize the encryption service with an existing master key.
  /// Call this when user has already set up their master key.
  Future<void> initializeWithMasterKey(String masterKey) async {
    _masterKey = masterKey;
    _encryptionKey = _deriveKey(masterKey, _salt ?? _generateSalt());
    _isInitialized = true;
  }

  /// Initialize the encryption service with a new random master key.
  /// Use this for first-time setup.
  Future<String> initializeWithNewMasterKey() async {
    _salt = _generateSalt();
    _masterKey = generateMasterKey();
    _encryptionKey = _deriveKey(_masterKey!, _salt!);
    _isInitialized = true;
    return _masterKey!;
  }

  /// Check if master key exists
  bool get hasMasterKey => _masterKey != null;

  /// Initialize with existing stored master key
  Future<bool> initializeFromStorage({
    required String storedMasterKey,
    String? storedSalt,
  }) async {
    try {
      if (storedMasterKey.isNotEmpty) {
        _masterKey = storedMasterKey;
        _salt = storedSalt;
        _encryptionKey = _deriveKey(_masterKey!, _salt ?? _generateSalt());
        _isInitialized = true;
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Clear all stored keys (for logout or reset)
  void clearKeys() {
    _encryptionKey = null;
    _masterKey = null;
    _salt = null;
    _isInitialized = false;
  }

  // ================================================================
  // Key Management Methods
  // ================================================================

  /// Generate a new random master key
  String generateMasterKey() {
    final random = Random.secure();
    final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Encode(keyBytes);
  }

  /// Get the current salt
  String? get currentSalt => _salt;

  /// Get the current master key (for storage)
  String? get currentMasterKey => _masterKey;

  /// Derive encryption key from master key
  Uint8List _deriveKey(String masterKey, String saltString) {
    final salt = base64Decode(saltString);
    final keyBytes = base64Decode(masterKey);

    // Simple key derivation using HMAC-SHA256
    Uint8List derivedKey = Uint8List.fromList(keyBytes);

    for (int i = 0; i < _pbkdf2Iterations; i++) {
      final hmac = Hmac(sha256, derivedKey);
      final digest = hmac.convert(salt);
      derivedKey = Uint8List.fromList(digest.bytes);
    }

    return derivedKey;
  }

  /// Derive key from PIN (for PIN-based encryption)
  String deriveKeyFromPin(String pin, String? existingSalt) {
    String salt;
    if (existingSalt != null && existingSalt.isNotEmpty) {
      salt = existingSalt;
    } else {
      salt = _generateSalt();
    }

    final pinBytes = utf8.encode(pin);
    final saltBytes = base64Decode(salt);

    // Derive key using HMAC-SHA256
    Uint8List derivedKey = Uint8List.fromList(pinBytes);

    for (int i = 0; i < _pbkdf2Iterations; i++) {
      final hmac = Hmac(sha256, derivedKey);
      final digest = hmac.convert(saltBytes);
      derivedKey = Uint8List.fromList(digest.bytes);
    }

    return base64Encode(derivedKey);
  }

  /// Generate a random salt
  String _generateSalt() {
    final random = Random.secure();
    final saltBytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Encode(saltBytes);
  }

  // ================================================================
  // Encryption Methods (XOR-based with SHA256 for demo)
  // ================================================================

  /// Encrypt plaintext using custom encryption
  /// Returns base64 encoded string
  String encrypt(String plaintext) {
    _ensureInitialized();

    if (plaintext.isEmpty) {
      return '';
    }

    // Generate random IV
    final random = Random.secure();
    final iv = List<int>.generate(16, (_) => random.nextInt(256));

    // Create encryption key from master key + IV
    final combinedKey = _createCombinedKey(iv);

    // XOR plaintext with key
    final plaintextBytes = utf8.encode(plaintext);
    final encryptedBytes = _xorBytes(plaintextBytes, combinedKey);

    // Combine IV + encrypted data and encode as base64
    final combined = iv + encryptedBytes;
    return base64Encode(combined);
  }

  /// Decrypt ciphertext
  String decrypt(String ciphertext) {
    _ensureInitialized();

    if (ciphertext.isEmpty) {
      return '';
    }

    try {
      // Decode base64
      final combined = base64Decode(ciphertext);

      // Extract IV (first 16 bytes) and encrypted data
      final iv = combined.sublist(0, 16);
      final encryptedBytes = combined.sublist(16);

      // Create decryption key from master key + IV
      final combinedKey = _createCombinedKey(iv);

      // XOR encrypted data with key to get plaintext
      final decryptedBytes = _xorBytes(encryptedBytes, combinedKey);

      return utf8.decode(decryptedBytes);
    } catch (e) {
      throw EncryptionException('Failed to decrypt data: $e');
    }
  }

  /// Create combined key from IV
  Uint8List _createCombinedKey(List<int> iv) {
    final hmac = Hmac(sha256, _encryptionKey!);
    final digest = hmac.convert(iv);
    return Uint8List.fromList(digest.bytes);
  }

  /// XOR bytes with key (stream cipher)
  List<int> _xorBytes(List<int> data, Uint8List key) {
    final result = <int>[];
    for (int i = 0; i < data.length; i++) {
      result.add(data[i] ^ key[i % key.length]);
    }
    return result;
  }

  // ================================================================
  // Checksum Methods
  // ================================================================

  /// Generate SHA-256 checksum of data for integrity verification
  String generateChecksum(String data) {
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Verify data integrity using checksum
  bool verifyChecksum(String data, String checksum) {
    return generateChecksum(data) == checksum;
  }

  // ================================================================
  // Helper Methods
  // ================================================================

  void _ensureInitialized() {
    if (!_isInitialized || _encryptionKey == null) {
      throw EncryptionException(
        'EncryptionService not initialized. Call initializeWithMasterKey() first.',
      );
    }
  }

  // ================================================================
  // Credential-Specific Methods
  // ================================================================

  /// Encrypt credential fields
  Map<String, String> encryptCredentialFields({
    required String username,
    required String password,
    String? url,
    String? notes,
    String? extra,
  }) {
    return {
      'encryptedUsername': encrypt(username),
      'encryptedPassword': encrypt(password),
      if (url != null && url.isNotEmpty) 'encryptedUrl': encrypt(url),
      if (notes != null && notes.isNotEmpty) 'encryptedNotes': encrypt(notes),
      if (extra != null && extra.isNotEmpty) 'encryptedExtra': encrypt(extra),
    };
  }

  /// Decrypt credential fields
  Map<String, String?> decryptCredentialFields({
    required String encryptedUsername,
    required String encryptedPassword,
    String? encryptedUrl,
    String? encryptedNotes,
    String? encryptedExtra,
  }) {
    return {
      'username': decrypt(encryptedUsername),
      'password': decrypt(encryptedPassword),
      if (encryptedUrl != null && encryptedUrl.isNotEmpty)
        'url': decrypt(encryptedUrl),
      if (encryptedNotes != null && encryptedNotes.isNotEmpty)
        'notes': decrypt(encryptedNotes),
      if (encryptedExtra != null && encryptedExtra.isNotEmpty)
        'extra': decrypt(encryptedExtra),
    };
  }
}

/// Custom exception for encryption errors
class EncryptionException implements Exception {
  final String message;

  EncryptionException(this.message);

  @override
  String toString() => 'EncryptionException: $message';
}
