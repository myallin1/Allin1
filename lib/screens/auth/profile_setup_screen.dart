import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../screens/bike_taxi/hero_dashboard_shell.dart';
import '../../screens/dashboard_screen.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    super.key,
    this.preferredRole = UserType.customer,
  });

  final UserType preferredRole;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<UserType>('preferredRole', preferredRole));
  }
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _selectedVehicleType = 'bike';
  bool _agreedEmergencyResponder = false;
  bool _saving = false;

  bool get _isHeroSetup => widget.preferredRole == UserType.hero;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _completeSetup() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_isHeroSetup && !_agreedEmergencyResponder) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please accept the SOS Network first responder agreement',
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    setState(() => _saving = true);
    final authService = AuthService();
    final phone = _phoneController.text.trim();
    final selectedRole = widget.preferredRole;

    try {
      await authService.completeProfileSetup(
        uid: user.uid,
        phoneNumber: phone,
        userType: selectedRole,
        vehicleType:
            selectedRole == UserType.hero ? _selectedVehicleType : null,
      );

      await SessionService().saveSession(
        userType: selectedRole,
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName,
        phoneNumber: phone,
        rememberMe: true,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => _isHeroSetup
              ? const HeroDashboardShell()
              : const DashboardScreen(),
        ),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Setup failed: $error'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.primaryColor;
    final onSurface = theme.colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.62);
    final softFill = primary.withValues(alpha: 0.08);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.18),
                      blurRadius: 30,
                      spreadRadius: 1,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [primary, primary.withValues(alpha: 0.7)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const Icon(
                          Icons.person_add_alt_1_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Complete Your Profile',
                        style: GoogleFonts.outfit(
                          color: onSurface,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isHeroSetup
                            ? 'We need your contact number and vehicle details before you can continue inside the Hero app.'
                            : 'We need your contact number before you can continue inside Allin1.',
                        style: GoogleFonts.outfit(
                          color: muted,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Phone Number',
                        style: GoogleFonts.outfit(
                          color: onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.number,
                        maxLength: 10,
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'Enter 10-digit mobile number',
                          hintStyle: GoogleFonts.outfit(color: muted),
                          prefixIcon: Icon(
                            Icons.phone_iphone_rounded,
                            color: primary,
                          ),
                          filled: true,
                          fillColor: softFill,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(color: primary, width: 1.5),
                          ),
                        ),
                        validator: (value) {
                          final input = value?.trim() ?? '';
                          if (input.length != 10) {
                            return 'Enter a valid 10-digit number';
                          }
                          if (!RegExp(r'^[0-9]{10}$').hasMatch(input)) {
                            return 'Numbers only';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),
                      if (_isHeroSetup) ...[
                        Text(
                          'Vehicle Category',
                          style: GoogleFonts.outfit(
                            color: onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedVehicleType,
                          items: const [
                            DropdownMenuItem(
                              value: 'bike',
                              child: Text('Bike Taxi'),
                            ),
                            DropdownMenuItem(
                              value: 'auto',
                              child: Text('Auto Rickshaw'),
                            ),
                            DropdownMenuItem(
                              value: 'car',
                              child: Text('Cab / Mini'),
                            ),
                            DropdownMenuItem(
                              value: 'emergency_manpower',
                              child: Text('Only Emergency Manpower'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() => _selectedVehicleType = value);
                          },
                          decoration: InputDecoration(
                            prefixIcon: Icon(
                              Icons.two_wheeler_rounded,
                              color: primary,
                            ),
                            filled: true,
                            fillColor: softFill,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide:
                                  BorderSide(color: primary, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        InkWell(
                          onTap: () {
                            setState(() {
                              _agreedEmergencyResponder =
                                  !_agreedEmergencyResponder;
                            });
                          },
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: softFill,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: _agreedEmergencyResponder
                                    ? primary
                                    : primary.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Checkbox(
                                  value: _agreedEmergencyResponder,
                                  activeColor: primary,
                                  onChanged: (value) {
                                    setState(() {
                                      _agreedEmergencyResponder =
                                          value ?? false;
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'I agree to act as an Emergency First Responder (SOS Network) in my area.',
                                    style: GoogleFonts.outfit(
                                      color: onSurface,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: softFill,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: primary.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.verified_user_rounded, color: primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _isHeroSetup
                                    ? 'Hero account setup'
                                    : 'Customer account setup',
                                style: GoogleFonts.outfit(
                                  color: onSurface,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _completeSetup,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Complete Setup',
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
