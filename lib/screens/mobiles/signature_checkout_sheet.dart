// ================================================================
// signature_checkout_sheet.dart — 1-Tap Checkout for Signature Mobiles
// ================================================================
// Supports:
// - Doorstep Express Delivery by Hero Rider vs Store Pickup at NJ Tech
// - Name, Phone & Address autofill
// - UPI (PhonePe / GPay) / COD / Store Pay selection
// - Direct order placement & instant tracking transition
// ================================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/signature_mobile_models.dart';
import '../../services/signature_mobile_service.dart';
import 'signature_order_tracking_sheet.dart';

const Color _bg = Color(0xFF0F0F1E);
const Color _surface = Color(0xFF18182E);
const Color _card = Color(0xFF22223D);
const Color _pink = Color(0xFFFF4FA3);
const Color _green = Color(0xFF00E676);
const Color _gold = Color(0xFFFFD600);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF8888AA);

class SignatureCheckoutSheet extends StatefulWidget {
  final SignatureProduct product;

  const SignatureCheckoutSheet({super.key, required this.product});

  static void show(BuildContext context, {required SignatureProduct product}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SignatureCheckoutSheet(product: product),
    );
  }

  @override
  State<SignatureCheckoutSheet> createState() => _SignatureCheckoutSheetState();
}

