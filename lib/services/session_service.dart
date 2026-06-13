// ================================================================
// Session Service - Authentication & Session Management
// Allin1 Super App v1.0
// ================================================================

import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'credential_service.dart';

enum UserType { customer, hero, admin }

class SessionService {
  static final SessionService _instance = SessionService._internal();
  factory SessionService() => _instance;
  SessionService._internal();

  static const String _sessionBoxName = 'session';
  static const String _userTypeKey = 'userType';
  static const String _rememberMeKey = 'rememberMe';
  static const String _userDataKey = 'userData';

  Box<dynamic>? _sessionBox;

  // ================================================================
  // Initialize Session Storage
  // ================================================================
  Future<void> init() async {
    _sessionBox ??= await Hive.openBox(_sessionBoxName);
  }

  // ================================================================
  // Save Session Data
  // ================================================================
  Future<void> saveSession({
    required UserType userType,
    required String uid,
    required String email,
    String? displayName,
    String? phoneNumber,
    bool rememberMe = false,
  }) async {
    if (_sessionBox == null || !_sessionBox!.isOpen) {
      await init();
    }

    await _sessionBox!.put(_userTypeKey, userType.index);
    await _sessionBox!.put(_rememberMeKey, rememberMe);

    final userData = {
      'uid': uid,
      'email': email,
      'displayName': displayName ?? '',
      'phoneNumber': phoneNumber ?? '',
    };
    await _sessionBox!.put(_userDataKey, jsonEncode(userData));
  }

  // ================================================================
  // Get Current User Type
  // ================================================================
  UserType? getCurrentUserType() {
    if (_sessionBox == null || !_sessionBox!.isOpen) {
      return null;
    }
    final index = _sessionBox!.get(_userTypeKey) as int?;
    if (index == null) {
      return null;
    }
    return UserType.values[index];
  }

  // ================================================================
  // Get Current User Data
  // ================================================================
  Map<String, dynamic>? getCurrentUserData() {
    if (_sessionBox == null || !_sessionBox!.isOpen) {
      return null;
    }
    final data = _sessionBox!.get(_userDataKey) as String?;
    if (data == null) {
      return null;
    }
    return jsonDecode(data) as Map<String, dynamic>;
  }

  // ================================================================
  // Check if Remember Me is Enabled
  // ================================================================
  bool isRememberMeEnabled() {
    if (_sessionBox == null || !_sessionBox!.isOpen) {
      return false;
    }
    return _sessionBox!.get(_rememberMeKey, defaultValue: false) as bool? ??
        false;
  }

  // ================================================================
  // Check if User is Logged In
  // ================================================================
  bool isLoggedIn() {
    final user = FirebaseAuth.instance.currentUser;
    return user != null;
  }

  // ================================================================
  // Get Current Firebase User
  // ================================================================
  User? getCurrentUser() {
    return FirebaseAuth.instance.currentUser;
  }

  // ================================================================
  // Get Current UID
  // ================================================================
  String? getCurrentUid() {
    return FirebaseAuth.instance.currentUser?.uid;
  }

  // ================================================================
  // Clear Session (Logout)
  // ================================================================
  Future<void> clearSession() async {
    if (_sessionBox == null || !_sessionBox!.isOpen) {
      await init();
    }

    // Clear credential cache before logout
    try {
      final credentialService = CredentialService();
      await credentialService.clearCache();
    } catch (e) {
      // Ignore cache clearing errors
    }

    await _sessionBox!.clear();
    await FirebaseAuth.instance.signOut();
  }

  // ================================================================
  // Save User Type
  // ================================================================
  Future<void> setUserType(UserType userType) async {
    if (_sessionBox == null || !_sessionBox!.isOpen) {
      await init();
    }
    await _sessionBox!.put(_userTypeKey, userType.index);
  }

  // ================================================================
  // Check if Admin
  // ================================================================
  bool isAdmin() {
    return getCurrentUserType() == UserType.admin;
  }

  // ================================================================
  // Check if Hero (Driver)
  // ================================================================
  bool isHero() {
    return getCurrentUserType() == UserType.hero;
  }

  // Legacy aliases — kept for backward compatibility
  @Deprecated('Use isHero() instead')
  bool isCaptain() => isHero();
  @Deprecated('Use isHero() instead')
  bool isRider() => isHero();

  // ================================================================
  // Check if Customer
  // ================================================================
  bool isCustomer() {
    return getCurrentUserType() == UserType.customer;
  }

  // Legacy alias — kept for backward compatibility
  @Deprecated('Use isCustomer() instead')
  bool isRegularUser() => isCustomer();
}
