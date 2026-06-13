// ================================================================
// Auth Service - Enhanced Authentication
// Allin1 Super App v1.0
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'session_service.dart';

// ================================================================
// Auth Result Class
// ================================================================
class AuthResult {
  final bool success;
  final String? error;
  final User? user;
  final bool requiresProfileSetup;
  final Map<String, dynamic>? userData;

  AuthResult({
    required this.success,
    this.error,
    this.user,
    this.requiresProfileSetup = false,
    this.userData,
  });
}

class AuthService {
  static const String _googleWebClientId =
      '357526153693-02b0behmsf3k720jujg3e8j82frj04q7.apps.googleusercontent.com';

  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb ? _googleWebClientId : null,
    serverClientId: kIsWeb ? null : _googleWebClientId,
    scopes: const ['email', 'profile'],
  );
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SessionService _sessionService = SessionService();

  // ================================================================
  // Check if Username Exists
  // ================================================================
  Future<bool> isUsernameTaken(String username) async {
    final normalizedUsername = username.toLowerCase().trim();
    final querySnapshot = await _firestore
        .collection('users')
        .where('usernameLower', isEqualTo: normalizedUsername)
        .limit(1)
        .get();
    return querySnapshot.docs.isNotEmpty;
  }

  // ================================================================
  // Validate Username Format
  // ================================================================
  String? validateUsername(String username) {
    if (username.isEmpty) {
      return 'Username is required';
    }
    if (username.length < 3) {
      return 'Username must be at least 3 characters';
    }
    if (username.length > 20) {
      return 'Username must be less than 20 characters';
    }
    // Only allow alphanumeric and underscore
    final usernameRegex = RegExp(r'^[a-zA-Z0-9_]+$');
    if (!usernameRegex.hasMatch(username)) {
      return 'Username can only contain letters, numbers, and underscores';
    }
    return null; // Valid
  }

  // ================================================================
  // Register New User (Rider or Regular User)
  // ================================================================
  Future<AuthResult> registerWithEmail({
    required String email,
    required String password,
    required String username,
    required UserType userType,
    String? phoneNumber,
  }) async {
    try {
      // Validate username format
      final usernameError = validateUsername(username);
      if (usernameError != null) {
        return AuthResult(success: false, error: usernameError);
      }

      // Check if username is taken
      final isTaken = await isUsernameTaken(username);
      if (isTaken) {
        return AuthResult(success: false, error: 'Username is already taken');
      }

      // Create Firebase user
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user == null) {
        return AuthResult(success: false, error: 'Failed to create account');
      }

      // Save user data to Firestore
      await _saveUserData(
        uid: credential.user!.uid,
        email: email,
        username: username,
        userType: userType,
        phoneNumber: phoneNumber,
      );

      // Save session
      await _sessionService.saveSession(
        userType: userType,
        uid: credential.user!.uid,
        email: email,
        displayName: username,
        phoneNumber: phoneNumber,
      );

      return AuthResult(
        success: true,
        user: credential.user,
        requiresProfileSetup: (phoneNumber ?? '').trim().isEmpty,
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _getAuthErrorMessage(e.code));
    } catch (e) {
      return AuthResult(success: false, error: 'Registration failed: $e');
    }
  }

  // ================================================================
  // Login with Email
  // ================================================================
  Future<AuthResult> loginWithEmail({
    required String email,
    required String password,
    required UserType userType,
    bool rememberMe = false,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // 🔥 Force refresh to fetch latest claims
      await FirebaseAuth.instance.currentUser?.getIdToken(true);

      if (credential.user == null) {
        return AuthResult(success: false, error: 'Login failed');
      }

      // Verify user type
      final userData = await getUserData(credential.user!.uid);
      if (userData == null) {
        return AuthResult(success: false, error: 'User data not found');
      }

      if (userType == UserType.admin) {
        if (!_isAdminUserData(userData)) {
          await _auth.signOut();
          return AuthResult(
            success: false,
            error:
                'Admin access denied. Add userType: 2 and isAdmin: true in users/${credential.user!.uid}.',
          );
        }
        await _ensureAdminUserDoc(credential.user!, userData);
      }
      // REMOVED the strict userType checking block here so Sellers can enter freely!

      // Save session
      await _sessionService.saveSession(
        userType: userType,
        uid: credential.user!.uid,
        email: email,
        displayName: userData['username'] as String?,
        phoneNumber: _normalizedPhone(userData, credential.user),
        rememberMe: rememberMe,
      );

      return AuthResult(
        success: true,
        user: credential.user,
        requiresProfileSetup: _requiresProfileSetup(userData, credential.user!),
        userData: userData,
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _getAuthErrorMessage(e.code));
    } catch (e) {
      return AuthResult(success: false, error: 'Login failed: $e');
    }
  }

  // ================================================================
  // Login with Google
  // ================================================================
  Future<AuthResult> loginWithGoogle({
    required UserType userType,
    bool rememberMe = false,
  }) async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return AuthResult(success: false, error: 'Google sign-in cancelled');
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      // 🔥 Force refresh to fetch latest claims
      await FirebaseAuth.instance.currentUser?.getIdToken(true);

      if (userCredential.user == null) {
        return AuthResult(success: false, error: 'Google sign-in failed');
      }

      // Check if user exists in Firestore
      var userData = await getUserData(userCredential.user!.uid);

      if (userType == UserType.admin) {
        if (userData == null || !_isAdminUserData(userData)) {
          debugPrint(
            'Admin login warning: ${userCredential.user!.email ?? userCredential.user!.uid} '
            'is signed in with Google but does not have userType: 2 / isAdmin: true in Firestore.',
          );
          await _auth.signOut();
          await _googleSignIn.signOut();
          return AuthResult(
            success: false,
            error:
                'Admin account not authorized. Add userType: 2 and isAdmin: true in users/${userCredential.user!.uid}.',
          );
        }
        await _ensureAdminUserDoc(userCredential.user!, userData);
      }
      // REMOVED the strict userType checking block here so Sellers can enter freely!

      // Save or update user data
      if (userData == null && userType != UserType.admin) {
        // New user - create record
        await _saveUserData(
          uid: userCredential.user!.uid,
          email: userCredential.user!.email ?? '',
          username: userCredential.user!.displayName ?? 'user',
          userType: userType,
          phoneNumber: userCredential.user!.phoneNumber,
        );
        userData = await getUserData(userCredential.user!.uid);
      }

      // Save session
      await _sessionService.saveSession(
        userType: userType,
        uid: userCredential.user!.uid,
        email: userCredential.user!.email ?? '',
        displayName: userCredential.user!.displayName,
        phoneNumber: _normalizedPhone(userData, userCredential.user),
        rememberMe: rememberMe,
      );

      return AuthResult(
        success: true,
        user: userCredential.user,
        requiresProfileSetup:
            _requiresProfileSetup(userData, userCredential.user!),
        userData: userData,
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _getAuthErrorMessage(e.code));
    } catch (e) {
      return AuthResult(success: false, error: 'Google sign-in failed: $e');
    }
  }

  // ================================================================
  // Login as Guest
  // ================================================================
  Future<AuthResult> loginAsGuest() async {
    try {
      final result = await _auth.signInAnonymously();

      // 🔥 Force refresh to fetch latest claims
      await FirebaseAuth.instance.currentUser?.getIdToken(true);

      if (result.user == null) {
        return AuthResult(success: false, error: 'Guest login failed');
      }

      // Save guest session
      await _sessionService.saveSession(
        userType: UserType.customer,
        uid: result.user!.uid,
        email: 'guest@anonymous',
        displayName: 'Guest',
      );

      return AuthResult(success: true, user: result.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _getAuthErrorMessage(e.code));
    } catch (e) {
      return AuthResult(success: false, error: 'Guest login failed: $e');
    }
  }

  // ================================================================
  // Admin Login (Special authentication)
  // ================================================================
  Future<AuthResult> adminLogin({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // 🔥 Force refresh to fetch latest claims
      await FirebaseAuth.instance.currentUser?.getIdToken(true);

      if (credential.user == null) {
        return AuthResult(success: false, error: 'Admin login failed');
      }

      // Verify admin status
      final userData = await getUserData(credential.user!.uid);
      if (userData == null || !_isAdminUserData(userData)) {
        await _auth.signOut();
        return AuthResult(
          success: false,
          error:
              'Admin account not authorized. Add userType: 2 and isAdmin: true in users/${credential.user!.uid}.',
        );
      }

      await _ensureAdminUserDoc(credential.user!, userData);

      // Save admin session
      await _sessionService.saveSession(
        userType: UserType.admin,
        uid: credential.user!.uid,
        email: email,
        displayName: userData['username'] as String?,
        rememberMe: true,
      );

      return AuthResult(success: true, user: credential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _getAuthErrorMessage(e.code));
    } catch (e) {
      return AuthResult(success: false, error: 'Admin login failed: $e');
    }
  }

  // ================================================================
  // Logout
  // ================================================================
  Future<void> logout() async {
    await _sessionService.clearSession();
    await _googleSignIn.signOut();
  }

  // ================================================================
  // Get Current User
  // ================================================================
  User? getCurrentUser() {
    return _auth.currentUser;
  }

  // ================================================================
  // Check if Logged In
  // ================================================================
  bool isLoggedIn() {
    return _auth.currentUser != null;
  }

  // ================================================================
  // Private: Save User Data to Firestore
  // ================================================================
  Future<void> _saveUserData({
    required String uid,
    required String email,
    required String username,
    required UserType userType,
    String? phoneNumber,
    String? vehicleType,
  }) async {
    final normalizedVehicleType =
        userType == UserType.hero ? (vehicleType ?? 'bike') : null;
    await _firestore.collection('users').doc(uid).set({
      'uid': uid,
      'email': email,
      'username': username,
      'usernameLower': username.toLowerCase(),
      'userType': userType.index,
      'phone': phoneNumber ?? '',
      'phoneNumber': phoneNumber ?? '',
      'role': userType == UserType.hero ? 'hero' : userType.name,
      'isSetupComplete': (phoneNumber ?? '').trim().isNotEmpty,
      'createdAt': FieldValue.serverTimestamp(),
      'isVerified': userType != UserType.hero,
      if (normalizedVehicleType != null) 'vehicleType': normalizedVehicleType,
      if (userType == UserType.hero) ...{
        'heroCategory': normalizedVehicleType,
        'vehicleCategoryLabel':
            _heroVehicleCategoryLabel(normalizedVehicleType ?? 'bike'),
        'isEmergencyHelper': true,
      },
    });
  }

  // ================================================================
  // Update User Phone Number
  // ================================================================
  Future<void> updateUserPhone(String uid, String phone) async {
    await _firestore.collection('users').doc(uid).update({
      'phone': phone,
      'phoneNumber': phone,
      'isSetupComplete': phone.trim().isNotEmpty,
    });
  }

  Future<void> completeProfileSetup({
    required String uid,
    required String phoneNumber,
    required UserType userType,
    String? vehicleType,
  }) async {
    final normalizedVehicleType =
        userType == UserType.hero ? (vehicleType ?? 'bike') : null;
    await _firestore.collection('users').doc(uid).set(
      {
        'phone': phoneNumber,
        'phoneNumber': phoneNumber,
        'role': userType.name,
        'userType': userType.index,
        'isSetupComplete': true,
        'setupCompletedAt': FieldValue.serverTimestamp(),
        if (normalizedVehicleType != null) 'vehicleType': normalizedVehicleType,
        if (userType == UserType.hero) ...{
          'heroCategory': normalizedVehicleType,
          'vehicleCategoryLabel':
              _heroVehicleCategoryLabel(normalizedVehicleType ?? 'bike'),
          'isEmergencyHelper': true,
          'sosNetworkAcceptedAt': FieldValue.serverTimestamp(),
        },
      },
      SetOptions(merge: true),
    );

    if (userType == UserType.hero) {
      final heroRef = _firestore.collection('heroes').doc(uid);
      final existingHero = await heroRef.get();
      await heroRef.set(
        {
          'uid': uid,
          'heroId': uid,
          'phone': phoneNumber,
          'phoneNumber': phoneNumber,
          'vehicleType': normalizedVehicleType ?? 'bike',
          'heroCategory': normalizedVehicleType ?? 'bike',
          'vehicleCategoryLabel':
              _heroVehicleCategoryLabel(normalizedVehicleType ?? 'bike'),
          'isEmergencyHelper': true,
          'sosNetworkAcceptedAt': FieldValue.serverTimestamp(),
          'status': 'offline',
          'isOnline': false,
          'isAvailable': true,
          if (!existingHero.exists) 'approvalStatus': 'pending',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
  }

  String _heroVehicleCategoryLabel(String vehicleType) {
    switch (vehicleType) {
      case 'auto':
        return 'Auto Rickshaw';
      case 'car':
        return 'Cab / Mini';
      case 'emergency_manpower':
        return 'Only Emergency Manpower';
      case 'bike':
      default:
        return 'Bike Taxi';
    }
  }

  // ================================================================
  // Private: Get User Data from Firestore
  // ================================================================
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) {
      return null;
    }
    return doc.data();
  }

  // ================================================================
  // Private: Get Auth Error Message
  // ================================================================
  String _getAuthErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email';
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'No Firebase Authentication account found for this email, or the password is incorrect';
      case 'wrong-password':
        return 'Incorrect password';
      case 'email-already-in-use':
        return 'This email is already registered';
      case 'invalid-email':
        return 'Invalid email address';
      case 'weak-password':
        return 'Password is too weak';
      case 'admin-restricted-operation':
        return 'This operation is restricted. Enable Anonymous auth in Firebase Console.';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later';
      default:
        return 'Authentication error: $code';
    }
  }

  bool _isAdminUserData(Map<String, dynamic> userData) {
    return userData['userType'] == UserType.admin.index ||
        userData['userType'] == 2 ||
        userData['userType'] == 'admin' ||
        userData['userType'] == '2' ||
        userData['role'] == 'admin' ||
        userData['role'] == 'Admin' ||
        userData['admin'] == true ||
        userData['admin'] == 'true' ||
        userData['isAdmin'] == true ||
        userData['isAdmin'] == 'true';
  }

  Future<void> _ensureAdminUserDoc(
    User user,
    Map<String, dynamic> existingUserData,
  ) async {
    await _firestore.collection('users').doc(user.uid).set(
      {
        'email': user.email ?? existingUserData['email'] ?? '',
        'username': existingUserData['username'] ??
            user.displayName ??
            (user.email?.split('@').first ?? 'admin'),
        'userType': UserType.admin.index,
        'role': 'admin',
        'admin': true,
        'isAdmin': true,
        'isSetupComplete': true,
        'lastAdminLoginAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  bool _requiresProfileSetup(Map<String, dynamic>? userData, User user) {
    if (userData == null) {
      return true;
    }

    final phone = _normalizedPhone(userData, user).trim();
    final isSetupComplete = userData['isSetupComplete'] == true;
    return phone.isEmpty || !isSetupComplete;
  }

  String _normalizedPhone(Map<String, dynamic>? userData, User? user) {
    final phoneNumber = (userData?['phoneNumber'] as String?)?.trim() ?? '';
    if (phoneNumber.isNotEmpty) {
      return phoneNumber;
    }

    final legacyPhone = (userData?['phone'] as String?)?.trim() ?? '';
    if (legacyPhone.isNotEmpty) {
      return legacyPhone;
    }

    return user?.phoneNumber?.trim() ?? '';
  }
}
