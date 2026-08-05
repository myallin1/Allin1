// ================================================================
// CustomHotelViewScreen — customer-facing live menu + cart/checkout
// for one Custom Hotel.
// ================================================================
// NEW (CTO mandate — Custom Hotel Integration System, Instant Customer
// App Sync + Ordering & Checkout Pipeline). Menu browsing stays exactly
// as before (live StreamBuilder over
// CustomHotelService.visibleItemsStream()); this pass adds an in-memory
// cart (State field, cleared on checkout — no persistence needed
// beyond one session, same as this app has no other "saved cart"
// concept anywhere) and a checkout bottom sheet that places the order.
//
// ISOLATION (CTO mandate #2 and #4): placing an order here writes to
// its OWN `custom_hotel_orders` Firestore collection
// (CustomHotelService.placeOrder) — never the legacy `orders`
// collection, never anything grocery_order_screen.dart or
// custom_food_order_screen.dart touch. Admin/Hero dispatch visibility
// (mandate #3) is achieved by additionally calling the EXISTING,
// UNMODIFIED ServiceRequestService.createServiceRequest with
// requestType 'custom_hotel_order' — the exact same shared dispatch
// utility custom_food_order_screen.dart already uses for its own
// 'custom_food_order' type, so hero broadcast + the admin dispatch
// screen's existing `service_requests` listeners pick this up with
// zero changes to either of those files.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/custom_hotel_service.dart';
import '../services/service_request_service.dart';

const Color _kBg = Color(0xFFFFFFFF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF9999BB);
const Color _kPink = Color(0xFFFF4FA3);
const Color _kPinkDark = Color(0xFFBE2A7A);

class CustomHotelViewScreen extends StatefulWidget {
  const CustomHotelViewScreen({required this.hotelId, required this.hotelName, super.key});
  final String hotelId;
  final String hotelName;

  @override
  State<CustomHotelViewScreen> createState() => _CustomHotelViewScreenState();
}

class _CustomHotelViewScreenState extends State<CustomHotelViewScreen> {
  final CustomHotelService _service = CustomHotelService();
  // itemId -> quantity. Item details are re-read from the live stream
  // when building the checkout summary, so the cart never holds stale
  // price/name copies if the seller edits an item mid-session.
  final Map<String, int> _cart = {};

  void _addToCart(String itemId) {
    setState(() => _cart[itemId] = (_cart[itemId] ?? 0) + 1);
  }

  void _removeFromCart(String itemId) {
    setState(() {
      final current = _cart[itemId] ?? 0;
      if (current <= 1) {
        _cart.remove(itemId);
      } else {
        _cart[itemId] = current - 1;
      }
    });
  }

