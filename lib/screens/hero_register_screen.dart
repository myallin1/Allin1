// ================================================================
// Hero Register Screen
// Allin1 Super App - Hero Onboarding
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

// ROUTING FIX: import added — was missing, causing "undefined class" compile error
import 'hero_verification_pending.dart';

const Color _bg = Color(0xFF0A0A12);
const Color _card = Color(0xFF1A1A2A);
const Color _green = Color(0xFF00C853);
const Color _gold = Color(0xFFFFBB00);
const Color _njPink = Color(0xFFFF4FA3); // NJ TECH brand pink
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _red = Color(0xFFFF5252);

class _HeroCategory {
  const _HeroCategory({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.dbLabel,
  });

  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final String dbLabel;
}

const List<_HeroCategory> _heroCategories = <_HeroCategory>[
  _HeroCategory(
    key: 'bike',
    title: 'Bike Taxi',
    subtitle: 'Fast two-wheeler rides',
    icon: Icons.two_wheeler_rounded,
    dbLabel: 'Bike Taxi',
  ),
  _HeroCategory(
    key: 'auto',
    title: 'Auto Rickshaw',
    subtitle: 'City auto service',
    icon: Icons.electric_rickshaw_rounded,
    dbLabel: 'Auto Rickshaw',
  ),
  _HeroCategory(
    key: 'car',
    title: 'Cab / Mini',
    subtitle: 'Cab and mini vehicle',
    icon: Icons.local_taxi_rounded,
    dbLabel: 'Cab / Mini',
  ),
  _HeroCategory(
    key: 'parcel',
    title: 'Parcel Delivery',
    subtitle: 'Goods and package delivery',
    icon: Icons.local_shipping_rounded,
    dbLabel: 'Parcel Delivery',
  ),
  _HeroCategory(
    key: 'emergency_manpower',
    title: 'Only Emergency Manpower',
    subtitle: 'SOS responder only',
    icon: Icons.health_and_safety_rounded,
    dbLabel: 'Only Emergency Manpower',
  ),
];

class HeroRegisterScreen extends StatefulWidget {
  const HeroRegisterScreen({super.key});

  @override
  State<HeroRegisterScreen> createState() => _HeroRegisterScreenState();
}

