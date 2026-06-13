// ================================================================
// Ads Management Screen - Admin Panel
// Manage local business ads with external image URL (ImgBB/freeimage.host)
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AdsManagementScreen extends StatefulWidget {
  const AdsManagementScreen({super.key});

  @override
  State<AdsManagementScreen> createState() => _AdsManagementScreenState();
}

class _AdsManagementScreenState extends State<AdsManagementScreen> {
  // ── Theme ────────────────────────────────────────────────────
  static const Color _bg = Color(0xFF0A0A12);
  static const Color _surface = Color(0xFF12121E);
  static const Color _card = Color(0xFF1A1A2A);
  static const Color _purple = Color(0xFF6C63FF);
  static const Color _orange = Color(0xFFFF6B35);
  static const Color _green = Color(0xFF00C853);
  static const Color _gold = Color(0xFFFFBB00);
  static const Color _red = Color(0xFFFF5252);
  static const Color _text = Color(0xFFEEEEF5);
  static const Color _muted = Color(0xFF7777A0);
  static const Color _border = Color(0x1AFFFFFF);

  // Form fields
  final _shopController = TextEditingController();
  final _offerController = TextEditingController();
  final _emojiController = TextEditingController();
  final _phoneController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _actionUrlController = TextEditingController();
  final _coinsController = TextEditingController();
  String _selectedCategory = 'general';
  String _selectedColor = _orange.toARGB32().toRadixString(16);
  bool _isActive = true;

  @override
  void dispose() {
    _shopController.dispose();
    _offerController.dispose();
    _emojiController.dispose();
    _phoneController.dispose();
    _imageUrlController.dispose();
    _actionUrlController.dispose();
    _coinsController.dispose();
    super.dispose();
  }

