// ================================================================
// seller_grocery_products_screen.dart — grocery seller's "My
// Products": browse the shared master catalog, toggle items ON with
// your own price + stock, and manage what's already live — including
// recording a walk-in "Direct Sale" separately from app-order sales.
// ================================================================
// Sep 2026 — universal catalog build. Firestore-hosted revival of
// seller_menu_setup_screen.dart's exact toggle-on/set-price pattern
// (that screen used a hardcoded Dart list, DefaultMenuData; this one
// reads master_catalog/ instead, so admin can add SKUs without an app
// release). Saved items land in the SAME sellers/{id}/menu_items
// subcollection food already uses — see MenuItemModel's `department`
// field comment for why no new collection was needed.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/food_models.dart';
import '../models/master_catalog_model.dart';
import '../services/food_seller_service.dart';
import '../services/master_catalog_service.dart';

const Color _bg = Color(0xFFF7FAF8);
const Color _card = Color(0xFFFFFFFF);
const Color _teal = Color(0xFF11998E);
const Color _gold = Color(0xFFC79200);
const Color _text = Color(0xFF1A1A1A);
const Color _muted = Color(0xFF6B7280);
const Color _border = Color(0x1A11998E);
const Color _red = Color(0xFFD64545);

class SellerGroceryProductsScreen extends StatefulWidget {
  final String sellerId;
  const SellerGroceryProductsScreen({required this.sellerId, super.key});

  @override
  State<SellerGroceryProductsScreen> createState() => _SellerGroceryProductsScreenState();
}

