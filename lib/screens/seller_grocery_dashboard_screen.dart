// ================================================================
// SellerGroceryDashboardScreen
//
// UPDATED (Sep 2026 — universal catalog build, reversing the earlier
// "broadcast-only, no catalog" decision documented below): a grocery
// seller can now ALSO run a real digital catalog — "My Products" lets
// them toggle items on from the shared master_catalog with their own
// price/stock, and this screen now lists incoming catalog_grocery_order
// orders exactly the way seller_dashboard_screen.dart already does for
// food, reusing the SAME advanceSellerStage/requestDeliveryBroadcast
// pipeline (generic, never food-specific to begin with).
//
// The original free-text broadcast flow (grocery_order_screen.dart ->
// requestType 'grocery_order', not tied to any specific seller) is
// UNCHANGED and untouched — this is a second, additive path for
// sellers who want to run a real catalog instead of relying on a hero
// to shop from an arbitrary store.
// ================================================================
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/food_models.dart';
import '../models/service_request_model.dart';
import '../services/app_minimizer_service.dart';
import '../services/db_usage_tracker.dart';
import '../services/food_seller_service.dart';
import '../services/service_request_service.dart';
import 'seller_grocery_products_screen.dart';

const Color _bg = Color(0xFFF7FAF8);
const Color _card = Color(0xFFFFFFFF);
const Color _teal = Color(0xFF11998E);
const Color _green = Color(0xFF2E9E63);
const Color _gold = Color(0xFFC79200);
const Color _orange = Color(0xFFE07A00);
const Color _text = Color(0xFF1A1A1A);
const Color _muted = Color(0xFF6B7280);
const Color _border = Color(0x1A11998E);
const Color _red = Color(0xFFD64545);

class SellerGroceryDashboardScreen extends StatefulWidget {
  const SellerGroceryDashboardScreen({super.key});

  @override
  State<SellerGroceryDashboardScreen> createState() =>
      _SellerGroceryDashboardScreenState();
}

