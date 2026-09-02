// ================================================================
// grocery_seller_detail_screen.dart — customer catalog browsing +
// cart + checkout for ONE grocery seller (Sep 2026 universal catalog
// build).
// ================================================================
// Reuses, rather than reinvents, three pieces already proven for food:
//   - CategoryGatewayService.loadSellerProducts() — already generic
//     over any sellers/{id}/menu_items subcollection, already a
//     one-time .get() + limit(100) + 45-min Hive cache. Zero backend
//     changes needed for this screen to read grocery items.
//   - CartService — a genuinely universal singleton cart (id/sellerId/
//     name/price/qty), no food coupling at all.
//   - FoodCheckoutScreen — already takes hotelName/items/subtotal/
//     sellerId as plain generic values; a grocery store's name/items
//     fit that shape exactly, including the seller-direct-UPI option.
//
// The one NEW thing checkout needs here that food's flow doesn't:
// stock is CATALOG stock (must be atomically, server-verified
// decremented — see catalog_order_service.dart / reserveMenuItemStock
// .ts), not a free-text list a hero interprets by eye.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../services/catalog_order_service.dart';
import '../services/category_gateway_service.dart';
import '../services/phonepe_payment_service.dart';
import 'food_checkout_screen.dart';

const Color _bg = Color(0xFFFFFFFF);
const Color _text = Color(0xFF1A1A2E);
const Color _muted = Color(0xFF9999BB);
const Color _teal = Color(0xFF11998E);
const Color _red = Color(0xFFD64545);

class GrocerySellerDetailScreen extends StatefulWidget {
  final String sellerId;
  final String sellerName;
  const GrocerySellerDetailScreen({required this.sellerId, required this.sellerName, super.key});

  @override
  State<GrocerySellerDetailScreen> createState() => _GrocerySellerDetailScreenState();
}

class _GrocerySellerDetailScreenState extends State<GrocerySellerDetailScreen> {
  final CartService _cart = CartService();
  StreamSubscription<List<CartItem>>? _cartSub;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _products = [];
  bool _placingOrder = false;

