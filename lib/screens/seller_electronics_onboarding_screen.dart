// ================================================================
// SellerElectronicsOnboardingScreen — MINIMAL, intentionally.
//
// Same reasoning as seller_grocery_onboarding_screen.dart: exists so
// the vertical picker has somewhere real to route an Electronics
// seller and businessVertical is written/routed correctly end-to-end.
// Does NOT invent what a real electronics seller's registration should
// collect (product categories? repair services vs retail? warranty
// terms?) — and notably, this app already has a customer-facing
// electronics REPAIR flow (NJ Tech Store -> electronics_service
// requests -> admin assigns to a Hero) built earlier. Whether an
// "Electronics Seller" account should plug into that same
// service_requests pipeline, or be a separate retail-product listing
// concept entirely, is a real product decision for Nizam — not
// something to guess here. For now: basic profile only.
// ================================================================
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/food_models.dart';
import '../services/food_seller_service.dart';
import 'seller_electronics_dashboard_screen.dart';

const Color _bg = Color(0xFF08080F);
const Color _card = Color(0xFF141420);
const Color _card2 = Color(0xFF1A1A28);
const Color _teal = Color(0xFF11998E);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);

class SellerElectronicsOnboardingScreen extends StatefulWidget {
  const SellerElectronicsOnboardingScreen({super.key});

  @override
  State<SellerElectronicsOnboardingScreen> createState() =>
      _SellerElectronicsOnboardingScreenState();
}

class _SellerElectronicsOnboardingScreenState
    extends State<SellerElectronicsOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  bool _isSaving = false;

  final FoodSellerService _service = FoodSellerService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) throw Exception('Not authenticated');

      final now = DateTime.now();
      final seller = SellerModel(
        id: uid,
        name: _nameController.text.trim(),
        category: 'electronics',
        subCategory: '',
        address: _addressController.text.trim(),
        latitude: 0.0,
        longitude: 0.0,
        phone: _phoneController.text.trim(),
        isOpen: false,
        status: 'active',
        createdAt: now,
        updatedAt: now,
        businessVertical: 'electronics',
      );

      await _service.createSellerProfile(seller);
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => const SellerElectronicsDashboardScreen(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _text),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Electronics Shop Registration',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w600),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _card2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Text(
                  'Full electronics seller tools are coming soon. For now '
                  'this saves your basic shop profile so you can be '
                  'reached — Nizam will finalize what electronics sellers '
                  'need next.',
                  style: GoogleFonts.outfit(color: _muted, fontSize: 12.5),
                ),
              ),
              const SizedBox(height: 20),
              _field(
                controller: _nameController,
                label: 'Shop Name',
                hint: 'e.g. NJ Tech Erode',
                icon: Icons.storefront_rounded,
                validatorMsg: 'Shop name is required',
              ),
              const SizedBox(height: 14),
              _field(
                controller: _phoneController,
                label: 'Phone Number',
                hint: 'Phone Number',
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
                validatorMsg: 'Phone is required',
              ),
              const SizedBox(height: 14),
              _field(
                controller: _addressController,
                label: 'Shop Address',
                hint: 'Shop Address',
                icon: Icons.location_on,
                maxLines: 2,
                validatorMsg: 'Address is required',
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _onSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Save & Continue',
                          style: GoogleFonts.outfit(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required String validatorMsg,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.outfit(
                  color: _text, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            style: GoogleFonts.outfit(color: _text, fontSize: 16),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.outfit(color: _muted, fontSize: 14),
              filled: true,
              fillColor: _card2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _teal, width: 1.5),
              ),
              prefixIcon: Icon(icon, color: _teal),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? validatorMsg : null,
          ),
        ],
      ),
    );
  }
}
