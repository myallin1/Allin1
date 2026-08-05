import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/local_sync_service.dart';

// ================================================================
// CustomerLoginScreen — Sign Up (mobile-number-first) + Sign In
// ================================================================
// NEW (CTO mandate — Login Screen Redesign). Previously: a single
// "Continue with Google" button with NO mobile-number step and NO
// Firestore users/{uid} write anywhere in this file — sign-in just
// jumped straight to /dashboard. Redesigned per the CTO's explicit
// flow:
//   1. A mandatory mobile number field, shown first.
//   2. "Sign in with Google" (NEW USER path) — validates the mobile
//      number, signs in with Google, and writes that number into the
//      brand-new users/{uid} doc as part of account creation. Edge
//      case (CTO-confirmed): if this Google account turns out to
//      already have a users/{uid} doc (someone tapped the New-user
//      button by mistake), this treats it as an existing-user login
//      instead — the typed mobile number is simply discarded, nothing
//      is overwritten, and they go straight to the dashboard.
//   3. "Already have an account?" divider.
//   4. "Sign in here" (EXISTING USER path) — Google sign-in only, no
//      mobile number required or validated (CTO-confirmed) — for a
//      returning customer whose phone number is already on file.
//
// Both buttons share the exact same Google Sign-In mechanics as the
// original file (same GoogleSignIn config, same credential exchange) —
// only what happens with the resulting UserCredential differs.
class CustomerLoginScreen extends StatefulWidget {
  const CustomerLoginScreen({super.key});

  @override
  State<CustomerLoginScreen> createState() => _CustomerLoginScreenState();
}

class _CustomerLoginScreenState extends State<CustomerLoginScreen> {
  static const String _googleWebClientId =
      '357526153693-02b0behmsf3k720jujg3e8j82frj04q7.apps.googleusercontent.com';
  static const Color _bg = Color(0xFF0D0D0D);
  static const Color _border = Color(0xFF2C2C2C);

  final TextEditingController _mobileController = TextEditingController();
  bool _loadingNewUser = false;
  bool _loadingExistingUser = false;
  String? _mobileError;

  @override
  void dispose() {
    _mobileController.dispose();
    super.dispose();
  }

  bool get _busy => _loadingNewUser || _loadingExistingUser;

  /// India-focused, matches the digit-count check already used
  /// elsewhere in this app (auth_service.dart's own phone validation
  /// convention) — 10 digits, optionally with a country code prefix
  /// the user typed themselves; we only care that at least 10 digits
  /// are present.
  bool _isValidMobile(String value) {
    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
    return digitsOnly.length >= 10;
  }

  Future<GoogleSignInAccount?> _pickGoogleAccount() async {
    final googleSignIn = GoogleSignIn(
      clientId: kIsWeb ? _googleWebClientId : null,
      serverClientId: kIsWeb ? null : _googleWebClientId,
      scopes: const ['email', 'profile'],
    );
    return googleSignIn.signIn();
  }

  Future<UserCredential?> _signInWithGoogleAccount(GoogleSignInAccount account) async {
    final googleAuth = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return FirebaseAuth.instance.signInWithCredential(credential);
  }

  Future<void> _afterSignIn(String uid) async {
    // Force refresh to fetch latest claims — unchanged from the
    // original file's behavior.
    await FirebaseAuth.instance.currentUser?.getIdToken(true);

    // ── Local-First: kick off background delta-sync after login ──
    unawaited(
      LocalSyncService.instance.syncAll(
        userId: uid,
        city: 'Erode', // TODO: make dynamic when multi-city goes live
      ),
    );

    if (mounted) {
      await Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
    }
  }

