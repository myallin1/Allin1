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
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../models/food_models.dart';
import '../services/cloudinary_upload_service.dart';
import '../services/food_seller_service.dart';
import '../widgets/menu_photo_pick_crop.dart';
import 'package:erode_superapp/widgets/cached_cloud_image.dart';

const int kMaxHomeKitchenItems = 10;

// NEW (Aug 18 2026 bandwidth audit, per Nizam: "100kb range la pakka
// clarity oda varramari namma plan pannanum" for seller dish photos
// specifically). CloudinaryUploadService's own default
// (kPhotoTargetBytes, 150KB) is shared by every casual-photo upload
// site in the app — lowering it globally would also shrink offer
// banners, hero payment QR previews, etc. This constant is scoped to
// menu/dish photos only.
const int _kMenuPhotoTargetBytes = 100 * 1024;

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
          // Renders the SAME shape the seller cropped for (Aug 18
          // 2026). A round crop shown in a rounded square would
          // reveal the corners the seller deliberately framed out.
          _shapedThumb(
            shape: MenuPhotoShapeX.fromStorage(item.imageShape),
            child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                ? CachedCloudImage(
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
                // PHASE 3: price row now reflects a live offer, and the
                // section chip lets a seller confirm at a glance that
                // their grouping is right — without opening each dish.
                Row(
                  children: [
                    if (item.discountedPrice != null &&
                        item.discountedPrice! > 0 &&
                        item.discountedPrice! < item.price) ...[
                      Text(
                        '₹${item.discountedPrice!.toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                          color: _tealLight,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '₹${item.price.toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                          color: _muted,
                          fontSize: 12,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _red.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'OFFER',
                          style: GoogleFonts.outfit(
                            color: _red,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ] else
                      Text(
                        '₹${item.price.toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                          color: _tealLight,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
                if ((item.categoryName ?? '').trim().isNotEmpty &&
                    item.categoryName != 'Menu' &&
                    item.categoryName != 'Home Kitchen') ...[
                  const SizedBox(height: 5),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: _card2,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _border),
                    ),
                    child: Text(
                      item.categoryName!,
                      style: GoogleFonts.outfit(
                          color: _muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
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

  /// Clips a thumbnail to the shape the seller chose. Square uses
  /// the original ClipRRect(12) so every pre-existing dish looks
  /// byte-for-byte identical to before this feature landed.
  Widget _shapedThumb({required MenuPhotoShape shape, required Widget child}) {
    if (shape == MenuPhotoShape.circle) {
      return ClipOval(child: SizedBox(width: 68, height: 68, child: child));
    }
    return ClipRRect(borderRadius: BorderRadius.circular(12), child: child);
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

  // ── PHASE 3 (Aug 17 2026 seller audit) ────────────────────────────
  // Nizam: "menu style yellam advanced international corporate app mari
  // infra build aganum, customere combo offers lam podanum".
  //
  // Both of these were ALREADY supported by MenuItemModel and already
  // read by the customer app — they were simply never written by this
  // editor, which is why every menu rendered as one flat ungrouped list
  // at full price. No model change, no schema change, no customer-side
  // change: this closes the write side of fields that were already
  // wired end to end.

  /// Section this dish belongs to — "Biriyani", "Starters", "Combo
  /// Offers"...
  ///
  /// seller_detail_screen.dart groups the customer-facing menu by
  /// exactly this field. Until now the dashboard passed one hardcoded
  /// value ('Menu' / 'Home Kitchen') for EVERY dish, so the grouping
  /// logic dutifully produced a single group containing everything —
  /// the real reason the menu looked flat and "dummy".
  final _categoryCtrl = TextEditingController();

  /// Offer price. When set and lower than [_priceCtrl], the customer
  /// app shows it as the live price with the original struck through —
  /// MenuItemModel.discountedPrice has existed since the model was
  /// written. This is how a seller runs a combo/festival offer.
  final _offerPriceCtrl = TextEditingController();

  bool _isVeg = true;
  bool _isSaving = false;
  // Was PlatformFile? (raw FilePicker result) — now holds the CROPPED
  // bytes returned by pickAndCropMenuPhoto(), see _pickImage() above.
  Uint8List? _pickedImageBytes;
  // Shape the seller framed for (Aug 18 2026 CTO review). Seeded
  // from the existing item on edit so re-saving without touching
  // the photo never silently flips a round dish back to square.
  MenuPhotoShape _pickedImageShape = MenuPhotoShape.square;
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
      // Seed the saved shape so editing a dish's PRICE (without
      // re-picking the photo) re-saves the same shape it already had,
      // instead of silently resetting a round photo back to square.
      _pickedImageShape = MenuPhotoShapeX.fromStorage(e.imageShape);
      // Don't seed the old hardcoded placeholder back into the field —
      // showing 'Menu' as if the seller had chosen it would make them
      // keep it, and nothing would ever get grouped.
      final existingCat = (e.categoryName ?? '').trim();
      _categoryCtrl.text =
          (existingCat == 'Menu' || existingCat == 'Home Kitchen')
              ? ''
              : existingCat;
      if (e.discountedPrice != null && e.discountedPrice! > 0) {
        _offerPriceCtrl.text = e.discountedPrice!.toStringAsFixed(0);
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _categoryCtrl.dispose();
    _offerPriceCtrl.dispose();
    super.dispose();
  }

  // FIX (Aug 18 2026 bandwidth audit, per Nizam: "seller menu image...
  // round cut baground image cut pannivaikura custom options irukka
  // bcoz customer big size image vachchutta namma bandwith
  // theenthurum"): this used to go straight from FilePicker to state —
  // whatever framing/aspect the seller's raw photo happened to have
  // shipped as-is. pickAndCropMenuPhoto() adds the same proven
  // pick-then-crop step hero_qr_pick_crop.dart already uses for payment
  // QRs (square bounding box, circular framing guide so the seller
  // centers the dish and crops the background out), with the same
  // graceful fallback — if cropping fails/cancels, the originally
  // picked bytes are used rather than the whole action silently doing
  // nothing.
  Future<void> _pickImage() async {
    try {
      final picked = await pickAndCropMenuPhoto(context);
      if (picked != null && mounted) {
        setState(() {
          _pickedImageBytes = picked.bytes;
          _pickedImageShape = picked.shape;
        });
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
    if (widget.existing == null && _pickedImageBytes == null) {
      _showError('Please add a photo of the dish');
      return;
    }

    // Offer price is optional, but a nonsensical one must not reach the
    // customer app — an "offer" at or above the normal price would
    // render as a struck-through saving of zero (or worse, negative),
    // which reads as a trick rather than a deal.
    final offerRaw = _offerPriceCtrl.text.trim();
    double? offerPrice;
    if (offerRaw.isNotEmpty) {
      offerPrice = double.tryParse(offerRaw);
      if (offerPrice == null || offerPrice <= 0) {
        _showError('Offer price must be a number greater than 0');
        return;
      }
      if (offerPrice >= price) {
        _showError(
            'Offer price must be LOWER than the normal price (₹${price.toStringAsFixed(0)})');
        return;
      }
    }

    // Falls back to the screen's own title when the seller leaves it
    // blank, so behaviour is identical to before for anyone who ignores
    // the new field — their dishes just stay in one group, as today.
    final category = _categoryCtrl.text.trim().isEmpty
        ? widget.categoryName
        : _categoryCtrl.text.trim();

    setState(() => _isSaving = true);
    try {
      final itemId = widget.existing?.id ?? const Uuid().v4();
      String? imageUrl = _existingImageUrl;

      if (_pickedImageBytes != null) {
        imageUrl = await CloudinaryUploadService().uploadImageBytes(
          _pickedImageBytes!,
          fileName: '$itemId.jpg',
          folder: 'home_kitchen_menu/${widget.sellerId}',
          // NEW (Aug 18 2026 bandwidth audit): was the default 150KB
          // (kPhotoTargetBytes) — menu photos specifically now target
          // ~100KB per Nizam's request, on top of the crop step above.
          targetBytes: _kMenuPhotoTargetBytes,
        );
      }

      if (widget.existing == null) {
        final item = MenuItemModel(
          id: itemId,
          name: name,
          description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          price: price,
          discountedPrice: offerPrice,
          isVeg: _isVeg,
          imageUrl: imageUrl,
          categoryName: category,
          imageShape: _pickedImageShape.storageValue,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await widget.service.addMenuItem(widget.sellerId, item);
      } else {
        await widget.service.updateMenuItem(widget.sellerId, itemId, {
          'name': name,
          'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          'price': price,
          // Explicit null clears a finished offer. Omitting the key
          // would leave a stale discount live forever with no way for
          // the seller to end it.
          'discountedPrice': offerPrice,
          'isVeg': _isVeg,
          'imageUrl': imageUrl,
          // Kept in lockstep with imageUrl: the card renders this
          // shape, so a stale value would mis-frame the dish.
          'imageShape': _pickedImageShape.storageValue,
          'categoryName': category,
          // MenuItemModel.toJson writes 'category' as a display-layer
          // alias of categoryName, because SellerDetailScreen's grouping
          // reads the raw map, not the model. updateMenuItem() bypasses
          // toJson (it takes a field map), so the alias has to be kept
          // in sync by hand here or an edited dish would group under its
          // OLD category while the list showed the new one.
          'category': category,
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
              // ── Section / category (Phase 3) ────────────────────
              _buildTextField(
                _categoryCtrl,
                'Section (e.g. Biriyani, Starters, Combo Offers)',
              ),
              const SizedBox(height: 4),
              Text(
                'Dishes with the same section name appear grouped together '
                'in the customer app. Leave blank to keep it ungrouped.',
                style: GoogleFonts.outfit(
                    color: _muted, fontSize: 11, height: 1.35),
              ),
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
                  const SizedBox(width: 10),
                  // ── Offer price (Phase 3) ─────────────────────────
                  Expanded(
                    child: _buildTextField(
                      _offerPriceCtrl,
                      'Offer ₹ (optional)',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Set an offer price and customers see it as the live price '
                'with the old price struck through. Clear it to end the offer.',
                style: GoogleFonts.outfit(
                    color: _muted, fontSize: 11, height: 1.35),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Spacer(),
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
    // Preview mirrors the chosen shape so the seller sees exactly
    // what the customer will get, before they save.
    final isRound = _pickedImageShape == MenuPhotoShape.circle;
    if (_pickedImageBytes != null) {
      final img = Image.memory(_pickedImageBytes!,
          fit: BoxFit.cover, width: double.infinity);
      return isRound
          ? Center(
              child: ClipOval(
                child: SizedBox(
                    width: 150, height: 150, child: img),
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(14), child: img);
    }
    if (_existingImageUrl != null && _existingImageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: CachedCloudImage(
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