class _SignatureCheckoutSheetState extends State<SignatureCheckoutSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  SignatureDeliveryMode _deliveryMode = SignatureDeliveryMode.doorstep;
  String _paymentMethod = 'upi';
  int _quantity = 1;
  bool _isPlacing = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _nameController.text = user?.displayName ?? 'Customer';
    _phoneController.text = user?.phoneNumber ?? '';
    _addressController.text = 'Erode, Tamil Nadu';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  double get _subtotal => widget.product.price * _quantity;
  double get _deliveryFee =>
      (_deliveryMode == SignatureDeliveryMode.storePickup || _subtotal >= 2000) ? 0.0 : 49.0;
  double get _totalAmount => _subtotal + _deliveryFee;

  Future<void> _placeOrder() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final address = _addressController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your name and phone number.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_deliveryMode == SignatureDeliveryMode.doorstep && address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your delivery address.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isPlacing = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final customerId = user?.uid ?? 'cust_${DateTime.now().millisecondsSinceEpoch}';

      final item = SignatureOrderItem(
        productId: widget.product.id,
        productName: widget.product.name,
        brand: widget.product.brand,
        price: widget.product.price,
        quantity: _quantity,
        storage: widget.product.storage,
        color: widget.product.color,
        imageUrl: widget.product.imageUrl,
      );

      final order = await SignatureMobileService.instance.placeOrder(
        customerId: customerId,
        customerName: name,
        customerPhone: phone,
        items: [item],
        deliveryFee: _deliveryFee,
        deliveryMode: _deliveryMode,
        deliveryAddress: _deliveryMode == SignatureDeliveryMode.storePickup
            ? 'NJ Tech Service Center, Erode (Self-Pickup)'
            : address,
        paymentMethod: _paymentMethod,
        paymentStatus: _paymentMethod == 'upi' ? 'paid' : 'pending',
      );

      if (!mounted) return;
      Navigator.pop(context); // Close checkout sheet

      // Open tracking sheet
      SignatureOrderTrackingSheet.show(context, orderId: order.orderId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Order placed successfully with NJ Tech Signature!'),
          backgroundColor: _green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to place order: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isPlacing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag Handle & Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _muted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _pink.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.shopping_bag_rounded, color: _pink, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Checkout · Signature Mobiles',
                            style: GoogleFonts.outfit(
                              color: _text,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'NJ Tech Verified Storefront',
                            style: GoogleFonts.inter(color: _green, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: _muted),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(color: _card, height: 1),

          // Scrollable Form
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Product Summary Card
                _buildProductItemCard(),

                const SizedBox(height: 18),

                // Delivery Mode Selection
                _buildDeliveryModeSelector(),

                const SizedBox(height: 18),

                // Customer Info Fields
                _buildCustomerInfoFields(),

                const SizedBox(height: 18),

                // Payment Method Selector
                _buildPaymentMethodSelector(),

                const SizedBox(height: 18),

                // Bill Breakdown Card
                _buildBillSummaryCard(),

                const SizedBox(height: 24),
              ],
            ),
          ),

          // Bottom Place Order Bar
          _buildBottomAction(),
        ],
      ),
    );
  }

  Widget _buildProductItemCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 60,
              height: 60,
              color: _card,
              child: Image.network(
                widget.product.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.phone_android_rounded, color: _pink),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.product.name,
                  style: GoogleFonts.inter(
                    color: _text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${widget.product.condition} • ${widget.product.warrantyText}',
                  style: GoogleFonts.inter(color: _muted, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '₹${widget.product.price.toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(
                        color: _green,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    // Quantity Controller
                    Container(
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove, color: _muted, size: 16),
                            onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            padding: EdgeInsets.zero,
                          ),
                          Text('$_quantity',
                              style: GoogleFonts.inter(color: _text, fontWeight: FontWeight.w700)),
                          IconButton(
                            icon: const Icon(Icons.add, color: _text, size: 16),
                            onPressed: () => setState(() => _quantity++),
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            padding: EdgeInsets.zero,
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
  }

  Widget _buildDeliveryModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Delivery Method',
          style: GoogleFonts.outfit(color: _text, fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _deliveryMode = SignatureDeliveryMode.doorstep),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _deliveryMode == SignatureDeliveryMode.doorstep
                        ? _pink.withValues(alpha: 0.15)
                        : _surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _deliveryMode == SignatureDeliveryMode.doorstep
                          ? _pink
                          : _card,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.delivery_dining_rounded, color: _pink, size: 24),
                      const SizedBox(height: 6),
                      Text('🛵 Doorstep',
                          style: GoogleFonts.inter(color: _text, fontWeight: FontWeight.w700, fontSize: 12)),
                      Text('Hero Express Rider',
                          style: GoogleFonts.inter(color: _muted, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _deliveryMode = SignatureDeliveryMode.storePickup),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _deliveryMode == SignatureDeliveryMode.storePickup
                        ? _pink.withValues(alpha: 0.15)
                        : _surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _deliveryMode == SignatureDeliveryMode.storePickup
                          ? _pink
                          : _card,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.storefront_rounded, color: _gold, size: 24),
                      const SizedBox(height: 6),
                      Text('🏬 Store Pickup',
                          style: GoogleFonts.inter(color: _text, fontWeight: FontWeight.w700, fontSize: 12)),
                      Text('NJ Tech Center (Free)',
                          style: GoogleFonts.inter(color: _muted, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCustomerInfoFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Contact & Location',
          style: GoogleFonts.outfit(color: _text, fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _nameController,
          style: GoogleFonts.inter(color: _text, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Full Name',
            labelStyle: GoogleFonts.inter(color: _muted, fontSize: 12),
            filled: true,
            fillColor: _surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            prefixIcon: const Icon(Icons.person_rounded, color: _muted, size: 18),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          style: GoogleFonts.inter(color: _text, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Phone Number',
            labelStyle: GoogleFonts.inter(color: _muted, fontSize: 12),
            filled: true,
            fillColor: _surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            prefixIcon: const Icon(Icons.phone_rounded, color: _muted, size: 18),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
        if (_deliveryMode == SignatureDeliveryMode.doorstep) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _addressController,
            maxLines: 2,
            style: GoogleFonts.inter(color: _text, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Delivery Address in Erode',
              labelStyle: GoogleFonts.inter(color: _muted, fontSize: 12),
              filled: true,
              fillColor: _surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              prefixIcon: const Icon(Icons.location_on_rounded, color: _pink, size: 18),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPaymentMethodSelector() {
    final options = [
      {'id': 'upi', 'label': 'UPI / PhonePe / GPay', 'icon': Icons.account_balance_wallet_rounded, 'color': _green},
      {'id': 'cod', 'label': 'Cash / Card on Delivery', 'icon': Icons.payments_rounded, 'color': _gold},
      {'id': 'store_pay', 'label': 'Pay at NJ Tech Counter', 'icon': Icons.store_rounded, 'color': _pink},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment Option',
          style: GoogleFonts.outfit(color: _text, fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        ...options.map((opt) {
          final isSelected = _paymentMethod == opt['id'];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              onTap: () => setState(() => _paymentMethod = opt['id'] as String),
              tileColor: _surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: isSelected ? _pink : _card),
              ),
              leading: Icon(opt['icon'] as IconData, color: opt['color'] as Color),
              title: Text(
                opt['label'] as String,
                style: GoogleFonts.inter(
                  color: _text,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              trailing: Icon(
                isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                color: isSelected ? _pink : _muted,
                size: 20,
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildBillSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _card),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Items Subtotal', style: GoogleFonts.inter(color: _muted, fontSize: 12)),
              Text('₹${_subtotal.toStringAsFixed(0)}', style: GoogleFonts.inter(color: _text, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Delivery Fee', style: GoogleFonts.inter(color: _muted, fontSize: 12)),
              Text(
                _deliveryFee == 0 ? 'FREE' : '₹${_deliveryFee.toStringAsFixed(0)}',
                style: GoogleFonts.inter(
                  color: _deliveryFee == 0 ? _green : _text,
                  fontWeight: _deliveryFee == 0 ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const Divider(color: _card, height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Payable', style: GoogleFonts.outfit(color: _text, fontSize: 15, fontWeight: FontWeight.w700)),
              Text(
                '₹${_totalAmount.toStringAsFixed(0)}',
                style: GoogleFonts.outfit(color: _green, fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomAction() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _card)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: _isPlacing ? null : _placeOrder,
          style: ElevatedButton.styleFrom(
            backgroundColor: _pink,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: _isPlacing
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.verified_rounded, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Place Order • ₹${_totalAmount.toStringAsFixed(0)}',
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
