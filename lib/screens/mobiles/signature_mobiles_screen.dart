// ================================================================
// signature_mobiles_screen.dart — NJ Tech Signature Mobiles Flagship Store
// ================================================================
// Premium customer storefront for:
// 1. Brand New Smartphones (Sealed, Official Warranty)
// 2. NJ Tech Certified Pre-Owned Phones (Battery Health %, Quality Inspected)
// 3. Spares & Accessories (Displays, Fast Chargers, Cables, Cases)
// 4. 1-Tap Order Flow with Live Tracking & Customer Feedback
// ================================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/signature_mobile_models.dart';
import '../../services/signature_mobile_service.dart';
import 'signature_checkout_sheet.dart';
import 'signature_order_tracking_sheet.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF131326);
const Color _card = Color(0xFF1C1C36);
const Color _pink = Color(0xFFFF4FA3);
const Color _green = Color(0xFF00E676);
const Color _gold = Color(0xFFFFD600);
const Color _cyan = Color(0xFF00E5FF);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF8888AA);

class SignatureMobilesScreen extends StatefulWidget {
  final SignatureCategory? initialCategory;

  const SignatureMobilesScreen({super.key, this.initialCategory});

  @override
  State<SignatureMobilesScreen> createState() => _SignatureMobilesScreenState();
}

class _SignatureMobilesScreenState extends State<SignatureMobilesScreen> {
  late SignatureCategory? _selectedCategory = widget.initialCategory;
  String _selectedBrand = 'All';
  final TextEditingController _searchController = TextEditingController();

  List<SignatureProduct> _products = [];
  bool _isLoading = true;

