// ================================================================
// Hero Login/Register Screen
// Allin1 Super App - Hero Onboarding
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'hero_pending_screen.dart';
import 'hero_register_screen.dart';

// THEME FIX: was a dark theme, inconsistent with the customer app's
// language/sign-in page (welcome_screen.dart), which Nizam pointed to as
// the reference look. Palette below is lifted straight from that file so
// the hero and customer apps' opening screens read as one family — white
// background, pink brand accent, the same ink/muted text colors.
const Color _bg = Colors.white;
const Color _card = Color(0xFFFFF3F9);
const Color _green = Color(0xFF00C853);
const Color _gold = Color(0xFFFFBB00);
const Color _text = Color(0xFF4A1236);
const Color _muted = Color(0xFF8A4E72);
const Color _pink = Color(0xFFFF4FA3);
const Color _pinkLight = Color(0xFFFF92C8);
const Color _border = Color(0xFFF0DCE8);

class HeroLoginScreen extends StatefulWidget {
  const HeroLoginScreen({super.key});

  @override
  State<HeroLoginScreen> createState() => _HeroLoginScreenState();
}

class _HeroLoginScreenState extends State<HeroLoginScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _otpSent = false;
  final bool _showEmailLogin = false;
  String _verificationId = '';

  bool _isApprovedHero(Map<String, dynamic>? heroData) {
    return heroData?['approvalStatus']?.toString().trim().toLowerCase() ==
        'approved';
  }

  bool _isPendingHero(Map<String, dynamic>? heroData) {
    return heroData?['approvalStatus']?.toString().trim().toLowerCase() ==
        'pending';
  }

  Future<void> _syncHeroIdentityFields(
    User user,
    Map<String, dynamic>? heroData,
  ) async {
    await FirebaseFirestore.instance.collection('heroes').doc(user.uid).set({
      'uid': user.uid,
      'heroId': user.uid,
      'email': user.email ?? heroData?['email'] ?? '',
      'phone': user.phoneNumber ?? heroData?['phone'] ?? '',
      'phoneNumber':
          user.phoneNumber ??
          heroData?['phoneNumber'] ??
          heroData?['phone'] ??
          '',
      'name':
          user.displayName ??
          heroData?['name'] ??
          heroData?['captainName'] ??
          '',
      // FIX (Hero Registration/Approval bug, CTO mandate): this was the
      // other half of the disconnect — this identity-sync merge-set could
      // be the FIRST write to heroes/{uid} for a hero, and it never set
      // approvalStatus at all. If auth_service.dart's
      // completeProfileSetup() ran afterward and only checked
      // `!existingHero.exists` (now fixed to check the field itself), the
      // hero's doc would permanently have no approvalStatus and never
      // show up in Admin's pending-approvals query. Backfilling it here
      // too closes the gap regardless of which write path runs first.
      if (!(heroData?.containsKey('approvalStatus') ?? false))
        'approvalStatus': 'pending',
    }, SetOptions(merge: true),);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _sendOTP() async {
    if (_phoneController.text.length < 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid phone number'),
            backgroundColor: Color(0xFFFF5252),
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: '+91${_phoneController.text}',
        verificationCompleted: (credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
        },
        verificationFailed: (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Verification failed: ${e.message}'),
                backgroundColor: const Color(0xFFFF5252),
              ),
            );
          }
        },
        codeSent: (verificationId, resendToken) {
          setState(() {
            _otpSent = true;
            _verificationId = verificationId;
          });
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: const Color(0xFFFF5252),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _verifyOTP() async {
    if (_otpController.text.length < 6) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter the 6-digit OTP'),
            backgroundColor: Color(0xFFFF5252),
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: _otpController.text,
      );

      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      final user = userCredential.user;
      if (user == null) {
        throw Exception('User not found after OTP verification');
      }

      // STRICT CHECK ORDER:
      // 1) heroes collection (approved only)
      final heroDoc = await FirebaseFirestore.instance
          .collection('heroes')
          .doc(user.uid)
          .get();

      final heroData = heroDoc.data();
      if (heroDoc.exists) {
        await _syncHeroIdentityFields(user, heroData);
      }
      if (heroDoc.exists && _isApprovedHero(heroData)) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/hero-home');
        }
        return;
      }
      if (heroDoc.exists && _isPendingHero(heroData)) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const HeroPendingScreen(),
            ),
          );
        }
        return;
      }

      // 2) heroes_pending collection
      final pendingDoc = await FirebaseFirestore.instance
          .collection('heroes_pending')
          .doc(user.uid)
          .get();

      if (pendingDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your registration is pending admin approval'),
              backgroundColor: _gold,
            ),
          );
          await FirebaseAuth.instance.signOut();
          Navigator.pop(context);
        }
        return;
      }

      // 3) New user - redirect to registration
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const HeroRegisterScreen(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification failed: ${e.toString()}'),
            backgroundColor: const Color(0xFFFF5252),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loginWithEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter email and password'),
            backgroundColor: Color(0xFFFF5252),
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      final user = userCredential.user;
      if (user == null) {
        throw Exception('User not found after email login');
      }

      // Check heroes collection (approved only)
      final heroDoc = await FirebaseFirestore.instance
          .collection('heroes')
          .doc(user.uid)
          .get();

      final heroData = heroDoc.data();
      if (heroDoc.exists) {
        await _syncHeroIdentityFields(user, heroData);
      }
      if (heroDoc.exists && _isApprovedHero(heroData)) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/hero-home');
        }
        return;
      }
      if (heroDoc.exists && _isPendingHero(heroData)) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const HeroPendingScreen(),
            ),
          );
        }
        return;
      }

      // Check heroes_pending collection
      final pendingDoc = await FirebaseFirestore.instance
          .collection('heroes_pending')
          .doc(user.uid)
          .get();

      if (pendingDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your registration is pending admin approval'),
              backgroundColor: _gold,
            ),
          );
          await FirebaseAuth.instance.signOut();
          Navigator.pop(context);
        }
        return;
      }

      // Not a hero - sign out and show error
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This email is not registered as a Hero'),
            backgroundColor: Color(0xFFFF5252),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login failed: ${e.toString()}'),
            backgroundColor: const Color(0xFFFF5252),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loginWithGoogle() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    const googleWebClientId =
        '357526153693-02b0behmsf3k720jujg3e8j82frj04q7.apps.googleusercontent.com';
    final googleSignIn = GoogleSignIn(
      clientId: kIsWeb ? googleWebClientId : null,
      serverClientId: kIsWeb ? null : googleWebClientId,
      scopes: const ['email', 'profile'],
    );

    try {
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) throw Exception('User not found after Google sign-in');

      final heroDoc = await FirebaseFirestore.instance
          .collection('heroes')
          .doc(user.uid)
          .get();
 
      if (!mounted) return;
 
      if (!heroDoc.exists) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const HeroRegisterScreen(),
          ),
        );
        return;
      }
 
      final heroData = heroDoc.data();
      await _syncHeroIdentityFields(user, heroData);
 
      if (_isApprovedHero(heroData)) {
        Navigator.pushReplacementNamed(context, '/hero-home');
        return;
      }
 
      if (_isPendingHero(heroData)) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const HeroPendingScreen(),
          ),
        );
        return;
      }

      await FirebaseAuth.instance.signOut();
      await googleSignIn.signOut();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your account is pending Admin approval'),
          backgroundColor: Color(0xFFF5C542),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google sign-in failed: $e'),
          backgroundColor: const Color(0xFFFF5252),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        // FIX: was a fixed-height Column with Spacer()s, which only works
        // when content is short enough to fit one screen. Nizam wants the
        // "How to be an Allin1 Hero?" guidance visible on THIS page (above
        // the login/register options, not inside the registration form or
        // a separate page) — that's real height, so this needs to scroll
        // on smaller phones instead of overflowing. Spacers replaced with
        // fixed gaps accordingly.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 32),
              // Logo — was the 2.4 MB bapx_nj_logo.gif, now drawn in code.
              // See the matching comment in customer_login_screen.dart.
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF4FA3), Color(0xFFFF92C8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Center(
                  child: Text('🦸', style: TextStyle(fontSize: 48)),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Hero Partner',
                style: GoogleFonts.outfit(
                  color: _text,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Login to start accepting rides',
                style: GoogleFonts.outfit(
                  color: _muted,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 28),
              // FIX: guidance card, per Nizam's explicit instruction — shown
              // here on the opening page, ABOVE the Google sign-in /
              // Register as Hero options below, with a graphic icon per
              // step (not just a number) so it reads at a glance.
              const _HowToBecomeHeroCard(),
              const SizedBox(height: 28),
              // THEME FIX: was a transparent-outline/white-text button
              // designed for a dark background — now a solid pink button
              // matching welcome_screen.dart's "Continue with Google" on
              // the customer app, for the same light theme.
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _loginWithGoogle,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pink,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _pink.withValues(alpha: 0.5),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.login_rounded, size: 19, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'Sign in with Google',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),
              // Register Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const HeroRegisterScreen(),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _gold,
                    side: const BorderSide(color: _gold),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Register as Hero',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ── "How to be an Allin1 Hero?" guidance card ──────────────────────
// Shown on THIS opening/login page, above the Google sign-in / Register
// as Hero options — per Nizam's explicit instruction. Each step gets its
// own icon badge (not just a number) so it reads as a graphical
// instruction at a glance, not a wall of text. Same 3 stages
// HeroPendingScreen tracks live after a hero actually submits the form.
class _HowToBecomeHeroCard extends StatelessWidget {
  const _HowToBecomeHeroCard();

  static const List<_HowToStep> _steps = [
    _HowToStep(
      icon: Icons.badge_rounded,
      title: 'Fill Your Details & Upload Proof',
      subtitle: 'Personal info + License, Aadhaar, PAN photos',
    ),
    _HowToStep(
      icon: Icons.fact_check_rounded,
      title: 'KYC Verification',
      subtitle: 'Admin checks your documents and calls to confirm',
    ),
    _HowToStep(
      icon: Icons.emoji_events_rounded,
      title: 'Onboarding Complete',
      subtitle: "You're approved — go online and start earning",
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF4FA3), Color(0xFFBE2A7A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF4FA3).withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How to be an Allin1 Hero?',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < _steps.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                  alignment: Alignment.center,
                  child: Icon(_steps[i].icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _steps[i].title,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _steps[i].subtitle,
                          style: GoogleFonts.outfit(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (i != _steps.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 19),
                child: Container(
                  width: 2,
                  height: 20,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _HowToStep {
  const _HowToStep({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}