class _SellerGroceryProductsScreenState extends State<SellerGroceryProductsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final FoodSellerService _service = FoodSellerService();

  bool _loading = true;
  List<MenuItemModel> _myItems = [];
  List<MasterCatalogItemModel> _catalog = [];
  // itemId -> (enabled, priceController, stockController)
  final Map<String, _CatalogEntry> _catalogEntries = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    try {
      // A seller managing their OWN stock needs to see items they've
      // turned OFF too (getAvailableMenuItems filters isAvailable==true,
      // which would hide them), so this reads the full per-seller stream
      // once rather than the available-only helper.
      final results = await Future.wait([
        _service.listenToMenuItems(widget.sellerId).first,
        MasterCatalogService.instance.listActiveForSeller('grocery'),
      ]);
      _myItems = (results[0] as List<MenuItemModel>).where((i) => i.department == 'grocery').toList();
      _catalog = results[1] as List<MasterCatalogItemModel>;

      for (final catalogItem in _catalog) {
        final existing = _myItems.where((m) => m.sourceCatalogItemId == catalogItem.id);
        final entry = _CatalogEntry();
        if (existing.isNotEmpty) {
          entry.enabled = existing.first.isAvailable;
          entry.priceController.text = existing.first.price.toStringAsFixed(0);
          entry.stockController.text = (existing.first.stockQuantity ?? 0).toString();
        }
        _catalogEntries[catalogItem.id] = entry;
      }

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint('[SellerGroceryProducts] load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final e in _catalogEntries.values) {
      e.priceController.dispose();
      e.stockController.dispose();
    }
    super.dispose();
  }

  Future<void> _saveCatalogSelections() async {
    setState(() => _isSaving = true);
    try {
      final batch = <MenuItemModel>[];
      for (final catalogItem in _catalog) {
        final entry = _catalogEntries[catalogItem.id]!;
        if (!entry.enabled) continue;
        final price = double.tryParse(entry.priceController.text.trim());
        final stock = int.tryParse(entry.stockController.text.trim());
        if (price == null || price <= 0) continue; // skip incomplete entries silently — caught below
        // FIX (audit pass, Sep 2026 — real data-loss bug): batchUpsertMenuItems
        // writes via SetOptions(merge:true), but MenuItemModel.toJson()
        // unconditionally includes appOrderSoldCount/directSaleCount —
        // merge only skips fields ABSENT from the payload, not fields
        // present with a default value. Building this MenuItemModel with
        // no sold-count args (defaulting to 0) meant EVERY re-save of an
        // already-selling item — even just bumping its stock — silently
        // wiped its real sold history back to zero. Carry the existing
        // item's counts through if this item was already active.
        MenuItemModel? existing;
        for (final m in _myItems) {
          if (m.sourceCatalogItemId == catalogItem.id) {
            existing = m;
            break;
          }
        }
        batch.add(MenuItemModel(
          id: catalogItem.id,
          name: catalogItem.name,
          price: price,
          isAvailable: true,
          stockQuantity: stock,
          categoryName: catalogItem.category,
          imageUrl: catalogItem.imageUrl,
          department: 'grocery',
          sourceCatalogItemId: catalogItem.id,
          appOrderSoldCount: existing?.appOrderSoldCount ?? 0,
          directSaleCount: existing?.directSaleCount ?? 0,
        ),);
      }

      final invalidCount = _catalogEntries.values.where((e) =>
          e.enabled && (double.tryParse(e.priceController.text.trim()) == null ||
              double.tryParse(e.priceController.text.trim())! <= 0),).length;

      if (invalidCount > 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$invalidCount item(s) need a valid price'), backgroundColor: _red),
          );
        }
        setState(() => _isSaving = false);
        return;
      }

      await _service.batchUpsertMenuItems(widget.sellerId, batch);

      // Also turn OFF anything the seller just unchecked that was
      // previously on — batchUpsertMenuItems only writes ENABLED items
      // above, so an unchecked item's own doc needs an explicit
      // isAvailable:false, not just omission.
      for (final catalogItem in _catalog) {
        final entry = _catalogEntries[catalogItem.id]!;
        final wasOn = _myItems.any((m) => m.sourceCatalogItemId == catalogItem.id && m.isAvailable);
        if (wasOn && !entry.enabled) {
          await _service.updateMenuItem(widget.sellerId, catalogItem.id, {'isAvailable': false});
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${batch.length} product(s)'), backgroundColor: _teal),
      );
      await _load();
      _tabController.animateTo(0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: _red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _recordDirectSale(MenuItemModel item) async {
    final qty = await showDialog<int>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController(text: '1');
        return AlertDialog(
          title: Text('Record Direct Sale — ${item.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('For a walk-in customer at your shop counter — tracked '
                  'separately from app orders.',
                  style: GoogleFonts.outfit(fontSize: 12, color: _muted),),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity sold', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final q = int.tryParse(ctrl.text.trim());
                if (q == null || q <= 0) return;
                Navigator.pop(ctx, q);
              },
              child: const Text('Record'),
            ),
          ],
        );
      },
    );
    if (qty == null) return;

    try {
      // FieldValue.increment (not a locally-computed value) so two
      // direct-sale entries recorded moments apart never race against
      // each other's stale read of item.stockQuantity.
      await _service.updateMenuItem(widget.sellerId, item.id, {
        if (item.stockQuantity != null) 'stockQuantity': FieldValue.increment(-qty),
        'directSaleCount': FieldValue.increment(qty),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recorded: $qty sold directly'), backgroundColor: _teal),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: _red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        elevation: 0,
        title: Text('My Grocery Products',
            style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700),),
        bottom: TabBar(
          controller: _tabController,
          labelColor: _teal,
          unselectedLabelColor: _muted,
          indicatorColor: _teal,
          tabs: [
            Tab(text: 'My Products (${_myItems.where((i) => i.isAvailable).length})'),
            const Tab(text: 'Add From Catalog'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : TabBarView(
              controller: _tabController,
              children: [_buildMyProductsTab(), _buildCatalogTab()],
            ),
    );
  }

  Widget _buildMyProductsTab() {
    final active = _myItems.where((i) => i.isAvailable).toList();
    if (active.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_outlined, size: 56, color: _muted),
            const SizedBox(height: 12),
            Text('No products yet — add some from the catalog tab.',
                style: GoogleFonts.outfit(color: _muted),),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: active.length,
      itemBuilder: (context, i) => _buildMyProductCard(active[i]),
    );
  }

  Widget _buildMyProductCard(MenuItemModel item) {
    final stock = item.stockQuantity;
    final lowStock = stock != null && stock <= 3;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: lowStock ? _red.withValues(alpha: 0.4) : _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.name,
                    style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 14),),
              ),
              Text('₹${item.price.toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(color: _teal, fontWeight: FontWeight.w800, fontSize: 14),),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            stock != null ? 'Stock: $stock' : 'Stock: not tracked',
            style: GoogleFonts.outfit(
                color: lowStock ? _red : _muted, fontSize: 12, fontWeight: lowStock ? FontWeight.w700 : FontWeight.w500,),
          ),
          const SizedBox(height: 4),
          // The dual-channel split Nizam asked for — app-order sales
          // (reserveMenuItemStock.ts, server-side) vs. direct/walk-in
          // sales (_recordDirectSale above, client-side) shown apart.
          Row(
            children: [
              Icon(Icons.shopping_bag_outlined, size: 13, color: _muted),
              const SizedBox(width: 4),
              Text('App: ${item.appOrderSoldCount}', style: GoogleFonts.outfit(color: _muted, fontSize: 11)),
              const SizedBox(width: 14),
              Icon(Icons.storefront_outlined, size: 13, color: _muted),
              const SizedBox(width: 4),
              Text('Direct: ${item.directSaleCount}', style: GoogleFonts.outfit(color: _muted, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _recordDirectSale(item),
                  icon: const Icon(Icons.point_of_sale_rounded, size: 15),
                  label: const Text('Record Direct Sale', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(foregroundColor: _gold, side: const BorderSide(color: _gold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogTab() {
    if (_catalog.isEmpty) {
      return Center(
        child: Text('No grocery catalog items yet — ask admin to add some.',
            style: GoogleFonts.outfit(color: _muted),),
      );
    }
    final byCategory = <String, List<MasterCatalogItemModel>>{};
    for (final item in _catalog) {
      byCategory.putIfAbsent(item.category, () => []).add(item);
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: _teal.withValues(alpha: 0.08),
          child: Text(
            'Toggle ON items you stock, set your price + quantity, then Save.',
            style: GoogleFonts.outfit(color: _text, fontSize: 12),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: byCategory.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.key,
                        style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 14),),
                    const SizedBox(height: 8),
                    ...entry.value.map(_buildCatalogTile),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveCatalogSelections,
              style: ElevatedButton.styleFrom(backgroundColor: _teal),
              child: _isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('Save', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCatalogTile(MasterCatalogItemModel item) {
    final entry = _catalogEntries[item.id]!;
    return StatefulBuilder(
      builder: (context, setLocalState) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              Switch(
                value: entry.enabled,
                activeThumbColor: _teal,
                onChanged: (v) => setLocalState(() => entry.enabled = v),
              ),
              Expanded(
                flex: 2,
                child: Text(item.name,
                    style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600),),
              ),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: entry.priceController,
                  enabled: entry.enabled,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(hintText: '₹', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 60,
                child: TextField(
                  controller: entry.stockController,
                  enabled: entry.enabled,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(hintText: 'Qty', isDense: true, border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CatalogEntry {
  bool enabled = false;
  final TextEditingController priceController = TextEditingController();
  final TextEditingController stockController = TextEditingController();
}
