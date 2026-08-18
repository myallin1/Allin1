// ================================================================
// SellerCustomHotelBuilderScreen — the "empty canvas" menu builder.
// ================================================================
// NEW (CTO mandate — Custom Hotel Integration System). Reached from
// SellerDashboardScreen's new "OR — Build a Custom Hotel" card (added
// additively, next to the existing "Manage Menu" button — see that
// file's comment at the call site). Talks ONLY to CustomHotelService /
// the `custom_hotels` collection — never touches `sellers/{uid}` or
// `sellers/{uid}/menu_items`, so the existing seller menu flow
// (SellerHomeKitchenMenuScreen / FoodSellerService) is provably
// unaffected by this screen's existence.
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;

import '../services/auth_service.dart';
import '../services/cloudinary_upload_service.dart';
import '../services/custom_hotel_service.dart';
import 'package:erode_superapp/widgets/cached_cloud_image.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF0D0D18);
const Color _card = Color(0xFF141420);
const Color _teal = Color(0xFF11998E);
const Color _tealLight = Color(0xFF38EF7D);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);
const Color _red = Color(0xFFFF5252);

class SellerCustomHotelBuilderScreen extends StatefulWidget {
  const SellerCustomHotelBuilderScreen({required this.sellerId, required this.sellerName, super.key});
  final String sellerId;
  final String sellerName;

  @override
  State<SellerCustomHotelBuilderScreen> createState() => _SellerCustomHotelBuilderScreenState();
}

class _SellerCustomHotelBuilderScreenState extends State<SellerCustomHotelBuilderScreen> {
  final CustomHotelService _service = CustomHotelService();
  bool _ensuring = true;

  @override
  void initState() {
    super.initState();
    // FIX (audit: "Seller custom-menu phone not wiring to customer side"):
    // ensureHotelDoc() used to be called with no phone at all, so
    // custom_hotels/{sellerId} never had a number for the customer's Call
    // button to read. Resolve it the same Firestore-first / Auth-fallback
    // way AuthService already resolves customer/hero phones — a seller
    // who signed up via Google + a typed mobile number has that number
    // only in sellers/{uid}.phone, never on the FirebaseAuth user object.
    AuthService().resolveSellerPhone(widget.sellerId, user: FirebaseAuth.instance.currentUser).then((phone) {
      return _service.ensureHotelDoc(
        sellerId: widget.sellerId,
        hotelName: widget.sellerName,
        sellerPhone: phone,
      );
    }).whenComplete(() {
      if (mounted) setState(() => _ensuring = false);
    });
  }

