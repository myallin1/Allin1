// ================================================================
// seller_home_kitchen_menu_screen.dart
// Self-serve custom menu editor for Home Made Foods (home_made
// subCategory) sellers. Unlike SellerMenuSetupScreen (which only lets
// a Hotel seller toggle prices on a fixed, admin-curated catalog),
// this screen lets a home-cook AUTHOR their own dish: their own photo,
// name, description, and price — up to kMaxHomeKitchenItems dishes.
// Each dish has its own on/off (isAvailable) switch; only items
// switched ON are visible to customers (FoodSellerService's
// getAvailableMenuItems() / customer-facing queries already filter on
// isAvailable == true, so no customer-app change was needed for that
// part — this screen is purely the seller-side authoring UI).
//
// Image upload uses FilePicker(withData: true) + Cloudinary's unsigned
// upload API (see cloudinary_upload_service.dart) — NOT Firebase
// Storage, since Storage now requires the Blaze plan to create a
// bucket at all, and Allin1 is staying on the free Spark plan.
// FilePicker's withData:true gives raw bytes, which also avoids the
// dart:io File()-on-web problem (file.path is null on Flutter Web).
// ================================================================
import 'dart:async';

import 'package:colorful_iconify_flutter/icons/fluent_emoji_flat.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../models/food_models.dart';
import '../services/cloudinary_upload_service.dart';
import '../services/food_seller_service.dart';

const int kMaxHomeKitchenItems = 10;

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

class SellerHomeKitchenMenuScreen extends StatefulWidget {
  final String sellerId;

  // FIX (per Nizam's request): this screen used to be reachable only
  // by 'home_made' subCategory sellers — every other seller (Hotel,
  // etc.) got routed to SellerMenuSetupScreen's fixed preset-toggle
  // catalog instead of being able to author their own dishes at all.
  // Generalized this screen into the one custom-menu-creation UI for
  // EVERY seller by making the title/category label overridable;
  // existing 'home_made' call sites don't need to change since these
  // default to the exact copy they already showed.
  final String title;
  final String categoryName;

  const SellerHomeKitchenMenuScreen({
    required this.sellerId,
    this.title = 'My Home Kitchen Menu',
    this.categoryName = 'Home Kitchen',
    super.key,
  });

  @override
  State<SellerHomeKitchenMenuScreen> createState() =>
      _SellerHomeKitchenMenuScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('sellerId', sellerId));
    properties.add(StringProperty('title', title));
    properties.add(StringProperty('categoryName', categoryName));
  }
}