  @override
  void initState() {
    super.initState();
    _cartSub = _cart.cartStream.listen((_) {
      if (mounted) setState(() {});
    });
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _products = forceRefresh
          ? await CategoryGatewayService().forceRefreshProducts(widget.sellerId, Category.grocery)
          : await CategoryGatewayService().loadSellerProducts(widget.sellerId, Category.grocery);
    } catch (e) {
      _error = 'Could not load products. Please try again.';
      debugPrint('[GrocerySellerDetail] load failed: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _cartSub?.cancel();
    super.dispose();
  }

  Future<void> _addToCart(Map<String, dynamic> product) async {
    final id = product['id'] as String;
    if (_cart.hasCrossSellerConflict(widget.sellerId)) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Start a new order?'),
          content: Text('Your cart has items from ${_cart.currentSellerName}. Adding this will clear it.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start New')),
          ],
        ),
      );
      if (proceed != true) return;
      _cart.clear();
    }
    await _cart.addItem(CartItem(
      id: id,
      sellerId: widget.sellerId,
      name: (product['name'] as String?) ?? 'Item',
      price: (product['price'] as num?)?.toDouble() ?? 0,
      image: product['imageUrl'] as String?,
      category: product['categoryName'] as String?,
    ),);
    // FIX (audit pass — real bug): CartService.addItem() only ever sets
    // _currentSellerId, never _currentSellerName (see that method's own
    // body) — seller_detail_screen.dart's food flow covers this by
    // calling setCurrentSeller() right after every addItem() too. Without
    // it here, the cross-seller conflict dialog below rendered "items
    // from null" instead of the actual store name.
    _cart.setCurrentSeller(widget.sellerId, widget.sellerName);
  }

  /// STRUCTURAL GUARANTEE (Sep 2026 stock-HOLD rewrite — see
  /// catalog_order_service.dart's header): stock is HELD here, first,
  /// before FoodCheckoutScreen — and therefore any payment method,
  /// including PhonePe — is ever shown. If the hold fails, the
  /// customer sees an error and the checkout screen never opens at
  /// all, which is what makes "pay for an out-of-stock item"
  /// impossible rather than merely unlikely.
  Future<void> _checkout() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final cartItemsSnapshot = List<CartItem>.from(_cart.items);

    setState(() => _placingOrder = true);
    StockHoldResult hold;
    try {
      hold = await CatalogOrderService.instance.holdStock(
        sellerId: widget.sellerId,
        items: cartItemsSnapshot
            .map((i) => CatalogOrderItem(itemId: i.id, quantity: i.quantity))
            .toList(),
      );
    } on StockUnavailableException catch (e) {
      if (mounted) {
        setState(() => _placingOrder = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: _red),
        );
      }
      return;
    } catch (e) {
      if (mounted) {
        setState(() => _placingOrder = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start checkout: $e'), backgroundColor: _red),
        );
      }
      return;
    }
    if (mounted) setState(() => _placingOrder = false);

    // Stock is now HELD (locked, decremented) — the checkout screen
    // shows the SAME items/subtotal the hold just server-resolved, not
    // whatever the cart's cached prices happened to say.
    final itemsPreview = hold.itemsDetail
        .map((item) => {'name': item['name'], 'quantity': item['quantity'], 'total': item['total']})
        .toList();

    final checkoutResult = await Navigator.push<FoodCheckoutResult>(
      context,
      MaterialPageRoute<FoodCheckoutResult>(
        builder: (_) => FoodCheckoutScreen(
          hotelName: widget.sellerName,
          items: itemsPreview,
          subtotal: hold.subtotal,
          sellerId: widget.sellerId,
        ),
      ),
    );

    if (checkoutResult == null) {
      // Customer backed out without completing any payment method —
      // release the hold immediately rather than leaving these units
      // locked for the full HOLD_TTL_MINUTES.
      unawaited(CatalogOrderService.instance.releaseHold(hold.holdId));
      return;
    }
    if (!mounted) return;

    setState(() => _placingOrder = true);
    try {
      final resolvedPhone = checkoutResult.customerPhone.isNotEmpty
          ? checkoutResult.customerPhone
          : await AuthService().resolveCustomerPhone(user);

      final requestId = await CatalogOrderService.instance.confirmAndCreateOrder(
        hold: hold,
        sellerId: widget.sellerId,
        sellerName: widget.sellerName,
        department: 'grocery',
        customerId: user.uid,
        customerName: checkoutResult.customerName,
        customerPhone: resolvedPhone,
        deliveryAddress: checkoutResult.address,
        deliveryLat: checkoutResult.lat,
        deliveryLng: checkoutResult.lng,
        paymentMethod: checkoutResult.paymentMethod,
        // FoodCheckoutScreen already reserved this id and created the
        // PhonePe payment record against it BEFORE stock was even
        // checked — passing it through here is what lets
        // phonepe_payment_service.dart's confirmLink() join the two.
        preGeneratedRequestId: checkoutResult.reservedRequestId,
      );

      // Closes the loop opened by FoodCheckoutScreen's own PhonePe path
      // — see seller_detail_screen.dart's identical call for the food
      // flow and phonepe_payment_service.dart's confirmLink() doc
      // comment for why this has to be a separate, best-effort step.
      if (checkoutResult.paymentMethod == 'phonepe_upi' &&
          checkoutResult.merchantTransactionId != null) {
        unawaited(
          PhonePePaymentService.instance
              .confirmLink(
                merchantTransactionId: checkoutResult.merchantTransactionId!,
                requestId: requestId,
              )
              .catchError((Object e) {
            debugPrint('[GrocerySellerDetail] PhonePe confirmLink failed (non-fatal): $e');
            return false;
          }),
        );
      }

      _cart.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order placed! Track it from My Orders.')),
      );
      Navigator.pop(context);
    } catch (e) {
      // Note: StockUnavailableException cannot happen here anymore —
      // stock was already locked in at holdStock() above. A failure at
      // this stage is order-creation-only (network, etc.); the hold
      // stays 'held' and the scheduled sweep reclaims it if this is
      // never retried successfully.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not place order: $e'), backgroundColor: _red),
        );
      }
    } finally {
      if (mounted) setState(() => _placingOrder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartIsForThisSeller = _cart.currentSellerId == widget.sellerId;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text(widget.sellerName, style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: GoogleFonts.outfit(color: _muted)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: () => _load(forceRefresh: true), child: const Text('Retry')),
                    ],
                  ),
                )
              : _products.isEmpty
                  ? Center(child: Text('No products listed yet.', style: GoogleFonts.outfit(color: _muted)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                      itemCount: _products.length,
                      itemBuilder: (context, i) => _buildProductTile(_products[i], cartIsForThisSeller),
                    ),
      bottomNavigationBar: (cartIsForThisSeller && _cart.isNotEmpty)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _placingOrder ? null : _checkout,
                    style: ElevatedButton.styleFrom(backgroundColor: _teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    child: _placingOrder
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('${_cart.itemCount} items · ₹${_cart.subtotal.toStringAsFixed(0)} — Checkout',
                            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800),),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildProductTile(Map<String, dynamic> product, bool cartIsForThisSeller) {
    final id = product['id'] as String;
    final name = (product['name'] as String?) ?? 'Item';
    final price = (product['price'] as num?)?.toDouble() ?? 0;
    final stock = (product['stockQuantity'] as num?)?.toInt();
    final unit = (product['categoryName'] as String?) ?? '';
    final outOfStock = stock != null && stock <= 0;
    // FIX (audit pass, Sep 2026 — real cross-seller bug): item ids come
    // from the SHARED master catalog, so two different grocery sellers
    // who both stock "Sunflower Oil 1L" (a very normal, expected case —
    // that's the whole point of a shared catalog) end up with the exact
    // same itemId in their own separate menu_items docs. CartService
    // only matches by id, not (sellerId, id) — so without gating on
    // cartIsForThisSeller, a customer with SELLER B's items still in
    // their cart, now browsing SELLER A's page, would see B's quantity
    // shown against A's identical-id product, and the +/- buttons here
    // would silently edit B's cart entry instead of adding a new one
    // for A. Once the cart genuinely belongs to a different seller,
    // every item on THIS seller's page is correctly "not yet in cart."
    final inCartQty = cartIsForThisSeller
        ? _cart.items.where((i) => i.id == id).fold<int>(0, (s, i) => s + i.quantity)
        : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _teal.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 14)),
                if (unit.isNotEmpty) Text(unit, style: GoogleFonts.outfit(color: _muted, fontSize: 11)),
                const SizedBox(height: 4),
                Text('₹${price.toStringAsFixed(0)}', style: GoogleFonts.outfit(color: _teal, fontWeight: FontWeight.w800, fontSize: 14)),
                if (outOfStock)
                  Text('Out of stock', style: GoogleFonts.outfit(color: _red, fontSize: 11, fontWeight: FontWeight.w700))
                else if (stock != null && stock <= 3)
                  Text('Only $stock left', style: GoogleFonts.outfit(color: Colors.orange, fontSize: 11)),
              ],
            ),
          ),
          if (!outOfStock)
            inCartQty > 0
                ? Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: _teal),
                        onPressed: () => _cart.updateQuantity(id, inCartQty - 1),
                      ),
                      Text('$inCartQty', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: _teal),
                        onPressed: () => _cart.updateQuantity(id, inCartQty + 1),
                      ),
                    ],
                  )
                : OutlinedButton(
                    onPressed: () => _addToCart(product),
                    style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal)),
                    child: const Text('Add'),
                  ),
        ],
      ),
    );
  }
}
