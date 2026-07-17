import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/default_menu_data.dart';
import '../models/food_models.dart';
import '../services/food_seller_service.dart';

const Color _bg = Color(0xFF08080F);
const Color _surface = Color(0xFF0D0D18);
const Color _card = Color(0xFF141420);
const Color _card2 = Color(0xFF1A1A28);
const Color _teal = Color(0xFF11998E);
const Color _tealLight = Color(0xFF38EF7D);
const Color _gold = Color(0xFFF5C542);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);
const Color _red = Color(0xFFFF5252);

class _MenuItemEntry {
  final DefaultMenuItem defaultItem;
  bool enabled;
  final TextEditingController priceController;

  _MenuItemEntry({
    required this.defaultItem,
  })  : enabled = false,
        priceController = TextEditingController();
}

class SellerMenuSetupScreen extends StatefulWidget {
  final String sellerId;

  const SellerMenuSetupScreen({required this.sellerId, super.key});

  @override
  State<SellerMenuSetupScreen> createState() => _SellerMenuSetupScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('sellerId', sellerId));
  }
}

class _SellerMenuSetupScreenState extends State<SellerMenuSetupScreen> {
  final FoodSellerService _service = FoodSellerService();
  final Map<String, List<_MenuItemEntry>> _categoryItems = {};
  final Set<String> _expandedCategories = {};
  bool _isSaving = false;
  int _totalEnabled = 0;
  bool _isLoadingSeller = true;
  String _hotelType = 'both';

  @override
  void initState() {
    super.initState();
    _loadSellerProfile();
  }

  Future<void> _loadSellerProfile() async {
    try {
      final seller = await _service.getSeller(widget.sellerId);
      if (seller != null) {
        _hotelType = seller.hotelType;
        final filteredItems =
            DefaultMenuData.filterByHotelType(seller.hotelType);
        _buildItemList(filteredItems);
        if (mounted) setState(() => _isLoadingSeller = false);
      }
      _loadExistingMenuItems();
    } catch (_) {
      final items = DefaultMenuData.filterByHotelType('both');
      _buildItemList(items);
      if (mounted) setState(() => _isLoadingSeller = false);
    }
  }

  void _buildItemList(List<DefaultMenuItem> items) {
    _categoryItems.clear();
    _expandedCategories.addAll(DefaultMenuData.categoryOrder);
    for (final item in items) {
      _categoryItems.putIfAbsent(item.category, () => []);
      _categoryItems[item.category]!.add(_MenuItemEntry(defaultItem: item));
    }
    _updateCount();
  }

