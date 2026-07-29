// ================================================================
// SellerDashboardScreen — Hotel Operational Hub
// Allin1 Super App — Food/E-commerce Pipeline
// Online/Offline toggle, active orders monitoring, menu management
// ================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/food_models.dart';
import '../services/food_seller_service.dart';
import 'seller_electronics_dashboard_screen.dart';
import 'seller_grocery_dashboard_screen.dart';
import 'seller_home_kitchen_menu_screen.dart';
import 'seller_vertical_picker_screen.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF0D0D18);
const Color _card = Color(0xFF141420);
const Color _card2 = Color(0xFF1A1A28);
const Color _teal = Color(0xFF11998E);
const Color _tealLight = Color(0xFF38EF7D);
const Color _green = Color(0xFF3DBA6F);
const Color _gold = Color(0xFFF5C542);
const Color _red = Color(0xFFFF5252);
const Color _orange = Color(0xFFFF8A00);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);

class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  State<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends State<SellerDashboardScreen> {
  final FoodSellerService _service = FoodSellerService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isLoadingProfile = true;
  SellerModel? _seller;
  StreamSubscription<List<FoodOrderModel>>? _ordersSub;
  List<FoodOrderModel> _activeOrders = [];
  int _menuItemCount = 0;

  // FIX (root cause of "customer places order, seller never sees it"):
  // the customer-side checkout in seller_detail_screen.dart deliberately
  // writes catalog/menu food orders to `service_requests` (requestType
  // 'catalog_food_order') instead of `food_orders`, to reuse the
  // existing hero-dispatch broadcast mechanism for delivery. But this
  // dashboard only ever listened to `food_orders` — so those orders
  // were being created successfully and dispatched to heroes, but the
  // SELLER (who needs to actually prepare the food) had no visibility
  // into them at all. Added a second, read-only stream here so sellers
  // can at least see what's been ordered from them. Also required a
  // Firestore rule fix — service_requests read previously had no
  // clause granting the seller (details.sellerId) access; see
  // firestore.rules.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _catalogOrdersSub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _catalogOrders = [];

