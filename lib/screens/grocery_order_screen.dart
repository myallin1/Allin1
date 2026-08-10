// ================================================================
// grocery_order_screen.dart — Broadcast Order System: Grocery Order
// Net-new screen (confirmed no prior version existed — only
// decorative category-banner icons). Text list and/or photo of a
// handwritten list; at least one is required. Image upload uses
// Cloudinary (not Firebase Storage — Storage now requires the Blaze
// plan to create a bucket at all, and Allin1 is staying on Spark).
// ================================================================
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/cloudinary_upload_service.dart';
import '../services/grocery_ai_notes_service.dart';
import '../services/service_request_service.dart';
import '../widgets/location_capture_field.dart';
import '../services/auth_service.dart';
import '../widgets/quick_order_line_items.dart';
import '../widgets/server_busy_dialog.dart';
import 'dmart_screen.dart';
import 'grocery_order_status_screen.dart';
import 'service_request_tracking_screen.dart';

const Color _kPink = Color(0xFFFF4FA3);
const Color _kBg = Color(0xFFFFFFFF);
const Color _kSurface = Color(0xFFF8F8FF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF9999BB);
const Color _kGreen = Color(0xFF00C853);
const Color _kBorder = Color(0xFFEEEEF5);

class GroceryOrderScreen extends StatefulWidget {
  const GroceryOrderScreen({super.key});
  @override
  State<GroceryOrderScreen> createState() => _GroceryOrderScreenState();
}

class _GroceryOrderScreenState extends State<GroceryOrderScreen> {
  List<OrderLineItem> _lineItems = [OrderLineItem()];
  // NEW (per Nizam's request — every service request needs a real
  // navigable delivery point for the hero): this form used to collect
  // zero location data at all, not even a text address.
  final _deliveryAddressCtrl = TextEditingController();
  double? _deliveryLat;
  double? _deliveryLng;
  // FIX (per Nizam's DMart-screenshot workflow request): was a single
  // PlatformFile -- a customer who browses DMart's cart (or any store)
  // and wants the hero to buy exactly what's shown needs to upload
  // MULTIPLE screenshots (their cart can span several scroll screens),
  // not just one. Capped at 10 -- enough for a large cart without
  // letting an upload balloon into dozens of images.
  static const int _maxImages = 10;
  final List<PlatformFile> _pickedFiles = [];
  bool _submitting = false;

  // NEW (CTO mandate — Dual-Mode Grocery Cart, Modes 2 & 3): the ONLY
  // touch this file gets for the new Guru-driven item flow. Consumes
  // anything Guru noted via chat/voice/"I Need This" and appends it
  // into `_listCtrl` — the exact same text field the customer would
  // type into by hand. `_submit()`, `_canSubmit`, the Cloudinary
  // upload, and the Firestore write below are completely untouched.
  @override
  void initState() {
    super.initState();
    final pending = GroceryAiNotesService.instance.consumeAll();
    if (pending.isNotEmpty) {
      final newItems = pending
          .where((line) => line.trim().isNotEmpty)
          .map((line) => OrderLineItem(name: line.trim()))
          .toList();
      if (newItems.isNotEmpty) {
        _lineItems = [
          ..._lineItems.where((it) => !it.isEmpty),
          ...newItems,
        ];
        if (_lineItems.isEmpty) _lineItems = [OrderLineItem()];
      }
    }
  }

  @override
  void dispose() {
    _deliveryAddressCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting &&
      (_lineItems.any((it) => !it.isEmpty) || _pickedFiles.isNotEmpty) &&
      _deliveryAddressCtrl.text.trim().isNotEmpty;

  // NEW (per Nizam/CTO's DMart UX workaround): DMart's own site rejects
  // Erode as a serviceable pincode -- that's DMart's business/inventory
  // logic, not something this app can bypass. Rather than let the
  // customer discover that dead end themselves inside the WebView, this
  // interstitial explains it up front and gives two pincodes (Coimbatore
  // 641014, Mumbai 400001) known to pass DMart's own gate, so they can
  // actually browse the catalog, then points them straight at the
  // screenshot-upload flow below to complete the order for real.
  Future<void> _openDmartWithPincodeNotice(BuildContext context) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _kBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Before you open DMart', style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 16)),
        // FIX (QA bug — dense single paragraph was hard to scan):
        // refactored into a clean 3-step numbered list, one action per
        // line, same information as before.
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "DMart doesn't officially deliver here, but you can still browse and order:",
              style: TextStyle(color: _kMuted, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            _DmartStep(
              number: '1',
              text: 'When DMart asks for your location, enter Pincode 641014 (Coimbatore) or 400001 (Mumbai).',
            ),
            const SizedBox(height: 10),
            _DmartStep(
              number: '2',
              text: 'Add whatever you need to your DMart cart, then take screenshots of it.',
            ),
            const SizedBox(height: 10),
            _DmartStep(
              number: '3',
              text: 'Come back and upload those screenshots in our Send Order section below.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel', style: TextStyle(color: _kMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kGreen),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Got it, Open DMart', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (proceed == true && context.mounted) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const DmartScreen()),
      );
    }
  }