class _SellerHomeKitchenMenuScreenState
    extends State<SellerHomeKitchenMenuScreen> {
  final FoodSellerService _service = FoodSellerService();
  StreamSubscription<List<MenuItemModel>>? _sub;
  List<MenuItemModel> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _sub = _service.listenToMenuItems(widget.sellerId).listen((items) {
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _toggleAvailable(MenuItemModel item) async {
    try {
      await _service.updateMenuItem(
        widget.sellerId,
        item.id,
        {'isAvailable': !item.isAvailable},
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update: $e'), backgroundColor: _red),
      );
    }
  }

  Future<void> _deleteItem(MenuItemModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        title: Text('Delete "${item.name}"?',
            style: GoogleFonts.outfit(color: _text),),
        content: Text(
          'This dish will be removed from your menu permanently.',
          style: GoogleFonts.outfit(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: _muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: GoogleFonts.outfit(color: _red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteMenuItem(widget.sellerId, item.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e'), backgroundColor: _red),
      );
    }
  }

  Future<void> _openEditor({MenuItemModel? existing}) async {
    if (existing == null && _items.length >= kMaxHomeKitchenItems) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Max $kMaxHomeKitchenItems dishes reached. Delete one to add a new dish.',
          ),
          backgroundColor: _gold,
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DishEditorSheet(
        sellerId: widget.sellerId,
        service: _service,
        existing: existing,
        categoryName: widget.categoryName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canAddMore = _items.length < kMaxHomeKitchenItems;
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
          widget.title,
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w600),
        ),
        actions: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 14),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _teal.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_items.length}/$kMaxHomeKitchenItems dishes',
                style: GoogleFonts.outfit(
                  color: _tealLight,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : Column(
              children: [
                _buildInfoBanner(),
                Expanded(
                  child: _items.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                          itemCount: _items.length,
                          itemBuilder: (context, index) =>
                              _buildDishCard(_items[index]),
                        ),
                ),
              ],
            ),
      floatingActionButton: canAddMore
          ? FloatingActionButton.extended(
              backgroundColor: _teal,
              onPressed: _openEditor,
              icon: const Icon(Icons.add_a_photo_outlined, color: Colors.white),
              label: Text(
                'Add Dish',
                style:
                    GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            )
          : null,
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _teal.withValues(alpha: 0.1),
        border: Border(bottom: BorderSide(color: _teal.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline, color: _gold, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Add your own dishes with a photo, name and price. Switch a '
              'dish ON to make it live for customers right away.',
              style: GoogleFonts.outfit(color: _text.withValues(alpha: 0.8), fontSize: 12),
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
          const Icon(Icons.ramen_dining_outlined, size: 64, color: _muted),
          const SizedBox(height: 16),
          Text(
            'No dishes added yet',
            style: GoogleFonts.outfit(color: _muted, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap "Add Dish" to add your first home-made dish',
            style: GoogleFonts.outfit(color: _muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDishCard(MenuItemModel item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                ? Image.network(
                    CloudinaryUploadService.optimizedUrl(item.imageUrl!, width: 136),
                    width: 68,
                    height: 68,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _dishPlaceholder(),
                  )
                : _dishPlaceholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: GoogleFonts.outfit(
                      color: _text, fontSize: 15, fontWeight: FontWeight.w600,),
                ),
                if ((item.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(color: _muted, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  '₹${item.price.toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(
                      color: _tealLight, fontSize: 14, fontWeight: FontWeight.w700,),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Switch(
                value: item.isAvailable,
                activeThumbColor: _teal,
                onChanged: (_) => _toggleAvailable(item),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: _muted, size: 18),
                    onPressed: () => _openEditor(existing: item),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: _red, size: 18),
                    onPressed: () => _deleteItem(item),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dishPlaceholder() {
    return Container(
      width: 68,
      height: 68,
      color: _card2,
      child: Center(
        // Reusing FluentEmojiFlat.hamburger — a confirmed-valid icon
        // identifier already used elsewhere (dashboard_screen.dart,
        // product_card.dart) rather than guessing an unverified name.
        child: SvgPicture.string(FluentEmojiFlat.hamburger, width: 34, height: 34),
      ),
    );
  }
}

class _DishEditorSheet extends StatefulWidget {
  final String sellerId;
  final FoodSellerService service;
  final MenuItemModel? existing;
  final String categoryName;

  const _DishEditorSheet({
    required this.sellerId,
    required this.service,
    this.existing,
    this.categoryName = 'Home Kitchen',
  });

  @override
  State<_DishEditorSheet> createState() => _DishEditorSheetState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('sellerId', sellerId));
    properties.add(DiagnosticsProperty<FoodSellerService>('service', service));
    properties.add(DiagnosticsProperty<MenuItemModel?>('existing', existing));
    properties.add(StringProperty('categoryName', categoryName));
  }
}

class _DishEditorSheetState extends State<_DishEditorSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  bool _isVeg = true;
  bool _isSaving = false;
  PlatformFile? _pickedImage;
  String? _existingImageUrl;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _descCtrl.text = e.description ?? '';
      _priceCtrl.text = e.price.toStringAsFixed(0);
      _isVeg = e.isVeg;
      _existingImageUrl = e.imageUrl;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform
          .pickFiles(type: FileType.image, withData: true);
      if (result != null && result.files.isNotEmpty) {
        setState(() => _pickedImage = result.files.first);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not pick image: $e'), backgroundColor: _red),
      );
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim());

    if (name.isEmpty) {
      _showError('Please enter a dish name');
      return;
    }
    if (price == null || price <= 0) {
      _showError('Please enter a valid price');
      return;
    }
    if (widget.existing == null && _pickedImage == null) {
      _showError('Please add a photo of the dish');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final itemId = widget.existing?.id ?? const Uuid().v4();
      String? imageUrl = _existingImageUrl;

      if (_pickedImage != null && _pickedImage!.bytes != null) {
        imageUrl = await CloudinaryUploadService().uploadImageBytes(
          _pickedImage!.bytes!,
          fileName: '$itemId.jpg',
          folder: 'home_kitchen_menu/${widget.sellerId}',
        );
      }

      if (widget.existing == null) {
        final item = MenuItemModel(
          id: itemId,
          name: name,
          description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          price: price,
          isVeg: _isVeg,
          imageUrl: imageUrl,
          categoryName: widget.categoryName,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await widget.service.addMenuItem(widget.sellerId, item);
      } else {
        await widget.service.updateMenuItem(widget.sellerId, itemId, {
          'name': name,
          'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          'price': price,
          'isVeg': _isVeg,
          'imageUrl': imageUrl,
        });
      }

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      _showError('Failed to save dish: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: _red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                widget.existing == null ? 'Add a Dish' : 'Edit Dish',
                style: GoogleFonts.outfit(
                    color: _text, fontSize: 18, fontWeight: FontWeight.w700,),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  width: double.infinity,
                  height: 140,
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border),
                  ),
                  child: _buildImagePreview(),
                ),
              ),
              const SizedBox(height: 14),
              _buildTextField(_nameCtrl, 'Dish name (e.g. Sambar Rice)'),
              const SizedBox(height: 10),
              _buildTextField(_descCtrl, 'Short description (optional)', maxLines: 2),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      _priceCtrl,
                      'Price (₹)',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    label: Text('Veg', style: GoogleFonts.outfit(fontSize: 12)),
                    selected: _isVeg,
                    selectedColor: _teal.withValues(alpha: 0.3),
                    onSelected: (v) => setState(() => _isVeg = true),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: Text('Non-Veg', style: GoogleFonts.outfit(fontSize: 12)),
                    selected: !_isVeg,
                    selectedColor: _red.withValues(alpha: 0.3),
                    onSelected: (v) => setState(() => _isVeg = false),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white,),
                        )
                      : Text(
                          widget.existing == null ? 'Add Dish' : 'Save Changes',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    if (_pickedImage != null && _pickedImage!.bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.memory(_pickedImage!.bytes!, fit: BoxFit.cover, width: double.infinity),
      );
    }
    if (_existingImageUrl != null && _existingImageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          CloudinaryUploadService.optimizedUrl(_existingImageUrl!, width: 800),
          fit: BoxFit.cover,
          width: double.infinity,
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.add_a_photo_outlined, color: _muted, size: 32),
          const SizedBox(height: 6),
          Text('Tap to add photo', style: GoogleFonts.outfit(color: _muted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String hint,
      {int maxLines = 1, TextInputType? keyboardType,}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: GoogleFonts.outfit(color: _text, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.outfit(color: _muted, fontSize: 13),
        filled: true,
        fillColor: _card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _teal, width: 1.5),
        ),
      ),
    );
  }
}