class _HeroRegisterScreenState extends State<HeroRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController(); // T1: D.O.B
  final _addressController = TextEditingController(); // T1: Address
  final _licenseNumberController = TextEditingController();
  final _aadhaarController = TextEditingController(); // T1: Aadhaar No
  final _panController = TextEditingController(); // T1: PAN No
  String? _selectedVehicleType;
  bool _agreedEmergencyResponder = false;

  // T2: CEO WhatsApp placeholder — replace 91XXXXXXXXXX with real number
  static const String _adminWhatsApp = '91XXXXXXXXXX';
  static const String _adminPhone = '+91XXXXXXXXXX';

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _addressController.dispose();
    _licenseNumberController.dispose();
    _aadhaarController.dispose();
    _panController.dispose();
    super.dispose();
  }

  String _normalizeVehicleType(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.contains('auto')) return 'auto';
    if (normalized.contains('emergency') || normalized.contains('manpower')) {
      return 'emergency_manpower';
    }
    if (normalized.contains('car') ||
        normalized.contains('cab') ||
        normalized.contains('truck')) {
      return 'car';
    }
    return 'bike';
  }

  String _vehicleCategoryLabel(String key) {
    return _heroCategories
        .firstWhere(
          (category) => category.key == key,
          orElse: () => _heroCategories.first,
        )
        .dbLabel;
  }

  Future<void> _launchWhatsApp() async {
    // T2: CEO-specified message — number is a placeholder, replace before release
    final message = Uri.encodeComponent(
      'Hi NJ TECH, I have submitted my Hero Registration. Here are my documents.',
    );
    final url = Uri.parse('https://wa.me/$_adminWhatsApp?text=$message');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open WhatsApp')),
      );
    }
  }

  Future<void> _launchCall() async {
    final url = Uri.parse('tel:$_adminPhone');

    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open phone dialer'),
        ),
      );
    }
  }

  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final selectedVehicleType = _selectedVehicleType;
    if (selectedVehicleType == null || selectedVehicleType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your Hero category'),
          backgroundColor: _red,
        ),
      );
      return;
    }
    if (!_agreedEmergencyResponder) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please accept the SOS Network first responder agreement',
          ),
          backgroundColor: _red,
        ),
      );
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }
      final vehicleType = _normalizeVehicleType(selectedVehicleType);
      final vehicleCategoryLabel = _vehicleCategoryLabel(vehicleType);

      // Save to heroes collection
      await FirebaseFirestore.instance.collection('heroes').doc(user.uid).set({
        'heroId': user.uid,
        'uid': user.uid,
        'name': _nameController.text.trim(),
        'phone': user.phoneNumber ?? _phoneController.text.trim(),
        'email': user.email ?? '',
        // T1: New fields per CEO directive
        'dob': _dobController.text.trim(),
        'address': _addressController.text.trim(),
        'aadhaarNumber': _aadhaarController.text.trim(),
        'panNumber': _panController.text.trim(),
        'vehicleType': vehicleType,
        'heroCategory': vehicleType,
        'vehicleCategoryLabel': vehicleCategoryLabel,
        'isEmergencyHelper': true,
        'sosNetworkAcceptedAt': FieldValue.serverTimestamp(),
        'licenseNumber': _licenseNumberController.text.trim(),
        // T1: No document URLs — hero sends physical docs via WhatsApp
        'approvalStatus': 'pending',
        'status': 'offline',
        'onboardingMethod': 'manual_whatsapp',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Registration submitted! Awaiting admin approval.',
            ),
            backgroundColor: _gold,
          ),
        );

        // ROUTING FIX: Do NOT sign the user out.
        // Navigate directly to the verification pending screen so the
        // hero can see their status and contact admin immediately.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (_) => HeroVerificationPendingScreen(heroId: user.uid),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      // Task 4: Typed Firebase Auth error — prints exact code to console
      debugPrint(
        '[HeroRegister] FirebaseAuthException: ${e.code} — ${e.message}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Auth error (${e.code}): ${e.message ?? e.toString()}',
            ),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on FirebaseException catch (e) {
      // Task 4: Typed Firestore / Database error — prints plugin + code
      debugPrint(
        '[HeroRegister] FirebaseException [${e.plugin}]: ${e.code} — ${e.message}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Database error (${e.code}): ${e.message ?? e.toString()}',
            ),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, st) {
      // Task 4: Unexpected error — full stack trace to console for debugging
      debugPrint('[HeroRegister] Unexpected error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registration failed: ${e.toString()}'),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildHeroCategorySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hero Category',
          style: GoogleFonts.outfit(
            color: _text,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 430;
            final cardWidth = isCompact
                ? constraints.maxWidth
                : (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 10,
              children: _heroCategories.map((category) {
                final selected = _selectedVehicleType == category.key;
                return SizedBox(
                  width: cardWidth,
                  child: _HeroCategoryCard(
                    category: category,
                    selected: selected,
                    onTap: () {
                      setState(() {
                        _selectedVehicleType = category.key;
                      });
                    },
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Hero Registration',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(
                'Fill in all details accurately. Documents are verified via WhatsApp.',
                style: GoogleFonts.outfit(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 20),

              // ── Personal Information ──────────────────────────
              _sectionLabel('👤  Personal Information'),
              const SizedBox(height: 12),
              _field(
                controller: _nameController,
                label: 'Full Name',
                icon: Icons.person_rounded,
                validator: (v) => v!.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              _field(
                controller: _phoneController,
                label: 'Contact Number',
                icon: Icons.phone_rounded,
                keyboardType: TextInputType.phone,
                validator: (v) => v!.trim().length < 10
                    ? 'Enter a valid 10-digit number'
                    : null,
              ),
              const SizedBox(height: 12),
              // T1: Date of Birth — text entry (dd/mm/yyyy)
              _field(
                controller: _dobController,
                label: 'Date of Birth (dd/mm/yyyy)',
                icon: Icons.cake_rounded,
                keyboardType: TextInputType.datetime,
                validator: (v) =>
                    v!.trim().isEmpty ? 'Date of birth is required' : null,
              ),
              const SizedBox(height: 12),
              _field(
                controller: _addressController,
                label: 'Full Address',
                icon: Icons.home_rounded,
                maxLines: 2,
                validator: (v) =>
                    v!.trim().isEmpty ? 'Address is required' : null,
              ),
              const SizedBox(height: 20),

              // ── Document Numbers ──────────────────────────────
              _sectionLabel('📄  Document Numbers'),
              const SizedBox(height: 12),
              _field(
                controller: _licenseNumberController,
                label: 'Driving License Number',
                icon: Icons.drive_eta_rounded,
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    v!.trim().isEmpty ? 'License number is required' : null,
              ),
              const SizedBox(height: 12),
              _field(
                controller: _aadhaarController,
                label: 'Aadhaar Number',
                icon: Icons.fingerprint_rounded,
                keyboardType: TextInputType.number,
                validator: (v) => v!.trim().length != 12
                    ? 'Enter valid 12-digit Aadhaar'
                    : null,
              ),
              const SizedBox(height: 12),
              _field(
                controller: _panController,
                label: 'PAN Number',
                icon: Icons.credit_card_rounded,
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    v!.trim().length < 10 ? 'Enter valid PAN number' : null,
              ),
              const SizedBox(height: 20),

              // ── Vehicle Category ──────────────────────────────
              _sectionLabel('🚗  Vehicle Category'),
              const SizedBox(height: 12),
              _buildHeroCategorySelector(),
              const SizedBox(height: 16),
              _buildEmergencyResponderAgreement(),
              const SizedBox(height: 24),

              // ── T2: Step 2 WhatsApp Card ──────────────────────
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1B2E1B), Color(0xFF122012)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFF25D366).withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF25D366).withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF25D366).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            '💬',
                            style: TextStyle(fontSize: 20),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Step 2: Document Verification',
                            style: GoogleFonts.outfit(
                              color: const Color(0xFF25D366),
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Send photos of your Driving License, PAN Card, and Aadhaar Card to our official WhatsApp for profile activation.',
                      style: GoogleFonts.outfit(
                        color: _text,
                        fontSize: 13,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _launchWhatsApp,
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: Text(
                          'Send Documents via WhatsApp',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _launchCall,
                        icon: const Icon(Icons.call_rounded, size: 16),
                        label: Text(
                          'Call Admin for Quick Verification',
                          style:
                              GoogleFonts.outfit(fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          // T3: was Colors.blue — now NJ Pink
                          foregroundColor: _njPink,
                          side: BorderSide(
                            color: _njPink.withValues(alpha: 0.5),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ── Submit ────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitRegistration,
                  style: ElevatedButton.styleFrom(
                    // T3: was _green — now NJ Pink per brand fix
                    backgroundColor: _njPink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 6,
                    shadowColor: _njPink.withValues(alpha: 0.4),
                  ),
                  child: Text(
                    'Submit Registration →',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Your form will be reviewed. Approval typically takes 2–4 hours.',
                  style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  // ── Reusable helpers ─────────────────────────────────────────
  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(
          text,
          style: GoogleFonts.outfit(
            color: _text,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.words,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      maxLines: maxLines,
      style: GoogleFonts.outfit(color: _text, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.outfit(color: _muted, fontSize: 13),
        prefixIcon: Icon(icon, color: _muted, size: 20),
        filled: true,
        fillColor: _card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _njPink, width: 1.5),
        ),
        errorStyle: const TextStyle(color: _red, fontSize: 11),
      ),
      validator: validator,
    );
  }

  Widget _buildEmergencyResponderAgreement() {
    return InkWell(
      onTap: () {
        setState(() {
          _agreedEmergencyResponder = !_agreedEmergencyResponder;
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _agreedEmergencyResponder
              ? _green.withValues(alpha: 0.16)
              : _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _agreedEmergencyResponder
                ? _green
                : Colors.white.withValues(alpha: 0.1),
            width: _agreedEmergencyResponder ? 1.6 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _agreedEmergencyResponder,
              activeColor: _green,
              checkColor: Colors.white,
              side: const BorderSide(color: _muted),
              onChanged: (value) {
                setState(() {
                  _agreedEmergencyResponder = value ?? false;
                });
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'I agree to act as an Emergency First Responder (SOS Network) in my area.',
                style: GoogleFonts.outfit(
                  color: _text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroCategoryCard extends StatelessWidget {
  const _HeroCategoryCard({
    required _HeroCategory category,
    required bool selected,
    required VoidCallback onTap,
  })  : _category = category,
        _selected = selected,
        _onTap = onTap;

  final _HeroCategory _category;
  final bool _selected;
  final VoidCallback _onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: _selected
                // T3: was [_gold, Color(0xFFFF6B35)] — orange eradicated
                ? const [Color(0xFFFF4FA3), Color(0xFFBE2A7A)]
                : const [Color(0xFF24243A), Color(0xFF151524)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: _selected ? _njPink : Colors.white.withValues(alpha: 0.08),
            width: _selected ? 1.6 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color:
                  (_selected ? _njPink : Colors.black).withValues(alpha: 0.28),
              blurRadius: _selected ? 22 : 12,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: _selected ? 0.22 : 0.08),
              ),
              child: Icon(
                _category.icon,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _category.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _category.subtitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