  // ── Firestore Operations ────────────────────────────────────
  Future<void> _saveAd() async {
    if (_shopController.text.trim().isEmpty) {
      _snack('Shop name is required', _red);
      return;
    }

    try {
      final adData = {
        'shop': _shopController.text.trim(),
        'offer': _offerController.text.trim(),
        'emoji': _emojiController.text.trim().isEmpty
            ? '📢'
            : _emojiController.text.trim(),
        'phone': _phoneController.text.trim(),
        'category': _selectedCategory,
        'isActive': _isActive,
        'color': '#$_selectedColor',
        'imageUrl': _imageUrlController.text.trim(),
        'actionUrl': _actionUrlController.text.trim(),
        'coinsReward': int.tryParse(_coinsController.text.trim()) ?? 50,
        'views': 0,
        'clicks': 0,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('ads').add(adData);

      if (mounted) {
        Navigator.pop(context);
        _snack('Ad created successfully!', _green);
      }
    } catch (e) {
      _snack('Save error: $e', _red);
    }
  }

  Future<void> _updateAd(String adId, Map<String, dynamic> updates) async {
    try {
      await FirebaseFirestore.instance
          .collection('ads')
          .doc(adId)
          .update(updates);
      _snack('Ad updated!', _green);
    } catch (e) {
      _snack('Update error: $e', _red);
    }
  }

  Future<void> _deleteAd(String adId) async {
    try {
      // Delete from Firestore only (external image URL - no storage cleanup needed)
      await FirebaseFirestore.instance.collection('ads').doc(adId).delete();

      _snack('Ad deleted!', _green);
    } catch (e) {
      _snack('Delete error: $e', _red);
    }
  }

  // ── UI Helpers ──────────────────────────────────────────────
  void _snack(String msg, Color color) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showAddEditSheet({DocumentSnapshot? adData}) {
    // Pre-fill if editing
    if (adData != null) {
      final data = adData.data()! as Map<String, dynamic>;
      _shopController.text = data['shop'] as String? ?? '';
      _offerController.text = data['offer'] as String? ?? '';
      _emojiController.text = data['emoji'] as String? ?? '';
      _phoneController.text = data['phone'] as String? ?? '';
      _imageUrlController.text = data['imageUrl'] as String? ?? '';
      _actionUrlController.text = data['actionUrl'] as String? ?? '';
      _coinsController.text = (data['coinsReward'] ?? 50).toString();
      _selectedCategory = data['category'] as String? ?? 'general';
      _selectedColor = (data['color'] as String?)?.replaceFirst('#', '') ??
          _orange.toARGB32().toRadixString(16);
      _isActive = data['isActive'] as bool? ?? true;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Text(
                    adData != null ? '✏️ Edit Ad' : '➕ New Ad',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _text,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: _muted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Image URL Input
              TextFormField(
                controller: _imageUrlController,
                style: const TextStyle(color: _text),
                decoration: InputDecoration(
                  labelText: '🖼️ Image URL',
                  hintText: 'Paste: https://iili.io/xxxxx.jpg',
                  prefixIcon: const Icon(Icons.image, color: _purple),
                  filled: true,
                  fillColor: _card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _border),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Action URL Input
              TextFormField(
                controller: _actionUrlController,
                style: const TextStyle(color: Color(0xFFEEEEF5)),
                decoration: InputDecoration(
                  labelText: '🔗 Action / Affiliate URL',
                  hintText: 'Paste link: https://bitli.in/xxxxx',
                  labelStyle: const TextStyle(color: Color(0xFF7777A0)),
                  hintStyle: const TextStyle(color: Color(0xFF7777A0)),
                  prefixIcon: const Icon(Icons.link, color: Color(0xFF6C63FF)),
                  filled: true,
                  fillColor: const Color(0xFF1A1A2A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF6C63FF)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF7777A0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Color(0xFF6C63FF), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Coins Reward Input
              TextFormField(
                controller: _coinsController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Color(0xFFEEEEF5)),
                decoration: InputDecoration(
                  labelText: '🪙 Coins Reward',
                  hintText: '500',
                  labelStyle: const TextStyle(color: Color(0xFF7777A0)),
                  prefixIcon: const Icon(
                    Icons.monetization_on,
                    color: Color(0xFFFFBB00),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1A1A2A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Form Fields
              _buildTextField(
                controller: _shopController,
                label: 'Shop/Brand Name',
                icon: Icons.store,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _offerController,
                label: 'Offer Text',
                icon: Icons.local_offer,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _emojiController,
                      label: 'Emoji',
                      icon: Icons.emoji_emotions,
                      maxLength: 2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTextField(
                      controller: _phoneController,
                      label: 'Phone',
                      icon: Icons.phone,
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Category Dropdown
              Text(
                'Category',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: _muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCategory,
                    isExpanded: true,
                    dropdownColor: _card,
                    icon: const Icon(Icons.arrow_drop_down, color: _muted),
                    style: const TextStyle(color: _text, fontSize: 14),
                    items: const [
                      DropdownMenuItem(value: 'food', child: Text('🍔 Food')),
                      DropdownMenuItem(
                        value: 'grocery',
                        child: Text('🛒 Grocery'),
                      ),
                      DropdownMenuItem(value: 'tech', child: Text('📱 Tech')),
                      DropdownMenuItem(
                        value: 'general',
                        child: Text('📢 General'),
                      ),
                    ],
                    onChanged: (val) =>
                        setState(() => _selectedCategory = val!),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Color Dropdown
              Text(
                'Card Color',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: _muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedColor,
                    isExpanded: true,
                    dropdownColor: _card,
                    icon: const Icon(Icons.arrow_drop_down, color: _muted),
                    style: const TextStyle(color: _text, fontSize: 14),
                    items: const [
                      DropdownMenuItem(
                        value: 'ffff6b35',
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 8,
                              backgroundColor: _orange,
                            ),
                            SizedBox(width: 8),
                            Text('Orange'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'ff6c63ff',
                        child: Row(
                          children: [
                            CircleAvatar(radius: 8, backgroundColor: _purple),
                            SizedBox(width: 8),
                            Text('Purple'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'ff00c853',
                        child: Row(
                          children: [
                            CircleAvatar(radius: 8, backgroundColor: _green),
                            SizedBox(width: 8),
                            Text('Green'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'ffffbb00',
                        child: Row(
                          children: [
                            CircleAvatar(radius: 8, backgroundColor: _gold),
                            SizedBox(width: 8),
                            Text('Gold'),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (val) => setState(() => _selectedColor = val!),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Active Toggle
              Row(
                children: [
                  const Text(
                    'Active',
                    style: TextStyle(color: _text, fontSize: 14),
                  ),
                  const Spacer(),
                  Switch(
                    value: _isActive,
                    activeThumbColor: _green,
                    onChanged: (val) => setState(() => _isActive = val),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Save Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saveAd,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    adData != null ? 'Update Ad' : 'Create Ad',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int? maxLength,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            color: _muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLength: maxLength,
          keyboardType: keyboardType,
          style: const TextStyle(color: _text, fontSize: 14),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: _muted, size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _border),
            ),
            filled: true,
            fillColor: _card,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
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
          '📢 Ads Management',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: _text,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle, color: _green),
            tooltip: 'New Ad',
            onPressed: _showAddEditSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats Row
          _buildStatsRow(),
          const SizedBox(height: 12),
          // Ads List
          Expanded(child: _buildAdsList()),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('ads').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        final total = docs.length;
        final active = docs.where((d) {
          final data = d.data()! as Map<String, dynamic>;
          return data['isActive'] == true;
        }).length;
        final views = docs.fold<int>(
          0,
          (sum, d) =>
              sum + ((d.data()! as Map<String, dynamic>)['views'] as int? ?? 0),
        );

        return Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _statItem('📊', 'Total', total.toString(), _purple),
              _statItem('✅', 'Active', active.toString(), _green),
              _statItem('👁️', 'Views', views.toString(), _gold),
            ],
          ),
        );
      },
    );
  }

  Widget _statItem(String emoji, String label, String value, Color color) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.outfit(fontSize: 10, color: _muted),
        ),
      ],
    );
  }

  Widget _buildAdsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ads')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('📢', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                Text(
                  'No ads yet',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap + to create your first ad',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: _muted,
                  ),
                ),
              ],
            ),
          );
        }

        final ads = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: ads.length,
          itemBuilder: (context, index) {
            final ad = ads[index];
            final data = ad.data()! as Map<String, dynamic>;
            final isActive = data['isActive'] == true;
            final color = Color(
              int.parse(
                (data['color'] as String?)?.replaceFirst('#', '0xff') ??
                    '0xff${_orange.toARGB32().toRadixString(16)}',
              ),
            );

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isActive ? color.withValues(alpha: 0.3) : _border,
                  width: isActive ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  // Ad Image
                  if (data['imageUrl'] != null &&
                      (data['imageUrl'] as String).isNotEmpty)
                    ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(16)),
                      child: Image.network(
                        data['imageUrl'] as String,
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 150,
                          color: _surface,
                          child: const Center(
                            child: Icon(Icons.broken_image, color: _muted),
                          ),
                        ),
                        loadingBuilder: (_, child, progress) => progress == null
                            ? child
                            : Container(
                                height: 150,
                                color: _surface,
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                      ),
                    ),

                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          children: [
                            Text(
                              '${data['emoji'] ?? '📢'} ${data['shop'] ?? 'Unknown'}',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: _text,
                              ),
                            ),
                            const Spacer(),
                            // Active Toggle
                            Switch(
                              value: isActive,
                              activeThumbColor: _green,
                              onChanged: (val) => _updateAd(ad.id, {
                                'isActive': val,
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // Offer
                        Text(
                          data['offer'] as String? ?? '',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: _muted,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Category & Stats
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: color.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                data['category'] as String? ?? 'general',
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  color: color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Row(
                              children: [
                                const Icon(
                                  Icons.visibility,
                                  size: 14,
                                  color: _muted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${data['views'] ?? 0}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _muted,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Icon(
                                  Icons.touch_app,
                                  size: 14,
                                  color: _muted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${data['clicks'] ?? 0}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _muted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Actions
                        Row(
                          children: [
                            // Edit
                            IconButton(
                              icon: const Icon(Icons.edit, color: _purple),
                              tooltip: 'Edit',
                              onPressed: () => _showAddEditSheet(adData: ad),
                            ),
                            // Delete
                            IconButton(
                              icon: const Icon(Icons.delete, color: _red),
                              tooltip: 'Delete',
                              onPressed: () => _confirmDelete(ad.id),
                            ),
                            const Spacer(),
                            // Phone
                            if (data['phone'] != null &&
                                (data['phone'] as String).isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _green.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: _green.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.phone,
                                      size: 12,
                                      color: _green,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      data['phone'] as String,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: _green,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDelete(String adId) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Delete Ad?',
          style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'This will delete the ad permanently.',
          style: TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _muted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteAd(adId);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: _red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
