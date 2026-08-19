// ================================================================
// SellerMobileListingEditor — add / edit one phone listing
// ================================================================
// THE COST DECISION LIVES HERE, in the photo section.
//
// A seller picking a model from the shared catalog gets that model's
// shared image for free — no upload, no storage, and the same single
// Cloudinary asset is reused by every shop listing that model. Ten
// shops selling a Galaxy S24 cost us ONE image, not ten.
//
// A photo upload is offered but only actually needed when:
//   * the phone is USED (a buyer must see the real unit — a stock
//     image would misrepresent it), or
//   * the model isn't in the shared catalog yet.
// Uploads are compressed to ~100 KB, the same budget as menu photos.
//
// If neither a shared image nor an upload exists, the customer UI
// falls back to a local icon. It never shows a broken image and never
// pulls a scraped third-party URL — that path was considered and
// rejected on copyright and reliability grounds.
// ================================================================

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/mobile_models.dart';
import '../services/cloudinary_upload_service.dart';
import '../services/mobile_catalog_service.dart';
import '../services/mobile_listing_service.dart';
import '../widgets/cached_cloud_image.dart';
import '../widgets/video_link_field.dart';
import '../widgets/menu_photo_pick_crop.dart';

const Color _bg = Color(0xFFF7FAF8);
const Color _card = Color(0xFFFFFFFF);
const Color _pink = Color(0xFFE0418F);
const Color _green = Color(0xFF2E9E63);
const Color _text = Color(0xFF1A1A1A);
const Color _muted = Color(0xFF6B7280);
const Color _border = Color(0x1A11998E);
const Color _red = Color(0xFFD64545);

/// Same ~100 KB budget as seller menu photos.
const int _kListingPhotoTargetBytes = 100 * 1024;

class SellerMobileListingEditor extends StatefulWidget {
  final String sellerId;
  final String sellerName;
  final String sellerPhone;
  final MobileListing? existing;
  final String initialCondition;

  const SellerMobileListingEditor({
    super.key,
    required this.sellerId,
    required this.sellerName,
    required this.sellerPhone,
    this.existing,
    this.initialCondition = MobileCondition.isNew,
  });

  @override
  State<SellerMobileListingEditor> createState() =>
      _SellerMobileListingEditorState();
}

class _SellerMobileListingEditorState extends State<SellerMobileListingEditor> {
  final MobileListingService _service = MobileListingService();

  final _brandCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _variantCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _mrpCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _warrantyCtrl = TextEditingController();
  final _youtubeCtrl = TextEditingController();

  late String _condition = widget.existing?.condition ?? widget.initialCondition;
  String _modelKey = '';
  String? _grade;
  Uint8List? _newPhotoBytes;
  String? _existingPhotoUrl;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;
  bool get _isUsed => _condition == MobileCondition.used;

  @override
  void initState() {
    super.initState();
    MobileCatalogService.instance.ensureLoaded();
    final e = widget.existing;
    if (e != null) {
      _brandCtrl.text = e.brand;
      _modelCtrl.text = e.model;
      _variantCtrl.text = e.variant;
      _colorCtrl.text = e.color;
      _priceCtrl.text = e.price == 0 ? '' : e.price.toInt().toString();
      _mrpCtrl.text = e.mrp == null ? '' : e.mrp!.toInt().toString();
      _notesCtrl.text = e.notes ?? '';
      _warrantyCtrl.text =
          e.warrantyMonths == 0 ? '' : e.warrantyMonths.toString();
      _modelKey = e.modelKey;
      _grade = e.conditionGrade;
      _existingPhotoUrl = e.imageUrl;
      _youtubeCtrl.text = e.youtubeUrl ?? '';
    }
    _grade ??= kUsedConditionGrades.first;
  }

  @override
  void dispose() {
    _brandCtrl.dispose();
    _modelCtrl.dispose();
    _variantCtrl.dispose();
    _colorCtrl.dispose();
    _priceCtrl.dispose();
    _mrpCtrl.dispose();
    _notesCtrl.dispose();
    _warrantyCtrl.dispose();
    _youtubeCtrl.dispose();
    super.dispose();
  }

