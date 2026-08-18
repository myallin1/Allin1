// ================================================================
// Cart Screen - Shopping Cart
// Allin1 Super App - Allin1
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../providers/cart_provider.dart';
// GUEST MODE (Aug 11 2026): requireRealAuth() guard on the submit action.
import '../services/auth_prompt_service.dart';
import '../services/auth_service.dart';

const Color kSurface = Color(0xFF0D0D18);
const Color kCard = Color(0xFF141420);
const Color kCard2 = Color(0xFF1A1A28);
const Color kPurple = Color(0xFF7B6FE0);
const Color kGreen = Color(0xFF3DBA6F);
const Color kGold = Color(0xFFF5C542);
const Color kRed = Color(0xFFE05555);
const Color kText = Color(0xFFEEEEF5);
const Color kMuted = Color(0xFF7777A0);
const Color kBorder = Color(0x267B6FE0);

class CartScreen extends StatefulWidget {
  // ================================================================
  // ⚠️ UNREACHABLE SCREEN — DO NOT WIRE UP WITHOUT READING THIS
  // (Aug 17 2026 order-pipeline audit, Phase 2)
  // ================================================================
  // Nothing in lib/ navigates to CartScreen — verified by grep; the only
  // occurrence of the class name in the entire codebase is this file
  // itself. That is the ONLY reason it is not currently losing customer
  // orders.
  //
  // Its _placeOrder() writes to the `orders` collection. NOTHING READS
  // THAT COLLECTION: not the seller dashboard, not any hero screen, not
  // dispatch. The only readers are admin_orders_cleanup_screen.dart and
  // admin_deletion_service.dart, both of which only DELETE. So an order
  // placed here would tell the customer "Order Placed", and then no
  // seller and no hero would ever learn it existed.
  //
  // If a cart screen is wanted, point it at ServiceRequestService
  // .createServiceRequest() (requestType 'catalog_food_order') the way
  // seller_detail_screen.dart's checkout does — that is the pipeline the
  // seller dashboard and hero dispatch are actually wired to.
  //
  // Left in place rather than deleted: it is a complete, working cart UI
  // and the fix is a write-target change, not a rewrite.
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _addressController = TextEditingController();
  bool _isOrdering = false;