  Future<void> _openCheckout(List<CustomHotelItem> allItems) async {
    final cartItems = allItems.where((i) => _cart.containsKey(i.id)).toList();
    if (cartItems.isEmpty) return;
    final placed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CheckoutSheet(
        hotelId: widget.hotelId,
        hotelName: widget.hotelName,
        cartItems: cartItems,
        quantities: Map<String, int>.from(_cart),
        service: _service,
        onQuantityChanged: (itemId, qty) {
          setState(() {
            if (qty <= 0) {
              _cart.remove(itemId);
            } else {
              _cart[itemId] = qty;
            }
          });
        },
      ),
    );
    if (placed == true && mounted) {
      setState(() => _cart.clear());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _kText),
        title: Text(widget.hotelName, style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 17)),
      ),
      // NEW — live: if the seller closes the hotel entirely while the
      // customer is on this exact screen, the hotel doc itself leaves
      // openHotelsStream on the Food Hub list, but a customer already
      // inside here should also see an honest "closed" state rather
      // than a stale menu — hence the extra hotelStream check below.
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _service.hotelStream(widget.hotelId),
        builder: (context, hotelSnap) {
          final isOpen = hotelSnap.data?.data()?['isOpen'] as bool? ?? false;
          if (hotelSnap.hasData && !isOpen) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.storefront_outlined, color: _kMuted, size: 40),
                    const SizedBox(height: 12),
                    Text('This hotel just closed.', style: GoogleFonts.outfit(color: _kText, fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Please check back later.', style: GoogleFonts.outfit(color: _kMuted, fontSize: 12)),
                  ],
                ),
              ),
            );
          }
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _service.visibleItemsStream(widget.hotelId),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data?.docs ?? const [];
              final items = docs.map(CustomHotelItem.fromDoc).toList();
              if (items.isEmpty) {
                return Center(
                  child: Text('No items available right now.', style: GoogleFonts.outfit(color: _kMuted, fontSize: 13)),
                );
              }
              // FIX — an item removed from the live menu (deleted, or
              // toggled invisible) while it's sitting in the cart must
              // drop out of the cart too, otherwise checkout could try
              // to order something no longer on the menu.
              final visibleIds = items.map((i) => i.id).toSet();
              _cart.removeWhere((id, _) => !visibleIds.contains(id));

              final cartCount = _cart.values.fold<int>(0, (a, b) => a + b);
              final cartTotal = items
                  .where((i) => _cart.containsKey(i.id))
                  .fold<double>(0, (sum, i) => sum + i.price * (_cart[i.id] ?? 0));

              return Stack(
                children: [
                  ListView.builder(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, cartCount > 0 ? 90 : 16),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      final qty = _cart[item.id] ?? 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F7FC),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: item.photoUrl.isEmpty
                                  ? Container(
                                      width: 64,
                                      height: 64,
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(colors: [_kPink, _kPinkDark]),
                                      ),
                                      child: const Icon(Icons.restaurant_rounded, color: Colors.white),
                                    )
                                  : Image.network(item.photoUrl, width: 64, height: 64, fit: BoxFit.cover),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.name, style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 14)),
                                  const SizedBox(height: 2),
                                  Text('₹${item.price.toStringAsFixed(0)}', style: GoogleFonts.outfit(color: _kPinkDark, fontWeight: FontWeight.w700, fontSize: 12.5)),
                                  if (item.description.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(item.description, style: GoogleFonts.outfit(color: _kMuted, fontSize: 11.5)),
                                  ],
                                ],
                              ),
                            ),
                            // NEW — Add to Cart / quantity stepper
                            // (CTO mandate #1).
                            qty == 0
                                ? OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: _kPink),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => _addToCart(item.id),
                                    child: const Text('Add', style: TextStyle(color: _kPink, fontWeight: FontWeight.w700)),
                                  )
                                : Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, color: _kPink, size: 20),
                                        onPressed: () => _removeFromCart(item.id),
                                      ),
                                      Text('$qty', style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w700)),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline, color: _kPink, size: 20),
                                        onPressed: () => _addToCart(item.id),
                                      ),
                                    ],
                                  ),
                          ],
                        ),
                      );
                    },
                  ),
                  if (cartCount > 0)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: SafeArea(
                        top: false,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kPink,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () => _openCheckout(items),
                          child: Text(
                            'View Cart ($cartCount) — ₹${cartTotal.toStringAsFixed(0)}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet({
    required this.hotelId,
    required this.hotelName,
    required this.cartItems,
    required this.quantities,
    required this.service,
    required this.onQuantityChanged,
  });

  final String hotelId;
  final String hotelName;
  final List<CustomHotelItem> cartItems;
  final Map<String, int> quantities;
  final CustomHotelService service;
  final void Function(String itemId, int qty) onQuantityChanged;

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  late final Map<String, int> _qty = Map<String, int>.from(widget.quantities);
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  bool _placing = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _nameCtrl.text = user?.displayName ?? '';
    _phoneCtrl.text = user?.phoneNumber ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  double get _total => widget.cartItems.fold<double>(0, (sum, i) => sum + i.price * (_qty[i.id] ?? 0));

  Future<void> _placeOrder() async {
    final address = _addressCtrl.text.trim();
    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a delivery address.')));
      return;
    }
    final activeItems = widget.cartItems.where((i) => (_qty[i.id] ?? 0) > 0).toList();
    if (activeItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your cart is empty.')));
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in to place an order.')));
      return;
    }

    setState(() => _placing = true);
    try {
      final itemsPayload = activeItems
          .map((i) => {
                'itemId': i.id,
                'name': i.name,
                'price': i.price,
                'quantity': _qty[i.id] ?? 0,
              })
          .toList();
      final customerName = _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : (user.displayName ?? 'Customer');
      final customerPhone = _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : (user.phoneNumber ?? '');

      // Step 1 (CTO mandate #2 — Isolated Order Database): the
      // definitive order/receipt record, in its own collection.
      final orderId = await widget.service.placeOrder(
        sellerId: widget.hotelId,
        hotelName: widget.hotelName,
        items: itemsPayload,
        totalAmount: _total,
        customerId: user.uid,
        customerName: customerName,
        customerPhone: customerPhone,
        deliveryAddress: address,
      );

      // Step 2 (CTO mandate #3 — Admin/Hero dispatch visibility): reuse
      // the EXISTING shared dispatch utility as-is (no changes to
      // ServiceRequestService or the admin/hero screens that already
      // read from it) — same call shape custom_food_order_screen.dart
      // already makes for its own order type.
      final itemsSummary = activeItems.map((i) => '${_qty[i.id]}x ${i.name}').join(', ');
      final requestId = await ServiceRequestService().createServiceRequest(
        requestType: 'custom_hotel_order',
        customerId: user.uid,
        customerName: customerName,
        customerPhone: customerPhone,
        details: {
          'sellerId': widget.hotelId,
          'hotelName': widget.hotelName,
          'customHotelOrderId': orderId,
          'items': itemsSummary,
          'itemsDetailed': itemsPayload,
          'deliveryAddress': address,
          'totalAmount': _total,
        },
      );
      await widget.service.linkServiceRequest(orderId: orderId, serviceRequestId: requestId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order placed! The hotel and a delivery hero will be notified.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not place order: $e')));
      }
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Review Order', style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 4),
            Text(widget.hotelName, style: GoogleFonts.outfit(color: _kMuted, fontSize: 12.5)),
            const SizedBox(height: 12),
            ...widget.cartItems.map((item) {
              final qty = _qty[item.id] ?? 0;
              if (qty <= 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${item.name} x$qty', style: GoogleFonts.outfit(color: _kText, fontSize: 13)),
                    ),
                    Text('₹${(item.price * qty).toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w700, fontSize: 13)),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: _kPink, size: 18),
                      onPressed: () => setState(() {
                        final next = qty - 1;
                        _qty[item.id] = next;
                        widget.onQuantityChanged(item.id, next);
                      }),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, color: _kPink, size: 18),
                      onPressed: () => setState(() {
                        final next = qty + 1;
                        _qty[item.id] = next;
                        widget.onQuantityChanged(item.id, next);
                      }),
                    ),
                  ],
                ),
              );
            }),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total', style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 15)),
                Text('₹${_total.toStringAsFixed(0)}', style: GoogleFonts.outfit(color: _kPinkDark, fontWeight: FontWeight.w800, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: _kText),
              decoration: const InputDecoration(labelText: 'Your Name', labelStyle: TextStyle(color: _kMuted)),
            ),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: _kText),
              decoration: const InputDecoration(labelText: 'Phone Number', labelStyle: TextStyle(color: _kMuted)),
            ),
            TextField(
              controller: _addressCtrl,
              maxLines: 2,
              style: const TextStyle(color: _kText),
              decoration: const InputDecoration(labelText: 'Delivery Address', labelStyle: TextStyle(color: _kMuted)),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _kPink, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: _placing ? null : _placeOrder,
                child: Text(
                  _placing ? 'Placing Order...' : 'Place Order',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