  Future<void> _openItemEditor({CustomHotelItem? existing}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ItemEditorSheet(
        sellerId: widget.sellerId,
        service: _service,
        existing: existing,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_ensuring) {
      return const Scaffold(backgroundColor: _bg, body: Center(child: CircularProgressIndicator(color: _teal)));
    }
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        title: Text('Custom Hotel Builder', style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _teal,
        onPressed: () => _openItemEditor(),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Item', style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          // NEW — global Hotel Open/Close toggle (CTO mandate #3). Live
          // via hotelStream, so a toggle flip anywhere (e.g. this
          // seller signed in on a second device) reflects here too.
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _service.hotelStream(widget.sellerId),
            builder: (context, snap) {
              final isOpen = snap.data?.data()?['isOpen'] as bool? ?? false;
              return Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isOpen ? _tealLight : _border),
                ),
                child: Row(
                  children: [
                    Icon(isOpen ? Icons.storefront_rounded : Icons.storefront_outlined,
                        color: isOpen ? _tealLight : _muted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isOpen ? 'Your Custom Hotel is OPEN — visible to customers' : 'Your Custom Hotel is CLOSED',
                        style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    Switch(
                      value: isOpen,
                      activeThumbColor: _tealLight,
                      onChanged: (v) => _service.setHotelOpen(sellerId: widget.sellerId, isOpen: v),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _service.sellerItemsStream(widget.sellerId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                  return const Center(child: CircularProgressIndicator(color: _teal));
                }
                final docs = snap.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Empty canvas — tap "Add Item" to build your menu.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(color: _muted, fontSize: 13),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final item = CustomHotelItem.fromDoc(docs[i]);
                    return _ItemCard(
                      item: item,
                      onTap: () => _openItemEditor(existing: item),
                      onToggleVisible: (v) =>
                          _service.setItemVisible(sellerId: widget.sellerId, itemId: item.id, isVisible: v),
                      onDelete: () => _service.deleteItem(sellerId: widget.sellerId, itemId: item.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.onTap, required this.onToggleVisible, required this.onDelete});
  final CustomHotelItem item;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggleVisible;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: item.photoUrl.isEmpty
                ? Container(width: 56, height: 56, color: _bg, child: const Icon(Icons.fastfood_rounded, color: _muted))
                : CachedCloudImage(
                    CloudinaryUploadService.optimizedUrl(item.photoUrl, width: 112),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name.isEmpty ? '(untitled)' : item.name,
                      style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 13.5)),
                  const SizedBox(height: 2),
                  Text('₹${item.price.toStringAsFixed(0)}', style: GoogleFonts.outfit(color: _tealLight, fontSize: 12)),
                  if (item.description.isNotEmpty)
                    Text(item.description,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(color: _muted, fontSize: 11)),
                ],
              ),
            ),
          ),
          Column(
            children: [
              Switch(value: item.isVisible, activeThumbColor: _tealLight, onChanged: onToggleVisible),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: _red, size: 18),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: _surface,
                    title: const Text('Delete item?', style: TextStyle(color: _text)),
                    content: Text('Remove "${item.name}" permanently?', style: const TextStyle(color: _muted)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          onDelete();
                        },
                        child: const Text('Delete', style: TextStyle(color: _red)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ItemEditorSheet extends StatefulWidget {
  const _ItemEditorSheet({required this.sellerId, required this.service, this.existing});
  final String sellerId;
  final CustomHotelService service;
  final CustomHotelItem? existing;

  @override
  State<_ItemEditorSheet> createState() => _ItemEditorSheetState();
}

class _ItemEditorSheetState extends State<_ItemEditorSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _price = TextEditingController(text: widget.existing?.price.toStringAsFixed(0) ?? '');
  late final TextEditingController _desc = TextEditingController(text: widget.existing?.description ?? '');
  bool _visible = true;
  String _photoUrl = '';
  Uint8List? _pickedBytes;
  bool _saving = false;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _visible = widget.existing?.isVisible ?? true;
    _photoUrl = widget.existing?.photoUrl ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _desc.dispose();
    super.dispose();
  }

  Uint8List? _compress(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      // Auto-crop to a perfect 1:1 square to maintain uniformity and save bandwidth
      final size = decoded.width < decoded.height ? decoded.width : decoded.height;
      final squared = img.copyCrop(
        decoded,
        x: (decoded.width - size) ~/ 2,
        y: (decoded.height - size) ~/ 2,
        width: size,
        height: size,
      );
      final resized = squared.width > 800 ? img.copyResize(squared, width: 800, height: 800) : squared;
      // Use 85 quality for "super clarity premium 3D look" while staying ~100kb
      return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    setState(() => _pickedBytes = _compress(bytes) ?? bytes);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.trim()) ?? 0.0;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item name is required.')));
      return;
    }
    setState(() => _saving = true);
    try {
      var photoUrl = _photoUrl;
      if (_pickedBytes != null) {
        setState(() => _uploadingPhoto = true);
        photoUrl = await CloudinaryUploadService().uploadImageBytes(
          _pickedBytes!,
          fileName: 'custom_hotel_${widget.sellerId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          folder: 'custom_hotels',
          // NEW (Aug 18 2026 bandwidth audit): this screen's own
          // _compress() above already center-crops to a square and
          // resizes to 800px — was still uploaded at the default 150KB
          // (kPhotoTargetBytes) target. Menu/dish photos specifically
          // now target ~100KB per Nizam's request, matching
          // seller_home_kitchen_menu_screen.dart's menu-photo pipeline.
          targetBytes: 100 * 1024,
        );
        setState(() => _uploadingPhoto = false);
      }
      await widget.service.saveItem(
        sellerId: widget.sellerId,
        item: CustomHotelItem(
          id: widget.existing?.id ?? '',
          name: name,
          price: price,
          description: _desc.text.trim(),
          photoUrl: photoUrl,
          isVisible: _visible,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save item: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.existing == null ? 'Add Item' : 'Edit Item',
                style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _pickPhoto,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _pickedBytes != null
                    ? Image.memory(_pickedBytes!, width: double.infinity, height: 140, fit: BoxFit.cover)
                    : (_photoUrl.isNotEmpty
                        ? CachedCloudImage(
                            CloudinaryUploadService.optimizedUrl(_photoUrl, width: 800),
                            width: double.infinity,
                            height: 140,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: double.infinity,
                            height: 140,
                            color: _card,
                            child: const Center(child: Icon(Icons.add_a_photo_outlined, color: _muted, size: 32)),
                          )),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              style: const TextStyle(color: _text),
              decoration: const InputDecoration(labelText: 'Item Name', labelStyle: TextStyle(color: _muted)),
            ),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: _text),
              decoration: const InputDecoration(labelText: 'Price (₹)', labelStyle: TextStyle(color: _muted)),
            ),
            TextField(
              controller: _desc,
              maxLines: 2,
              style: const TextStyle(color: _text),
              decoration: const InputDecoration(labelText: 'Description', labelStyle: TextStyle(color: _muted)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Visible to customers', style: GoogleFonts.outfit(color: _text, fontSize: 13)),
                const Spacer(),
                Switch(value: _visible, activeThumbColor: _tealLight, onChanged: (v) => setState(() => _visible = v)),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _teal, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving ? (_uploadingPhoto ? 'Uploading photo...' : 'Saving...') : 'Save Item',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