  @override
  void initState() {
    super.initState();
    // Load delivery settings from platform configuration
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CartProvider>().loadDeliverySettings();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: kText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'My Cart',
          style: GoogleFonts.outfit(color: kText, fontWeight: FontWeight.w600),
        ),
        actions: [
          Consumer<CartProvider>(
            builder: (context, cart, _) => cart.itemCount > 0
                ? TextButton(
                    onPressed: () => _showClearCartDialog(context, cart),
                    child:
                        Text('Clear', style: GoogleFonts.outfit(color: kRed)),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: Consumer<CartProvider>(
        builder: (context, cart, _) {
          if (cart.isEmpty) {
            return _buildEmptyState();
          }
          return _buildCartContent(cart);
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🛒', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text(
            'Your cart is empty',
            style: GoogleFonts.outfit(color: kText, fontSize: 20),
          ),
          const SizedBox(height: 8),
          Text(
            'Add items to get started',
            style: GoogleFonts.outfit(color: kMuted),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPurple,
              foregroundColor: Colors.white,
            ),
            child: const Text('Browse Stores'),
          ),
        ],
      ),
    );
  }

  Widget _buildCartContent(CartProvider cart) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cart items
          ...cart.items.map((item) => _buildCartItem(cart, item)),

          const SizedBox(height: 20),
          _buildPriceBreakdown(cart),

          const SizedBox(height: 20),
          _buildDeliveryAddress(),

          const SizedBox(height: 20),
          _buildPlaceOrderButton(cart),
        ],
      ),
    );
  }

  Widget _buildCartItem(CartProvider cart, CartItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          Text(item.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: GoogleFonts.outfit(
                    color: kText,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '₹${item.price.toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(color: kMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          // Quantity controls
          DecoratedBox(
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove, size: 18),
                  color: kText,
                  onPressed: () => cart.decrementQuantity(item.id),
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
                Text(
                  '${item.quantity}',
                  style: GoogleFonts.outfit(color: kText, fontSize: 14),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  color: kText,
                  onPressed: () => cart.incrementQuantity(item.id),
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '₹${item.total.toStringAsFixed(0)}',
            style: GoogleFonts.outfit(
              color: kGold,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceBreakdown(CartProvider cart) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          _buildPriceRow('Subtotal', cart.subtotal),
          const SizedBox(height: 8),
          _buildPriceRow(
            'Delivery Fee',
            cart.deliveryFee,
            subtitle: cart.hasFreeDelivery ? 'FREE' : null,
          ),
          if (!cart.hasFreeDelivery) ...[
            const SizedBox(height: 4),
            Text(
              'Free delivery on orders above ₹200',
              style: GoogleFonts.outfit(color: kMuted, fontSize: 11),
            ),
          ],
          const Divider(color: kBorder, height: 20),
          _buildPriceRow('Total', cart.total, isTotal: true),
        ],
      ),
    );
  }

  Widget _buildPriceRow(
    String label,
    double amount, {
    String? subtitle,
    bool isTotal = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            color: isTotal ? kText : kMuted,
            fontSize: isTotal ? 16 : 14,
            fontWeight: isTotal ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        Text(
          subtitle ?? '₹${amount.toStringAsFixed(0)}',
          style: GoogleFonts.outfit(
            color: subtitle != null ? kGreen : (isTotal ? kGold : kText),
            fontSize: isTotal ? 20 : 14,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildDeliveryAddress() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DELIVERY ADDRESS',
          style: GoogleFonts.outfit(
            color: kMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _addressController,
          maxLines: 2,
          style: GoogleFonts.outfit(color: kText),
          decoration: InputDecoration(
            hintText: 'Enter your delivery address',
            hintStyle: GoogleFonts.outfit(color: kMuted),
            filled: true,
            fillColor: kCard2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kPurple),
            ),
          ),
          validator: (v) => v!.isEmpty ? 'Address required' : null,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.access_time, color: kMuted, size: 14),
            const SizedBox(width: 4),
            Text(
              'Estimated time: 30-45 minutes',
              style: GoogleFonts.outfit(color: kMuted, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlaceOrderButton(CartProvider cart) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isOrdering ? null : () => _placeOrder(cart),
        style: ElevatedButton.styleFrom(
          backgroundColor: kGold,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: _isOrdering
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.black,
                  strokeWidth: 2,
                ),
              )
            : Text(
                'Place Order • ₹${cart.total.toStringAsFixed(0)}',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }

  void _showClearCartDialog(BuildContext context, CartProvider cart) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard2,
        title: Text('Clear Cart?', style: GoogleFonts.outfit(color: kText)),
        content: Text(
          'Remove all items from your cart?',
          style: GoogleFonts.outfit(color: kMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: kMuted)),
          ),
          TextButton(
            onPressed: () {
              cart.clearCart();
              Navigator.pop(ctx);
            },
            child: Text('Clear', style: GoogleFonts.outfit(color: kRed)),
          ),
        ],
      ),
    );
  }

  Future<void> _placeOrder(CartProvider cart) async {
    if (_addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter delivery address',
            style: GoogleFonts.notoSansTamil(color: Colors.white),
          ),
          backgroundColor: kRed,
        ),
      );
      return;
    }

    // GUEST MODE (Aug 11 2026): also not in the spec's list — found by
    // grepping direct writes to the gated collections. This one writes
    // straight to orders/{id}, which isRealUser() now blocks for guests.
    // Note the bare `return` below: before this guard, a signed-out
    // customer tapping "Place Order" got absolutely no feedback at all.
    if (!await requireRealAuth(
      context,
      reason: 'Sign in and we’ll get this order moving',
    )) {
      return;
    }
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // GUEST MODE: this used to be a bare `return` — the button did
      // nothing at all and said nothing about why. Silent failure is
      // worse than a harsh red box, so it gets the branded snack too.
      if (mounted) {
        showSignInRequiredSnack(context, message: 'Sign in to place your order');
      }
      return;
    }

    setState(() => _isOrdering = true);

    try {
      final orderId = const Uuid().v4();
      final resolvedCustomerPhone = await AuthService().resolveCustomerPhone(user);

      await FirebaseFirestore.instance.collection('orders').doc(orderId).set({
        'items': cart.items.map((i) => i.toJson()).toList(),
        'subtotal': cart.subtotal,
        'deliveryFee': cart.deliveryFee,
        'total': cart.total,
        'deliveryAddress': _addressController.text.trim(),
        'status': 'pending',
        'category': 'food', // Default category
        'customerId': user.uid,
        'customerPhone': resolvedCustomerPhone,
        'paymentStatus': 'pending',
        'estimatedTime': '30-45 minutes',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Clear cart after order
      cart.clearCart();

      if (mounted) {
        // Navigate to order tracking
        await Navigator.pushReplacementNamed(
          context,
          '/order-tracking',
          arguments: orderId,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error placing order: $e',
              style: GoogleFonts.notoSansTamil(color: Colors.white),
            ),
            backgroundColor: kRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isOrdering = false);
      }
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }
}
