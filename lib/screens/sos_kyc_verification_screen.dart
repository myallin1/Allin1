// ================================================================
// SosKycVerificationScreen — one-time KYC gate before SOS activates
// ================================================================
// NEW (per Nizam's request): a customer's SOS button used to fire
// instantly on a 3-tap gesture with zero verification — easy to
// trigger by accident or misuse, which wastes a safety feature meant
// for genuine emergencies. This screen collects basic identity details
// + 3 mandatory document photos (same Cloudinary upload pattern as
// hero_register_screen.dart) and submits them to sos_kyc_requests/{uid}
// for admin review. Once admin approves (Cus SOS Approval tab), the
// customer's SOS unlocks permanently — this is a ONE-TIME activation,
// not a per-incident approval gate (an emergency can't wait on manual
// admin review each time it's used).
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/cloudinary_upload_service.dart';

const Color _bg = Color(0xFFFFFFFF);
const Color _card = Color(0xFFFFF3F9);
const Color _pink = Color(0xFFFF4FA3);
const Color _navy = Color(0xFF071A35);
const Color _text = Color(0xFF201A22);
const Color _muted = Color(0xFF8C7A88);
const Color _red = Color(0xFFE0245E);
const Color _green = Color(0xFF00A84A);
const Color _border = Color(0x33FF4FA3);

class SosKycVerificationScreen extends StatefulWidget {
  const SosKycVerificationScreen({super.key});

  @override
  State<SosKycVerificationScreen> createState() => _SosKycVerificationScreenState();
}