class _SellerGroceryDashboardScreenState
    extends State<SellerGroceryDashboardScreen> {
  final FoodSellerService _service = FoodSellerService();
  SellerModel? _seller;
  bool _loading = true;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ordersSub;
  List<ServiceRequestModel> _orders = [];
  final Set<String> _busyRequestIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final seller = await _service.getSeller(uid);
    if (mounted) {
      setState(() {
        _seller = seller;
        _loading = false;
      });
    }
    if (seller != null) _listenToOrders(seller.id);
  }

  // Same equality-only + limit(50) shape as seller_dashboard_screen
  // .dart's own catalog listener — reuses the identical composite
  // index (requestType, details.sellerId, status, createdAt) already
  // deployed for that screen, since the field set matches exactly.
  //
  // FIX (audit pass, Sep 2026 — real leak): _load() is this screen's
  // RefreshIndicator.onRefresh, and _load() calls this method on every
  // pull-to-refresh. Without cancelling the PREVIOUS subscription
  // first, every refresh attached a brand-new .snapshots() listener on
  // top of the still-live old one — each one independently double-
  // counting DbUsageTracker reads and, since _ordersSub just gets
  // overwritten, only the LAST one is ever reachable to cancel in
  // dispose(). Every prior refresh's listener leaked for the lifetime
  // of the app process. seller_dashboard_screen.dart's own onRefresh
  // deliberately avoids this by never re-calling its listener-attaching
  // method on refresh — this fixes it at the root instead, so the
  // method is safe to call more than once regardless of caller.
  void _listenToOrders(String sellerId) {
    unawaited(_ordersSub?.cancel());
    _ordersSub = FirebaseFirestore.instance
        .collection('service_requests')
        .where('requestType', isEqualTo: 'catalog_grocery_order')
        .where('details.sellerId', isEqualTo: sellerId)
        .where('status', whereIn: [
          'pending',
          'admin_review',
          'hero_assigned',
          'in_progress',
          'nearing_completion',
        ],)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen((snap) {
      DbUsageTracker.instance.recordRead(snap.docs.length, 'seller_grocery_orders');
      final models = snap.docs.map((d) => ServiceRequestModel.fromFirestore(d.data(), d.id)).toList();
      if (mounted) setState(() => _orders = models);
    }, onError: (Object e) {
      debugPrint('[SellerGroceryDashboard] Orders listener error: $e');
    });
  }

  @override
  void dispose() {
    _ordersSub?.cancel();
    super.dispose();
  }

  void _handleBackPress() {
    if (kIsWeb) {
      if (AppMinimizer.consumeWebHintOnce()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Press your device's Home button to minimize"),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    unawaited(AppMinimizer.moveToBackground());
  }

  Future<void> _advanceSellerStage(ServiceRequestModel request, String stage) async {
    if (_busyRequestIds.contains(request.requestId)) return;
    setState(() => _busyRequestIds.add(request.requestId));
    try {
      await ServiceRequestService().advanceSellerStage(
        request.requestId,
        stage,
        sellerId: _seller?.id,
        etaMinutes: _seller?.estimatedPrepTimeMin,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update order: $e'), backgroundColor: _red),
        );
      }
    } finally {
      if (mounted) setState(() => _busyRequestIds.remove(request.requestId));
    }
  }

  Future<void> _confirmPayment(ServiceRequestModel request) async {
    if (_busyRequestIds.contains(request.requestId)) return;
    setState(() => _busyRequestIds.add(request.requestId));
    try {
      await ServiceRequestService().confirmSellerPaymentReceived(request.requestId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not confirm payment: $e'), backgroundColor: _red),
        );
      }
    } finally {
      if (mounted) setState(() => _busyRequestIds.remove(request.requestId));
    }
  }

  Future<void> _bookDeliveryPartner(ServiceRequestModel request) async {
    if (_busyRequestIds.contains(request.requestId)) return;
    setState(() => _busyRequestIds.add(request.requestId));
    try {
      final fired = await ServiceRequestService().requestDeliveryBroadcast(request.requestId);
      if (fired) {
        unawaited(
          ServiceRequestService()
              .advanceSellerStage(
                request.requestId,
                ServiceRequestService.kSellerStageDeliveryRequested,
                sellerId: _seller?.id,
              )
              .catchError((Object e) {
            debugPrint('[SellerGroceryDashboard] delivery_requested stage write failed (non-fatal): $e');
          }),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(fired
              ? 'Delivery partners notified — first to accept takes it'
              : "Couldn't notify delivery partners — please try again"),
          backgroundColor: fired ? _green : _muted,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not notify delivery partners: $e'), backgroundColor: _red),
        );
      }
    } finally {
      if (mounted) setState(() => _busyRequestIds.remove(request.requestId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackPress();
      },
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _teal)),
      );
    }
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        elevation: 0,
        title: Text(
          _seller?.name ?? 'Grocery Store',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_seller != null)
            IconButton(
              icon: const Icon(Icons.inventory_2_outlined, color: _teal),
              tooltip: 'My Products',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => SellerGroceryProductsScreen(sellerId: _seller!.id),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: _muted),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/', (route) => false);
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildProductsEntryCard(),
            const SizedBox(height: 20),
            if (_seller != null) ...[
              _infoRow(Icons.store, 'Store Name', _seller!.name),
              _infoRow(Icons.phone, 'Phone', _seller!.phone),
              _infoRow(Icons.location_on, 'Address', _seller!.address),
            ],
            const SizedBox(height: 20),
            Text('Incoming Catalog Orders (${_orders.length})',
                style: GoogleFonts.outfit(color: _text, fontSize: 16, fontWeight: FontWeight.w700),),
            const SizedBox(height: 4),
            Text(
              'Orders placed against YOUR catalog via "My Products" — the '
              'free-text broadcast flow (customers typing a shopping list) '
              'is unaffected and still works the same as before.',
              style: GoogleFonts.outfit(color: _muted, fontSize: 11.5),
            ),
            const SizedBox(height: 12),
            if (_orders.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
                child: Column(
                  children: [
                    Icon(Icons.inbox_outlined, size: 44, color: _muted.withValues(alpha: 0.5)),
                    const SizedBox(height: 10),
                    Text('No catalog orders yet', style: GoogleFonts.outfit(color: _muted)),
                  ],
                ),
              )
            else
              ..._orders.map(_buildOrderCard),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsEntryCard() {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: _seller == null
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => SellerGroceryProductsScreen(sellerId: _seller!.id)),
              ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.inventory_2_outlined, color: _teal, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('My Products', style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(
                    'Toggle items on from the shared catalog, set your own price + '
                    'stock, and track direct vs. app sales.',
                    style: GoogleFonts.outfit(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _muted),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(ServiceRequestModel request) {
    final details = request.rawDetails;
    final customerName = request.customerName.isNotEmpty ? request.customerName : 'Customer';
    final items = (details['items'] as List<dynamic>?) ?? [];
    final subtotal = (details['subtotal'] as num?)?.toDouble() ?? 0;
    final address = (details['deliveryAddress'] as String?) ?? '';
    final status = request.status.isNotEmpty ? request.status.replaceAll('_', ' ') : 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _teal.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(customerName, style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 13)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _teal.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(color: _teal, fontSize: 10, fontWeight: FontWeight.w700),),
              ),
            ],
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final item in items)
              if (item is Map)
                Text('${item['quantity'] ?? 1} × ${item['name'] ?? 'Item'}',
                    style: GoogleFonts.outfit(color: _muted, fontSize: 12),),
          ],
          if (address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(address, style: GoogleFonts.outfit(color: _muted, fontSize: 11)),
          ],
          const SizedBox(height: 6),
          Text('₹${subtotal.toStringAsFixed(0)}', style: GoogleFonts.outfit(color: _gold, fontWeight: FontWeight.w800, fontSize: 14)),
          _buildActionStrip(request),
        ],
      ),
    );
  }

  /// Mirrors seller_dashboard_screen.dart's _buildSellerActionStrip
  /// exactly (same stage machine, same payment-confirm gate) — kept as
  /// a separate copy rather than a shared widget since the two screens'
  /// surrounding card styles differ enough that extracting a shared
  /// widget now would need its own prop surface anyway; not worth the
  /// indirection for one method.
  Widget _buildActionStrip(ServiceRequestModel request) {
    final assignedHeroName = request.assignedHeroName ?? '';
    if (assignedHeroName.isNotEmpty || request.status == 'hero_assigned') {
      return _stageBanner(Icons.delivery_dining,
          assignedHeroName.isNotEmpty ? '$assignedHeroName is collecting this order' : 'Delivery partner assigned', _green,);
    }
    if (request.status == 'admin_review') {
      return _stageBanner(Icons.support_agent_rounded, "Under review by our team", _orange);
    }

    final stage = request.sellerStage;
    final busy = _busyRequestIds.contains(request.requestId);

    switch (stage) {
      case ServiceRequestService.kSellerStageNew:
      case null:
        return _actionButton('Accept Order', Icons.check_circle_outline, _teal, busy,
            () => _advanceSellerStage(request, ServiceRequestService.kSellerStageAccepted),);
      case ServiceRequestService.kSellerStageAccepted:
        return _actionButton('Start Packing', Icons.inventory_outlined, _orange, busy,
            () => _advanceSellerStage(request, ServiceRequestService.kSellerStagePreparing),);
      case ServiceRequestService.kSellerStagePreparing:
        return _actionButton('Order Packed', Icons.check_box_outlined, _gold, busy,
            () => _advanceSellerStage(request, ServiceRequestService.kSellerStageReady),);
      case ServiceRequestService.kSellerStageReady:
        final paymentMethod = request.rawDetails['paymentMethod'] as String?;
        if (paymentMethod == 'seller_direct_upi' && request.sellerPaymentConfirmed != true) {
          return _actionButton('Confirm Payment Received', Icons.verified_rounded, _gold, busy,
              () => _confirmPayment(request),);
        }
        return _actionButton('Book Delivery Partner', Icons.two_wheeler_rounded, _green, busy,
            () => _bookDeliveryPartner(request),);
      case ServiceRequestService.kSellerStageDeliveryRequested:
        return _stageBanner(Icons.podcasts_rounded, 'Notifying delivery partners nearby…', _gold);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _actionButton(String label, IconData icon, Color color, bool busy, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        width: double.infinity,
        height: 42,
        child: ElevatedButton.icon(
          onPressed: busy ? null : onTap,
          icon: busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(icon, size: 18),
          label: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, maxLines: 1, style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            disabledBackgroundColor: color.withValues(alpha: 0.4),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }

  Widget _stageBanner(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Flexible(child: Text(text, style: GoogleFonts.outfit(color: color, fontWeight: FontWeight.w600, fontSize: 13))),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _teal, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.outfit(color: _muted, fontSize: 11),),
                Text(value.isEmpty ? '—' : value,
                    style: GoogleFonts.outfit(color: _text, fontSize: 14),),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
