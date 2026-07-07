// ================================================================
// grocery_order_screen.dart — Broadcast Order System: Grocery Order
// Net-new screen (confirmed no prior version existed — only
// decorative category-banner icons). Text list and/or photo of a
// handwritten list; at least one is required. Image upload reuses
// the exact Firebase Storage pattern from hero_document_screen.dart.
// ================================================================
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/service_request_service.dart';
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
  PlatformFile? _pickedFile;
  bool _submitting = false;

  @override
  void dispose() {
    _listCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting && (_listCtrl.text.trim().isNotEmpty || _pickedFile != null);

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
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
      if (_pickedFile != null && _pickedFile!.path != null) {
        final storageRef = FirebaseStorage.instance.ref(
          'service_request_images/${user.uid}/$requestId/${_pickedFile!.name}',
        );
        final uploadTask = storageRef.putFile(File(_pickedFile!.path!));
        final snapshot = await uploadTask;
        listImageUrl = await snapshot.ref.getDownloadURL();
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
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPink,
                  elevation: 4,
                  shadowColor: _kPink.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _canSubmit ? _submit : null,
                child: _submitting
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Send Order', style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