class _SosKycVerificationScreenState extends State<SosKycVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  // FIX (per Nizam's request): the hero registration form collects the
  // TYPED number alongside each document photo, so admin can read the
  // number off the photo and compare it against what the person typed
  // — this form only collected photos, with no typed number to check
  // against. Added for parity with hero_register_screen.dart.
  final _aadhaarNumberController = TextEditingController();
  final _panNumberController = TextEditingController();
  final _licenseNumberController = TextEditingController();
  DateTime? _dob;

  PlatformFile? _aadhaarPhoto;
  PlatformFile? _panPhoto;
  PlatformFile? _licensePhoto;

  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _aadhaarNumberController.dispose();
    _panNumberController.dispose();
    _licenseNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _pickDocPhoto(String docType) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (!mounted) return;
      setState(() {
        switch (docType) {
          case 'aadhaar':
            _aadhaarPhoto = file;
            break;
          case 'pan':
            _panPhoto = file;
            break;
          case 'license':
            _licensePhoto = file;
            break;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not pick photo: $e'), backgroundColor: _red),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your date of birth'), backgroundColor: _red),
      );
      return;
    }
    final missing = <String>[
      if (_aadhaarPhoto == null) 'Aadhaar photo',
      if (_panPhoto == null) 'PAN photo',
      if (_licensePhoto == null) 'License photo',
    ];
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please upload: ${missing.join(', ')}'), backgroundColor: _red),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login first'), backgroundColor: _red),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final urls = <String, String>{};
      final jobs = <String, PlatformFile?>{
        'aadhaarDocUrl': _aadhaarPhoto,
        'panDocUrl': _panPhoto,
        'licenseDocUrl': _licensePhoto,
      };
      for (final entry in jobs.entries) {
        final file = entry.value;
        if (file == null || file.bytes == null) continue;
        final url = await CloudinaryUploadService().uploadImageBytes(
          file.bytes!,
          fileName: '${entry.key}_${file.name}',
          folder: 'sos_kyc/${user.uid}',
          // Higher than the 100KB default — admin needs to actually
          // read these ID documents to verify identity before
          // activating SOS, so keep a bit more clarity.
          targetBytes: 200 * 1024,
        );
        urls[entry.key] = url;
      }

      await FirebaseFirestore.instance.collection('sos_kyc_requests').doc(user.uid).set({
        'userId': user.uid,
        'name': _nameController.text.trim(),
        'dob': Timestamp.fromDate(_dob!),
        'address': _addressController.text.trim(),
        'aadhaarNumber': _aadhaarNumberController.text.trim(),
        'panNumber': _panNumberController.text.trim(),
        'licenseNumber': _licenseNumberController.text.trim(),
        'userPhone': user.phoneNumber ?? '',
        'userEmail': user.email ?? '',
        ...urls,
        'status': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Submitted! Admin will verify and activate your SOS shortly.'),
          backgroundColor: _green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submission failed: $e'), backgroundColor: _red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text('Verify KYC to Activate SOS',
            style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 16),),
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: _pink, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This one-time verification protects the SOS network from misuse, '
                          'so genuine emergencies always get a fast response. Once approved, '
                          'your SOS button stays active forever — no need to verify again.',
                          style: GoogleFonts.outfit(color: _navy, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _field(controller: _nameController, label: 'Full Name'),
                const SizedBox(height: 14),
                _dobField(),
                const SizedBox(height: 14),
                _field(controller: _addressController, label: 'Address', maxLines: 2),
                const SizedBox(height: 20),
                Text('Documents (number + photo, all required)',
                    style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 14),),
                const SizedBox(height: 4),
                Text(
                  'Type the number exactly as printed — admin checks it against your photo.',
                  style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                ),
                const SizedBox(height: 10),
                // FIX: each number field sits directly ABOVE its own
                // photo picker (not grouped separately) — same
                // line-by-line pairing as hero_register_screen.dart, so
                // admin's review screen can mirror this exact pairing.
                _field(controller: _aadhaarNumberController, label: 'Aadhaar Number'),
                const SizedBox(height: 8),
                _docPickerRow('Aadhaar photo', _aadhaarPhoto, () => _pickDocPhoto('aadhaar'),
                    onClear: () => setState(() => _aadhaarPhoto = null),),
                const SizedBox(height: 16),
                _field(controller: _panNumberController, label: 'PAN Number'),
                const SizedBox(height: 8),
                _docPickerRow('PAN photo', _panPhoto, () => _pickDocPhoto('pan'),
                    onClear: () => setState(() => _panPhoto = null),),
                const SizedBox(height: 16),
                _field(controller: _licenseNumberController, label: 'License Number'),
                const SizedBox(height: 8),
                _docPickerRow('License photo', _licensePhoto, () => _pickDocPhoto('license'),
                    onClear: () => setState(() => _licensePhoto = null),),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _pink,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Submit for Verification',
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700),),
                  ),
                ),
              ],
            ),
          ),
          if (_isSubmitting)
            Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.4),
                  child: const Center(child: CircularProgressIndicator(color: _pink)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _field({required TextEditingController controller, required String label, int maxLines = 1}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: GoogleFonts.outfit(color: _text),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.outfit(color: _muted),
        filled: true,
        fillColor: _card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _dobField() {
    return InkWell(
      onTap: _pickDob,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Date of Birth',
          labelStyle: GoogleFonts.outfit(color: _muted),
          filled: true,
          fillColor: _card,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
        child: Text(
          _dob == null ? 'Select date' : '${_dob!.day}/${_dob!.month}/${_dob!.year}',
          style: GoogleFonts.outfit(color: _dob == null ? _muted : _text),
        ),
      ),
    );
  }

  Widget _docPickerRow(String label, PlatformFile? file, VoidCallback onPick, {required VoidCallback onClear}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Icon(file != null ? Icons.check_circle_rounded : Icons.upload_file_rounded,
              color: file != null ? _green : _pink, size: 20,),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              file != null ? '$label — ${file.name}' : label,
              style: GoogleFonts.outfit(color: _text, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (file != null)
            IconButton(icon: const Icon(Icons.close, size: 18, color: _muted), onPressed: onClear)
          else
            TextButton(onPressed: onPick, child: const Text('Choose', style: TextStyle(color: _pink))),
        ],
      ),
    );
  }
}
