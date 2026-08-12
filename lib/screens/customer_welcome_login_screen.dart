// ================================================================
// customer_welcome_login_screen.dart
// ================================================================
// NEW (Aug 8 2026 — Nizam's "Unified Welcome Screen" architectural
// decision): merges what used to be TWO separate screens shown to a
// signed-out customer into ONE:
//
//   1. welcome_screen.dart (white/pink theme) — language picker +
//      "Continue with Google" / "Sign in later".
//   2. customer_login_screen.dart (black theme) — mandatory mobile
//      number field + Google sign-in that binds the phone number to
//      the new Firestore users/{uid} doc.
//
// Both of those files are left in place, UNROUTED from the customer
// boot path (welcome_screen.dart already had no other live caller;
// customer_login_screen.dart is still reachable via the '/login' named
// route for any other place in the app that pushes it directly).
//
// Design: primary White/Pink brand theme (matches AppSplashVideoScreen
// / BrandedLoadingScreen), not the old black CustomerLoginScreen look.
//
// Boot placement (per Nizam's explicit flow): App Boot -> app_splash.mp4
// (once) -> THIS screen (only if FirebaseAuth.currentUser == null) ->
// CustomerDashboard. Shown on EVERY launch while signed out (Nizam's
// explicit choice, not first-launch-only) — "Login Later" always lets
// a guest through without blocking browsing.
//
// Auth logic reused exactly from customer_login_screen.dart's
// _signUpWithGoogle(): mobile number is mandatory, written into a
// brand-new users/{uid} doc on account CREATION only. If the chosen
// Google account already has a users/{uid} doc (returning customer
// signing in from a signed-out state, e.g. after a manual sign-out),
// the typed mobile number is safely discarded — never overwrites an
// existing profile — and this just becomes a normal login.
// ================================================================
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Phone cache warm-up on sign-in (Aug 11 2026).
import '../services/auth_service.dart';
import '../services/local_sync_service.dart';
import '../services/localization_service.dart';

const Color _kPink = Color(0xFFFF4FA3);
const Color _kPinkLight = Color(0xFFFF92C8);
const Color _kInk = Color(0xFF4A1236);
const Color _kMuted = Color(0xFF8A4E72);
const Color _kBorder = Color(0xFFF0DCE8);
const Color _kFieldFill = Color(0xFFFFF6FA);

class CustomerWelcomeLoginScreen extends StatefulWidget {
  /// Where to go once the customer is done here (signed in, or chose
  /// "Login Later"). Kept as an injected `next` widget — same pattern
  /// the old WelcomeScreen used — so this screen stays decoupled from
  /// exactly what "the dashboard" is.
  final Widget next;

  const CustomerWelcomeLoginScreen({required this.next, super.key});

  @override
  State<CustomerWelcomeLoginScreen> createState() =>
      _CustomerWelcomeLoginScreenState();
}