  final List<String> _brands = [
    'All',
    'Apple',
    'Samsung',
    'OnePlus',
    'Xiaomi',
    'NJ Tech Signature',
  ];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    final results = await SignatureMobileService.instance.getProducts(
      category: _selectedCategory,
      brand: _selectedBrand == 'All' ? null : _selectedBrand,
      query: _searchController.text.trim(),
    );
    if (mounted) {
      setState(() {
        _products = results;
        _isLoading = false;
      });
    }
  }

  void _showMyOrders() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to view your orders.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_rounded, color: _pink),
                  const SizedBox(width: 10),
                  Text(
                    'My Signature Orders',
                    style: GoogleFonts.outfit(
                      color: _text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: _muted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(color: _card, height: 1),
            Expanded(
              child: StreamBuilder<List<SignatureOrder>>(
                stream: SignatureMobileService.instance.streamOrdersForCustomer(user.uid),
                builder: (context, snapshot) {
                  final orders = snapshot.data ?? [];
                  if (orders.isEmpty) {
                    return Center(
                      child: Text(
                        'No orders placed yet.',
                        style: GoogleFonts.inter(color: _muted),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: orders.length,
                    itemBuilder: (context, i) {
                      final o = orders[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _card),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    o.items.isNotEmpty ? o.items.first.productName : 'Order',
                                    style: GoogleFonts.inter(
                                      color: _text,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Total: ₹${o.totalAmount.toStringAsFixed(0)} • Status: ${o.status.name.toUpperCase()}',
                                    style: GoogleFonts.inter(color: _muted, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                SignatureOrderTrackingSheet.show(context, orderId: o.orderId);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _pink,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              child: const Text('Track', style: TextStyle(fontSize: 12)),
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
        ),
      ),
    );
  }

  void _showProductDetails(SignatureProduct product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _pink.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.verified_rounded, color: _pink, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'NJ Tech Signature Verified',
                    style: GoogleFonts.inter(color: _pink, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: _muted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(color: _card, height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // High-res Image Preview
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      height: 200,
                      color: _surface,
                      child: Image.network(
                        product.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.phone_android_rounded, color: _pink, size: 48),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title & Brand
                  Text(
                    product.name,
                    style: GoogleFonts.outfit(
                      color: _text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          product.condition,
                          style: GoogleFonts.inter(color: _cyan, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (product.batteryHealth != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '🔋 ${product.batteryHealth}% Battery Health',
                            style: GoogleFonts.inter(color: _green, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                      const Spacer(),
                      const Icon(Icons.star_rounded, color: _gold, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${product.rating} (${product.reviewCount})',
                        style: GoogleFonts.inter(color: _text, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Price Bar
                  Row(
                    children: [
                      Text(
                        '₹${product.price.toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                          color: _green,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (product.mrp > product.price) ...[
                        Text(
                          '₹${product.mrp.toStringAsFixed(0)}',
                          style: GoogleFonts.outfit(
                            color: _muted,
                            fontSize: 16,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${product.discountPercent.toInt()}% OFF',
                            style: GoogleFonts.inter(color: _green, fontSize: 10, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Warranty & Trust Banner
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _pink.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.shield_rounded, color: _pink, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.warrantyText,
                                style: GoogleFonts.inter(color: _text, fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              Text(
                                '32-Point Quality Passed • Tested by NJ Tech Center',
                                style: GoogleFonts.inter(color: _muted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Highlights
                  if (product.highlights.isNotEmpty) ...[
                    Text(
                      'Highlights',
                      style: GoogleFonts.outfit(color: _text, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    ...product.highlights.map((h) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: _green, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(h, style: GoogleFonts.inter(color: _text, fontSize: 12)),
                              ),
                            ],
                          ),
                        )),
                  ],
                ],
              ),
            ),

            // Bottom Buy Now Bar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: _surface,
                border: Border(top: BorderSide(color: _card)),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    SignatureCheckoutSheet.show(context, product: product);
                  },
                  icon: const Icon(Icons.flash_on_rounded, color: Colors.white),
                  label: Text(
                    'Instant Buy Now • ₹${product.price.toStringAsFixed(0)}',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pink,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ),
          ],
        ),
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
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _pink.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.phone_iphone_rounded, color: _pink, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Signature Mobiles & Spares',
                    style: GoogleFonts.outfit(
                      color: _text,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'NJ Tech Flagship · New & Certified Pre-Owned',
                    style: GoogleFonts.inter(color: _green, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_rounded, color: _pink),
            tooltip: 'My Orders',
            onPressed: _showMyOrders,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Header
          _buildSearchAndFilters(),

          // Product Grid
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _pink))
                : _products.isEmpty
                    ? Center(
                        child: Text(
                          'No products found matching your search.',
                          style: GoogleFonts.inter(color: _muted),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.65,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: _products.length,
                        itemBuilder: (context, index) {
                          final p = _products[index];
                          return _buildProductCard(p);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      color: _surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          // Search Field
          TextField(
            controller: _searchController,
            onChanged: (_) => _loadProducts(),
            style: GoogleFonts.inter(color: _text, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search iPhone 15, S24 Ultra, Fast Chargers, Spares...',
              hintStyle: GoogleFonts.inter(color: _muted, fontSize: 12),
              filled: true,
              fillColor: _card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Icons.search_rounded, color: _muted, size: 18),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),

          const SizedBox(height: 10),

          // Category Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildCategoryChip('All Items', null),
                _buildCategoryChip('🌟 New Mobiles', SignatureCategory.newMobile),
                _buildCategoryChip('🔋 Used Certified', SignatureCategory.usedMobile),
                _buildCategoryChip('🔌 Accessories', SignatureCategory.accessory),
                _buildCategoryChip('🛠️ Display & Spares', SignatureCategory.sparePart),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Brand Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _brands.map((b) {
                final isSelected = _selectedBrand == b;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    backgroundColor: _card,
                    selectedColor: _pink.withValues(alpha: 0.2),
                    side: BorderSide(
                      color: isSelected ? _pink : _muted.withValues(alpha: 0.2),
                    ),
                    label: Text(
                      b,
                      style: GoogleFonts.inter(
                        color: isSelected ? _pink : _text,
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() => _selectedBrand = b);
                      _loadProducts();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label, SignatureCategory? cat) {
    final isSelected = _selectedCategory == cat;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        backgroundColor: _card,
        selectedColor: _pink,
        label: Text(
          label,
          style: GoogleFonts.inter(
            color: isSelected ? Colors.white : _text,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        selected: isSelected,
        onSelected: (selected) {
          setState(() => _selectedCategory = selected ? cat : null);
          _loadProducts();
        },
      ),
    );
  }

  Widget _buildProductCard(SignatureProduct p) {
    return GestureDetector(
      onTap: () => _showProductDetails(p),
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image & Condition Tag
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  child: Container(
                    height: 110,
                    width: double.infinity,
                    color: _card,
                    child: Image.network(
                      p.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.phone_android_rounded, color: _pink, size: 36),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      p.category == SignatureCategory.newMobile
                          ? 'NEW'
                          : p.category == SignatureCategory.usedMobile
                              ? '${p.batteryHealth ?? 90}% BH'
                              : 'SPARE',
                      style: GoogleFonts.inter(
                        color: p.category == SignatureCategory.newMobile ? _green : _cyan,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: GoogleFonts.inter(
                        color: _text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.storage != null ? '${p.storage} • ${p.brand}' : p.brand,
                      style: GoogleFonts.inter(color: _muted, fontSize: 10),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Text(
                          '₹${p.price.toStringAsFixed(0)}',
                          style: GoogleFonts.outfit(
                            color: _green,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.star_rounded, color: _gold, size: 12),
                        Text(
                          '${p.rating}',
                          style: GoogleFonts.inter(color: _muted, fontSize: 10),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      height: 28,
                      child: ElevatedButton(
                        onPressed: () => SignatureCheckoutSheet.show(context, product: p),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _pink,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: EdgeInsets.zero,
                        ),
                        child: const Text('Buy Now', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
