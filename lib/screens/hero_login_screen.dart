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

const Color _bg = Color(0xFF0A0A12);
const Color _card = Color(0xFF1A1A2A);
const Color _green = Color(0xFF00C853);
const Color _gold = Color(0xFFFFBB00);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);

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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(flex: 2),
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
              const Spacer(),
              // Sign in with Google Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _loginWithGoogle,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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
                            Text(
                              'G',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
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
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
