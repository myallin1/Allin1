// ================================================================
// SellerDetailScreen — Allin1 Super App
// Seller details with product menu and cart integration
// ================================================================

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/cart_service.dart';
import '../services/category_gateway_service.dart';
import '../widgets/product_card.dart';

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

    final item = CartItem(
      id: product['id'] as String? ?? '',
      sellerId: sellerId,
      name: product['name'] as String? ?? 'Unknown',
      price: (product['price'] as num?)?.toDouble() ?? 0.0,
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
            const SizedBox(height: 8),
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
class _CartBottomSheet extends StatelessWidget {
  final CartService cart;

  const _CartBottomSheet({required this.cart});

  @override
  Widget build(BuildContext context) {
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
                    onPressed: () {
                      // TODO: Navigate to checkout
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('🚧 Checkout coming soon!'),
                            backgroundColor: Color(0xFFFFBB00),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFBB00),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
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
    properties.add(DiagnosticsProperty<CartService>('cart', cart));
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
      ObjectFlagProperty<void Function(int)>.has('onUpdateQty', onUpdateQty),
    );
    properties.add(ObjectFlagProperty<VoidCallback>.has('onRemove', onRemove));
  }
}
