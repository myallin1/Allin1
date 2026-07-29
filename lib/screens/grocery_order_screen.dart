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
import '../services/service_request_service.dart';
import '../widgets/location_capture_field.dart';
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
  final _listCtrl = TextEditingController();
  // NEW (per Nizam's request — every service request needs a real
  // navigable delivery point for the hero): this form used to collect
  // zero location data at all, not even a text address.
  final _deliveryAddressCtrl = TextEditingController();
  double? _deliveryLat;
  double? _deliveryLng;
  PlatformFile? _pickedFile;
  bool _submitting = false;

  @override
  void dispose() {
    _listCtrl.dispose();
    _deliveryAddressCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting &&
      (_listCtrl.text.trim().isNotEmpty || _pickedFile != null) &&
      _deliveryAddressCtrl.text.trim().isNotEmpty;

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform
          .pickFiles(type: FileType.image, withData: true);
      if (result != null && result.files.isNotEmpty) {
        setState(() => _pickedFile = result.files.first);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick image: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      final service = ServiceRequestService();
      final requestId = service.reserveRequestId();

      String? listImageUrl;
      if (_pickedFile != null && _pickedFile!.bytes != null) {
        listImageUrl = await CloudinaryUploadService().uploadImageBytes(
          _pickedFile!.bytes!,
          fileName: _pickedFile!.name,
          folder: 'service_request_images/${user.uid}/$requestId',
        );
      }

      await service.createServiceRequest(
        preGeneratedRequestId: requestId,
        requestType: 'grocery_order',
        customerId: user.uid,
        customerName: user.displayName ?? 'Customer',
        customerPhone: user.phoneNumber ?? '',
        details: {
          'listText': _listCtrl.text.trim(),
          'listImageUrl': listImageUrl,
          'deliveryAddress': _deliveryAddressCtrl.text.trim(),
          if (_deliveryLat != null) 'locationLat': _deliveryLat,
          if (_deliveryLng != null) 'locationLng': _deliveryLng,
        },
      );

      unawaited(Future.delayed(
        const Duration(seconds: kServiceRequestPingExpirySeconds),
        () => ServiceRequestService().markTimeoutIfStillPending(requestId),
      ));

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send order: $e'), backgroundColor: Colors.red),
        );
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
            TextField(
              controller: _listCtrl,
              maxLines: 6,
              style: const TextStyle(fontSize: 14),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'e.g., 1kg rice, 1L milk, 2 bread, tomatoes...',
                hintStyle: TextStyle(color: _kMuted.withValues(alpha: 0.6), fontSize: 13),
                filled: true,
                fillColor: _kSurface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 16),
            Text('Or upload a photo of your list', style: GoogleFonts.outfit(color: _kText, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _pickedFile != null ? _kGreen.withValues(alpha: 0.4) : _kBorder),
                ),
                child: Row(
                  children: [
                    Icon(
                      _pickedFile != null ? Icons.check_circle_rounded : Icons.add_a_photo_outlined,
                      color: _pickedFile != null ? _kGreen : _kPink,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _pickedFile?.name ?? 'Tap to choose an image',
                        style: TextStyle(color: _pickedFile != null ? _kText : _kMuted, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_pickedFile != null)
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: _kMuted, size: 18),
                        onPressed: () => setState(() => _pickedFile = null),
                      ),
                  ],
                ),
              ),
            ),
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
      // FIX (per Nizam's correction): consistent bottom page-split UI
      // across all service request types — a Book/Send button and a
      // "Booking Status" button opening a full task-history list,
      // matching the pink/white pattern from custom_food_order_screen.
      // dart and hero_booking_screen.dart. Grocery had neither before.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPink,
                      elevation: 4,
                      shadowColor: _kPink.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _canSubmit ? _submit : null,
                    icon: _submitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.shopping_cart_checkout_rounded, color: Colors.white, size: 18),
                    label: Text('Send Order', style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _kPink, width: 1.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const GroceryOrderStatusScreen()),
                    ),
                    icon: const Icon(Icons.receipt_long_rounded, color: _kPink, size: 18),
                    label: Text('Order Status', style: GoogleFonts.outfit(color: _kPink, fontSize: 14, fontWeight: FontWeight.bold)),
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
