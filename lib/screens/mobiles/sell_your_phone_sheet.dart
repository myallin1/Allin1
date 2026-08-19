// ================================================================
// "Sell your old phone" sheet
// ================================================================
// The customer-submitted half of the Used Mobiles flow (Nizam: "shop
// sells + customer can submit", Aug 18 2026).
//
// This is an ENQUIRY, not a listing. The customer's phone does NOT go
// straight onto the public Used grid — it comes to us as an
// electronics_service request so a real person can inspect it, quote a
// price, buy it, and then list it properly. That keeps quality control
// (and stops the used grid filling with unverified junk), and it means
// this whole feature needs no new collection, no moderation queue, and
// no extra storage: it rides the pipeline that already exists.
//
// One optional photo, compressed to ~100 KB like every other upload in
// this app. Skipping the photo is fine — we just get fewer details.
// ================================================================

import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/mobile_models.dart';
import '../../services/auth_prompt_service.dart';
import '../../services/auth_service.dart';
import '../../services/cloudinary_upload_service.dart';
import '../../services/service_request_service.dart';
import '../../widgets/menu_photo_pick_crop.dart';
import '../service_request_tracking_screen.dart';
import 'mobile_hub_screen.dart';

/// Same ~100 KB budget used for seller menu photos. An enquiry photo
/// only has to show condition, not print quality.
const int _kSellPhotoTargetBytes = 100 * 1024;

Future<void> showSellYourPhoneSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _SellYourPhoneSheet(),
  );
}

class _SellYourPhoneSheet extends StatefulWidget {
  const _SellYourPhoneSheet();

  @override
  State<_SellYourPhoneSheet> createState() => _SellYourPhoneSheetState();
}

class _SellYourPhoneSheetState extends State<_SellYourPhoneSheet> {
  final _modelCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _expectedPriceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();

