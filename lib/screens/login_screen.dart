// ================================================================
// LoginScreen v3.0 — Allin1 Super App
// Google Sign-In (FREE on Firebase Spark plan!)
// No Blaze plan needed · No brand verification · Works instantly
// ================================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/session_service.dart';
import 'auth/profile_setup_screen.dart';
import 'dashboard_screen.dart';

// ── Theme ──────────────────────────────────────────────────────
const Color kBg = Color(0xFF08080F);
const Color kSurface = Color(0xFF0D0D18);
const Color kCard = Color(0xFF141420);
const Color kCard2 = Color(0xFF1A1A28);
const Color kPurple = Color(0xFF7B6FE0);
const Color kPurple2 = Color(0xFF9B8FF0);
const Color kOrange = Color(0xFFE07C6F);
const Color kGreen = Color(0xFF3DBA6F);
const Color kGold = Color(0xFFF5C542);
const Color kText = Color(0xFFEEEEF5);
const Color kMuted = Color(0xFF7777A0);
const Color kBorder = Color(0x267B6FE0);

class LoginScreen extends StatefulWidget {
  final UserType? presetUserType;
  final bool lockUserType;
  final String? title;
  final String? subtitle;
  final String? lockedUserLabel;
  final String? postLoginRoute;

  const LoginScreen({
    super.key,
    this.presetUserType,
    this.lockUserType = false,
    this.title,
    this.subtitle,
    this.lockedUserLabel,
    this.postLoginRoute,
  });
  @override
  State<LoginScreen> createState() => _LoginScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(EnumProperty<UserType?>('presetUserType', presetUserType))
      ..add(DiagnosticsProperty<bool>('lockUserType', lockUserType))
      ..add(StringProperty('title', title))
      ..add(StringProperty('subtitle', subtitle))
      ..add(StringProperty('lockedUserLabel', lockedUserLabel))
      ..add(StringProperty('postLoginRoute', postLoginRoute));
  }
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  String _error = '';
  UserType _selectedUserType = UserType.customer; // Default to customer
  bool _needsPhoneNumber = false;
  final TextEditingController _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  User? _currentUser;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    if (widget.presetUserType != null) {
      _selectedUserType = widget.presetUserType!;
    }
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim =
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic),
    );
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      // Use AuthService with selected user type
      final authService = AuthService();
      final result = await authService.loginWithGoogle(
        userType: _selectedUserType,
        rememberMe: true,
      );

      if (!mounted) {
        return;
      }

      if (result.success && result.user != null) {
        if (result.requiresProfileSetup) {
          setState(() {
            _loading = false;
          });
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => ProfileSetupScreen(
                preferredRole: _selectedUserType == UserType.hero
                    ? UserType.hero
                    : UserType.customer,
              ),
            ),
          );
        } else {
          _navigateAfterLogin();
        }
      } else {
        setState(() {
          _loading = false;
          _error = result.error ?? 'Google sign-in failed';
        });
        if (_selectedUserType == UserType.admin && mounted) {
          debugPrint('Admin login warning: ${result.error ?? 'Unknown admin Google sign-in error'}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.error ?? 'Admin login failed'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Sign-in failed. Please try again.\n$e';
      });
      if (_selectedUserType == UserType.admin) {
        debugPrint('Admin login warning: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Admin login failed: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Anonymous (Guest / Dev mode) ───────────────────────────
  Future<void> _continueAsGuest() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      // Use standard anonymous sign-in
      final UserCredential result =
          await FirebaseAuth.instance.signInAnonymously();

      if (result.user != null) {
        // Navigate directly to Dashboard after successful guest login
        if (mounted) {
          _selectedUserType = UserType.customer;
          _navigateAfterLogin();
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _loading = false;
        if (e.code == 'admin-restricted-operation') {
          _error =
              'Guest login is disabled. Please enable Anonymous sign-in in Firebase Console.';
        } else {
          _error = 'Guest login failed: ${e.message}';
        }
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Guest login failed: $e';
      });
    }
  }

  Future<void> _submitPhoneNumber() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_currentUser == null) {
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final authService = AuthService();
      final phone = _phoneController.text.trim();

      // 1. Update Firestore
      await authService.updateUserPhone(_currentUser!.uid, phone);

      // 2. Update Session (Hive)
      await SessionService().saveSession(
        userType: _selectedUserType,
        uid: _currentUser!.uid,
        email: _currentUser!.email ?? '',
        displayName: _currentUser!.displayName,
        phoneNumber: phone,
        rememberMe: true,
      );

      _navigateAfterLogin();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to update phone number: $e';
      });
    }
  }

  void _navigateAfterLogin() {
    if (!mounted) {
      return;
    }
    if (widget.postLoginRoute != null && widget.postLoginRoute!.isNotEmpty) {
      Navigator.of(context).pushReplacementNamed(widget.postLoginRoute!);
      return;
    }
    if (_selectedUserType == UserType.admin) {
      Navigator.of(context).pushReplacementNamed('/admin-panel');
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const DashboardScreen()),
    );
  }

  // ================================================================
  // BUILD
  // ================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: SafeArea(
            child: SingleChildScrollView(
              child: SizedBox(
                height: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.top,
                child: Column(
                  children: [
                    // ── TOP SPACE ───────────────────────────
                    const Spacer(flex: 2),

                    // ── LOGO + TITLE ────────────────────────
                    _buildLogoSection(),

                    const Spacer(flex: 2),

                    // ── SIGN-IN CARD ────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _buildSignInCard(),
                    ),

                    const Spacer(),

                    // ── FOOTER ──────────────────────────────
                    _buildFooter(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── LOGO SECTION ─────────────────────────────────────────────
  Widget _buildLogoSection() {
    return Column(
      children: [
        // App icon with glow
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [kPurple, kOrange],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(
                color: Color(0x807B6FE0),
                blurRadius: 30,
                spreadRadius: 2,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.shopping_cart, size: 42, color: Colors.white),
          ),
        ),
        const SizedBox(height: 24),

        // App name
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            colors: [kPurple2, kOrange],
          ).createShader(r),
          child: Text(
            'Allin1 Super App',
            style: GoogleFonts.notoSansTamil(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(height: 8),

        Text(
          'Allin1 Super App',
          style: GoogleFonts.inter(fontSize: 16, color: kMuted),
        ),
        const SizedBox(height: 16),

        // Feature pills
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            _pill(Icons.restaurant, 'Food'),
            _pill(Icons.local_grocery_store, 'Grocery'),
            _pill(Icons.devices, 'Tech'),
            _pill(Icons.directions_bike, 'Bike Taxi'),
          ],
        ),
      ],
    );
  }

  Widget _pill(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: kCard2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: kPurple2),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 10, color: kText)),
          ],
        ),
      );

  // ── User Type Selector ────────────────────────────────────────
  Widget _buildUserTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Login as:',
          style: TextStyle(
            fontSize: 12,
            color: kMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Hero Button
            Expanded(
              child: _userTypeButton(
                icon: Icons.directions_car,
                label: 'Hero',
                isSelected: _selectedUserType == UserType.hero,
                color: kGreen,
                onTap: () => setState(() => _selectedUserType = UserType.hero),
              ),
            ),
            const SizedBox(width: 8),
            // Customer Button
            Expanded(
              child: _userTypeButton(
                icon: Icons.person,
                label: 'Customer',
                isSelected: _selectedUserType == UserType.customer,
                color: kPurple,
                onTap: () =>
                    setState(() => _selectedUserType = UserType.customer),
              ),
            ),
            const SizedBox(width: 8),
            // Admin Button
            Expanded(
              child: _userTypeButton(
                icon: Icons.admin_panel_settings,
                label: 'Admin',
                isSelected: _selectedUserType == UserType.admin,
                color: kOrange,
                onTap: () => setState(() => _selectedUserType = UserType.admin),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLockedUserTypeBadge() {
    String label;
    IconData icon;
    Color color;

    switch (_selectedUserType) {
      case UserType.hero:
        label = 'Hero';
        icon = Icons.directions_car;
        color = kGreen;
        break;
      case UserType.admin:
        label = 'Admin';
        icon = Icons.admin_panel_settings;
        color = kOrange;
        break;
      case UserType.customer:
        label = 'Customer';
        icon = Icons.person;
        color = kPurple;
        break;
    }

    if (widget.lockedUserLabel != null && widget.lockedUserLabel!.isNotEmpty) {
      label = widget.lockedUserLabel!;
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                '$label Login',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _userTypeButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : kCard2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : kBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? color : kMuted, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? color : kMuted,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── SIGN-IN CARD ─────────────────────────────────────────────
  Widget _buildSignInCard() {
    final cardTitle = widget.title ?? 'Sign In';
    final cardSubtitle = widget.subtitle ?? 'Continue to Allin1 Super App';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3308080F),
            blurRadius: 30,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            cardTitle,
            style: GoogleFonts.notoSansTamil(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: kText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            cardSubtitle,
            style: const TextStyle(fontSize: 12, color: kMuted),
          ),

          const SizedBox(height: 24),

          if (_needsPhoneNumber)
            _buildPhoneCollectionUI()
          else ...[
            // ── User Type Selector ────────────────────────────────
            if (widget.lockUserType)
              _buildLockedUserTypeBadge()
            else
              _buildUserTypeSelector(),

            const SizedBox(height: 16),

            // ── Google Sign-In Button ────────────────────────
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(color: kPurple),
              )
            else
              _googleButton(),

            // ── Divider ──────────────────────────────────────
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  Expanded(child: Divider(color: kBorder)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'or',
                      style: TextStyle(fontSize: 12, color: kMuted),
                    ),
                  ),
                  Expanded(child: Divider(color: kBorder)),
                ],
              ),
            ),

            // ── Guest Button ──────────────────────────────────
            Visibility(
              visible: false,
              child: _guestButton(),
            ),
          ],

          // ── Error ────────────────────────────────────────
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x1AE05555),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x4DE05555)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 16,
                    color: Color(0xFFE05555),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFE05555),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── GOOGLE BUTTON ─────────────────────────────────────────────
  Widget _googleButton() {
    return GestureDetector(
      onTap: _signInWithGoogle,
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Google G logo (SVG-style with text)
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
              child: CustomPaint(painter: _GoogleLogoPainter()),
            ),
            const SizedBox(width: 12),
            Text(
              'Continue with Google',
              style: GoogleFonts.notoSansTamil(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF3C4043),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── GUEST BUTTON ─────────────────────────────────────────────
  Widget _guestButton() {
    return GestureDetector(
      onTap: _continueAsGuest,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          color: kCard2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_outline, size: 18, color: kMuted),
            const SizedBox(width: 8),
            Text(
              'Guest-ஆ பார்க்க (Demo)',
              style: GoogleFonts.notoSansTamil(fontSize: 14, color: kMuted),
            ),
          ],
        ),
      ),
    );
  }

  // ── FOOTER ───────────────────────────────────────────────────
  Widget _buildFooter() {
    return Column(
      children: [
        const Text(
          'Powered by NJ TECH',
          style: TextStyle(fontSize: 11, color: kMuted),
        ),
        const SizedBox(height: 4),
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            colors: [kPurple2, kOrange],
          ).createShader(r),
          child: const Text(
            'Food · Grocery · Tech · Bike Taxi',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  // ── PHONE COLLECTION UI ──────────────────────────────────────
  Widget _buildPhoneCollectionUI() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          const Text(
            'Almost there! Enter your 10-digit mobile number to continue.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: kText),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Mobile Number',
              labelStyle: const TextStyle(color: kMuted),
              hintText: '9876543210',
              hintStyle: TextStyle(color: kMuted.withValues(alpha: 0.5)),
              prefixIcon: const Icon(Icons.phone_iphone, color: kPurple2),
              filled: true,
              fillColor: kCard2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: kBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: kPurple),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Required';
              }
              if (value.length != 10) {
                return 'Enter 10 digits';
              }
              if (!RegExp(r'^[0-9]+$').hasMatch(value)) {
                return 'Numbers only';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          if (_loading)
            const CircularProgressIndicator(color: kPurple)
          else
            GestureDetector(
              onTap: _submitPhoneNumber,
              child: Container(
                width: double.infinity,
                height: 54,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [kPurple, kPurple2]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: kPurple.withValues(alpha: 0.4),
                      blurRadius: 15,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    'Submit & Continue',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() => _needsPhoneNumber = false),
            child: const Text('Back to Login', style: TextStyle(color: kMuted)),
          ),
        ],
      ),
    );
  }
}