  /// The shared image this listing would inherit if the seller uploads
  /// nothing. Null when the model is off-catalog or has no photo yet.
  String? get _sharedImageUrl =>
      MobileCatalogService.instance.sharedImageUrlFor(_modelKey);

  Future<void> _pickFromCatalog() async {
    await MobileCatalogService.instance.ensureLoaded();
    if (!mounted) return;
    final picked = await showModalBottomSheet<CatalogPhone>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _CatalogPickerSheet(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _modelKey = picked.modelKey;
      _brandCtrl.text = picked.brand;
      _modelCtrl.text = picked.model;
      if (picked.variants.isNotEmpty && _variantCtrl.text.trim().isEmpty) {
        _variantCtrl.text = picked.variants.first;
      }
    });
  }

  Future<void> _pickPhoto() async {
    // askShape: false — see sell_your_phone_sheet.dart: phone listings
    // render in rectangular cards, so the food-only shape chooser is
    // skipped.
    final picked = await pickAndCropMenuPhoto(context, askShape: false);
    if (picked != null && mounted) {
      setState(() => _newPhotoBytes = picked.bytes);
    }
  }

  Future<void> _save() async {
    final brand = _brandCtrl.text.trim();
    final model = _modelCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;

    if (brand.isEmpty || model.isEmpty) {
      _toast('Please enter the brand and model');
      return;
    }
    if (price <= 0) {
      _toast('Please enter a valid price');
      return;
    }
    final mrp = _mrpCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_mrpCtrl.text.trim());
    if (mrp != null && mrp <= price) {
      _toast('Original price must be higher than the selling price');
      return;
    }

    // Reject a bad paste HERE rather than shipping a listing whose
    // video button leads nowhere. Empty is fine — video is optional.
    final ytRaw = _youtubeCtrl.text.trim();
    if (ytRaw.isNotEmpty && !isValidYoutubeUrl(ytRaw)) {
      _toast('That does not look like a YouTube link. Paste the '
          'share link from the YouTube app.');
      return;
    }

    setState(() => _saving = true);
    try {
      // Only upload when the seller actually chose a new photo. An
      // unchanged listing re-saves its existing URL, so editing a price
      // never re-uploads an image.
      String? imageUrl = _existingPhotoUrl;
      if (_newPhotoBytes != null) {
        imageUrl = await CloudinaryUploadService().uploadImageBytes(
          _newPhotoBytes!,
          fileName:
              '${widget.sellerId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          folder: 'mobile_listings/${widget.sellerId}',
          targetBytes: _kListingPhotoTargetBytes,
        );
      }

      final listing = MobileListing(
        id: widget.existing?.id ?? '',
        sellerId: widget.sellerId,
        sellerName: widget.sellerName,
        sellerPhone: widget.sellerPhone,
        condition: _condition,
        brand: brand,
        model: model,
        modelKey: _modelKey,
        variant: _variantCtrl.text.trim(),
        color: _colorCtrl.text.trim(),
        price: price,
        mrp: mrp,
        imageUrl: imageUrl,
        conditionGrade: _isUsed ? _grade : null,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        warrantyMonths: int.tryParse(_warrantyCtrl.text.trim()) ?? 0,
        inStock: widget.existing?.inStock ?? true,
        youtubeUrl: ytRaw.isEmpty ? null : ytRaw,
      );

      if (_isEdit) {
        await _service.updateListing(listing);
      } else {
        await _service.addListing(listing);
      }

      if (!mounted) return;
      Navigator.pop(context);
    } on StateError catch (e) {
      // Listing-cap message from the service — show it as-is, it's
      // already customer-readable.
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast('Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: _red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        elevation: 0,
        title: Text(
          _isEdit ? 'Edit Phone' : 'Add Phone',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildConditionToggle(),
          const SizedBox(height: 18),
          _buildCatalogPicker(),
          const SizedBox(height: 18),
          _field(_brandCtrl, 'Brand *', 'e.g. Samsung'),
          _field(_modelCtrl, 'Model *', 'e.g. Galaxy A55 5G'),
          _field(_variantCtrl, 'Variant', 'e.g. 8/256'),
          _field(_colorCtrl, 'Colour', 'e.g. Awesome Navy'),
          _field(_priceCtrl, 'Selling price (₹) *', '0',
              keyboard: TextInputType.number),
          _field(_mrpCtrl, 'Original price (₹)',
              'Optional — shows a discount badge',
              keyboard: TextInputType.number),
          _field(_warrantyCtrl, 'Warranty (months)', '0',
              keyboard: TextInputType.number),
          if (_isUsed) _buildGradePicker(),
          _field(_notesCtrl, _isUsed ? 'Condition details' : 'Notes',
              _isUsed ? 'Bill/box available, minor scratches…' : 'Optional',
              maxLines: 3),
          _buildYoutubeField(),
          const SizedBox(height: 4),
          _buildPhotoSection(),
          const SizedBox(height: 26),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _pink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      _isEdit ? 'Save Changes' : 'Add to My Shop',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConditionToggle() {
    const options = [
      [MobileCondition.isNew, 'Brand New'],
      [MobileCondition.used, 'Used'],
    ];
    return Row(
      children: options.map((o) {
        final value = o[0];
        final label = o[1];
        final active = _condition == value;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _condition = value),
            child: Container(
              margin: EdgeInsets.only(right: value == MobileCondition.isNew ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: active ? _pink : _card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: active ? _pink : _border),
              ),
              child: Center(
                child: Text(
                  label,
                  style: GoogleFonts.outfit(
                    color: active ? Colors.white : _muted,
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCatalogPicker() {
    final shared = _sharedImageUrl;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _pickFromCatalog,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _pink.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _pink.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.list_alt_rounded, color: _pink, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _modelKey.isEmpty
                        ? 'Pick from phone list'
                        : 'Picked from list',
                    style: GoogleFonts.outfit(
                      color: _text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _modelKey.isEmpty
                        ? 'Fills brand/model for you — and gives a free photo'
                        : (shared != null
                            ? 'Free photo included — no upload needed'
                            : 'Brand and model filled in'),
                    style: GoogleFonts.outfit(color: _muted, fontSize: 11),
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

  Widget _buildGradePicker() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Condition grade',
            style: GoogleFonts.outfit(
              color: _text,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kUsedConditionGrades.map((g) {
              final active = _grade == g;
              return GestureDetector(
                onTap: () => setState(() => _grade = g),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: active ? _pink : _card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: active ? _pink : _border),
                  ),
                  child: Text(
                    g,
                    style: GoogleFonts.outfit(
                      color: active ? Colors.white : _muted,
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// Optional YouTube link. Costs us nothing to store or serve — see
  /// MobileListing.youtubeUrl — which is why video is offered on phones
  /// but not on food. Uses the SHARED VideoLinkField so the seller app
  /// and the admin offers form validate identically; two hand-rolled
  /// copies would inevitably accept different URL shapes.
  Widget _buildYoutubeField() {
    return VideoLinkField(
      controller: _youtubeCtrl,
      onChanged: () => setState(() {}),
      label: 'Video of this phone',
      helper: 'A 30-second clip showing the phone switched on sells a used '
          'device far better than photos. Upload it to your shop\'s YouTube '
          'channel (free), then paste the share link here.',
      fillColor: _card,
      textColor: _text,
      mutedColor: _muted,
      borderColor: _border,
      accentColor: _pink,
    );
  }

  Widget _buildPhotoSection() {
    final shared = _sharedImageUrl;
    final hasOwn = _newPhotoBytes != null ||
        (_existingPhotoUrl != null && _existingPhotoUrl!.isNotEmpty);

    // For a NEW phone already matched to a catalog model with a shared
    // photo, an upload is genuinely unnecessary — say so plainly rather
    // than nudging the seller into spending our storage for nothing.
    final uploadOptional = !_isUsed && shared != null && !hasOwn;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isUsed ? 'Photo of this phone *' : 'Photo',
          style: GoogleFonts.outfit(
            color: _text,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _isUsed
              ? 'Buyers need to see the actual phone before they commit.'
              : (uploadOptional
                  ? 'Already covered by the standard photo below — upload only if you want your own.'
                  : 'Optional. Pick from the phone list above to get a free photo.'),
          style: GoogleFonts.outfit(color: _muted, fontSize: 11),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview of whatever the customer will actually see.
            Container(
              width: 96,
              height: 108,
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildPreview(shared),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (uploadOptional)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Free photo in use',
                        style: GoogleFonts.outfit(
                          color: _green,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  if (uploadOptional) const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _pickPhoto,
                    icon: const Icon(Icons.add_a_photo_outlined,
                        color: _pink, size: 17),
                    label: Text(
                      hasOwn ? 'Change photo' : 'Upload photo',
                      style: GoogleFonts.outfit(color: _text, fontSize: 12.5),
                    ),
                  ),
                  if (hasOwn) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => setState(() {
                        _newPhotoBytes = null;
                        _existingPhotoUrl = null;
                      }),
                      child: Text(
                        'Remove my photo',
                        style:
                            GoogleFonts.outfit(color: _muted, fontSize: 11.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreview(String? shared) {
    if (_newPhotoBytes != null) {
      return Image.memory(_newPhotoBytes!, fit: BoxFit.cover);
    }
    if (_existingPhotoUrl != null && _existingPhotoUrl!.isNotEmpty) {
      return CachedCloudImage(_existingPhotoUrl!,
          fit: BoxFit.cover, cacheWidth: 220);
    }
    if (shared != null) {
      return CachedCloudImage(shared, fit: BoxFit.contain, cacheWidth: 220);
    }
    return const Center(
      child: Icon(Icons.smartphone_rounded, color: _muted, size: 30),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    String hint, {
    int maxLines = 1,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(
              color: _text,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            maxLines: maxLines,
            keyboardType: keyboard,
            style: GoogleFonts.outfit(color: _text, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.outfit(color: _muted, fontSize: 12.5),
              filled: true,
              fillColor: _card,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _pink),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// Catalog picker — searches the bundled JSON. Zero network, zero DB.
// ================================================================
class _CatalogPickerSheet extends StatefulWidget {
  const _CatalogPickerSheet();

  @override
  State<_CatalogPickerSheet> createState() => _CatalogPickerSheetState();
}

class _CatalogPickerSheetState extends State<_CatalogPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final results = MobileCatalogService.instance.search(_query);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: TextField(
                    autofocus: true,
                    onChanged: (v) => setState(() => _query = v),
                    style: GoogleFonts.outfit(color: _text, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search brand or model…',
                      hintStyle:
                          GoogleFonts.outfit(color: _muted, fontSize: 13),
                      prefixIcon:
                          const Icon(Icons.search_rounded, color: _muted),
                      filled: true,
                      fillColor: _card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _pink),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: results.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(30),
                            child: Text(
                              'Not in the list — just close this and type the '
                              'brand and model yourself.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                  color: _muted, fontSize: 13),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                          itemCount: results.length,
                          itemBuilder: (context, i) {
                            final p = results[i];
                            return ListTile(
                              onTap: () => Navigator.pop(context, p),
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _card,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: p.imageUrl.isEmpty
                                    ? const Icon(Icons.smartphone_rounded,
                                        color: _muted, size: 19)
                                    : CachedCloudImage(p.imageUrl,
                                        fit: BoxFit.contain, cacheWidth: 90),
                              ),
                              title: Text(
                                p.model,
                                style: GoogleFonts.outfit(
                                  color: _text,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                p.variants.isEmpty
                                    ? p.brand
                                    : '${p.brand} · ${p.variants.join(", ")}',
                                style: GoogleFonts.outfit(
                                    color: _muted, fontSize: 11),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
