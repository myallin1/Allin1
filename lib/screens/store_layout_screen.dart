// ================================================================
// store_layout_screen.dart — Instamart-style Split Store UI
// Premium Dark/Pink theme — NJ TECH Super App — May 2026
// ================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'order_tracking_screen.dart'; // Task 3

// ── Brand tokens (mirrors dashboard) ─────────────────────────────
const _kBg = Color(0xFF0D0B1A);
const _kPink = Color(0xFFFF4FA3);
const _kPinkD = Color(0xFFBE2A7A);
const _kText = Color(0xFFFFFFFF);
const _kMuted = Color(0xFF7A7890);
const _kCard = Color(0xFF1C1929);
const _kBorder = Color(0xFF2E2845);

// ── Data models ──────────────────────────────────────────────────
class _Category {
  final String id, label;
  final IconData icon;
  const _Category(this.id, this.label, this.icon);
}

class _Product {
  final String name, imageUrl, tag;
  final double price;
  const _Product(this.name, this.imageUrl, this.tag, this.price);
}

// ── Food categories & products ───────────────────────────────────
const _foodCats = [
  _Category('biriyani', 'Biriyani', Icons.rice_bowl_rounded),
  _Category('burger', 'Burgers', Icons.lunch_dining_rounded),
  _Category('pizza', 'Pizza', Icons.local_pizza_rounded),
  _Category('rolls', 'Rolls', Icons.wrap_text_rounded),
  _Category('desserts', 'Desserts', Icons.icecream_rounded),
  _Category('drinks', 'Drinks', Icons.local_drink_rounded),
];

const _groceryCats = [
  _Category('vegetables', 'Vegetables', Icons.eco_rounded),
  _Category('fruits', 'Fruits', Icons.apple_rounded),
  _Category('dairy', 'Dairy', Icons.water_drop_rounded),
  _Category('snacks', 'Snacks', Icons.cookie_rounded),
  _Category('grains', 'Grains', Icons.grain_rounded),
  _Category('cooldrinks', 'Cool Drinks', Icons.local_bar_rounded),
  _Category('beverages', 'Beverages', Icons.emoji_food_beverage_rounded),
];

