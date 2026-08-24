import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colorful_iconify_flutter/icons/fluent_emoji_flat.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../config/food_categories.dart';
import '../models/service_request_model.dart';
// GUEST MODE (Aug 11 2026): requireRealAuth() guard on the submit action.
import '../services/auth_prompt_service.dart';
import '../services/app_palette.dart';
// Imported with a prefix (rather than a `hide` clause on some other
// import) because the ambiguity here is with a `Category` symbol from
// one of this file's OTHER imports, not from flutter/material.dart
// (material.dart doesn't actually export anything named `Category` --
// the old `hide Category` clause on it was a no-op that never fixed
// the real conflict). Prefixing removes the ambiguity outright without
// needing to track down which specific package the other `Category`
// comes from.
import '../services/category_gateway_service.dart' as gateway;
import '../services/food_seller_service.dart';
import '../services/location_service.dart';
import '../services/map_service.dart';
import '../services/service_request_service.dart';
import '../utils/service_request_labels.dart';
import '../widgets/quick_order_line_items.dart';
import '../services/auth_service.dart';
import '../widgets/server_busy_dialog.dart';
import 'category_screen.dart';
import 'food_order_status_screen.dart';
import 'location_picker_screen.dart';
import 'partner_shop_order_screen.dart';
import 'embedded_shop_screen.dart';
import 'service_request_tracking_screen.dart';

class CustomFoodOrderScreen extends StatefulWidget {
  // FIX (per Nizam's request): lets a caller like PartnerShopOrderScreen
  // pre-fill the shop name + items summary and reuse this screen's
  // already-working order-submission pipeline (writes to
  // service_requests, dispatches to a hero) instead of building a
  // second, separate order-writing codepath for every partner shop.
  // Customer still confirms/edits delivery address + name here before
  // submitting, same as any other order.
  final String? initialShop;
  final String? initialItems;

  const CustomFoodOrderScreen({super.key, this.initialShop, this.initialItems});
  @override
  State<CustomFoodOrderScreen> createState() => _CustomFoodOrderScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('initialShop', initialShop));
    properties.add(StringProperty('initialItems', initialItems));
  }
}

