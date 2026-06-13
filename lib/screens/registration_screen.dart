// ================================================================
// Registration Screen - User Type Selection & Registration
// Allin1 Super App v1.0
// ================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/session_service.dart';
import 'dashboard_screen.dart';

// ── Theme Colors ─────────────────────────────────────────────
const Color kBg = Color(0xFF08080F);
const Color kSurface = Color(0xFF0D0D18);
const Color kCard = Color(0xFF141420);
const Color kCard2 = Color(0xFF1A1A28);
const Color kPurple = Color(0xFF7B6FE0);
const Color kPurple2 = Color(0xFF9B8FF0);
const Color kGreen = Color(0xFF3DBA6F);
const Color kOrange = Color(0xFFE07C6F);
const Color kRed = Color(0xFFE05555);
const Color kText = Color(0xFFEEEEF5);
const Color kMuted = Color(0xFF7777A0);
const Color kBorder = Color(0x267B6FE0);

class RegistrationScreen extends StatefulWidget {
  final UserType selectedUserType;

  const RegistrationScreen({
    required this.selectedUserType,
    super.key,
  });

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
        .add(EnumProperty<UserType>('selectedUserType', selectedUserType));
  }
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _usernameError;
  String? _generalError;

  late UserType _userType;

  @override
  void initState() {
    super.initState();
    _userType = widget.selectedUserType;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // ================================================================
  // Validate Username in Real-time
  // ================================================================
  Future<void> _validateUsername(String username) async {
    if (username.isEmpty) {
      setState(() => _usernameError = null);
      return;
    }

    final authService = AuthService();
    final formatError = authService.validateUsername(username);

    if (formatError != null) {
      setState(() => _usernameError = formatError);
      return;
    }

    // Check if username is taken
    final isTaken = await authService.isUsernameTaken(username);
    if (isTaken) {
      setState(() => _usernameError = 'Username is already taken');
    } else {
      setState(() => _usernameError = null);
    }
  }

  // ================================================================
  // Handle Registration
  // ================================================================
  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_usernameError != null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _generalError = null;
    });

    final authService = AuthService();
    final result = await authService.registerWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      username: _usernameController.text.trim(),
      userType: _userType,
      phoneNumber: _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim(),
    );

    if (!mounted) {
      return;
    }

    setState(() => _isLoading = false);

    if (result.success) {
      // Navigate to appropriate dashboard
      _navigateToDashboard();
    } else {
      setState(() => _generalError = result.error);
    }
  }

  // ================================================================
  // Navigate to Dashboard based on User Type
  // ================================================================
  void _navigateToDashboard() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const DashboardScreen()),
    );
  }

  // ================================================================
  // Get User Type Display Name
  // ================================================================
  String get _userTypeDisplayName {
    switch (_userType) {
      case UserType.hero:
        return 'Hero (Driver)';
      case UserType.customer:
        return 'Customer';
      case UserType.admin:
        return 'Admin';
    }
  }

  // ================================================================
  // Get User Type Icon
  // ================================================================
  IconData get _userTypeIcon {
    switch (_userType) {
      case UserType.hero:
        return Icons.directions_car;
      case UserType.customer:
        return Icons.person;
      case UserType.admin:
        return Icons.admin_panel_settings;
    }
  }

  // ================================================================
  // Get User Type Color
  // ================================================================
  Color get _userTypeColor {
    switch (_userType) {
      case UserType.hero:
        return kGreen;
      case UserType.customer:
        return kPurple;
      case UserType.admin:
        return kOrange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Register as $_userTypeDisplayName',
          style: GoogleFonts.poppins(color: kText),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── User Type Badge ─────────────────────────────────
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: _userTypeColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: _userTypeColor.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_userTypeIcon, color: _userTypeColor),
                    const SizedBox(width: 8),
                    Text(
                      _userTypeDisplayName,
                      style: GoogleFonts.poppins(
                        color: _userTypeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Username Field ─────────────────────────────────
              TextFormField(
                controller: _usernameController,
                style: const TextStyle(color: kText),
                decoration: InputDecoration(
                  labelText: 'Username',
                  labelStyle: const TextStyle(color: kMuted),
                  prefixIcon: const Icon(Icons.alternate_email, color: kMuted),
                  errorText: _usernameError,
                  filled: true,
                  fillColor: kCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: kPurple),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Username is required';
                  }
                  return null;
                },
                onChanged: _validateUsername,
              ),

              const SizedBox(height: 16),

              // ── Email Field ─────────────────────────────────────
              TextFormField(
                controller: _emailController,
                style: const TextStyle(color: kText),
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  labelStyle: const TextStyle(color: kMuted),
                  prefixIcon: const Icon(Icons.email, color: kMuted),
                  filled: true,
                  fillColor: kCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: kPurple),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Email is required';
                  }
                  if (!value.contains('@')) {
                    return 'Enter a valid email';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // ── Phone Field ─────────────────────────────────────
              TextFormField(
                controller: _phoneController,
                style: const TextStyle(color: kText),
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone Number (Optional)',
                  labelStyle: const TextStyle(color: kMuted),
                  prefixIcon: const Icon(Icons.phone, color: kMuted),
                  filled: true,
                  fillColor: kCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: kPurple),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Password Field ───────────────────────────────────
              TextFormField(
                controller: _passwordController,
                style: const TextStyle(color: kText),
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: const TextStyle(color: kMuted),
                  prefixIcon: const Icon(Icons.lock, color: kMuted),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: kMuted,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                  filled: true,
                  fillColor: kCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: kPurple),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Password is required';
                  }
                  if (value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // ── Confirm Password Field ───────────────────────────
              TextFormField(
                controller: _confirmPasswordController,
                style: const TextStyle(color: kText),
                obscureText: _obscureConfirmPassword,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  labelStyle: const TextStyle(color: kMuted),
                  prefixIcon: const Icon(Icons.lock_outline, color: kMuted),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: kMuted,
                    ),
                    onPressed: () {
                      setState(
                        () =>
                            _obscureConfirmPassword = !_obscureConfirmPassword,
                      );
                    },
                  ),
                  filled: true,
                  fillColor: kCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: kPurple),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please confirm your password';
                  }
                  if (value != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // ── Error Message ─────────────────────────────────────
              if (_generalError != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kRed.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: kRed, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _generalError!,
                          style: const TextStyle(color: kRed),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // ── Register Button ──────────────────────────────────
              ElevatedButton(
                onPressed: _isLoading ? null : _handleRegister,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Create Account',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),

              const SizedBox(height: 16),

              // ── Login Link ───────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Already have an account? ',
                    style: TextStyle(color: kMuted),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text(
                      'Login',
                      style: TextStyle(
                        color: kPurple,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
