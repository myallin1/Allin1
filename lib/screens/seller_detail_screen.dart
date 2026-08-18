// ================================================================
// SellerDetailScreen — Allin1 Super App
// Seller details with product menu and cart integration
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// GUEST MODE (Aug 11 2026): requireRealAuth() guard on the submit action.
import '../services/auth_prompt_service.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../services/category_gateway_service.dart';
import '../services/service_request_service.dart';
import '../widgets/product_card.dart';
import 'food_checkout_screen.dart';
import 'service_request_tracking_screen.dart';

/// Reusing service_requests (rather than a separate food_orders
/// hero-assignment pipeline) — see the decision in the seller
/// home-kitchen / catalog-checkout work: same proven broadcast-to-all-
/// eligible-heroes mechanism as hero_booking / grocery_order /
/// custom_food_order, no separate admin dispatch or tracking screen
/// needed to build.
const String kCatalogFoodOrderRequestType = 'catalog_food_order';

class SellerDetailScreen extends StatefulWidget {
  final Map<String, dynamic> seller;
  final Category category;

  const SellerDetailScreen({
    required this.seller,
    required this.category,
    super.key,
  });

  @override
  State<SellerDetailScreen> createState() => _SellerDetailScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Map<String, dynamic>>('seller', seller));
    properties.add(EnumProperty<Category>('category', category));
  }
}

