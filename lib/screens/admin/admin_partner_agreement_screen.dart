// ================================================================
// AdminPartnerAgreementScreen — Admin Panel
// Digital Partner Agreement & Shop Onboarding for Allin1 Super App
// Allows Admin to onboard local external partners (e.g. Signature Mobiles,
// local organic stores, pharmacies, wholesale shops) with agreed
// commission terms, delivery radius, and category mapping.
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/city_config.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _purple = Color(0xFF7C4DFF);
const Color _teal = Color(0xFF11998E);
const Color _gold = Color(0xFFFFBB00);
const Color _green = Color(0xFF00C853);
const Color _red = Color(0xFFFF5252);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x1AFFFFFF);

class AdminPartnerAgreementScreen extends StatefulWidget {
  const AdminPartnerAgreementScreen({super.key});

  @override
  State<AdminPartnerAgreementScreen> createState() =>
      _AdminPartnerAgreementScreenState();
}

class _AdminPartnerAgreementScreenState
    extends State<AdminPartnerAgreementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();

  // Form Controllers
  final _shopNameCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _logoUrlCtrl = TextEditingController();
  final _customCommissionCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // Active Partners Tab Filter Controllers
  final _searchCtrl = TextEditingController();
  String _activeTabCityFilter = 'all';

  // Selections
  String _selectedCity = kDefaultCity;
  String _selectedCategory = 'mobiles';
  double _selectedCommission = 2; // 2% Standard
  double _selectedRadiusKm = 10;
  bool _agreementAccepted = false;
  bool _isSubmitting = false;

  final List<Map<String, String>> _categories = [
    {
      'slug': 'mobiles',
      'label': '📱 Mobile Phones & Accessories',
      'vertical': 'electronics',
    },
    {
      'slug': 'spares',
      'label': '🔧 Mobile & Laptop Spares',
      'vertical': 'electronics',
    },
    {
      'slug': 'grocery',
      'label': '🛒 Organic & Supermarket',
      'vertical': 'grocery',
    },
    {
      'slug': 'food',
      'label': '🍲 Restaurant & Bakery',
      'vertical': 'hotel',
    },
    {
      'slug': 'electronics',
      'label': '💻 Gadgets & Consumer Electronics',
      'vertical': 'electronics',
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _shopNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _logoUrlCtrl.dispose();
    _customCommissionCtrl.dispose();
    _notesCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _getVerticalForCategory(String cat) {
    for (final c in _categories) {
      if (c['slug'] == cat) return c['vertical']!;
    }
    return 'electronics';
  }

  Future<void> _callPartner(String phone) async {
    final digits = phone.replaceAll(RegExp('[^0-9+]'), '');
    if (digits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number available to call'), backgroundColor: _red),
      );
      return;
    }
    final url = Uri.parse('tel:$digits');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open phone dialer'), backgroundColor: _red),
      );
    }
  }

  Future<void> _toggleShopOpen(String docId, bool currentOpen) async {
    try {
      await FirebaseFirestore.instance.collection('sellers').doc(docId).update({
        'isOpen': !currentOpen,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(currentOpen ? 'Shop paused (Offline)' : 'Shop activated (Online)'),
          backgroundColor: currentOpen ? _red : _green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e'), backgroundColor: _red),
      );
    }
  }

  Future<void> _submitPartner() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreementAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please confirm the Partner Agreement acceptance toggle.'),
          backgroundColor: _red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final adminUid = FirebaseAuth.instance.currentUser?.uid ?? 'admin';
      final docRef = firestore.collection('sellers').doc();
      final now = DateTime.now();

      final double commission = _selectedCommission == -1
          ? (double.tryParse(_customCommissionCtrl.text.trim()) ?? 2)
          : _selectedCommission;

      final shopName = _shopNameCtrl.text.trim();
      final ownerName = _ownerNameCtrl.text.trim();
      final phone = _phoneCtrl.text.trim();
      final address = _addressCtrl.text.trim();
      final logoUrl = _logoUrlCtrl.text.trim();
      final notes = _notesCtrl.text.trim();
      final vertical = _getVerticalForCategory(_selectedCategory);

      // Coordinate lookup based on selected city (prevents non-Erode cities from having Erode GPS)
      final (cityLat, cityLng) = cityCenterCoordinates(_selectedCity);

      // Create new Seller Document for this partner
      await docRef.set({
        'id': docRef.id,
        'name': shopName,
        'shopName': shopName,
        'ownerName': ownerName,
        'phone': phone,
        'address': address,
        'city': _selectedCity,
        'category': _selectedCategory,
        'subCategory': _selectedCategory,
        'businessVertical': vertical,
        'partnerType': 'external',
        'commissionPct': commission,
        'deliveryRadiusKm': _selectedRadiusKm,
        'partnerAgreementAcceptedAt': now.toIso8601String(),
        'agreementNotes': notes,
        'status': 'active', // Admin created = pre-approved & active
        'rating': 5.0,
        'isOpen': true,
        'hotelType': 'both',
        'latitude': cityLat,
        'longitude': cityLng,
        'imageUrl': logoUrl.isNotEmpty ? logoUrl : null,
        'shopLogoUrl': logoUrl.isNotEmpty ? logoUrl : null,
        'role': 'owner',
        'pendingPayouts': 0.0,
        'totalSettled': 0.0,
        'walletBalance': 0.0,
        'totalFeesDeducted': 0.0,
        'onboardedBy': adminUid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Record in partner_agreements audit log
      await firestore.collection('partner_agreements').doc(docRef.id).set({
        'sellerId': docRef.id,
        'shopName': shopName,
        'ownerName': ownerName,
        'phone': phone,
        'city': _selectedCity,
        'category': _selectedCategory,
        'commissionPct': commission,
        'deliveryRadiusKm': _selectedRadiusKm,
        'acceptedAt': now.toIso8601String(),
        'adminUid': adminUid,
        'termsVersion': 'v1.0_2026',
        'notes': notes,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 Partner "$shopName" onboarded successfully!'),
          backgroundColor: _green,
          action: SnackBarAction(
            label: 'Copy ID',
            textColor: Colors.white,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: docRef.id));
            },
          ),
        ),
      );

      // Reset form
      _shopNameCtrl.clear();
      _ownerNameCtrl.clear();
      _phoneCtrl.clear();
      _addressCtrl.clear();
      _logoUrlCtrl.clear();
      _customCommissionCtrl.clear();
      _notesCtrl.clear();
      setState(() {
        _agreementAccepted = false;
        _selectedCommission = 2;
        _tabController.index = 1; // Switch to Active Partners tab
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error onboarding partner: $e'),
          backgroundColor: _red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showPartnerDetailDialog(Map<String, dynamic> data, String id) {
    final name = data['name']?.toString() ?? 'Shop';
    final owner = data['ownerName']?.toString() ?? 'N/A';
    final phone = data['phone']?.toString() ?? 'N/A';
    final address = data['address']?.toString() ?? 'N/A';
    final city = cityLabelFor(data['city']?.toString() ?? kDefaultCity);
    final category = data['category']?.toString() ?? 'General';
    final commission = (data['commissionPct'] as num?)?.toDouble() ?? 0.0;
    final radius = (data['deliveryRadiusKm'] as num?)?.toDouble() ?? 10.0;
    final acceptedAt = data['partnerAgreementAcceptedAt']?.toString() ?? 'N/A';
    final notes = data['agreementNotes']?.toString() ?? '';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _teal.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.storefront_rounded, color: _teal, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 17),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dialogRow('Owner/Contact', owner),
              _dialogRow('Phone', phone),
              _dialogRow('City', city),
              _dialogRow('Address', address),
              _dialogRow('Category', category),
              _dialogRow('Commission Tier', '${commission.toStringAsFixed(1)}%'),
              _dialogRow('Delivery Radius', '${radius.toStringAsFixed(0)} km'),
              _dialogRow('Agreement Date', acceptedAt.contains('T') ? acceptedAt.split('T').first : acceptedAt),
              if (notes.isNotEmpty) _dialogRow('Notes', notes),
              const Divider(color: _border, height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Partner ID: $id',
                      style: const TextStyle(fontSize: 10, color: _muted, fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16, color: _teal),
                    tooltip: 'Copy ID',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: id));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied Partner ID'), duration: Duration(seconds: 2)),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          if (phone != 'N/A' && phone.isNotEmpty)
            TextButton.icon(
              onPressed: () => _callPartner(phone),
              icon: const Icon(Icons.phone, size: 16, color: _green),
              label: const Text('Call Shop', style: TextStyle(color: _green)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: _muted)),
          ),
        ],
      ),
    );
  }

  Widget _dialogRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: _text, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
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
          '🤝 Partner Shop Onboarding',
          style: GoogleFonts.outfit(
            color: _text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _teal,
          labelColor: _teal,
          unselectedLabelColor: _muted,
          tabs: const [
            Tab(icon: Icon(Icons.person_add_alt_1_rounded), text: 'New Agreement'),
            Tab(icon: Icon(Icons.store_rounded), text: 'Active Partners'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAgreementFormTab(),
          _buildActivePartnersTab(),
        ],
      ),
    );
  }

  Widget _buildAgreementFormTab() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('🏪 Shop Information', 'Enter verified business details'),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _shopNameCtrl,
            label: 'Shop Name *',
            hint: 'e.g. Signature Mobiles & Spares',
            icon: Icons.storefront_rounded,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Shop name is required' : null,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _ownerNameCtrl,
            label: 'Owner / Manager Name *',
            hint: 'e.g. Senthil Kumar',
            icon: Icons.person_outline_rounded,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Owner name is required'
                : null,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _phoneCtrl,
            label: 'Phone / WhatsApp *',
            hint: '10-digit mobile number',
            icon: Icons.phone_rounded,
            keyboardType: TextInputType.phone,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Phone is required';
              if (v.trim().length < 10) return 'Enter a valid 10-digit number';
              return null;
            },
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _addressCtrl,
            label: 'Shop Full Address *',
            hint: 'e.g. 42 Brough Road, Erode',
            icon: Icons.location_on_outlined,
            maxLines: 2,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Address is required' : null,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  label: 'City',
                  value: _selectedCity,
                  items: kSupportedCities.map((c) {
                    return DropdownMenuItem(
                      value: c.slug,
                      child: Text(c.label, style: const TextStyle(color: _text)),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedCity = v);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdown(
                  label: 'Category',
                  value: _selectedCategory,
                  items: _categories.map((c) {
                    return DropdownMenuItem(
                      value: c['slug'],
                      child: Text(
                        c['label']!,
                        style: const TextStyle(color: _text, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedCategory = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('💼 Commercial Terms & Commission', 'Agreed commission tier & radius'),
          const SizedBox(height: 12),
          _buildCommissionSelector(),
          const SizedBox(height: 16),
          _buildRadiusSelector(),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _logoUrlCtrl,
            label: 'Shop Logo / Photo URL (Optional)',
            hint: 'https://res.cloudinary.com/... or image link',
            icon: Icons.image_outlined,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _notesCtrl,
            label: 'Special Agreement Notes (Optional)',
            hint: 'e.g. Free 30-day trial, 5% on accessories only, etc.',
            icon: Icons.note_alt_outlined,
            maxLines: 2,
          ),
          const SizedBox(height: 24),
          _buildAgreementTermsCard(),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submitPartner,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_rounded, color: Colors.white),
              label: Text(
                _isSubmitting
                    ? 'Creating Partner Account...'
                    : '🤝 Complete Agreement & Onboard Shop',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                disabledBackgroundColor: _teal.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.outfit(
            color: _text,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(
            color: _muted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: _text, fontSize: 14),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _muted, fontSize: 13),
        hintText: hint,
        hintStyle: TextStyle(color: _text.withValues(alpha: 0.3), fontSize: 13),
        prefixIcon: Icon(icon, color: _teal, size: 20),
        filled: true,
        fillColor: _card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _teal, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: _card,
              icon: const Icon(Icons.arrow_drop_down, color: _teal),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCommissionSelector() {
    final tiers = [
      {'val': 0.0, 'label': '0% Free\n(Intro)'},
      {'val': 2.0, 'label': '2% Standard\n(Normal)'},
      {'val': 5.0, 'label': '5% Premium\n(Featured)'},
      {'val': -1.0, 'label': 'Custom\n%'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Commission Tier',
          style: TextStyle(color: _muted, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: tiers.map((t) {
            final double val = t['val']! as double;
            final isSelected = _selectedCommission == val;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedCommission = val),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? _teal.withValues(alpha: 0.2) : _card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? _teal : _border,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    t['label']! as String,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isSelected ? _teal : _text,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        if (_selectedCommission == -1) ...[
          const SizedBox(height: 12),
          _buildTextField(
            controller: _customCommissionCtrl,
            label: 'Custom Commission Percentage (%) *',
            hint: 'e.g. 1.5, 3.0, 7.5',
            icon: Icons.percent_rounded,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) {
              if (_selectedCommission == -1) {
                if (v == null || v.trim().isEmpty) return 'Please enter custom %';
                final n = double.tryParse(v.trim());
                if (n == null || n < 0 || n > 100) return 'Enter a valid rate (0-100)';
              }
              return null;
            },
          ),
        ],
      ],
    );
  }

  Widget _buildRadiusSelector() {
    final radii = [5.0, 10.0, 15.0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Delivery Radius',
          style: TextStyle(color: _muted, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: radii.map((r) {
            final isSelected = _selectedRadiusKm == r;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedRadiusKm = r),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? _purple.withValues(alpha: 0.2) : _card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? _purple : _border,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '${r.toInt()} km',
                      style: TextStyle(
                        color: isSelected ? _purple : _text,
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAgreementTermsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gavel_rounded, color: _gold, size: 20),
              const SizedBox(width: 8),
              Text(
                'Digital Agreement v1.0',
                style: GoogleFonts.outfit(
                  color: _gold,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '1. Allin1 acts as delivery and technology marketplace partner.\n'
            '2. Customer orders are picked up by verified Allin1 Heroes.\n'
            '3. Partner agrees to supply genuine products at agreed listed price.\n'
            '4. Platform commission deducted automatically on successful delivery.\n'
            '5. Settlement cycles processed weekly or on request.',
            style: TextStyle(
              color: _text,
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
          const Divider(color: _border, height: 20),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Partner Agreement Confirmed',
              style: TextStyle(
                color: _text,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: const Text(
              'Admin verified verbal or WhatsApp acceptance',
              style: TextStyle(color: _muted, fontSize: 11),
            ),
            value: _agreementAccepted,
            activeTrackColor: _teal,
            onChanged: (v) => setState(() => _agreementAccepted = v),
          ),
        ],
      ),
    );
  }

  Widget _buildActivePartnersTab() {
    return Column(
      children: [
        // Search & City Filter Strip
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          color: _surface,
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: _text, fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'Search shop name or phone…',
                  hintStyle: const TextStyle(color: _muted, fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, color: _teal, size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: _muted, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: _card,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _border),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildCityFilterChip('all', 'All Cities'),
                    ...kSupportedCities.map((c) => _buildCityFilterChip(c.slug, c.label)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('sellers')
                .where('partnerType', isEqualTo: 'external')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: _teal),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Error loading partners: ${snapshot.error}',
                    style: const TextStyle(color: _red),
                  ),
                );
              }

              final allDocs = snapshot.data?.docs ?? [];
              if (allDocs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.storefront_outlined, size: 54, color: _muted.withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      const Text(
                        'No External Partners Onboarded Yet',
                        style: TextStyle(color: _text, fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Switch to "New Agreement" tab to onboard your first shop.',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                );
              }

              // Sort client-side by createdAt descending
              final sortedDocs = allDocs.toList()
                ..sort((a, b) {
                  final aData = a.data()! as Map<String, dynamic>;
                  final bData = b.data()! as Map<String, dynamic>;
                  final aTs = aData['createdAt'] as Timestamp?;
                  final bTs = bData['createdAt'] as Timestamp?;
                  final aMs = aTs?.millisecondsSinceEpoch ?? 0;
                  final bMs = bTs?.millisecondsSinceEpoch ?? 0;
                  return bMs.compareTo(aMs);
                });

              // Apply search & city filters
              final query = _searchCtrl.text.trim().toLowerCase();
              final filteredDocs = sortedDocs.where((doc) {
                final data = doc.data()! as Map<String, dynamic>;
                final name = (data['name']?.toString() ?? '').toLowerCase();
                final phone = (data['phone']?.toString() ?? '').toLowerCase();
                final city = (data['city']?.toString() ?? kDefaultCity).toLowerCase();

                final matchesCity = _activeTabCityFilter == 'all' || city == _activeTabCityFilter;
                final matchesSearch = query.isEmpty || name.contains(query) || phone.contains(query);
                return matchesCity && matchesSearch;
              }).toList();

              if (filteredDocs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No partner shops match your filter.',
                      style: TextStyle(color: _muted, fontSize: 13),
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filteredDocs.length,
                itemBuilder: (context, index) {
                  final data = filteredDocs[index].data()! as Map<String, dynamic>;
                  final id = filteredDocs[index].id;
                  final name = data['name']?.toString() ?? 'Shop';
                  final phone = data['phone']?.toString() ?? '-';
                  final citySlug = data['city']?.toString() ?? kDefaultCity;
                  final city = cityLabelFor(citySlug).toUpperCase();
                  final commission = (data['commissionPct'] as num?)?.toDouble() ?? 0.0;
                  final category = data['category']?.toString() ?? 'General';
                  final isOpen = (data['isOpen'] as bool?) ?? true;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _teal.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.store_rounded, color: _teal, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      color: _text,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '📞 $phone • 📍 $city • $category',
                                    style: const TextStyle(color: _muted, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _toggleShopOpen(id, isOpen),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isOpen
                                      ? _green.withValues(alpha: 0.15)
                                      : _red.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isOpen
                                        ? _green.withValues(alpha: 0.4)
                                        : _red.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  isOpen ? 'ONLINE' : 'PAUSED',
                                  style: TextStyle(
                                    color: isOpen ? _green : _red,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(color: _border, height: 18),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _gold.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${commission.toStringAsFixed(1)}% Commission',
                                style: const TextStyle(
                                  color: _gold,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (phone != '-' && phone.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.phone_in_talk_rounded, size: 18, color: _green),
                                tooltip: 'Call Partner',
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                padding: EdgeInsets.zero,
                                onPressed: () => _callPartner(phone),
                              ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.info_outline_rounded, size: 18, color: _teal),
                              tooltip: 'View Agreement Details',
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              padding: EdgeInsets.zero,
                              onPressed: () => _showPartnerDetailDialog(data, id),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCityFilterChip(String slug, String label) {
    final isSelected = _activeTabCityFilter == slug;
    return GestureDetector(
      onTap: () => setState(() => _activeTabCityFilter = slug),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? _teal : _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? _teal : _border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : _muted,
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
