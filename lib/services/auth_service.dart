// ================================================================
// Auth Service - Enhanced Authentication
// Allin1 Super App v1.0
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';
// Phone cache (Aug 11 2026): removes a users/{uid} read from every booking.
import 'hive_cache.dart';
// GUEST MODE: upgradeGuestWithGoogle() reads the same 'campaign_source'
// pref the welcome screen's sign-up path reads, so attribution is not
// lost when a customer signs up from the auth sheet instead.
import 'package:shared_preferences/shared_preferences.dart';
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
  // GUEST MODE (Aug 11 2026) — silent anonymous session + upgrade
  // ================================================================
  // Why anonymous sign-in rather than letting currentUser stay null:
  // dozens of existing customer screens read
  // FirebaseAuth.instance.currentUser! directly, or gate an RTDB read on
  // auth != null. Giving every guest a real uid from the first frame
  // means all of those keep working untouched. The trade-off is that
  // anonymous users satisfy firestore.rules' isAuth() — which is exactly
  // why isRealUser() was added there in the same change. Read the
  // "GUEST MODE" comments in firestore.rules before widening anything
  // here.
  // ================================================================

  /// True only for a fully registered, contactable account.
  /// An anonymous guest returns false — this is the single source of
  /// truth for "may this person actually place an order?".
  bool get isRealUser {
    final u = _auth.currentUser;
    return u != null && !u.isAnonymous;
  }

  /// Idempotent. Signs in anonymously ONLY if nobody is signed in, so a
  /// relaunch never disturbs an existing real session.
  ///
  /// Called unawaited() from main_customer.dart — it is a network call
  /// and must never block first paint. A guest whose anonymous sign-in
  /// has not landed yet simply sees the dashboard shell for a moment
  /// longer; nothing in the boot path waits on it.
  Future<void> ensureGuestSession() async {
    // FIX (Aug 11 2026 — ROOT CAUSE of "customer books from Chrome/PWA,
    // hero never receives it"): this used to read _auth.currentUser
    // synchronously and sign in anonymously if it was null.
    //
    // On web, currentUser is null until Firebase finishes restoring the
    // persisted session out of IndexedDB — this codebase already
    // documents that restore being measurably slower than native (see
    // ride_search_screen.dart's Aug 10 fix and
    // bike_booking_screen.dart's _listenToNearbyCaptains). Because this
    // runs unawaited immediately after runApp(), it was racing that
    // restore and WINNING on a fresh PWA load: a returning, fully
    // registered customer got silently signed in as an anonymous guest.
    //
    // They then looked signed in, but every gated write
    // (rides / service_requests) was rejected by isRealUser() — and in
    // ride_search_screen._createRideInRTDB() the denied Firestore write
    // throws BEFORE active_ride_requests is created, so _requestId
    // stays empty and _startBroadcastPinging returns without writing a
    // single hero_pings node. The hero app had nothing to receive.
    //
    // Fix: wait for the first real authStateChanges() event — that is
    // Firebase telling us restore has finished and this is the true
    // answer — and only then decide. Same pattern as the two fixes
    // named above. The timeout keeps a genuinely-new visitor from
    // waiting forever on a stream that will only ever emit null.
    try {
      final restored = await _auth
          .authStateChanges()
          .first
          .timeout(const Duration(seconds: 5));
      if (restored != null) {
        // A real (or already-anonymous) session came back from storage.
        // Never disturb it.
        return;
      }
    } catch (e) {
      // Timed out or errored. Fall through and check one last time
      // below rather than assuming nobody is signed in.
      debugPrint('[AuthService] auth restore wait failed: $e');
    }

    // Belt and braces: restore may have landed between the stream event
    // and this line.
    if (_auth.currentUser != null) return;

    try {
      await _auth.signInAnonymously();
    } catch (e) {
      // Non-fatal by design: the app still runs and still browses. Any
      // screen that genuinely needs an account calls requireRealAuth()
      // at the moment of the action and will prompt then.
      debugPrint('[AuthService] ensureGuestSession failed: $e');
    }
  }

  /// Upgrades the CURRENT anonymous session to a real Google account,
  /// PRESERVING the uid so the guest's accumulated activity (cart,
  /// recent places, Hive cache keyed by uid) is not orphaned.
  ///
  /// [mobile] is the number typed in the sheet. It is written into a
  /// BRAND-NEW users/{uid} doc only — exactly matching
  /// customer_welcome_login_screen.dart's _signInWithGoogle(), which is
  /// the live sign-up path this reuses. A returning customer's existing
  /// profile is never overwritten.
  ///
  /// Deliberately does NOT navigate. The whole point of Guest Mode is
  /// that the customer resumes the action they originally tapped — the
  /// two login SCREENS both end in pushNamedAndRemoveUntil('/dashboard'),
  /// which would destroy the navigation stack and lose that action.
  Future<AuthResult> upgradeGuestWithGoogle({required String mobile}) async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // Account picker dismissed — a cancellation, not a failure.
        return AuthResult(success: false, error: 'Google sign-in cancelled');
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final current = _auth.currentUser;
      UserCredential userCredential;

      if (current != null && current.isAnonymous) {
        try {
          // THE important line: link, do not sign out and sign in fresh.
          // linkWithCredential keeps the same uid, so everything the
          // guest did before this moment stays attached to them.
          userCredential = await current.linkWithCredential(credential);

          // FIX (Aug 11 2026): re-sign-in with the SAME credential
          // immediately after linking.
          //
          // The ID token minted by anonymous sign-in carries
          // firebase.sign_in_provider == 'anonymous', and that claim
          // describes how THIS SESSION was established. Linking adds a
          // provider to the account; it does not necessarily re-mint the
          // session's provider claim, and getIdToken(true) refreshes the
          // token without changing how the session began. firestore.rules'
          // isRealUser() reads exactly that claim — so a freshly linked
          // customer could keep being treated as anonymous and have every
          // booking write denied.
          //
          // Signing in with the credential now that it BELONGS to this
          // account returns the SAME uid (that is the whole point of
          // having linked first), while minting a token whose provider is
          // genuinely google.com. Order matters: link first to keep the
          // uid, then sign in to fix the claim. Never sign in first.
          //
          // Wrapped separately because a failure here is not fatal — the
          // link already succeeded, so the account is correct either way,
          // and the hardened isRealUser() also accepts the email claim.
          try {
            userCredential = await _auth.signInWithCredential(credential);
          } catch (e) {
            debugPrint('[AuthService] post-link re-sign-in failed: $e');
          }
        } on FirebaseAuthException catch (e) {
          if (e.code == 'credential-already-in-use' ||
              e.code == 'email-already-in-use') {
            // This Google account already has an Allin1 account. There
            // is no way to merge two uids client-side (that needs the
            // Admin SDK, i.e. a Cloud Function, which the Spark plan
            // does not have). Signing in as the EXISTING account is the
            // correct call — their real order history matters more than
            // a guest session's cart. The anonymous uid is discarded.
            userCredential = await _auth.signInWithCredential(credential);
          } else {
            rethrow;
          }
        }
      } else {
        // No anonymous session to upgrade (ensureGuestSession() failed,
        // or someone signed out) — a plain sign-in is correct here.
        userCredential = await _auth.signInWithCredential(credential);
      }

      final user = userCredential.user;
      if (user == null) {
        return AuthResult(success: false, error: 'Google sign-in failed');
      }

      // Force refresh so custom claims land before any gated read.
      await user.getIdToken(true);

      final userDocRef = _firestore.collection('users').doc(user.uid);
      final existingDoc = await userDocRef.get();

      if (!existingDoc.exists) {
        // Genuinely new account. Field shape copied verbatim from
        // customer_welcome_login_screen.dart's _signInWithGoogle() —
        // 'phoneNumber' and 'phone' are BOTH written because some
        // admin/hero screens still read only 'phone', and
        // 'isSetupComplete: true' is required because _CustomerHomeGate
        // assumes any real customer already has a complete profile.
        final prefs = await SharedPreferences.getInstance();
        final String? source = prefs.getString('campaign_source');

        await userDocRef.set({
          'uid': user.uid,
          'email': user.email,
          'name': user.displayName ?? '',
          'photoUrl': user.photoURL ?? '',
          'phoneNumber': mobile,
          'phone': mobile,
          if (source != null) 'source': source,
          'isSetupComplete': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      // Existing profile: the typed mobile number is intentionally
      // discarded rather than overwriting a registered one.

      final userData = await getUserData(user.uid);

      // Warm the phone cache from the read we ALREADY did — so the very
      // first booking after sign-in costs zero extra Firestore reads and
      // waits on nothing before dispatching to heroes.
      await cacheCustomerPhone(user.uid, _normalizedPhone(userData, user));

      await _sessionService.saveSession(
        userType: UserType.customer,
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName,
        phoneNumber: _normalizedPhone(userData, user),
        rememberMe: true,
      );

      return AuthResult(success: true, user: user, userData: userData);
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
    // Write-through: the Hive cache is authoritative for reads, so it
    // MUST be updated here or a customer who corrects their number would
    // keep dispatching bookings with the old one for up to 90 days.
    await cacheCustomerPhone(uid, phone);
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

    // Write-through, same reason as updateUserPhone().
    if (userType == UserType.customer) {
      await cacheCustomerPhone(uid, phoneNumber);
    }

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
          // FIX (WhatsApp-model presence migration, CTO mandate): removed
          // 'status'/'isOnline'/'isAvailable' — Firestore no longer
          // tracks live presence at all. RTDB's online_heroes/{uid} node
          // (written the moment a hero actually goes online, backed by
          // onDisconnect()) is now the ONLY source of truth for that.
          // Writing a starting 'offline'/false value here was harmless on
          // its own, but kept the door open for exactly the bug this
          // migration fixes — a Firestore presence field that can go
          // stale and never self-correct.
          // FIX (Hero Registration/Approval bug, CTO mandate): was
          // `if (!existingHero.exists)` — only backfilled approvalStatus
          // when heroes/{uid} was created for the very first time here.
          // But hero_login_screen.dart's _syncHeroIdentityFields() can
          // create heroes/{uid} FIRST (via its own merge-set, which never
          // touches approvalStatus), so by the time this method runs,
          // existingHero.exists is already true and approvalStatus never
          // gets written at all. That hero's doc silently has NO
          // approvalStatus field forever, so Admin's
          // .where('approvalStatus', isEqualTo: 'pending') query in
          // hero_approvals_screen.dart never matches it — the hero is
          // stuck invisible to Admin with no way to be approved. Checking
          // whether the FIELD is missing (not whether the DOC is new)
          // catches that path too, without touching an approvalStatus
          // that's already set (approved/rejected/pending stays as-is).
          if (!(existingHero.data()?.containsKey('approvalStatus') ?? false))
            'approvalStatus': 'pending',
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
  // FIX (audit: "customer/hero number wiring" — Nizam: some order/
  // booking screens showed no phone number for a customer who signed
  // up with Google + a typed-in mobile number): FirebaseAuth's own
  // `user.phoneNumber` is ONLY populated by real phone-OTP auth, never
  // by a mobile number entered manually at signup for a Google/email
  // account — that number lives in Firestore users/{uid}.phoneNumber
  // (with .phone kept in sync). Several order-creation screens
  // (hero_booking_screen, grocery_order_screen, custom_food_order_screen,
  // cart_screen, custom_order_screen, seller_detail_screen,
  // nj_tech_store_screen) were reading `user.phoneNumber` directly and
  // writing an empty customerPhone for every such customer. This is the
  // same Firestore-first, Auth-field-fallback pattern already used
  // correctly by ride_search_screen.dart's _resolveCustomerPhone —
  // centralized here so every screen can share it.
  // ================================================================
  // Customer phone cache (Aug 11 2026 — zero-read, zero-delay dispatch)
  // ================================================================
  // The customer's mobile number never changes between bookings, yet
  // resolveCustomerPhone() was doing a full users/{uid} Firestore READ
  // on every single booking, from 16 call sites. Worse, in
  // ride_search_screen._createRideInRTDB() that read is the FIRST await
  // in the method — so every ride waited on a Firestore round-trip
  // before a single hero was pinged.
  //
  // Now it is cached in Hive, keyed per-uid (never a global key — two
  // accounts on one device must never inherit each other's number).
  // Booking flow cost: 0 Firestore reads, 0 network latency.
  //
  // 90-day TTL, not the HiveCache 30-minute default: this is a stable
  // identity fact, not volatile data. It is refreshed on every sign-in
  // and written through by updateUserPhone()/completeProfileSetup(), so
  // it cannot go stale behind the customer's back.
  static const Duration _phoneCacheTtl = Duration(days: 90);

  String _phoneCacheKey(String uid) => 'customer_phone_$uid';

  /// Writes the number to the local cache. Safe to call often — a
  /// no-op for an empty value, so a failed lookup never overwrites a
  /// good cached number with ''.
  Future<void> cacheCustomerPhone(String uid, String phone) async {
    final trimmed = phone.trim();
    if (uid.isEmpty || trimmed.isEmpty) return;
    try {
      await HiveCache.put(_phoneCacheKey(uid), trimmed, ttl: _phoneCacheTtl);
    } catch (e) {
      debugPrint('[AuthService] cacheCustomerPhone failed: $e');
    }
  }

  /// Reads the cached number without touching the network. Returns ''
  /// when cold.
  Future<String> cachedCustomerPhone(String uid) async {
    if (uid.isEmpty) return '';
    try {
      return (await HiveCache.get<String>(_phoneCacheKey(uid)))?.trim() ?? '';
    } catch (e) {
      debugPrint('[AuthService] cachedCustomerPhone failed: $e');
      return '';
    }
  }

  /// The ONE way to get a customer's phone number. Every booking screen
  /// calls this; nothing should read users/{uid} for a phone directly.
  ///
  /// Order: Hive cache -> users/{uid} (cached on the way out) -> the
  /// Auth field. Note the Auth field is almost always empty here, since
  /// `user.phoneNumber` is only ever populated by real phone-OTP auth
  /// and this app has none — it is kept purely as a last resort.
  Future<String> resolveCustomerPhone(User user) async {
    // 1. Local cache — the common path, 0 reads and no await on network.
    final cached = await cachedCustomerPhone(user.uid);
    if (cached.isNotEmpty) {
      return cached;
    }

    // 2. Cold cache: one Firestore read, then remember it forever.
    try {
      final data = await getUserData(user.uid);
      final resolved = _normalizedPhone(data, user).trim();
      if (resolved.isNotEmpty) {
        unawaited(cacheCustomerPhone(user.uid, resolved));
        return resolved;
      }
    } catch (_) {
      // fall through to Auth-field fallback below
    }

    final authPhone = user.phoneNumber?.trim() ?? '';
    if (authPhone.isNotEmpty) {
      unawaited(cacheCustomerPhone(user.uid, authPhone));
    }
    return authPhone;
  }

  // Same fallback chain as resolveCustomerPhone above, but reads
  // heroes/{uid} instead of users/{uid} — for the hero side of the same
  // "Auth phoneNumber only set by real phone-OTP auth" gap.
  Future<String> resolveHeroPhone(User user) async {
    try {
      final doc = await _firestore.collection('heroes').doc(user.uid).get();
      final data = doc.data();
      final resolved = _normalizedPhone(data, user).trim();
      if (resolved.isNotEmpty) {
        return resolved;
      }
    } catch (_) {
      // fall through to Auth-field fallback below
    }
    return user.phoneNumber?.trim() ?? '';
  }

  // FIX (audit: "Seller custom-menu phone not wiring to customer side" —
  // Nizam: a hotel vendor with no pre-existing catalog uses the "Build a
  // Custom Hotel" screen (SellerCustomHotelBuilderScreen /
  // CustomHotelService.ensureHotelDoc) to create their own menu from
  // scratch and toggle it on, but the customer side had nothing to call
  // — this is the SAME "FirebaseAuth phoneNumber only set by real
  // phone-OTP auth" gap as resolveCustomerPhone/resolveHeroPhone above,
  // just never closed on the seller side: `custom_hotels/{sellerId}`
  // was never written with a phone field at all (not even the
  // Auth-only lookup other screens had), so a Google-Sign-In seller
  // typing their mobile number at KYC had that number sitting only in
  // Firestore sellers/{uid}.phone/.phoneNumber with nothing reading it
  // into the new custom-hotel doc. Reads sellers/{uid} first (the field
  // admin_seller_approval_screen.dart's own Call button already reads
  // as 'phone'), falls back to legacy 'phoneNumber' key, then finally
  // the Auth object — same fallback order as _normalizedPhone above.
  Future<String> resolveSellerPhone(String sellerId, {User? user}) async {
    try {
      final doc = await _firestore.collection('sellers').doc(sellerId).get();
      final data = doc.data();
      final phone = (data?['phone'] as String?)?.trim() ?? '';
      if (phone.isNotEmpty) {
        return phone;
      }
      final legacyPhone = (data?['phoneNumber'] as String?)?.trim() ?? '';
      if (legacyPhone.isNotEmpty) {
        return legacyPhone;
      }
    } catch (_) {
      // fall through to Auth-field fallback below
    }
    final authUser = user ?? _auth.currentUser;
    if (authUser != null && authUser.uid == sellerId) {
      return authUser.phoneNumber?.trim() ?? '';
    }
    return '';
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