class _SellerDetailScreenState extends State<SellerDetailScreen> {
  List<Map<String, dynamic>> _products = [];
  bool _isLoading = true;
  String? _error;
  final CartService _cart = CartService();
  int _cartItemCount = 0;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _setupCartListener();
  }

  void _setupCartListener() {
    _cart.cartStream.listen((items) {
      if (mounted) {
        setState(() {
          _cartItemCount = items.fold(0, (sum, item) => sum + item.quantity);
        });
      }
    });
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final sellerId = widget.seller['id'] as String? ?? '';
      final products = await CategoryGatewayService()
          .loadSellerProducts(sellerId, widget.category);

      if (mounted) {
        setState(() {
          _products = products;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _getCategoryConfig();
    final isOpen = _isOpen();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A12),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            _buildSliverAppBar(config, isOpen),
          ];
        },
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFFFBB00)),
              )
            : _error != null
                ? _buildErrorState()
                : _products.isEmpty
                    ? _buildEmptyState()
                    : _buildProductList(),
      ),
      floatingActionButton: _cartItemCount > 0 ? _buildCartButton() : null,
    );
  }

  // ── Sliver App Bar ──────────────────────────────────────────
  Widget _buildSliverAppBar(_CategoryConfig config, bool isOpen) {
    final shopName = widget.seller['shopName'] as String? ?? 'Unknown Shop';
    final rating = widget.seller['rating'] as num? ?? 0;

    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: config.bgColor,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Shop banner gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    config.bgColor,
                    config.bgColor.withValues(alpha: 0.7),
                  ],
                ),
              ),
            ),
            // Shop info
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shopName,
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFEEEEF5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('⭐', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Text(
                        rating.toStringAsFixed(1),
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          color: const Color(0xFFEEEEF5),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isOpen
                              ? const Color(0xFF00C853).withValues(alpha: 0.2)
                              : const Color(0xFFFF5252).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isOpen ? 'Open' : 'Closed',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: isOpen
                                ? const Color(0xFF00C853)
                                : const Color(0xFFFF5252),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Product List ────────────────────────────────────────────
  Widget _buildProductList() {
    final productsByCategory = _groupProductsByCategory();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: productsByCategory.length,
      itemBuilder: (context, i) {
        final category = productsByCategory.keys.elementAt(i);
        final products = productsByCategory[category]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category Header
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                category,
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFEEEEF5),
                ),
              ),
            ),
            // Products Grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: products.length,
              itemBuilder: (context, j) {
                return ProductCard(
                  product: products[j],
                  onAddToCart: () => _addToCart(products[j]),
                );
              },
            ),
            const SizedBox(height: 80), // Space for FAB
          ],
        );
      },
    );
  }

  // ── Group Products by Category ──────────────────────────────
  Map<String, List<Map<String, dynamic>>> _groupProductsByCategory() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final product in _products) {
      final category = product['category'] as String? ?? 'All Items';
      grouped.putIfAbsent(category, () => []);
      grouped[category]!.add(product);
    }

    return grouped;
  }

  // ── Add to Cart ─────────────────────────────────────────────
  void _addToCart(Map<String, dynamic> product) {
    final sellerId = widget.seller['id'] as String? ?? '';
    final sellerName = widget.seller['shopName'] as String? ?? '';

    // Check cross-seller conflict
    if (_cart.hasCrossSellerConflict(sellerId)) {
      _showClearCartDialog(product, sellerId, sellerName);
      return;
    }

    // PHASE 3 (Aug 17 2026): charge the OFFER price when the seller has
    // set one. This is the load-bearing half of the offer feature — a
    // discount the customer can see but is not actually charged is worse
    // than no discount at all, because they find out at checkout.
    //
    // Guarded on `< base`, matching the seller-side validation, so a
    // malformed or stale discountedPrice can never RAISE the price.
    final basePrice = (product['price'] as num?)?.toDouble() ?? 0.0;
    final offer = (product['discountedPrice'] as num?)?.toDouble();
    final effectivePrice =
        (offer != null && offer > 0 && offer < basePrice) ? offer : basePrice;

    final item = CartItem(
      id: product['id'] as String? ?? '',
      sellerId: sellerId,
      name: product['name'] as String? ?? 'Unknown',
      price: effectivePrice,
      image: product['image'] as String?,
      category: product['category'] as String?,
    );

    _cart.addItem(item);
    _cart.setCurrentSeller(sellerId, sellerName);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${product['name']} added to cart!'),
          backgroundColor: const Color(0xFF00C853),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Clear Cart Dialog ───────────────────────────────────────
  void _showClearCartDialog(
    Map<String, dynamic> product,
    String sellerId,
    String sellerName,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          '🛒 Clear Cart?',
          style: TextStyle(
            color: Color(0xFFEEEEF5),
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Your cart has items from another shop. Clear existing cart to add items from $sellerName?',
          style: const TextStyle(color: Color(0xFF7777A0)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF7777A0)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5252),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              _cart.clear();
              _addToCart(product);
            },
            child: const Text(
              'Clear & Add',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ── Cart Button ─────────────────────────────────────────────
  Widget _buildCartButton() {
    return FloatingActionButton.extended(
      onPressed: _showCartBottomSheet,
      backgroundColor: const Color(0xFFFFBB00),
      icon: Stack(
        children: [
          const Icon(Icons.shopping_cart, color: Colors.black),
          if (_cartItemCount > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFFFF5252),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$_cartItemCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
      label: Text(
        '₹${_cart.subtotal.toStringAsFixed(0)}',
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ── Cart Bottom Sheet ───────────────────────────────────────
  void _showCartBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12121E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _CartBottomSheet(cart: _cart),
    );
  }

  // ── Error State ─────────────────────────────────────────────
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('❌', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              'Failed to load products',
              style: GoogleFonts.outfit(
                fontSize: 16,
                color: const Color(0xFFEEEEF5),
                fontWeight: FontWeight.w600,
              ),
            ),
            // FIX (Aug 17 2026 — "failed to load products nu red error
            // varuthu" and nobody could say WHY).
            //
            // CategoryGatewayService.loadSellerProducts() deliberately
            // rethrows instead of swallowing, precisely so a real
            // failure (permission-denied, missing index, offline) is
            // distinguishable from an empty menu — its own comment says
            // so. But this screen caught that error into `_error` and
            // then never displayed it, throwing away the one piece of
            // information the rethrow existed to deliver.
            //
            // Now shown. Firestore error strings name their own cause
            // ('permission-denied', 'failed-precondition: The query
            // requires an index'), so this turns a dead end into a
            // one-glance diagnosis for whoever is standing in the shop.
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 11.5,
                  height: 1.4,
                  color: const Color(0xFF9A9AB8),
                ),
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadProducts,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty State ─────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📦', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              'No products available',
              style: GoogleFonts.outfit(
                fontSize: 16,
                color: const Color(0xFFEEEEF5),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helper: Open/Closed ─────────────────────────────────────
  bool _isOpen() {
    final hours = widget.seller['hours'] as Map<String, dynamic>?;
    if (hours == null) return true;

    final now = DateTime.now();
    final currentTime = now.hour * 60 + now.minute;
    final openTime = hours['open'] as int?;
    final closeTime = hours['close'] as int?;

    if (openTime == null || closeTime == null) return true;
    return currentTime >= openTime && currentTime <= closeTime;
  }

  // ── Category Config ─────────────────────────────────────────
  _CategoryConfig _getCategoryConfig() {
    switch (widget.category) {
      case Category.food:
        return const _CategoryConfig(
          emoji: '🍔',
          bgColor: Color(0xFF1E0E0E),
        );
      case Category.grocery:
        return const _CategoryConfig(
          emoji: '🛒',
          bgColor: Color(0xFF0A1E0E),
        );
      case Category.tech:
        return const _CategoryConfig(
          emoji: '📱',
          bgColor: Color(0xFF10102A),
        );
      case Category.pharmacy:
        return const _CategoryConfig(
          emoji: '💊',
          bgColor: Color(0xFF1E1008),
        );
      default:
        return const _CategoryConfig(
          emoji: '🏪',
          bgColor: Color(0xFF1A1A2A),
        );
    }
  }
}

// ── Category Config ───────────────────────────────────────────
class _CategoryConfig {
  final String emoji;
  final Color bgColor;

  const _CategoryConfig({
    required this.emoji,
    required this.bgColor,
  });
}

// ── Cart Bottom Sheet ─────────────────────────────────────────
class _CartBottomSheet extends StatefulWidget {
  final CartService cart;

  const _CartBottomSheet({required this.cart});

  @override
  State<_CartBottomSheet> createState() => _CartBottomSheetState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<CartService>('cart', cart));
  }
}

class _CartBottomSheetState extends State<_CartBottomSheet> {
  bool _isPlacingOrder = false;

  Future<void> _checkout() async {
    final cart = widget.cart;
    if (cart.isEmpty || _isPlacingOrder) return;

    // GUEST MODE (Aug 11 2026): NOT in the original spec's list of nine
    // screens — found by grepping every createServiceRequest() call site
    // in lib/ rather than trusting the list. This is the catalog/menu
    // checkout ('catalog_food_order'), which writes to service_requests
    // exactly like the other order screens, so isRealUser() rejects it
    // from a guest too. Without this guard the seller's order simply
    // never arrives and nobody finds out why.
    if (!await requireRealAuth(
      context,
      reason: 'Sign in and this shop will start packing your order',
    )) {
      return;
    }
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        // GUEST MODE: was the harsh 0xFFFF5252 red.
        showSignInRequiredSnack(context, message: 'Sign in to place your order');
      }
      return;
    }

    // NEW (Aug 18 2026 — Nizam: "order book pannunathum udane order
    // aiduchu... namma food order form open agi... delevery details
    // nammakita ketu fill pannunathum, payment pannitu than order
    // confirm aganum"). Previously "Place Order" went straight from
    // this bottom sheet into the stock transaction + order creation
    // below with zero screens in between — no delivery address, no
    // payment step. FoodCheckoutScreen is the missing middle step: it
    // writes nothing itself, it only collects delivery details + a
    // payment decision and hands them back here. Everything below
    // (stock transaction, createServiceRequest, deferBroadcast, the
    // tracking-screen redirect) is completely unchanged — it now just
    // runs with real delivery/payment data instead of none at all.
    final itemsPreview = cart.items
        .map((item) => {
              'name': item.name,
              'quantity': item.quantity,
              'total': item.total,
            })
        .toList();
    final checkoutResult = await Navigator.push<FoodCheckoutResult>(
      context,
      MaterialPageRoute<FoodCheckoutResult>(
        builder: (_) => FoodCheckoutScreen(
          hotelName: cart.currentSellerName ?? 'Seller',
          items: itemsPreview,
          subtotal: cart.subtotal,
        ),
      ),
    );
    if (checkoutResult == null || !mounted) return; // customer backed out

    setState(() => _isPlacingOrder = true);
    try {
      final sellerId = cart.currentSellerId ?? '';
      final sellerName = cart.currentSellerName ?? 'Seller';
      
      // 1. Reserve stock via Transaction (Strict Concurrency Lock)
      final db = FirebaseFirestore.instance;
      await db.runTransaction((tx) async {
        final itemDocs = <String, DocumentSnapshot>{};
        
        // Read phase
        //
        // FIX (Aug 17 2026 seller-app audit — "seller app dummy mari
        // iruku"): this read `sellers/{id}/menu`, a subcollection that
        // DOES NOT EXIST. Menu items are written to
        // `sellers/{id}/menu_items` (FoodSellerService._menuItemsRef)
        // and displayed from `menu_items`
        // (CategoryGatewayService.loadSellerProducts, which carries its
        // own comment saying the codebase standardised on that name).
        // Only this checkout transaction was left on the old name, so
        // tx.get() always came back !exists and every single catalog
        // checkout threw 'Item ... not found' before an order could be
        // created. This one word was blocking the ENTIRE catalog order
        // pipeline — the seller's menu rendered fine, so it looked like
        // a dead "dummy" app rather than a broken write path.
        for (final item in cart.items) {
          final docRef = db
              .collection('sellers')
              .doc(sellerId)
              .collection('menu_items')
              .doc(item.id);
          final snap = await tx.get(docRef);
          if (!snap.exists) throw Exception('Item ${item.name} not found');
          itemDocs[item.id] = snap;
        }
        
        // Validation phase
        for (final item in cart.items) {
          final data = itemDocs[item.id]!.data() as Map<String, dynamic>;
          final isAvailable = data['isAvailable'] as bool? ?? true;
          final stockQuantity = (data['stockQuantity'] as num?)?.toInt();

          if (!isAvailable) {
            throw Exception('${item.name} is currently unavailable.');
          }
          if (stockQuantity != null && stockQuantity < item.quantity) {
            throw Exception('Only $stockQuantity ${item.name} left in stock.');
          }
        }

        // Write phase — DELIBERATELY REMOVED (Aug 17 2026 audit).
        //
        // This used to decrement stockQuantity on each menu item from
        // the CUSTOMER's session. That could never have worked:
        // firestore.rules:302 allows `update` on
        // sellers/{id}/menu_items/{itemId} only for isSellerOwner() or
        // isAdminAny(), so a customer's decrement is rejected with
        // permission-denied. Fixing the subcollection name above without
        // also removing this would simply have traded the old
        // 'Item not found' failure for a permission-denied one — the
        // checkout would still have been 100% broken.
        //
        // Not "fixed" by loosening the rule on purpose: letting any
        // signed-in customer write stock counts on someone else's shop
        // means one malicious account can zero out a hotel's entire menu.
        // Client-authoritative stock cannot be made safe without a
        // trusted server, and we are on the Spark plan (no Cloud
        // Functions), so the read-side validation above is kept (it still
        // blocks ordering an unavailable / insufficient-stock item) and
        // the seller stays the only writer of stock.
        //
        // Zero behavioural regression today: stockQuantity is never
        // populated by the dish editor UI, so it is null for every real
        // menu item and this loop was already a no-op in practice.
        // Seller-side stock entry is Phase 3 of the audit plan; when it
        // lands, decrement moves to the seller's own order-accept step.
      });

      // 2. Create the Order
      final itemsDetail = cart.items
          .map((item) => {
                'itemId': item.id,
                'name': item.name,
                'price': item.price,
                'quantity': item.quantity,
                'total': item.total,
              })
          .toList();

      // customerPhone/customerName now come from the checkout form the
      // customer just filled (FoodCheckoutScreen) rather than only
      // whatever Firebase Auth happened to have — same
      // resolveCustomerPhone() fallback kept for the rare case the form
      // field was left blank.
      final resolvedCustomerPhone = checkoutResult.customerPhone.isNotEmpty
          ? checkoutResult.customerPhone
          : await AuthService().resolveCustomerPhone(user);
      final requestId = await ServiceRequestService().createServiceRequest(
        // Aug 17 2026 seller audit: hold the hero ping until the hotel
        // marks the food ready. Previously heroes were pinged the
        // instant the customer paid, so a hero rode out and waited at
        // the counter for however long the cooking took.
        deferBroadcast: true,
        requestType: kCatalogFoodOrderRequestType,
        customerId: user.uid,
        customerName: checkoutResult.customerName,
        customerPhone: resolvedCustomerPhone,
        details: {
          'sellerId': sellerId,
          'sellerName': sellerName,
          'items': itemsDetail,
          'subtotal': cart.subtotal,
          // NEW (Aug 18 2026): catalog_food_order previously carried no
          // delivery address at all — a hero accepting it had nowhere
          // to navigate to. custom_hotel_order already has this shape
          // (deliveryAddress/lat/lng), matched here for consistency.
          'deliveryAddress': checkoutResult.address,
          if (checkoutResult.lat != null) 'deliveryLat': checkoutResult.lat,
          if (checkoutResult.lng != null) 'deliveryLng': checkoutResult.lng,
          'paymentMethod': checkoutResult.paymentMethod,
        },
      );

      cart.clear();

      if (!mounted) return;
      Navigator.pop(context); // close the cart bottom sheet
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ServiceRequestTrackingScreen(
            requestId: requestId,
            requestType: kCatalogFoodOrderRequestType,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to place order: $e'),
            backgroundColor: const Color(0xFFFF5252),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPlacingOrder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = widget.cart;
    return StreamBuilder<List<CartItem>>(
      stream: cart.cartStream,
      initialData: cart.items,
      builder: (context, snapshot) {
        final items = snapshot.data ?? [];

        return Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              // Header
              Row(
                children: [
                  const Text(
                    '🛒 Your Cart',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFEEEEF5),
                    ),
                  ),
                  const Spacer(),
                  if (items.isNotEmpty)
                    TextButton(
                      onPressed: cart.clear,
                      child: const Text(
                        'Clear All',
                        style: TextStyle(color: Color(0xFFFF5252)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Cart Items
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Text(
                          'Your cart is empty',
                          style: TextStyle(color: Color(0xFF7777A0)),
                        ),
                      )
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final item = items[i];
                          return _CartItemTile(
                            item: item,
                            onUpdateQty: (qty) =>
                                cart.updateQuantity(item.id, qty),
                            onRemove: () => cart.removeItem(item.id),
                          );
                        },
                      ),
              ),

              // Checkout Button
              if (items.isNotEmpty) ...[
                const Divider(color: Color(0xFF7777A0)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'Total:',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFFEEEEF5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '₹${cart.subtotal.toStringAsFixed(2)}',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        color: const Color(0xFFFFBB00),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isPlacingOrder ? null : _checkout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFBB00),
                      disabledBackgroundColor:
                          const Color(0xFFFFBB00).withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isPlacingOrder
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.black,),
                          )
                        : const Text(
                            'Proceed to Checkout',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<CartService>('cart', widget.cart));
  }
}

// ── Cart Item Tile ────────────────────────────────────────────
class _CartItemTile extends StatelessWidget {
  final CartItem item;
  final void Function(int) onUpdateQty;
  final VoidCallback onRemove;

  const _CartItemTile({
    required this.item,
    required this.onUpdateQty,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    color: Color(0xFFEEEEF5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${item.price.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Color(0xFFFFBB00),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          // Quantity Controls
          Row(
            children: [
              IconButton(
                onPressed: () => onUpdateQty(item.quantity - 1),
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                color: const Color(0xFF7777A0),
              ),
              Text(
                '${item.quantity}',
                style: const TextStyle(
                  color: Color(0xFFEEEEF5),
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                onPressed: () => onUpdateQty(item.quantity + 1),
                icon: const Icon(Icons.add_circle_outline, size: 20),
                color: const Color(0xFF7777A0),
              ),
            ],
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline, size: 20),
            color: const Color(0xFFFF5252),
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<CartItem>('item', item));
    properties.add(
        ObjectFlagProperty<void Function(int)>.has('onUpdateQty', onUpdateQty),);
    properties.add(ObjectFlagProperty<VoidCallback>.has('onRemove', onRemove));
  }
}