// ── Google Logo Painter ──────────────────────────────────────────
class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / 2;
    final r = size.width / 2;

    canvas
      ..drawArc(
        Rect.fromCircle(center: Offset(c, c), radius: r),
        -1.57,
        1.57,
        false,
        Paint()
          ..color = const Color(0xFF4285F4)
          ..strokeWidth = size.width * 0.22
          ..style = PaintingStyle.stroke,
      )
      ..drawArc(
        Rect.fromCircle(center: Offset(c, c), radius: r),
        0,
        1.57,
        false,
        Paint()
          ..color = const Color(0xFFEA4335)
          ..strokeWidth = size.width * 0.22
          ..style = PaintingStyle.stroke,
      )
      ..drawArc(
        Rect.fromCircle(center: Offset(c, c), radius: r),
        1.57,
        1.57,
        false,
        Paint()
          ..color = const Color(0xFFFBBC05)
          ..strokeWidth = size.width * 0.22
          ..style = PaintingStyle.stroke,
      )
      ..drawArc(
        Rect.fromCircle(center: Offset(c, c), radius: r),
        3.14,
        1.57,
        false,
        Paint()
          ..color = const Color(0xFF34A853)
          ..strokeWidth = size.width * 0.22
          ..style = PaintingStyle.stroke,
      )
      ..drawLine(
        Offset(c, c),
        Offset(size.width, c),
        Paint()
          ..color = const Color(0xFF4285F4)
          ..strokeWidth = size.width * 0.22,
      );
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}
