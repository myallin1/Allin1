import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/food_models.dart';
import '../services/food_seller_service.dart';
import 'seller_menu_setup_screen.dart';

const Color _bg = Color(0xFF08080F);
const Color _surface = Color(0xFF0D0D18);
const Color _card = Color(0xFF141420);
const Color _card2 = Color(0xFF1A1A28);
const Color _teal = Color(0xFF11998E);
const Color _tealLight = Color(0xFF38EF7D);
const Color _gold = Color(0xFFF5C542);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);

class SellerOnboardingScreen extends StatefulWidget {
  const SellerOnboardingScreen({super.key});

  @override
  State<SellerOnboardingScreen> createState() => _SellerOnboardingScreenState();
}

class _SellerOnboardingScreenState extends State<SellerOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  String _selectedHotelType = 'both';
  String _selectedSubCategory = 'biriyani';
  bool _isSaving = false;

  final FoodSellerService _service = FoodSellerService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const _hotelTypes = [
    ('both', 'Veg & Non-Veg', 'I serve everything', Icons.restaurant_menu),
    ('veg', 'Pure Veg', 'Only vegetarian', Icons.eco),
    ('non-veg', 'Non-Veg', 'Specialty non-veg', Icons.restaurant),
  ];

  static const _subCategories = [
    ('biriyani', 'Biriyani & Rice', '🍛'),
    ('parotta', 'Parotta & Breads', '🫓'),
    ('south_indian', 'South Indian Meals', '🥘'),
    ('fast_food', 'Fast Food & Snacks', '🍟'),
    ('multi_cuisine', 'Multi-Cuisine', '🍽️'),
  ];

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
        subCategory: _selectedSubCategory,
        hotelType: _selectedHotelType,
        address: _addressController.text.trim(),
        latitude: 0,
        longitude: 0,
        phone: _phoneController.text.trim(),
        isOpen: false,
        createdAt: now,
        updatedAt: now,
      );

      await _service.createSellerProfile(seller);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => SellerMenuSetupScreen(sellerId: uid),
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
        backgroundColor: _surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _text),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Hotel Registration',
          style: GoogleFonts.outfit(
            color: _text,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 28),
              _buildHotelNameField(),
              const SizedBox(height: 20),
              _buildHotelTypeSelector(),
              const SizedBox(height: 20),
              _buildCategorySelector(),
              const SizedBox(height: 20),
              _buildContactFields(),
              const SizedBox(height: 32),
              _buildSubmitButton(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_teal, Color(0xFF0D7A6E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Welcome to Allin1 Partner!',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Set up your hotel in 2 minutes. After registration, '
            'you can quickly enable your menu items from our predefined catalog.',
            style: GoogleFonts.outfit(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHotelNameField() {
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
          Text(
            'Hotel / Restaurant Name',
            style: GoogleFonts.outfit(
              color: _text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _nameController,
            style: GoogleFonts.outfit(color: _text, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'e.g. Hyderabadi Biriyani House',
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
              prefixIcon: const Icon(Icons.store, color: _teal),
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Hotel name is required'
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildHotelTypeSelector() {
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
          Text(
            'Hotel Type',
            style: GoogleFonts.outfit(
              color: _text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ..._hotelTypes.map(
            (type) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TypeTile(
                label: type.$1,
                title: type.$2,
                subtitle: type.$3,
                icon: type.$4,
                isSelected: _selectedHotelType == type.$1,
                onTap: () => setState(() => _selectedHotelType = type.$1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySelector() {
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
          Text(
            'Food Category',
            style: GoogleFonts.outfit(
              color: _text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'What type of food do you specialize in?',
            style: GoogleFonts.outfit(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _subCategories.map(
              (cat) {
                final isSelected = _selectedSubCategory == cat.$1;
                return GestureDetector(
                  onTap: () => setState(() => _selectedSubCategory = cat.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? _teal : _card2,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? _tealLight : _border,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(cat.$3, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Text(
                          cat.$2,
                          style: GoogleFonts.outfit(
                            color: isSelected ? Colors.white : _muted,
                            fontSize: 13,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildContactFields() {
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
          Text(
            'Contact & Address',
            style: GoogleFonts.outfit(
              color: _text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneController,
            style: GoogleFonts.outfit(color: _text, fontSize: 16),
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              hintText: 'Phone Number',
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
              prefixIcon: const Icon(Icons.phone, color: _teal),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Phone is required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _addressController,
            style: GoogleFonts.outfit(color: _text, fontSize: 16),
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Hotel Address',
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
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 30),
                child: Icon(Icons.location_on, color: _teal),
              ),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Address is required' : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _onSubmit,
        style: ElevatedButton.styleFrom(
          backgroundColor: _teal,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _teal.withValues(alpha: 0.4),
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
                'Save & Continue → Set Up Menu',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

class _TypeTile extends StatelessWidget {
  final String label;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeTile({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? _teal.withValues(alpha: 0.15) : _card2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _teal : _border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? _teal : _card,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : _muted,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      color: isSelected ? _tealLight : _text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? _teal : Colors.transparent,
                border: Border.all(
                  color: isSelected ? _teal : _muted,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('label', label));
    properties.add(StringProperty('title', title));
    properties.add(StringProperty('subtitle', subtitle));
    properties.add(DiagnosticsProperty<IconData>('icon', icon));
    properties.add(DiagnosticsProperty<bool>('isSelected', isSelected));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}