const _products = <String, List<_Product>>{
  // ── Food ──
  'biriyani': [
    _Product(
      'Chicken Biriyani',
      'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=400',
      'BESTSELLER',
      189,
    ),
    _Product(
      'Mutton Biriyani',
      'https://images.unsplash.com/photo-1589302168068-964664d93dc0?w=400',
      'SPICY🌶',
      249,
    ),
    _Product(
      'Veg Dum Biriyani',
      'https://images.unsplash.com/photo-1598515214211-89d3c73ae83b?w=400',
      'PURE VEG',
      149,
    ),
    _Product(
      'Egg Biriyani',
      'https://images.unsplash.com/photo-1633945274405-b6c8069047b0?w=400',
      'NEW',
      169,
    ),
  ],
  'burger': [
    _Product(
      'Crispy Chicken Burger',
      'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=400',
      'POPULAR',
      129,
    ),
    _Product(
      'Double Patty',
      'https://images.unsplash.com/photo-1553979459-d2229ba7433b?w=400',
      'LOADED',
      179,
    ),
    _Product(
      'Veggie Delight',
      'https://images.unsplash.com/photo-1520072959219-c595dc870360?w=400',
      'PURE VEG',
      99,
    ),
    _Product(
      'BBQ Bacon',
      'https://images.unsplash.com/photo-1554520735-0a6b8b6ce8b7?w=400',
      'SPECIAL',
      199,
    ),
  ],
  'pizza': [
    _Product(
      'Margherita',
      'https://images.unsplash.com/photo-1574071318508-1cdbab80d002?w=400',
      'CLASSIC',
      199,
    ),
    _Product(
      'Pepperoni',
      'https://images.unsplash.com/photo-1628840042765-356cda07504e?w=400',
      'POPULAR',
      249,
    ),
    _Product(
      'BBQ Chicken',
      'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=400',
      'SMOKY',
      269,
    ),
    _Product(
      'Veggie Supreme',
      'https://images.unsplash.com/photo-1571997478779-2adcbbe9ab2f?w=400',
      'VEG',
      219,
    ),
  ],
  'rolls': [
    _Product(
      'Chicken Kathi Roll',
      'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=400',
      'HOT',
      89,
    ),
    _Product(
      'Paneer Roll',
      'https://images.unsplash.com/photo-1600335895229-6e75511892c8?w=400',
      'VEG',
      79,
    ),
    _Product(
      'Egg Roll',
      'https://images.unsplash.com/photo-1565557623262-b51c2513a641?w=400',
      'CLASSIC',
      69,
    ),
    _Product(
      'Seekh Kabab Roll',
      'https://images.unsplash.com/photo-1561043433-aaf687c4cf04?w=400',
      'SMOKY',
      109,
    ),
  ],
  'desserts': [
    _Product(
      'Gulab Jamun',
      'https://images.unsplash.com/photo-1666387965467-cdddfbb0b5b9?w=400',
      'SWEET',
      59,
    ),
    _Product(
      'Ice Cream Sundae',
      'https://images.unsplash.com/photo-1563805042-7684c019e1cb?w=400',
      'COLD',
      99,
    ),
    _Product(
      'Brownie',
      'https://images.unsplash.com/photo-1606313564200-e75d5e30476c?w=400',
      'FUDGY',
      79,
    ),
    _Product(
      'Rasgulla',
      'https://images.unsplash.com/photo-1666636543970-c3e5e2c5e8a4?w=400',
      'SOFT',
      49,
    ),
  ],
  'drinks': [
    _Product(
      'Mango Lassi',
      'https://images.unsplash.com/photo-1553361371-9b22f78e8b1d?w=600&q=90',
      'FRESH',
      59,
    ),
    _Product(
      'Cold Coffee',
      'https://images.unsplash.com/photo-1568649929103-28ffbefaca1e?w=600&q=90',
      'CHILLED',
      79,
    ),
    _Product(
      'Fresh Lime Soda',
      'https://images.unsplash.com/photo-1556679343-c7306c1976bc?w=600&q=90',
      'TANGY',
      49,
    ),
    _Product(
      'Watermelon Juice',
      'https://images.unsplash.com/photo-1587049352846-4a222e784d38?w=600&q=90',
      'SUMMER',
      55,
    ),
    _Product(
      'Rose Milk',
      'https://images.unsplash.com/photo-1514362545857-3bc16c4c7d1b?w=600&q=90',
      'SWEET',
      45,
    ),
    _Product(
      'Tender Coconut',
      'https://images.unsplash.com/photo-1544145945-f90425340c7e?w=600&q=90',
      'NATURAL',
      60,
    ),
  ],
  // ── Grocery ──
  'vegetables': [
    _Product(
      'Tomatoes 1kg',
      'https://images.unsplash.com/photo-1546470427-e5380b53f0de?w=400',
      'FRESH',
      35,
    ),
    _Product(
      'Spinach 500g',
      'https://images.unsplash.com/photo-1576045057995-568f588f82fb?w=400',
      'ORGANIC',
      25,
    ),
    _Product(
      'Carrots 1kg',
      'https://images.unsplash.com/photo-1598170845058-32b9d6a5da37?w=400',
      'FARM',
      40,
    ),
    _Product(
      'Onion 2kg',
      'https://images.unsplash.com/photo-1518977676601-b53f82aba655?w=400',
      'LOCAL',
      55,
    ),
  ],
  'fruits': [
    _Product(
      'Mango 1kg',
      'https://images.unsplash.com/photo-1553279768-865429fa0078?w=400',
      'ALPHONSO',
      120,
    ),
    _Product(
      'Banana Dozen',
      'https://images.unsplash.com/photo-1571771894821-ce9b6c11b08e?w=400',
      'FRESH',
      45,
    ),
    _Product(
      'Apple 1kg',
      'https://images.unsplash.com/photo-1567306226416-28f0efdc88ce?w=400',
      'KASHMIR',
      160,
    ),
    _Product(
      'Grapes 500g',
      'https://images.unsplash.com/photo-1537640538966-79f369143f8f?w=400',
      'SEEDLESS',
      75,
    ),
  ],
  'dairy': [
    _Product(
      'Full Cream Milk 1L',
      'https://images.unsplash.com/photo-1550583724-b2692b85b150?w=400',
      'FRESH',
      62,
    ),
    _Product(
      'Paneer 200g',
      'https://images.unsplash.com/photo-1631452180539-96aca7d48617?w=400',
      'SOFT',
      85,
    ),
    _Product(
      'Curd 400g',
      'https://images.unsplash.com/photo-1488477181946-6428a0291777?w=400',
      'PROBIOTIC',
      40,
    ),
    _Product(
      'Butter 100g',
      'https://images.unsplash.com/photo-1589985270826-4b7bb135bc9d?w=400',
      'CREAMY',
      55,
    ),
  ],
  'snacks': [
    _Product(
      'Lays Chips',
      'https://images.unsplash.com/photo-1566478989037-eec170784d0b?w=400',
      'CRISPY',
      30,
    ),
    _Product(
      'Roasted Peanuts',
      'https://images.unsplash.com/photo-1567529684892-09290a1b2d05?w=400',
      'HEALTHY',
      45,
    ),
    _Product(
      'Dark Chocolate',
      'https://images.unsplash.com/photo-1549007994-cb92caebd54b?w=400',
      '70% COCOA',
      99,
    ),
    _Product(
      'Trail Mix',
      'https://images.unsplash.com/photo-1612257999756-4e3f7e1c5282?w=400',
      'ENERGY',
      79,
    ),
  ],
  'grains': [
    _Product(
      'Basmati Rice 5kg',
      'https://images.unsplash.com/photo-1586201375761-83865001e31c?w=400',
      'PREMIUM',
      320,
    ),
    _Product(
      'Atta 5kg',
      'https://images.unsplash.com/photo-1574323347407-f5e1ad6d020b?w=400',
      'WHOLE WHEAT',
      220,
    ),
    _Product(
      'Toor Dal 1kg',
      'https://images.unsplash.com/photo-1585032226651-759b368d7246?w=400',
      'ORGANIC',
      110,
    ),
    _Product(
      'Poha 500g',
      'https://images.unsplash.com/photo-1559181567-c3190ca9be5b?w=400',
      'THIN',
      35,
    ),
  ],
  // Task 2: Ultra-premium Cool Drinks & Beverages category
  'cooldrinks': [
    _Product(
      'Coca-Cola Can',
      'https://images.unsplash.com/photo-1554866585-cd94860890b7?w=600&q=90',
      'CHILLED❄️',
      40,
    ),
    _Product(
      'Sprite Can',
      'https://images.unsplash.com/photo-1625772299848-391b6a87d7b3?w=600&q=90',
      'REFRESHING',
      40,
    ),
    _Product(
      'Pepsi 750ml',
      'https://images.unsplash.com/photo-1503235930437-8c6293ba41f5?w=600&q=90',
      'CLASSIC',
      55,
    ),
    _Product(
      'Red Bull 250ml',
      'https://images.unsplash.com/photo-1613471550707-5bae795d56ff?w=600&q=90',
      'ENERGY⚡',
      110,
    ),
    _Product(
      'Iced Lemonade',
      'https://images.unsplash.com/photo-1523677011781-c91d1bbe2f9e?w=600&q=90',
      'FRESH',
      45,
    ),
    _Product(
      'Premium Mocktail',
      'https://images.unsplash.com/photo-1609951651556-5334e2706168?w=600&q=90',
      'PREMIUM',
      89,
    ),
    _Product(
      'Mango Frooti',
      'https://images.unsplash.com/photo-1546173159-315724a31696?w=600&q=90',
      'TROPICAL',
      35,
    ),
    _Product(
      'Limca 300ml',
      'https://images.unsplash.com/photo-1592194996308-7b43878e84a6?w=600&q=90',
      'TANGY',
      30,
    ),
  ],
  'beverages': [
    _Product(
      'Green Tea 25 bags',
      'https://images.unsplash.com/photo-1556679343-c7306c1976bc?w=600&q=90',
      'ANTIOXIDANT',
      120,
    ),
    _Product(
      'Fresh Orange Juice',
      'https://images.unsplash.com/photo-1621506289937-a8e4df240d0b?w=600&q=90',
      '100% NATURAL',
      99,
    ),
    _Product(
      'Tender Coconut Water',
      'https://images.unsplash.com/photo-1526364302788-5a69d90c4b14?w=600&q=90',
      'TENDER',
      45,
    ),
    _Product(
      'Protein Shake',
      'https://images.unsplash.com/photo-1533139502658-0198f920d8e8?w=600&q=90',
      'MUSCLE',
      199,
    ),
    _Product(
      'Cold Press Juice',
      'https://images.unsplash.com/photo-1610970881699-44a5587cabec?w=600&q=90',
      'DETOX',
      149,
    ),
    _Product(
      'Barley Water',
      'https://images.unsplash.com/photo-1544145945-f90425340c7e?w=600&q=90',
      'COOLING',
      55,
    ),
  ],
};