  // ── NEW USER path: mandatory mobile number, writes it into the
  // brand-new users/{uid} doc on account creation. ──
  Future<void> _signUpWithGoogle() async {
    final mobile = _mobileController.text.trim();
    if (!_isValidMobile(mobile)) {
      setState(() => _mobileError = 'Please enter a valid mobile number.');
      return;
    }
    setState(() {
      _mobileError = null;
      _loadingNewUser = true;
    });
    try {
      final account = await _pickGoogleAccount();
      if (account == null) {
        if (mounted) setState(() => _loadingNewUser = false);
        return;
      }
      final userCredential = await _signInWithGoogleAccount(account);
      final user = userCredential.user;
      if (user == null) {
        if (mounted) setState(() => _loadingNewUser = false);
        return;
      }

      final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final existingDoc = await userDocRef.get();

      if (!existingDoc.exists) {
        // Genuinely new account — this is where the typed mobile
        // number gets wired in, matching the established field-naming
        // convention this app already uses elsewhere (both
        // 'phoneNumber' and 'phone' are kept in sync — see
        // auth_service.dart's _saveUserData/completeProfileSetup,
        // which write both for the same reason: some existing
        // admin/hero screens still read only 'phone').
        await userDocRef.set({
          'uid': user.uid,
          'email': user.email,
          'name': user.displayName ?? '',
          'photoUrl': user.photoURL ?? '',
          'phoneNumber': mobile,
          'phone': mobile,
          'isSetupComplete': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      // FIX (CTO-confirmed edge case): existingDoc.exists == true means
      // this Google account already has an account — the typed mobile
      // number is intentionally discarded here (never overwrites an
      // existing profile), and this simply becomes a normal login.

      await _afterSignIn(user.uid);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign up failed: $e'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingNewUser = false);
    }
  }

  // ── EXISTING USER path: no mobile number required at all. ──
  Future<void> _signInExistingUser() async {
    setState(() => _loadingExistingUser = true);
    try {
      final account = await _pickGoogleAccount();
      if (account == null) {
        if (mounted) setState(() => _loadingExistingUser = false);
        return;
      }
      final userCredential = await _signInWithGoogleAccount(account);
      final user = userCredential.user;
      if (user == null) {
        if (mounted) setState(() => _loadingExistingUser = false);
        return;
      }
      await _afterSignIn(user.uid);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign in failed: $e'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingExistingUser = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF4FA3), Color(0xFFFF92C8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Center(
                  child: Text(
                    'NJ',
                    style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Create Your Account',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in to order food, groceries\nand book bike rides in Erode',
                style: TextStyle(color: Colors.grey[500], fontSize: 13.5, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // ── Mandatory mobile number field (new-user path) ──
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Mobile Number',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _mobileController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                onChanged: (_) {
                  if (_mobileError != null) setState(() => _mobileError = null);
                },
                decoration: InputDecoration(
                  hintText: 'Enter your mobile number',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  prefixIcon: const Icon(Icons.phone_iphone_rounded, color: Colors.white54),
                  filled: true,
                  fillColor: const Color(0xFF161616),
                  errorText: _mobileError,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFFF4FA3), width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── New-user Google Sign-In ──
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy ? null : _signUpWithGoogle,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    disabledBackgroundColor: Colors.white.withValues(alpha: 0.4),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _loadingNewUser
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFFFF6B35)),
                        )
                      : const _GoogleButtonLabel(label: 'Sign in with Google'),
                ),
              ),
              const SizedBox(height: 24),

              // ── "Already have an account?" divider ──
              Row(
                children: [
                  const Expanded(child: Divider(color: _border)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Already have an account?', style: TextStyle(color: Colors.grey[600], fontSize: 12.5)),
                  ),
                  const Expanded(child: Divider(color: _border)),
                ],
              ),
              const SizedBox(height: 16),

              // ── Existing-user Google Sign-In — no mobile field required ──
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _busy ? null : _signInExistingUser,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    side: const BorderSide(color: _border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _loadingExistingUser
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : const _GoogleButtonLabel(label: 'Sign in here', dark: false),
                ),
              ),

              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'By continuing, you agree to our\nTerms of Service & Privacy Policy',
                  style: TextStyle(color: Colors.grey[700], fontSize: 11, height: 1.5),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleButtonLabel extends StatelessWidget {
  const _GoogleButtonLabel({required this.label, this.dark = true});
  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
          child: const Center(
            child: Text('G', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF4285F4))),
          ),
        ),
        const SizedBox(width: 14),
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: dark ? Colors.black87 : Colors.white,
          ),
        ),
      ],
    );
  }
}