class _CustomerWelcomeLoginScreenState
    extends State<CustomerWelcomeLoginScreen> {
  static const String _googleWebClientId =
      '357526153693-02b0behmsf3k720jujg3e8j82frj04q7.apps.googleusercontent.com';

  static const List<({String code, String label, String hint})> _languages = [
    (code: 'ta', label: 'தமிழ்', hint: 'Tamil'),
    (code: 'en', label: 'English', hint: 'English'),
    (code: 'tg', label: 'Tanglish', hint: 'Tamil + English'),
  ];

  final TextEditingController _mobileController = TextEditingController();
  bool _busy = false;
  String? _mobileError;

  @override
  void dispose() {
    _mobileController.dispose();
    super.dispose();
  }

  String get _selectedLanguage =>
      context.watch<LocalizationService>().languageCode;

  Future<void> _chooseLanguage(String code) async {
    if (_busy) return;
    // Applied immediately, same as the old WelcomeScreen, so the
    // customer sees the choice take effect right away.
    await context.read<LocalizationService>().setLanguage(code);
  }

  bool _isValidMobile(String value) {
    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
    return digitsOnly.length >= 10;
  }

  Future<void> _continueAsGuest() async {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => widget.next),
    );
  }

  Future<void> _afterSignIn(String uid) async {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    unawaited(
      LocalSyncService.instance.syncAll(
        userId: uid,
        city: 'Erode', // TODO: make dynamic when multi-city goes live
      ),
    );
    if (mounted) await _continueAsGuest();
  }

  Future<void> _signInWithGoogle() async {
    if (_busy) return;
    final mobile = _mobileController.text.trim();
    if (!_isValidMobile(mobile)) {
      setState(() => _mobileError = 'Please enter a valid mobile number.');
      return;
    }
    setState(() {
      _mobileError = null;
      _busy = true;
    });
    try {
      final googleSignIn = GoogleSignIn(
        clientId: kIsWeb ? _googleWebClientId : null,
        serverClientId: kIsWeb ? null : _googleWebClientId,
        scopes: const ['email', 'profile'],
      );
      final account = await googleSignIn.signIn();
      if (account == null) {
        // User cancelled the picker — not an error, just stop here.
        if (mounted) setState(() => _busy = false);
        return;
      }
      final googleAuth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      final userDocRef =
          FirebaseFirestore.instance.collection('users').doc(user.uid);
      final existingDoc = await userDocRef.get();

      if (!existingDoc.exists) {
        // Genuinely new account — bind the typed mobile number, same
        // field-naming convention used everywhere else in this app
        // ('phoneNumber' and 'phone' both kept in sync).
        
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
      // Existing account (existingDoc.exists == true): the typed
      // mobile number is intentionally discarded — never overwrites an
      // already-registered profile — this just becomes a normal login.

      // Phone cache (Aug 11 2026): warm it here so this customer's first
      // booking costs zero Firestore reads and waits on no network call
      // before the hero ping goes out. Uses the number we already have in
      // hand for a new account, or the stored one for a returning login.
      await AuthService().cacheCustomerPhone(
        user.uid,
        existingDoc.exists
            ? ((existingDoc.data()?['phoneNumber'] as String?) ??
                (existingDoc.data()?['phone'] as String?) ??
                '')
            : mobile,
      );

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
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_kPink, _kPinkLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x24FF4FA3),
                            blurRadius: 22,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'NJ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "That'll Bapx NJ Tech",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _kInk,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Order food, grocery, tech & book bike rides in Erode',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _kMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 26),

                  // ── Language selector ──────────────────────────
                  const Text(
                    'மொழி / Language',
                    style: TextStyle(
                      color: _kInk,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: _languages
                        .map((lang) => Expanded(child: _languageChip(lang)))
                        .toList(),
                  ),

                  const SizedBox(height: 22),

                  // ── Mobile number field ─────────────────────────
                  const Text(
                    'Mobile Number',
                    style: TextStyle(
                      color: _kInk,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _mobileController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: _kInk, fontSize: 15),
                    onChanged: (_) {
                      if (_mobileError != null) {
                        setState(() => _mobileError = null);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'Enter your mobile number',
                      hintStyle: TextStyle(color: _kMuted.withValues(alpha: 0.6)),
                      prefixIcon: const Icon(Icons.phone_iphone_rounded, color: _kMuted),
                      filled: true,
                      fillColor: _kFieldFill,
                      errorText: _mobileError,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _kBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _kBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _kPink, width: 1.6),
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  // ── Gmail login button ──────────────────────────
                  SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _busy ? null : () => unawaited(_signInWithGoogle()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _kInk,
                        disabledBackgroundColor: Colors.white.withValues(alpha: 0.6),
                        elevation: 0,
                        side: const BorderSide(color: _kBorder, width: 1.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: _kPink,
                              ),
                            )
                          : const _GoogleButtonLabel(),
                    ),
                  ),

                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _busy ? null : () => unawaited(_continueAsGuest()),
                    style: TextButton.styleFrom(foregroundColor: _kMuted),
                    child: const Text(
                      'Login Later  →',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'You can look around freely.\n'
                    "We'll only ask you to sign in when you book.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _kMuted,
                      fontSize: 11.5,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _languageChip(({String code, String label, String hint}) lang) {
    final isSelected = _selectedLanguage == lang.code;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _busy ? null : () => unawaited(_chooseLanguage(lang.code)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFFF3F9) : _kFieldFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? _kPink : _kBorder,
              width: isSelected ? 1.8 : 1.2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                lang.label,
                style: TextStyle(
                  color: _kInk,
                  fontSize: 13.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: isSelected ? _kPink : _kBorder,
                size: 15,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleButtonLabel extends StatelessWidget {
  const _GoogleButtonLabel();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: _kFieldFill,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _kBorder),
          ),
          child: const Center(
            child: Text(
              'G',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF4285F4),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'Continue with Google',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: _kInk,
          ),
        ),
      ],
    );
  }
}