  Future<void> _loadExistingMenuItems() async {
    try {
      final existing = await _service.getAvailableMenuItems(widget.sellerId);
      for (final menuItem in existing) {
        for (final entries in _categoryItems.values) {
          for (final entry in entries) {
            if (entry.defaultItem.id == menuItem.id) {
              entry.enabled = true;
              entry.priceController.text = menuItem.price.toStringAsFixed(0);
            }
          }
        }
      }
      _updateCount();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _updateCount() {
    _totalEnabled = 0;
    for (final entries in _categoryItems.values) {
      for (final entry in entries) {
        if (entry.enabled) _totalEnabled++;
      }
    }
  }

  @override
  void dispose() {
    for (final entries in _categoryItems.values) {
      for (final entry in entries) {
        entry.priceController.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _saveMenu() async {
    final invalidItems = <String>[];
    for (final entries in _categoryItems.values) {
      for (final entry in entries) {
        if (entry.enabled) {
          final priceText = entry.priceController.text.trim();
          final price = double.tryParse(priceText);
          if (price == null || price <= 0) {
            invalidItems.add(entry.defaultItem.name);
          }
        }
      }
    }

    if (invalidItems.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please set valid prices for: ${invalidItems.take(3).join(", ")}${invalidItems.length > 3 ? "..." : ""}',
          ),
          backgroundColor: _red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final batchItems = <MenuItemModel>[];
      for (final entries in _categoryItems.values) {
        for (final entry in entries) {
          if (!entry.enabled) continue;
          final price = double.parse(entry.priceController.text.trim());
          batchItems.add(
            MenuItemModel(
              id: entry.defaultItem.id,
              name: entry.defaultItem.name,
              price: price,
              isVeg: entry.defaultItem.isVeg,
              tags: entry.defaultItem.tags,
              categoryName:
                  DefaultMenuData.categoryLabels[entry.defaultItem.category] ??
                      entry.defaultItem.category,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
        }
      }

      await _service.batchUpsertMenuItems(widget.sellerId, batchItems);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Menu saved! $_totalEnabled items published.'),
          backgroundColor: _teal,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save menu: $e'),
          backgroundColor: _red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _text),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Set Up Your Menu',
          style: GoogleFonts.outfit(
            color: _text,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_totalEnabled > 0)
            Center(
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _teal,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_totalEnabled items',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _isLoadingSeller
          ? const Center(
              child: CircularProgressIndicator(color: _teal),
            )
          : Column(
              children: [
                _buildInfoBanner(),
                Expanded(
                  child: _categoryItems.isEmpty
                      ? _buildEmptyState()
                      : _buildMenuList(),
                ),
                _buildBottomBar(),
              ],
            ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _teal.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(color: _teal.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline, color: _gold, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Toggle ON the items you have in stock and set your price. '
              'Only enabled items will appear in the Customer App.',
              style: GoogleFonts.outfit(
                color: _text.withValues(alpha: 0.8),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.restaurant_menu, size: 64, color: _muted),
          const SizedBox(height: 16),
          Text(
            'No menu items available',
            style: GoogleFonts.outfit(color: _muted, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: DefaultMenuData.categoryOrder.length,
      itemBuilder: (context, index) {
        final catKey = DefaultMenuData.categoryOrder[index];
        final items = _categoryItems[catKey];
        if (items == null || items.isEmpty) return const SizedBox.shrink();

        final label = DefaultMenuData.categoryLabels[catKey] ?? catKey;
        final isExpanded = _expandedCategories.contains(catKey);
        final enabledCount = items.where((e) => e.enabled).length;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedCategories.remove(catKey);
                      } else {
                        _expandedCategories.add(catKey);
                      }
                    });
                  },
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: GoogleFonts.outfit(
                              color: _text,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (enabledCount > 0)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _teal.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$enabledCount',
                              style: GoogleFonts.outfit(
                                color: _tealLight,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: _muted,
                        ),
                      ],
                    ),
                  ),
                ),
                if (isExpanded) ...items.map(_buildMenuItemTile),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMenuItemTile(_MenuItemEntry entry) {
    final isNonVeg = !entry.defaultItem.isVeg;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: _border.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          // Toggle switch
          GestureDetector(
            onTap: () {
              setState(() {
                entry.enabled = !entry.enabled;
                _updateCount();
                if (!entry.enabled) {
                  entry.priceController.clear();
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 26,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                color: entry.enabled ? _teal : _card2,
                border: Border.all(
                  color: entry.enabled ? _tealLight : _border,
                ),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: entry.enabled
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.all(2),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: entry.enabled ? Colors.white : _muted,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Emoji + Name + badges
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      entry.defaultItem.emoji,
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.defaultItem.name,
                        style: GoogleFonts.outfit(
                          color: entry.enabled ? _text : _muted,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (isNonVeg)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: _red.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'NON-VEG',
                          style: GoogleFonts.outfit(
                            color: _red,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (entry.defaultItem.tags.contains('bestseller'))
                      _buildTag('⭐ Best Seller', _gold),
                    if (entry.defaultItem.tags.contains('popular') &&
                        !entry.defaultItem.tags.contains('bestseller'))
                      _buildTag('🔥 Popular', Colors.orangeAccent),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Price input
          SizedBox(
            width: 90,
            child: TextFormField(
              controller: entry.priceController,
              enabled: entry.enabled,
              style: GoogleFonts.outfit(
                color: entry.enabled ? _text : _muted,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                hintText: entry.enabled ? '₹ 0' : 'OFF',
                hintStyle: GoogleFonts.outfit(
                  color: entry.enabled ? _muted : _muted.withValues(alpha: 0.4),
                  fontSize: 13,
                ),
                filled: true,
                fillColor:
                    entry.enabled ? _card2 : _card2.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _teal, width: 1.5),
                ),
                prefixText: entry.enabled ? '₹ ' : null,
                prefixStyle: GoogleFonts.outfit(
                  color: _tealLight,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final hasPrices = _categoryItems.values
        .expand((e) => e)
        .any((e) => e.enabled && e.priceController.text.trim().isNotEmpty);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: (_isSaving || !hasPrices) ? null : _saveMenu,
            style: ElevatedButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _teal.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _totalEnabled > 0
                        ? 'Publish $_totalEnabled Items to Store'
                        : 'Select items & set prices to continue',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