class _CustomFoodOrderScreenState extends State<CustomFoodOrderScreen> {
  late final _shopCtrl = TextEditingController(text: widget.initialShop ?? '');
  List<OrderLineItem> _lineItems = [OrderLineItem()];
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  bool _isLoading = false;
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialItems?.trim();
    if (initial != null && initial.isNotEmpty) {
      final parsed = initial
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .map((s) => OrderLineItem(name: s))
          .toList();
      if (parsed.isNotEmpty) _lineItems = parsed;
    }
  }

  // ── Hotel-name autocomplete ("erode hotels touch aguramari" — same
  // suggestion mechanism as the bike-taxi From/To fields, via the
  // existing MapService (Ola Maps first, OSM fallback), just applied
  // to this free-text shop field instead of a pickup/drop field. ──
  Timer? _shopDebounce;
  List<Map<String, dynamic>> _shopSuggestions = [];
  bool _shopSearching = false;
  Map<String, dynamic>? _selectedShop;

  // ── Delivery location (Use my location / Select on map) ──────────
  double? _deliveryLat;
  double? _deliveryLng;
  bool _locatingMe = false;

  @override
  void dispose() {
    _shopDebounce?.cancel();
    _shopCtrl.dispose();
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _onShopQueryChanged(String query) {
    _selectedShop = null;
    _shopDebounce?.cancel();
    if (query.trim().length < 2) {
      setState(() => _shopSuggestions = []);
      return;
    }
    _shopDebounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      setState(() => _shopSearching = true);
      try {
        final results = await MapService().search(query.trim());
        if (!mounted) return;
        setState(() {
          _shopSuggestions = results;
          _shopSearching = false;
        });
      } catch (_) {
        if (mounted) setState(() => _shopSearching = false);
      }
    });
  }

  void _pickShopSuggestion(Map<String, dynamic> suggestion) {
    _selectedShop = suggestion;
    _shopCtrl.text = (suggestion['name'] as String?)?.trim() ?? _shopCtrl.text;
    setState(() => _shopSuggestions = []);
    FocusScope.of(context).unfocus();
  }

  Future<void> _useMyLocation() async {
    setState(() => _locatingMe = true);
    try {
      // FAST PATH (Aug 16 2026): use dashboard's prefetched position first.
      final locationService = LocationService();
      var position = locationService.currentPosition;
      position ??= await locationService.getCurrentLocation();
      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not get your location. Check location permission.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      final point = LatLng(position.latitude, position.longitude);
      final reverse = await MapService().reverseGeocode(point);
      final address = (reverse?['name'] as String?)?.trim().isNotEmpty ?? false
          ? reverse!['name'] as String
          : (reverse?['address'] as String?) ?? 'Current location';
      if (!mounted) return;
      setState(() {
        _addressCtrl.text = address;
        _deliveryLat = position!.latitude;
        _deliveryLng = position!.longitude;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not fetch location: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _locatingMe = false);
    }
  }

  Future<void> _selectOnMap() async {
    final initialCenter = (_deliveryLat != null && _deliveryLng != null)
        ? LatLng(_deliveryLat!, _deliveryLng!)
        : null;
    final picked = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialCenter: initialCenter,
          title: 'Delivery location',
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _addressCtrl.text = picked.name;
      _deliveryLat = picked.lat;
      _deliveryLng = picked.lng;
    });
  }

  Future<void> _placeOrder() async {
    final hasItems = _lineItems.any((it) => !it.isEmpty);
    if (_shopCtrl.text.isEmpty || !hasItems || _addressCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in the required details 🍔'), backgroundColor: Colors.red),
      );
      return;
    }

    // GUEST MODE (Aug 11 2026): guard after form validation, before the
    // currentUser read. See auth_prompt_service.dart.
    if (!await requireRealAuth(
      context,
      reason: 'Sign in and your food is on its way',
    )) {
      return;
    }
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      final resolvedCustomerPhone = await AuthService().resolveCustomerPhone(user);
      final requestId = await ServiceRequestService().createServiceRequest(
        requestType: 'custom_food_order',
        customerId: user.uid,
        customerName: _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : (user.displayName ?? 'Customer'),
        customerPhone: resolvedCustomerPhone,
        details: {
          'items': quickOrderItemsToJson(_lineItems),
          'restaurantOrPreference': _shopCtrl.text.trim(),
          'deliveryAddress': _addressCtrl.text.trim(),
          if (_selectedShop != null) 'shopAddress': _selectedShop!['address'],
          if (_selectedShop?['lat'] != null) 'shopLat': _selectedShop!['lat'],
          if (_selectedShop?['lng'] != null) 'shopLng': _selectedShop!['lng'],
          if (_deliveryLat != null) 'deliveryLatitude': _deliveryLat,
          if (_deliveryLng != null) 'deliveryLongitude': _deliveryLng,
        },
      );

      unawaited(Future.delayed(
        const Duration(seconds: kServiceRequestPingExpirySeconds),
        () => ServiceRequestService().markTimeoutIfStillPending(requestId),
      ),);

      if (!mounted) return;
      // Clear the form so the just-placed order shows cleanly in the
      // "My Orders" list when the user taps back from tracking.
      _shopCtrl.clear();
      setState(() => _lineItems = [OrderLineItem()]);
      _addressCtrl.clear();
      _selectedShop = null;
      _deliveryLat = null;
      _deliveryLng = null;
      // `push` (not `pushReplacement`) so pressing back returns to this
      // Food Genie page and the live "My Orders" list below.
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ServiceRequestTrackingScreen(
            requestId: requestId,
            requestType: 'custom_food_order',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        showServerBusyDialog(context);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildField({required String label, required String hint, required TextEditingController ctrl, int lines = 1, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.outfit(color: kText, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            maxLines: lines,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: kMuted.withValues(alpha: 0.6), fontSize: 13),
              prefixIcon: icon != null ? Icon(icon, color: kPink, size: 20) : null,
              filled: true,
              fillColor: kSurface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPink,
                    elevation: 4,
                    shadowColor: kPink.withValues(alpha: 0.4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _isLoading ? null : _placeOrder,
                  icon: _isLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.restaurant_rounded, color: Colors.white, size: 18),
                  label: Text('Order Food', style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: kPink, width: 1.4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FoodOrderStatusScreen()),
                  ),
                  icon: Icon(Icons.receipt_long_rounded, color: kPink, size: 18),
                  label: Text('Order Status', style: GoogleFonts.outfit(color: kPink, fontSize: 17, fontWeight: FontWeight.bold)),
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
    syncAppPalette(context);
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: kText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Food Genie 🧞‍♂️', style: GoogleFonts.outfit(color: kText, fontWeight: FontWeight.w800, fontSize: 18)),
        centerTitle: true,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_currentTab == 1) _FoodSidebar(onCategoryTap: _openSidebarCategory),
          Expanded(
            child: _currentTab == 0
                ? Column(
                    children: [
                      Expanded(child: _buildFormBody()),
                      _buildActionButtons(),
                    ],
                  )
                : _buildHotelsGrid(),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (idx) => setState(() => _currentTab = idx),
        selectedItemColor: kPink,
        unselectedItemColor: kMuted,
        backgroundColor: Colors.white,
        elevation: 8,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.restaurant_menu_rounded),
            label: 'Custom Order',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.storefront_rounded),
            label: 'Hotels',
          ),
        ],
      ),
    );
  }

  Future<void> _openSidebarCategory(String subCategoryKey) async {
    final cat = foodSubCategoryByKey(subCategoryKey);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(color: kPink),
      ),
    );
    try {
      final sellers = await FoodSellerService().getSellersBySubCategory(subCategoryKey);
      if (!mounted) return;
      Navigator.pop(context); // close loading dialog
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CategoryScreen(
            category: gateway.Category.food,
            sellers: sellers.map((s) => s.toJson()).toList(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load ${cat?.label ?? subCategoryKey}: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildFormBody() {
    return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kGold.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Text('🤤', style: TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Order from ANY Shop!', style: GoogleFonts.outfit(color: Colors.orange[800], fontWeight: FontWeight.w800, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text('Just tell us what you want and from where. We will deliver it to you.', style: TextStyle(color: kText, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildShopField(),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('What do you want to eat?', style: GoogleFonts.outfit(color: kText, fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  QuickOrderLineItemsForm(
                    items: _lineItems,
                    itemLabel: 'Dish',
                    qtyLabel: 'Qty',
                    onChanged: (items) => setState(() => _lineItems = items),
                  ),
                ],
              ),
            ),
            _buildField(label: 'Your Name', hint: 'Enter your name', ctrl: _nameCtrl, icon: Icons.person_outline_rounded),
            _buildField(label: 'Delivery Location', hint: 'Enter your full address & landmark', ctrl: _addressCtrl, lines: 2, icon: Icons.location_on_outlined),
            _buildLocationButtons(),
            const SizedBox(height: 32),
            _buildMyOrders(),
            const SizedBox(height: 100),
          ],
        ),
      );
  }

  Widget _buildHotelsGrid() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Available Hotels', style: GoogleFonts.outfit(color: kText, fontSize: 14.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Tap to view live menu or order online', style: GoogleFonts.outfit(color: kMuted, fontSize: 12)),
          const SizedBox(height: 14),
          GridView.count(
            key: const Key('food_hub_partner_shops_grid'),
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.35,
            children: kPartnerShops
                .map(
                  (shop) => _HubTile(
                    label: shop.name,
                    subtitle: shop.subtitle,
                    icon: Icons.storefront_rounded,
                    gradient: shop.gradient,
                    imageAsset: shop.imageAsset,
                    onTap: () {
                      if (shop.embedded) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EmbeddedShopScreen(shop: shop),
                          ),
                        );
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PartnerShopOrderScreen(shop: shop),
                          ),
                        );
                      }
                    },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  // ── Restaurant / Shop Name field with tap-to-select suggestions —
  // same debounced MapService().search() mechanism the bike-taxi
  // From/To fields use, so typing a few letters of a real Erode hotel
  // shows matching places to tap instead of free-typing the name. ──
  Widget _buildShopField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Restaurant / Shop Name', style: GoogleFonts.outfit(color: kText, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _shopCtrl,
            onChanged: _onShopQueryChanged,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'e.g., Erode Amman Mess, 16th Road',
              hintStyle: TextStyle(color: kMuted.withValues(alpha: 0.6), fontSize: 13),
              prefixIcon: Icon(Icons.storefront_rounded, color: kPink, size: 20),
              suffixIcon: _shopSearching
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kPink)),
                    )
                  : null,
              filled: true,
              fillColor: kSurface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          if (_shopSuggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kPink.withValues(alpha: 0.15)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _shopSuggestions.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: kSurface),
                itemBuilder: (context, i) {
                  final s = _shopSuggestions[i];
                  final name = (s['name'] as String?) ?? '';
                  final address = (s['address'] as String?) ?? '';
                  return InkWell(
                    onTap: () => _pickShopSuggestion(s),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.location_on_outlined, color: kPink, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: GoogleFonts.outfit(color: kText, fontSize: 17, fontWeight: FontWeight.w700)),
                                if (address.isNotEmpty)
                                  Text(address, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: kMuted, fontSize: 11),),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // ── Use my location / Select on map — sits right under the
  // Delivery Location field, same pairing the user asked for ("type
  // pandra place-ku keela use my location, pakkathula select on map").
  Widget _buildLocationButtons() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _locatingMe ? null : _useMyLocation,
              icon: _locatingMe
                  ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: kPink))
                  : Icon(Icons.my_location_rounded, size: 16, color: kPink),
              label: Text('Use my location', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: kPink)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: kPink.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _selectOnMap,
              icon: Icon(Icons.map_outlined, size: 16, color: kPink),
              label: Text('Select on map', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: kPink)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: kPink.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── My Orders — live status list for this customer ───────────────
  Widget _buildMyOrders() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    final stream = FirebaseFirestore.instance
        .collection('service_requests')
        .where('customerId', isEqualTo: user.uid)
        .where('requestType', isEqualTo: 'custom_food_order')
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('My Orders', style: GoogleFonts.outfit(color: kText, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator(color: kPink, strokeWidth: 2)),
              );
            }
            if (snapshot.hasError) {
              return Text('Could not load your orders.', style: TextStyle(color: kMuted, fontSize: 12));
            }
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'No orders yet. Place your first order above! 🍔',
                  style: TextStyle(color: kMuted, fontSize: 13),
                ),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) =>
                  _orderCard(ServiceRequestModel.fromFirestore(docs[i].data(), docs[i].id)),
            );
          },
        ),
      ],
    );
  }

  Widget _orderCard(ServiceRequestModel request) {
    final details = request.rawDetails;
    final shop = (details['restaurantOrPreference'] as String?)?.trim();
    // Backward compat: 'items' used to be a plain String; now it's a
    // List<Map> of {sNo, name, qty} line items (see
    // quick_order_line_items.dart). Handle both shapes.
    final itemsRaw = details['items'];
    String? items;
    if (itemsRaw is List) {
      items = itemsRaw
          .whereType<Map>()
          .map((it) => '${it['qty'] ?? ''} ${it['name'] ?? ''}'.trim())
          .where((s) => s.isNotEmpty)
          .join(', ');
    } else if (itemsRaw is String) {
      items = itemsRaw.trim();
    }
    final status = request.status.isNotEmpty ? request.status : 'pending';
    final statusColor = serviceRequestStatusColor(status);
    final statusLabel = serviceRequestStatusLabel('custom_food_order', status);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ServiceRequestTrackingScreen(
            requestId: request.requestId,
            requestType: 'custom_food_order',
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEEEF5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (shop != null && shop.isNotEmpty) ? shop : 'Custom food order',
                    style: GoogleFonts.outfit(color: kText, fontSize: 17, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (items != null && items.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      items,
                      style: TextStyle(color: kMuted, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// _FoodSidebar — full-height vertical icon rail on the left edge of
// the food page (Swiggy/Zomato style, per Nizam's confirmed choice).
// Reads its icon set from kFoodSidebarCategoryKeys in
// lib/config/food_categories.dart, so adding a future category (e.g.
// "Sweets") is a one-line change there — nothing here needs editing.
// ================================================================
class _FoodSidebar extends StatelessWidget {
  final ValueChanged<String> onCategoryTap;

  const _FoodSidebar({required this.onCategoryTap});

  @override
  Widget build(BuildContext context) {
    final items = kFoodSidebarCategoryKeys
        .map(foodSubCategoryByKey)
        .whereType<FoodSubCategory>()
        .toList();

    return Container(
      width: 76,
      color: kSurface,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: items
                .map((cat) => _SidebarIcon(
                      category: cat,
                      onTap: () => onCategoryTap(cat.key),
                    ),)
                .toList(),
          ),
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(ObjectFlagProperty<ValueChanged<String>>.has('onCategoryTap', onCategoryTap));
  }
}

// Per-category accent colour + (where a confirmed-valid Fluent Emoji
// Flat SVG identifier exists — reusing exact identifiers already
// proven to compile on dashboard_screen.dart, since colorful_iconify_
// flutter's icon set is huge and unverifiable offline here) a richer
// SVG icon. Everything else keeps the plain-text emoji from
// food_categories.dart but in the new, larger, gradient-backed pill —
// still an upgrade even without a matching SVG asset.
const Map<String, Color> _kSidebarAccent = {
  'biriyani': Color(0xFFFF8A3D),
  'home_made': Color(0xFFFF4FA3),
  'parotta': Color(0xFFFFC24B),
  'south_indian': Color(0xFF3DBA6F),
  'fast_food': Color(0xFFFF5252),
  'multi_cuisine': Color(0xFF7B6FE0),
};

class _SidebarIcon extends StatelessWidget {
  final FoodSubCategory category;
  final VoidCallback onTap;

  const _SidebarIcon({required this.category, required this.onTap});

  Widget? _svgIcon() {
    switch (category.key) {
      case 'fast_food':
        return SvgPicture.string(FluentEmojiFlat.french_fries, width: 24, height: 24);
      case 'multi_cuisine':
        return SvgPicture.string(FluentEmojiFlat.pizza, width: 24, height: 24);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _kSidebarAccent[category.key] ?? kPink;
    final svg = _svgIcon();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: 0.20),
                    accent.withValues(alpha: 0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.4),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: svg ??
                    Text(category.emoji, style: const TextStyle(fontSize: 24)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              category.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: kText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<FoodSubCategory>('category', category));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}

class _HubTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final String? imageAsset;
  final VoidCallback onTap;

  const _HubTile({
    super.key,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    this.imageAsset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: gradient.first.withValues(alpha: 0.28), blurRadius: 16, offset: const Offset(0, 8))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white, 
                shape: BoxShape.circle,
                image: imageAsset != null
                    ? DecorationImage(image: AssetImage(imageAsset!), fit: BoxFit.cover)
                    : null,
              ),
              child: imageAsset == null ? Icon(icon, color: gradient.last, size: 22) : null,
            ),
            const Spacer(),
            Text(label, style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(subtitle, style: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.85), fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('label', label));
    properties.add(StringProperty('subtitle', subtitle));
    properties.add(DiagnosticsProperty<IconData>('icon', icon));
    properties.add(IterableProperty<Color>('gradient', gradient));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}
