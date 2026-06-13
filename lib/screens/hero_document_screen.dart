// ================================================================
// Captain Document Upload Screen
// Allin1 Super App - Allin1
// ================================================================

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color kSurface = Color(0xFF0D0D18);
const Color kCard = Color(0xFF141420);
const Color kCard2 = Color(0xFF1A1A28);
const Color kPurple = Color(0xFF7B6FE0);
const Color kGreen = Color(0xFF3DBA6F);
const Color kGold = Color(0xFFF5C542);
const Color kRed = Color(0xFFE05555);
const Color kText = Color(0xFFEEEEF5);
const Color kMuted = Color(0xFF7777A0);
const Color kBorder = Color(0x267B6FE0);

class CaptainDocumentScreen extends StatefulWidget {
  const CaptainDocumentScreen({super.key});

  @override
  State<CaptainDocumentScreen> createState() => _CaptainDocumentScreenState();
}

class _CaptainDocumentScreenState extends State<CaptainDocumentScreen> {
  // Document state
  final Map<String, DocumentUploadState> _docStates = {};

  // Bank details
  final _formKey = GlobalKey<FormState>();
  final _accountController = TextEditingController();
  final _ifscController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _upiController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadExistingDocs();
  }

  Future<void> _loadExistingDocs() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final docRef = FirebaseFirestore.instance
        .collection('heroes')
        .doc(user.uid)
        .collection('documents');

    final snapshot = await docRef.get();

    if (mounted) {
      setState(() {
        for (final doc in snapshot.docs) {
          _docStates[doc.id] = DocumentUploadState(
            fileName: doc.get('fileName') as String?,
            status: (doc.get('status') as String?) ?? 'pending_review',
            uploadedAt: (doc.get('uploadedAt') as Timestamp?)?.toDate(),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: kText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Captain Documents',
          style: GoogleFonts.outfit(color: kText, fontWeight: FontWeight.w600),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Identity Documents'),
              const SizedBox(height: 12),
              _buildDocSlot(
                'aadhaar_front',
                'Aadhaar Card (Front)',
                'Upload front side',
              ),
              _buildDocSlot(
                'aadhaar_back',
                'Aadhaar Card (Back)',
                'Upload back side',
              ),
              _buildDocSlot(
                'driving_license',
                'Driving License',
                'Upload license',
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Vehicle Documents'),
              const SizedBox(height: 12),
              _buildDocSlot('vehicle_rc', 'Vehicle RC Book', 'Upload RC'),
              _buildDocSlot(
                'selfie_vehicle',
                'Selfie with Vehicle',
                'Take photo',
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Bank Details'),
              const SizedBox(height: 12),
              _buildBankForm(),
              const SizedBox(height: 30),
              _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        color: kText,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildDocSlot(String docType, String title, String hint) {
    final state = _docStates[docType];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  color: kText,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              _buildStatusBadge(state?.status ?? 'pending'),
            ],
          ),
          const SizedBox(height: 12),
          if (state != null && state.fileName != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.image, color: kMuted, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.fileName!,
                      style: GoogleFonts.outfit(color: kText, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            OutlinedButton.icon(
              onPressed: () => _pickFile(docType),
              icon: const Icon(Icons.upload_file, size: 18),
              label: Text(hint),
              style: OutlinedButton.styleFrom(
                foregroundColor: kPurple,
                side: const BorderSide(color: kPurple),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case 'verified':
        color = kGreen;
        label = 'Verified';
        icon = Icons.check_circle;
        break;
      case 'rejected':
        color = kRed;
        label = 'Rejected';
        icon = Icons.cancel;
        break;
      default:
        color = kGold;
        label = 'Pending';
        icon = Icons.hourglass_empty;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(label, style: GoogleFonts.outfit(color: color, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildBankForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          TextFormField(
            controller: _accountController,
            keyboardType: TextInputType.number,
            style: GoogleFonts.roboto(color: kText),
            decoration: _buildInputDecoration('Account Number'),
            validator: (v) => v!.isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _ifscController,
            style: GoogleFonts.roboto(color: kText),
            decoration: _buildInputDecoration('IFSC Code'),
            validator: (v) => v!.isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _bankNameController,
            style: GoogleFonts.roboto(color: kText),
            decoration: _buildInputDecoration('Bank Name'),
            validator: (v) => v!.isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _upiController,
            style: GoogleFonts.roboto(color: kText),
            decoration: _buildInputDecoration('UPI ID (Optional)'),
          ),
        ],
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.outfit(color: kMuted),
      filled: true,
      fillColor: kCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kPurple),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submitDocuments,
        style: ElevatedButton.styleFrom(
          backgroundColor: kGold,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.black,
                  strokeWidth: 2,
                ),
              )
            : Text(
                'Submit Documents',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Future<void> _pickFile(String docType) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          throw Exception('User not logged in');
        }

        // Show uploading indicator
        if (mounted) {
          setState(() {
            _docStates[docType] = DocumentUploadState(
              fileName: file.name,
              status: 'uploading',
            );
          });
        }

        // Upload to Firebase Storage
        final storageRef = FirebaseStorage.instance.ref(
          'hero_documents/${user.uid}/$docType/${file.name}',
        );

        // Upload file
        final uploadTask = storageRef.putFile(File(file.path!));
        final snapshot = await uploadTask;
        final downloadUrl = await snapshot.ref.getDownloadURL();

        // Save to Firestore
        final docRef = FirebaseFirestore.instance
            .collection('heroes')
            .doc(user.uid)
            .collection('documents')
            .doc(docType);

        await docRef.set({
          'fileName': file.name,
          'fileUrl': downloadUrl,
          'status': 'pending_review',
          'uploadedAt': FieldValue.serverTimestamp(),
          'fileSize': file.size,
          'docType': docType,
        });

        // Update UI
        if (mounted) {
          setState(() {
            _docStates[docType] = DocumentUploadState(
              fileName: file.name,
              status: 'pending_review',
              uploadedAt: DateTime.now(),
              fileUrl: downloadUrl,
            );
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Document uploaded successfully!'),
              backgroundColor: kGreen,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _docStates[docType] = DocumentUploadState(
            status: 'error',
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading file: $e'),
            backgroundColor: kRed,
          ),
        );
      }
    }
  }

  Future<void> _submitDocuments() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    if (mounted) {
      setState(() => _isSubmitting = true);
    }

    try {
      final heroRef =
          FirebaseFirestore.instance.collection('heroes').doc(user.uid);

      // Update main hero document
      await heroRef.set(
        {
          'name': user.displayName ?? '',
          'phone': user.phoneNumber ?? '',
          'upiId': _upiController.text.trim(),
          'documentsSubmitted': true,
          'verificationStatus': 'under_review',
          'bankAccount': {
            'accountNo': _accountController.text.trim(),
            'ifsc': _ifscController.text.trim(),
            'bankName': _bankNameController.text.trim(),
          },
        },
        SetOptions(merge: true),
      );

      // Upload document metadata
      for (final entry in _docStates.entries) {
        await heroRef.collection('documents').doc(entry.key).set({
          'fileName': entry.value.fileName,
          'status': 'pending_review',
          'uploadedAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Documents submitted for review!',
              style: GoogleFonts.notoSansTamil(color: Colors.white),
            ),
            backgroundColor: kGreen,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error submitting: $e',
              style: GoogleFonts.notoSansTamil(color: Colors.white),
            ),
            backgroundColor: kRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  void dispose() {
    _accountController.dispose();
    _ifscController.dispose();
    _bankNameController.dispose();
    _upiController.dispose();
    super.dispose();
  }
}

class DocumentUploadState {
  final String? fileName;
  final String status;
  final DateTime? uploadedAt;
  final String? fileUrl;

  DocumentUploadState({
    required this.status,
    this.fileName,
    this.uploadedAt,
    this.fileUrl,
  });
}