// ================================================================
// StoreLayoutScreen
// ================================================================
class StoreLayoutScreen extends StatefulWidget {
  final String storeType; // 'food' | 'grocery'
  const StoreLayoutScreen({required this.storeType, super.key});

  @override
  State<StoreLayoutScreen> createState() => _StoreLayoutScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('storeType', storeType));
  }
}

class _StoreLayoutScreenState extends State<StoreLayoutScreen> {
  late String _selectedCatId;
  final Map<String, int> _cart = {};

  List<_Category> get _cats =>
      widget.storeType == 'food' ? _foodCats : _groceryCats;

  List<_Product> get _currentProducts => _products[_selectedCatId] ?? [];

  String get _title =>
      widget.storeType == 'food' ? '🍛 Food Delivery' : '🛒 Grocery Store';

  int get _cartCount => _cart.values.fold(0, (a, b) => a + b);

  @override
  void initState() {
    super.initState();
    _selectedCatId = _cats.first.id;
  }

  void _addToCart(String name) =>
      setState(() => _cart[name] = (_cart[name] ?? 0) + 1);

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: _kBg,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCategorySidebar(),
                Expanded(child: _buildProductGrid()),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _cartCount > 0 ? _buildCartBar() : null,
    );
  }

  // ── App header ─────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kPink, _kPinkD],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Fast delivery · Premium quality',
                      style: GoogleFonts.outfit(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // Cart badge
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.shopping_bag_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  if (_cartCount > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$_cartCount',
                            style: const TextStyle(
                              color: _kPink,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Left category sidebar ───────────────────────────────────────
  Widget _buildCategorySidebar() {
    return Container(
      width: 90,
      decoration: const BoxDecoration(
        color: _kCard,
        border: Border(right: BorderSide(color: _kBorder)),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _cats.length,
        itemBuilder: (_, i) {
          final cat = _cats[i];
          final selected = cat.id == _selectedCatId;
          return GestureDetector(
            onTap: () => setState(() => _selectedCatId = cat.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? _kPink.withValues(alpha: 0.13)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: selected
                    ? Border.all(
                        color: _kPink.withValues(alpha: 0.45),
                        width: 1.5,
                      )
                    : null,
              ),
              child: Column(
                children: [
                  // Premium icon container
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? _kPink.withValues(alpha: 0.18)
                          : Colors.white.withValues(alpha: 0.04),
                      border: Border.all(
                        color:
                            selected ? _kPink.withValues(alpha: 0.7) : _kBorder,
                        width: selected ? 1.8 : 1,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: _kPink.withValues(alpha: 0.35),
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                            ]
                          : [],
                    ),
                    child: Icon(
                      cat.icon,
                      size: 22,
                      color: selected ? _kPink : _kMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cat.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                      color: selected ? _kPink : _kMuted,
                    ),
                  ),
                  if (selected)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      width: 18,
                      height: 2,
                      decoration: BoxDecoration(
                        color: _kPink,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Right product grid ──────────────────────────────────────────
  Widget _buildProductGrid() {
    final products = _currentProducts;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.04, 0),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: GridView.builder(
        key: ValueKey(_selectedCatId),
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: MediaQuery.of(context).size.width > 800
              ? 4
              : MediaQuery.of(context).size.width > 550
                  ? 3
                  : 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 230, // fixed height per card — image + text + button
        ),
        itemCount: products.length,
        itemBuilder: (_, i) => _ProductCard(
          product: products[i],
          qty: _cart[products[i].name] ?? 0,
          onAdd: () => _addToCart(products[i].name),
        ),
      ),
    );
  }

  // ── Floating cart bar ───────────────────────────────────────────
  Widget _buildCartBar() {
    final total = _cart.entries.fold<double>(0, (sum, e) {
      final p = _currentProducts.firstWhere(
        (p) => p.name == e.key,
        orElse: () => const _Product('', '', '', 0),
      );
      return sum + p.price * e.value;
    });
    // Task 3: tap → Order Tracking screen
    return GestureDetector(
      onTap: () {
        final cartItems = _cart.entries
            .map((e) {
              final p = _currentProducts.firstWhere(
                (p) => p.name == e.key,
                orElse: () => const _Product('', '', '', 0),
              );
              return CartItem(name: p.name, qty: e.value, price: p.price);
            })
            .where((ci) => ci.name.isNotEmpty)
            .toList();
        Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => OrderTrackingScreen(
              items: cartItems,
              total: total,
              storeType: widget.storeType,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_kPink, _kPinkD]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _kPink.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$_cartCount items',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Spacer(),
            Text(
              'View Cart',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '₹${total.toStringAsFixed(0)}',
              style: GoogleFonts.outfit(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white,
              size: 14,
            ),
          ],
        ),
      ), // end Container
    ); // end GestureDetector
  }
}

// ================================================================
// Product Card Widget
// ================================================================
class _ProductCard extends StatefulWidget {
  final _Product product;
  final int qty;
  final VoidCallback onAdd;
  const _ProductCard({
    required this.product,
    required this.qty,
    required this.onAdd,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<_Product>('product', product))
      ..add(IntProperty('qty', qty))
      ..add(ObjectFlagProperty<VoidCallback>.has('onAdd', onAdd));
  }
}

class _ProductCardState extends State<_ProductCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  void _tap() {
    _pulse.forward().then((_) => _pulse.reverse());
    widget.onAdd();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: _kPink.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: AspectRatio(
              aspectRatio: 1.45, // wide enough to show image without crop
              child: Stack(
                children: [
                  Image.network(
                    p.imageUrl,
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => ColoredBox(
                      color: _kCard,
                      child: Center(
                        child: Text(
                          widget.product.name[0],
                          style: const TextStyle(fontSize: 36, color: _kText),
                        ),
                      ),
                    ),
                  ),
                  // Tag badge
                  if (p.tag.isNotEmpty)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _kPink,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          p.tag,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Info
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
            child: Text(
              p.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _kText,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
            child: Text(
              '₹${p.price.toStringAsFixed(0)}',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _kPink,
              ),
            ),
          ),
          const Spacer(),
          // Add to cart button
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: ScaleTransition(
              scale: Tween<double>(begin: 1, end: 0.93).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeOut),
              ),
              child: GestureDetector(
                onTap: _tap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    gradient: widget.qty > 0
                        ? const LinearGradient(colors: [_kPink, _kPinkD])
                        : null,
                    color: widget.qty == 0 ? Colors.transparent : null,
                    border: widget.qty == 0
                        ? Border.all(
                            color: _kPink.withValues(alpha: 0.6),
                            width: 1.5,
                          )
                        : null,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: widget.qty > 0
                        ? [
                            BoxShadow(
                              color: _kPink.withValues(alpha: 0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.qty > 0) ...[
                        const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.qty} Added',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ] else ...[
                        const Icon(Icons.add_rounded, color: _kPink, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'Add',
                          style: GoogleFonts.outfit(
                            color: _kPink,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