  Future<void> _pickImages() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;
      setState(() {
        for (final file in result.files) {
          if (_pickedFiles.length >= _maxImages) break;
          _pickedFiles.add(file);
        }
      });
      if (result.files.length > _maxImages && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Only the first $_maxImages images were added.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick images: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _removeImage(int index) {
    setState(() => _pickedFiles.removeAt(index));
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      final service = ServiceRequestService();
      final requestId = service.reserveRequestId();

      // FIX (multi-image upload, see _pickedFiles comment above):
      // uploads run concurrently rather than one-at-a-time -- a full
      // 10-screenshot DMart cart would otherwise take noticeably longer
      // to submit. `listImageUrl` (singular) is kept alongside the new
      // `listImageUrls` list purely for backward compatibility with the
      // existing hero/admin summary code that already checks
      // `details['listImageUrl']` to show a "📷 Photo list attached"
      // badge -- both point at the same first image.
      final uploadService = CloudinaryUploadService();
      final imagesToUpload = _pickedFiles.where((f) => f.bytes != null).toList();
      final listImageUrls = await Future.wait(
        imagesToUpload.map(
          (file) => uploadService.uploadImageBytes(
            file.bytes!,
            fileName: file.name,
            folder: 'service_request_images/${user.uid}/$requestId',
          ),
        ),
      );

      final resolvedCustomerPhone = await AuthService().resolveCustomerPhone(user);
      await service.createServiceRequest(
        preGeneratedRequestId: requestId,
        requestType: 'grocery_order',
        customerId: user.uid,
        customerName: user.displayName ?? 'Customer',
        customerPhone: resolvedCustomerPhone,
        details: {
          'items': quickOrderItemsToJson(_lineItems),
          // Backward compat: grocery_order_status_screen.dart and
          // requestSummary() in admin_new_orders_screen.dart still read
          // 'listText' as a plain string — keep it populated by joining
          // each line item's qty + name, comma-separated.
          'listText': _lineItems
              .where((it) => !it.isEmpty)
              .map((it) => [it.qty.trim(), it.name.trim()].where((s) => s.isNotEmpty).join(' '))
              .join(', '),
          'listImageUrl': listImageUrls.isNotEmpty ? listImageUrls.first : null,
          'listImageUrls': listImageUrls,
          'deliveryAddress': _deliveryAddressCtrl.text.trim(),
          if (_deliveryLat != null) 'locationLat': _deliveryLat,
          if (_deliveryLng != null) 'locationLng': _deliveryLng,
        },
      );

      unawaited(Future.delayed(
        const Duration(seconds: kServiceRequestPingExpirySeconds),
        () => ServiceRequestService().markTimeoutIfStillPending(requestId),
      ),);

      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ServiceRequestTrackingScreen(
            requestId: requestId,
            requestType: 'grocery_order',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        showServerBusyDialog(context);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Grocery Order', style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 18)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kGreen.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Text('🛒', style: TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Type it or snap a photo', style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 14)),
                        const SizedBox(height: 2),
                        const Text('Write your grocery list below, upload a photo of a handwritten list, or both.', style: TextStyle(color: _kMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Your grocery list', style: GoogleFonts.outfit(color: _kText, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            QuickOrderLineItemsForm(
              items: _lineItems,
              itemLabel: 'Item',
              qtyLabel: 'Qty',
              onChanged: (items) => setState(() => _lineItems = items),
            ),
            const SizedBox(height: 16),
            // FIX (multi-image, per Nizam's "screenshot your DMart cart, 1-10
            // images, hero fulfills manually" workflow): replaced the old
            // single-file tap-tile with a button that keeps launching the
            // picker (in `allowMultiple` mode, see _pickImages()) plus a
            // thumbnail wrap below showing every picked screenshot with its
            // own remove (x) button, so the customer can review/prune the
            // whole batch before submitting.
            Text('Or upload photos of your list (up to $_maxImages)', style: GoogleFonts.outfit(color: _kText, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            // NEW (per Nizam/CTO's DMart UX workaround): points customers
            // coming back from the "Store Order" DMart WebView straight at
            // this uploader, since that's how their DMart cart actually
            // becomes a real order (see _openDmartWithPincodeNotice above).
            Text('Upload your DMart cart screenshots here!', style: TextStyle(color: _kGreen, fontSize: 11.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickedFiles.length >= _maxImages ? null : _pickImages,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _pickedFiles.isNotEmpty ? _kGreen.withValues(alpha: 0.4) : _kBorder),
                ),
                child: Row(
                  children: [
                    Icon(
                      _pickedFiles.isNotEmpty ? Icons.check_circle_rounded : Icons.add_a_photo_outlined,
                      color: _pickedFiles.isNotEmpty ? _kGreen : _kPink,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _pickedFiles.isEmpty
                            ? 'Tap to choose images'
                            : '${_pickedFiles.length}/$_maxImages image${_pickedFiles.length == 1 ? '' : 's'} selected',
                        style: TextStyle(color: _pickedFiles.isNotEmpty ? _kText : _kMuted, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_pickedFiles.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_pickedFiles.length, (index) {
                  final file = _pickedFiles[index];
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _kBorder),
                          image: file.bytes != null
                              ? DecorationImage(image: MemoryImage(file.bytes!), fit: BoxFit.cover)
                              : null,
                          color: _kSurface,
                        ),
                        child: file.bytes == null
                            ? const Icon(Icons.image_outlined, color: _kMuted, size: 20)
                            : null,
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: GestureDetector(
                          onTap: () => _removeImage(index),
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(color: _kText, shape: BoxShape.circle),
                            child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ],
            const SizedBox(height: 20),
            Text('Delivery location', style: GoogleFonts.outfit(color: _kText, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _deliveryAddressCtrl,
              style: const TextStyle(fontSize: 14),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Where should the Hero deliver your groceries?',
                hintStyle: TextStyle(color: _kMuted.withValues(alpha: 0.6), fontSize: 13),
                filled: true,
                fillColor: _kSurface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 10),
            LocationCaptureField(
              addressController: _deliveryAddressCtrl,
              pickerTitle: 'Delivery location',
              accentColor: _kGreen,
              onLocationPicked: (lat, lng) {
                setState(() {
                  _deliveryLat = lat;
                  _deliveryLng = lng;
                });
              },
            ),
          ],
        ),
      ),
      // FIX (per Nizam's correction, then a follow-up 2-page-to-3-page
      // split): three equal-weight destinations now instead of two --
      // Send Order (this custom list form, the default landing page),
      // Store Order (DMart's e-menu, dmart_screen.dart -- previously a
      // banner buried inside this form's scroll content, now promoted
      // to its own top-level action in the center per Nizam's explicit
      // request), and Order Status (unchanged, full task-history list).
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    key: const Key('grocery_send_order_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPink,
                      elevation: 4,
                      shadowColor: _kPink.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: _canSubmit ? _submit : null,
                    icon: _submitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.shopping_cart_checkout_rounded, color: Colors.white, size: 18),
                    label: Text('Send Order', style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _kGreen, width: 1.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: () => _openDmartWithPincodeNotice(context),
                    icon: const Icon(Icons.storefront_rounded, color: _kGreen, size: 18),
                    label: Text('Store Order', style: GoogleFonts.outfit(color: _kGreen, fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _kPink, width: 1.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const GroceryOrderStatusScreen()),
                    ),
                    icon: const Icon(Icons.receipt_long_rounded, color: _kPink, size: 18),
                    label: Text('Status', style: GoogleFonts.outfit(color: _kPink, fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// NEW (QA fix — DMart pincode dialog readability): one row per numbered
// step, used by _openDmartWithPincodeNotice() above.
class _DmartStep extends StatelessWidget {
  final String number;
  final String text;
  const _DmartStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: _kGreen, shape: BoxShape.circle),
          child: Text(
            number,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              text,
              style: TextStyle(color: _kMuted, fontSize: 13.5, height: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}