  // FIX (root cause of the seller dashboard sometimes getting stuck
  // showing nothing after registration/login): _loadProfile() used to
  // read `_auth.currentUser?.uid` exactly ONCE, and if Firebase Auth's
  // session hadn't finished rehydrating yet (a real race right after a
  // fresh sign-in, especially coming out of a slow/COOP-interrupted
  // Google Sign-In popup on web), `uid` was null and this just
  // `return`ed — leaving `_isLoadingProfile` stuck at `true` forever,
  // with no retry and no listener for auth becoming ready later. Now
  // listens to authStateChanges() so a delayed auth rehydration is
  // picked up automatically instead of stranding the screen.
  StreamSubscription<User?>? _authSub;
  bool _showRetryButton = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _authSub = _auth.authStateChanges().listen((user) {
      if (user != null && _seller == null && mounted) {
        _loadProfile();
      }
    });
    // Safety net: if nothing has resolved after 8 seconds (auth never
    // became ready, or a slow network), stop spinning silently forever
    // and give the seller a manual way out instead of a stuck screen.
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && _isLoadingProfile) {
        setState(() => _showRetryButton = true);
      }
    });
  }

  Future<void> _loadProfile() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      // Don't leave the spinner stuck forever — authStateChanges()
      // above will call _loadProfile() again the moment a session
      // becomes available. If it never does (genuinely signed out),
      // _isLoadingProfile stays true and the retry button in build()'s
      // timeout fallback (see below) lets the seller recover manually
      // instead of being stuck on a blank/spinner screen indefinitely.
      return;
    }

    try {
      final seller = await _service.getSeller(uid);
      if (!mounted) return;

      if (seller == null) {
        // Brand-new seller, no profile yet — let them pick which
        // vertical (Hotel/Grocery/Electronics) they're registering as
        // before any onboarding form. Was a direct push to
        // SellerOnboardingScreen (Hotel-only) before verticals existed.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
              builder: (_) => const SellerVerticalPickerScreen()),
        );
        return;
      }

      // A seller already registered under a non-Hotel vertical (picked
      // Grocery/Electronics during onboarding) belongs on that
      // vertical's own dashboard, not this Hotel-shaped one — this
      // screen's order/menu logic below is entirely food/hotel-specific
      // and doesn't apply to them. Hotel (and anyone from before
      // verticals existed, who defaults to 'hotel') falls through and
      // keeps using this screen exactly as it always has.
      if (seller.businessVertical == 'grocery') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
              builder: (_) => const SellerGroceryDashboardScreen()),
        );
        return;
      }
      if (seller.businessVertical == 'electronics') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
              builder: (_) => const SellerElectronicsDashboardScreen()),
        );
        return;
      }

      setState(() {
        _seller = seller;
        _isLoadingProfile = false;
      });

      _listenToOrders(uid);
      _listenToCatalogOrders(uid);
      _loadMenuItemCount(uid);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingProfile = false);
      }
    }
  }

  void _listenToOrders(String sellerId) {
    _ordersSub = _service.listenToIncomingOrders(sellerId).listen(
      (List<FoodOrderModel> orders) {
        if (mounted) {
          setState(() => _activeOrders = orders);
        }
      },
    );
  }

  // See the FIX comment near _catalogOrders above — this is the
  // missing piece that let orders vanish for the seller. Equality-only
  // filters (requestType + details.sellerId + status whereIn), no
  // orderBy, so no composite index is needed.
  void _listenToCatalogOrders(String sellerId) {
    _catalogOrdersSub = FirebaseFirestore.instance
        .collection('service_requests')
        .where('requestType', isEqualTo: 'catalog_food_order')
        .where('details.sellerId', isEqualTo: sellerId)
        .where('status', whereIn: [
          'pending',
          'admin_review',
          'hero_assigned',
          'in_progress',
          'nearing_completion',
        ])
        .snapshots()
        .listen((snap) {
      if (mounted) {
        setState(() => _catalogOrders = snap.docs);
      }
    }, onError: (Object e) {
      debugPrint('[SellerDashboard] Catalog orders listener error: $e');
    });
  }

  Future<void> _loadMenuItemCount(String sellerId) async {
    try {
      final items = await _service.getAvailableMenuItems(sellerId);
      if (mounted) {
        setState(() => _menuItemCount = items.length);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _ordersSub?.cancel();
    _catalogOrdersSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _toggleOnlineStatus() async {
    if (_seller == null) return;
    final newStatus = !_seller!.isOpen;
    try {
      await _service.updateSellerProfile(_seller!.id, {
        'isOpen': newStatus,
      });
      setState(() => _seller = _seller!.copyWith(isOpen: newStatus));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: $e')),
        );
      }
    }
  }

  Future<void> _acceptOrder(String orderId) async {
    try {
      await _service.updateOrderStatus(orderId, 'accepted');
      await _service.updateOrderStatus(orderId, 'preparing');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept order: $e')),
        );
      }
    }
  }

  Future<void> _markFoodReady(String orderId) async {
    try {
      await _service.updateOrderStatus(orderId, 'ready');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    }
  }

  Future<void> _navigateToMenuSetup() async {
    if (_seller == null) return;
    // FIX (per Nizam's request): every seller now authors their own
    // custom dishes (own photo + name + description + price) instead
    // of only 'home_made' sellers getting that and everyone else being
    // limited to SellerMenuSetupScreen's fixed admin-curated
    // toggle-price catalog. A brand-new seller with no menu items at
    // all previously had no way to actually put their own food in
    // front of customers unless the admin's preset catalog happened to
    // already contain their dishes — this screen (originally built
    // only for Home Made Foods) is now the one menu-authoring flow for
    // every seller subCategory. SellerMenuSetupScreen is kept around
    // (not deleted) in case it's wanted again later, just no longer
    // wired into this button.
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SellerHomeKitchenMenuScreen(
          sellerId: _seller!.id,
          title: 'My Menu',
          categoryName: _seller!.subCategory == 'home_made' ? 'Home Kitchen' : 'Menu',
        ),
      ),
    );
    await _loadMenuItemCount(_seller!.id);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingProfile) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: _showRetryButton
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_rounded, color: _muted, size: 40),
                    const SizedBox(height: 12),
                    Text('Taking longer than usual to load your shop.',
                        style: GoogleFonts.outfit(color: _text, fontSize: 13)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: _teal),
                      onPressed: () {
                        setState(() {
                          _showRetryButton = false;
                          _isLoadingProfile = true;
                        });
                        _loadProfile();
                      },
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                      label: const Text('Retry', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                )
              : const CircularProgressIndicator(color: _teal),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // FIX (back-button audit, per Nizam's request): unlike the
        // customer/hero/admin root shells, this screen has no tabs to
        // reset first — a single-page dashboard — so back here should
        // just confirm-exit, same as tab 0 does elsewhere. Previously
        // there was NO handling at all: Navigator.canPop()==false at
        // this root meant back fell straight through to the OS/browser
        // default action and the app closed instantly.
        final exit = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: _bg,
            title: const Text('Leave the app?',
                style: TextStyle(fontWeight: FontWeight.w700)),
            content: const Text('Close Allin1 Seller?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Yes', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (exit == true && context.mounted) SystemNavigator.pop();
      },
      child: Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(
          _seller?.name ?? 'Seller Dashboard',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w600,
            color: _text,
          ),
        ),
        backgroundColor: _surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book, color: _muted),
            tooltip: 'Manage Menu',
            onPressed: _navigateToMenuSetup,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: _muted),
            onPressed: () {
              if (_seller != null) {
                _loadMenuItemCount(_seller!.id);
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (_seller != null) {
            await _loadMenuItemCount(_seller!.id);
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildOnlineToggle(),
              const SizedBox(height: 16),
              _buildStatsRow(),
              const SizedBox(height: 20),
              _buildActiveOrders(),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildOnlineToggle() {
    if (_seller == null) return const SizedBox.shrink();
    final isOpen = _seller!.isOpen;

    return GestureDetector(
      onTap: _toggleOnlineStatus,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isOpen ? [_teal, const Color(0xFF0D7A6E)] : [_card2, _card],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isOpen ? _tealLight : _border,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isOpen ? Colors.white.withValues(alpha: 0.2) : _card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isOpen ? Icons.store : Icons.store_mall_directory_outlined,
                color: isOpen ? Colors.white : _muted,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOpen ? 'Shop is Open' : 'Shop is Closed',
                    style: GoogleFonts.outfit(
                      color: isOpen ? Colors.white : _muted,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isOpen
                        ? 'Customers can see your menu & place orders'
                        : 'Tap to open and start receiving orders',
                    style: GoogleFonts.outfit(
                      color:
                          isOpen ? Colors.white.withValues(alpha: 0.8) : _muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 56,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                color: isOpen ? Colors.white : _card2,
                border: Border.all(
                  color: isOpen ? Colors.white : _border,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 250),
                    alignment:
                        isOpen ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.all(3),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isOpen ? _teal : _muted,
                      ),
                      child: Icon(
                        isOpen ? Icons.power : Icons.power_off,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _buildStatCard(
          icon: Icons.restaurant_menu,
          label: 'Menu Items',
          value: '$_menuItemCount',
          color: _teal,
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          icon: Icons.receipt_long,
          label: 'Active Orders',
          value: '${_activeOrders.length}',
          color: _activeOrders.isNotEmpty ? _orange : _muted,
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          icon: Icons.star,
          label: 'Rating',
          value: (_seller?.rating ?? 0).toStringAsFixed(1),
          color: _gold,
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.outfit(
                color: _text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.outfit(color: _muted, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveOrders() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Incoming Orders',
              style: GoogleFonts.outfit(
                color: _text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_activeOrders.isNotEmpty)
              Text(
                '${_activeOrders.length} active',
                style: GoogleFonts.outfit(color: _orange, fontSize: 12),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_activeOrders.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: Column(
              children: [
                Icon(Icons.inbox_outlined,
                    size: 48, color: _muted.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Text(
                  'No incoming orders',
                  style: GoogleFonts.outfit(color: _muted, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  (_seller?.isOpen ?? false) == true
                      ? 'Waiting for customers to place orders...'
                      : 'Open your shop to start receiving orders',
                  style: GoogleFonts.outfit(
                    color: _muted.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          )
        else
          ..._activeOrders.map(_buildOrderCard),
        if (_catalogOrders.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'App Orders (${_catalogOrders.length})',
            style: GoogleFonts.outfit(
              color: _text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Placed via your shop page — a hero will pick these up for delivery.',
            style: GoogleFonts.outfit(color: _muted, fontSize: 11.5),
          ),
          const SizedBox(height: 12),
          ..._catalogOrders.map(_buildCatalogOrderCard),
        ],
      ],
    );
  }

  Widget _buildCatalogOrderCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final details = (data['details'] as Map<String, dynamic>?) ?? {};
    final customerName = (data['customerName'] as String?) ?? 'Customer';
    final items = (details['items'] as List<dynamic>?) ?? [];
    final subtotal = (details['subtotal'] as num?)?.toDouble() ?? 0;
    final status = (data['status'] as String?) ?? 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(customerName,
                  style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 13)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(status,
                    style: GoogleFonts.outfit(color: _orange, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final item in items)
            if (item is Map)
              Text(
                '${item['quantity'] ?? 1} × ${item['name'] ?? 'Item'}',
                style: GoogleFonts.outfit(color: _muted, fontSize: 12),
              ),
          const SizedBox(height: 6),
          Text('₹${subtotal.toStringAsFixed(0)}',
              style: GoogleFonts.outfit(color: _gold, fontWeight: FontWeight.w800, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildOrderCard(FoodOrderModel order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
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
                child: const Icon(Icons.receipt, color: _teal, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order #${order.orderId.length > 8 ? order.orderId.substring(0, 8).toUpperCase() : order.orderId}',
                      style: GoogleFonts.outfit(
                        color: _text,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      order.statusDisplay,
                      style: GoogleFonts.outfit(
                        color: _statusColor(order.status),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '₹${order.totalAmount.toStringAsFixed(0)}',
                style: GoogleFonts.outfit(
                  color: _gold,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...order.items.take(3).map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.circle, size: 4, color: _muted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${(item.quantity ?? 1)}x ${(item.name ?? 'Unknown')}',
                          style:
                              GoogleFonts.outfit(color: _muted, fontSize: 13),
                        ),
                      ),
                      Text(
                        '₹${(item.totalPrice ?? 0).toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(color: _muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
          if (order.items.length > 3)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                '+${order.items.length - 3} more items',
                style: GoogleFonts.outfit(color: _muted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.person_outline, size: 14, color: _muted),
              const SizedBox(width: 4),
              Text(
                order.customerName ?? 'Customer',
                style: GoogleFonts.outfit(color: _muted, fontSize: 12),
              ),
              if (order.estimatedPrepTimeMin != null) ...[
                const Spacer(),
                const Icon(Icons.timer_outlined, size: 14, color: _orange),
                const SizedBox(width: 4),
                Text(
                  '${order.estimatedPrepTimeMin} min',
                  style: GoogleFonts.outfit(color: _orange, fontSize: 12),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (order.status == 'placed')
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton.icon(
                onPressed: () => _acceptOrder(order.orderId),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(
                  'Accept Order & Start Preparing',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          if (order.status == 'preparing')
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton.icon(
                onPressed: () => _markFoodReady(order.orderId),
                icon: const Icon(Icons.food_bank_outlined, size: 18),
                label: Text(
                  'Mark as Food Ready',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          if (order.status == 'ready')
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.delivery_dining, color: _gold, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Waiting for Hero to pick up',
                      style: GoogleFonts.outfit(
                        color: _gold,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'placed':
        return _tealLight;
      case 'accepted':
        return Colors.blueAccent;
      case 'preparing':
        return _orange;
      case 'ready':
        return _gold;
      case 'pickedUp':
        return _green;
      case 'delivered':
        return _muted;
      case 'cancelled':
        return _red;
      default:
        return _muted;
    }
  }
}