  String _grade = kUsedConditionGrades.first;
  Uint8List? _photoBytes;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _prefillPhone();
  }

  Future<void> _prefillPhone() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final phone = await AuthService().resolveCustomerPhone(user);
      if (mounted && phone.isNotEmpty) _contactCtrl.text = phone;
    } catch (_) {
      // Convenience only — never blocks the enquiry.
    }
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    _ageCtrl.dispose();
    _expectedPriceCtrl.dispose();
    _notesCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    // askShape: false — a phone photo always renders in a rectangular
    // card, so the Circle/Square chooser (which exists for food dishes)
    // would just be a pointless extra tap here.
    final picked = await pickAndCropMenuPhoto(context, askShape: false);
    if (picked != null && mounted) {
      setState(() => _photoBytes = picked.bytes);
    }
  }

  Future<void> _submit() async {
    if (_modelCtrl.text.trim().isEmpty) {
      _toast('Please enter your phone model');
      return;
    }
    if (_contactCtrl.text.trim().length < 10) {
      _toast('Please enter a valid contact number');
      return;
    }
    if (!await requireRealAuth(context,
        reason: 'Sign in to sell your phone')) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;

    setState(() => _sending = true);
    try {
      // Upload is best-effort: a Cloudinary failure must not lose the
      // customer's enquiry, so we carry on without the photo rather
      // than aborting the whole submission.
      String? photoUrl;

      // AUDIT FIX (Aug 19 2026, CTO review — "Cloudinary best-effort
      // upload risk"). Best-effort is still the right call: losing a
      // customer's enquiry because an image host blipped would be far
      // worse than losing the photo. What was wrong is that the failure
      // was INVISIBLE. Admin saw an enquiry with no photo and had no way
      // to tell "customer chose not to attach one" from "customer
      // attached one and it vanished" — two situations needing opposite
      // follow-up. Now the distinction is recorded on the request and
      // the customer is told, so they can re-send the photo on WhatsApp
      // instead of assuming the shop already has it.
      var photoAttemptedButFailed = false;
      if (_photoBytes != null) {
        try {
          photoUrl = await CloudinaryUploadService().uploadImageBytes(
            _photoBytes!,
            fileName: '${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg',
            folder: 'sell_phone_enquiries',
            targetBytes: _kSellPhotoTargetBytes,
          );
          // An upload that "succeeds" with an empty URL is the same
          // failure as a thrown exception, and just as invisible.
          // (uploadImageBytes returns a non-nullable String, so an
          // empty string is the only shape this failure can take.)
          if (photoUrl.trim().isEmpty) {
            photoUrl = null;
            photoAttemptedButFailed = true;
          }
        } catch (e) {
          debugPrint('❌ Sell-phone photo upload failed: $e');
          photoUrl = null;
          photoAttemptedButFailed = true;
        }
      }

      final requestId = await ServiceRequestService().createServiceRequest(
        requestType: 'electronics_service',
        customerId: user.uid,
        customerName: user.displayName ?? 'Customer',
        customerPhone: _contactCtrl.text.trim(),
        details: <String, dynamic>{
          'category': 'mobile',
          'categoryLabel': 'Mobile',
          'intent': 'sell_used_mobile',
          'phoneModel': _modelCtrl.text.trim(),
          'conditionGrade': _grade,
          if (_ageCtrl.text.trim().isNotEmpty) 'phoneAge': _ageCtrl.text.trim(),
          if (_expectedPriceCtrl.text.trim().isNotEmpty)
            'expectedPrice': _expectedPriceCtrl.text.trim(),
          if (photoUrl != null) 'phonePhotoUrl': photoUrl,
          if (photoAttemptedButFailed) 'photoUploadFailed': true,
          'issue': 'Sell old phone: ${_modelCtrl.text.trim()} ($_grade)'
              '${_expectedPriceCtrl.text.trim().isEmpty ? '' : ' — expects ₹${_expectedPriceCtrl.text.trim()}'}'
              '${_notesCtrl.text.trim().isEmpty ? '' : '\n${_notesCtrl.text.trim()}'}'
              // Surfaced in the free-text issue line too, not just as a
              // structured flag — the admin/hero screens render `issue`
              // today, so this reaches a human without any admin-side
              // change being required first.
              '${photoAttemptedButFailed ? '\n⚠️ Customer attached a photo but the upload failed — please request it directly.' : ''}',
        },
      );

      if (!mounted) return;

      // Told BEFORE this sheet pops, via the root messenger, so the
      // notice survives the navigation instead of being disposed with
      // the sheet. A customer who knows the photo didn't make it will
      // send it on WhatsApp; a customer who doesn't know assumes the
      // shop has already seen their cracked screen.
      if (photoAttemptedButFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Enquiry sent — but your photo could not be uploaded. '
              'Our team will ask you for it.',
            ),
            backgroundColor: kMobRed,
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      Navigator.pop(context);
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ServiceRequestTrackingScreen(
            requestId: requestId,
            requestType: 'electronics_service',
          ),
        ),
      );
    } catch (e) {
      if (mounted) _toast('Could not send: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: kMobRed),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              color: kMobBg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: kMobBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                    children: [
                      Text(
                        'Sell your old phone',
                        style: GoogleFonts.outfit(
                          color: kMobText,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tell us about your phone and we will get back with a price.',
                        style:
                            GoogleFonts.outfit(color: kMobMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 18),
                      _field(_modelCtrl, 'Phone model *',
                          'e.g. iPhone 12 128GB'),
                      _buildGradePicker(),
                      _field(_ageCtrl, 'How old is it?', 'e.g. 2 years'),
                      _field(_expectedPriceCtrl, 'Expected price (₹)',
                          'Optional',
                          keyboard: TextInputType.number),
                      _field(_notesCtrl, 'Anything else?',
                          'Bill/box available, any damage…',
                          maxLines: 3),
                      _field(_contactCtrl, 'Contact number *', '9XXXXXXXXX',
                          keyboard: TextInputType.phone),
                      _buildPhotoPicker(),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kMobGold,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _sending ? null : _submit,
                          child: _sending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  'Send Details',
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
                ),
              ],
            ),
          );
        },
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
            'Condition',
            style: GoogleFonts.outfit(
              color: kMobText,
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: active ? kMobGold : kMobSurface,
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: active ? kMobGold : kMobBorder),
                  ),
                  child: Text(
                    g,
                    style: GoogleFonts.outfit(
                      color: active ? Colors.white : kMobText,
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

  Widget _buildPhotoPicker() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Photo of your phone (optional)',
            style: GoogleFonts.outfit(
              color: kMobText,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _pickPhoto,
            child: Container(
              height: 110,
              width: double.infinity,
              decoration: BoxDecoration(
                color: kMobSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kMobBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: _photoBytes == null
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_outlined,
                            color: kMobMuted, size: 26),
                        SizedBox(height: 6),
                        Text('Tap to add a photo',
                            style: TextStyle(color: kMobMuted, fontSize: 12)),
                      ],
                    )
                  : Image.memory(_photoBytes!, fit: BoxFit.cover),
            ),
          ),
        ],
      ),
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
              color: kMobText,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            maxLines: maxLines,
            keyboardType: keyboard,
            style: GoogleFonts.outfit(color: kMobText, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.outfit(color: kMobMuted, fontSize: 12.5),
              filled: true,
              fillColor: kMobSurface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kMobBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kMobBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kMobGold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
