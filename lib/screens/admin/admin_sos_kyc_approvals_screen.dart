// ================================================================
// AdminSosKycApprovalsScreen — Admin Panel
// Approve / Reject one-time customer SOS-activation KYC requests
// ================================================================
// NEW (per Nizam's request): customers now must submit basic KYC +
// document photos once (sos_kyc_verification_screen.dart) before their
// SOS button activates — this screen is where admin reviews and
// approves/rejects those submissions. Deliberately mirrors
// hero_approvals_screen.dart's structure closely (same review pattern
// already proven in production) rather than inventing a new one.
// Embedded as a bottom-nav TAB inside SuperAdminHomeScreen (like
// AdminServiceRequestsScreen for Hero/Electronics) — no back button,
// Flutter's AppBar only adds one automatically when there's actually
// a route to pop back to.
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/cloudinary_upload_service.dart';
import 'package:erode_superapp/widgets/cached_cloud_image.dart';
import '../../services/firestore_usage_tracking.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _green = Color(0xFF00C853);
const Color _gold = Color(0xFFFFBB00);
const Color _red = Color(0xFFFF5252);
const Color _pink = Color(0xFFFF4FA3);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x1AFFFFFF);

class AdminSosKycApprovalsScreen extends StatefulWidget {
  const AdminSosKycApprovalsScreen({super.key});

  @override
  State<AdminSosKycApprovalsScreen> createState() => _AdminSosKycApprovalsScreenState();
}

class _AdminSosKycApprovalsScreenState extends State<AdminSosKycApprovalsScreen> {
  List<QueryDocumentSnapshot> _sortByTimestampDesc(
    Iterable<QueryDocumentSnapshot> docs,
    String field,
  ) {
    final sorted = docs.toList();
    sorted.sort((a, b) {
      final aData = a.data()! as Map<String, dynamic>;
      final bData = b.data()! as Map<String, dynamic>;
      final aTs = aData[field] as Timestamp?;
      final bTs = bData[field] as Timestamp?;
      final aMs = aTs?.millisecondsSinceEpoch ?? 0;
      final bMs = bTs?.millisecondsSinceEpoch ?? 0;
      return bMs.compareTo(aMs);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        title: Row(
          children: [
            const Text('🆘', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text('Cus SOS Approval',
                style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800, fontSize: 18),), // FIX (UI standardization, Aug 11 2026): app-bar titles are 18sp app-wide
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('sos_kyc_requests')
            .where('status', isEqualTo: 'pending')
            .trackedSnapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('⚠️', style: TextStyle(fontSize: 56)),
                    const SizedBox(height: 16),
                    Text('Error loading pending SOS requests',
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: _red),),
                    const SizedBox(height: 8),
                    Text('${snap.error}', style: const TextStyle(color: _muted, fontSize: 12), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => setState(() {}),
                      style: ElevatedButton.styleFrom(backgroundColor: _gold),
                      child: const Text('Retry', style: TextStyle(color: Colors.black)),
                    ),
                  ],
                ),
              ),
            );
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(color: _gold, strokeWidth: 2),
              ),
            );
          }
          final docs = _sortByTimestampDesc(snap.data?.docs ?? const [], 'submittedAt');
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('✅', style: TextStyle(fontSize: 56)),
                  const SizedBox(height: 16),
                  Text('No pending SOS verification requests',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: _text),),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data()! as Map<String, dynamic>;
              return _SosKycApprovalCard(
                uid: doc.id,
                data: data,
                onView: () => _showDetailDialog(doc.id, data),
                onApprove: () => _approve(doc.id, data),
                onReject: () => _reject(doc.id, data),
                onCall: () => _callCustomer(data['userPhone'] as String? ?? ''),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _callCustomer(String phone) async {
    final digits = phone.replaceAll(RegExp('[^0-9+]'), '');
    if (digits.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number on file for this customer'), backgroundColor: _red),
      );
      return;
    }
    final url = Uri.parse('tel:$digits');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open phone dialer'), backgroundColor: _red),
      );
    }
  }

  void _showDetailDialog(String uid, Map<String, dynamic> data) {
    final name = data['name'] as String? ?? 'N/A';
    final phone = data['userPhone'] as String? ?? 'N/A';
    final email = data['userEmail'] as String? ?? 'N/A';
    final address = data['address'] as String? ?? 'N/A';
    final dob = data['dob'] as Timestamp?;
    final submittedAt = data['submittedAt'] as Timestamp?;

    final aadhaarNumber = data['aadhaarNumber'] as String? ?? '';
    final panNumber = data['panNumber'] as String? ?? '';
    final licenseNumber = data['licenseNumber'] as String? ?? '';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(name, style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Phone', phone),
              _detailRow('Email', email),
              _detailRow('Address', address),
              _detailRow('DOB', dob != null ? '${dob.toDate().day}/${dob.toDate().month}/${dob.toDate().year}' : 'N/A'),
              _detailRow(
                'Submitted',
                submittedAt != null
                    ? '${submittedAt.toDate().day}/${submittedAt.toDate().month}/${submittedAt.toDate().year}'
                    : 'N/A',
              ),
              const SizedBox(height: 14),
              // FIX: per Nizam's request — pair each typed number
              // directly with its own proof photo (same pairing as
              // Hero Approvals), so admin can read the number off the
              // photo and compare it against what was typed, right
              // there, instead of a separate photo grid at the bottom.
              Text('Proof Verification',
                  style: GoogleFonts.outfit(color: _muted, fontSize: 11, fontWeight: FontWeight.w700),),
              const SizedBox(height: 8),
              _detailRowWithPhoto('Aadhaar', aadhaarNumber, data['aadhaarDocUrl'] as String?),
              _detailRowWithPhoto('PAN', panNumber, data['panDocUrl'] as String?),
              _detailRowWithPhoto('License', licenseNumber, data['licenseDocUrl'] as String?),
              const SizedBox(height: 8),
              Text('UID: $uid', style: const TextStyle(fontSize: 9, color: _muted, fontFamily: 'monospace')),
            ],
          ),
        ),
        actions: [
          if (phone != 'N/A' && phone.trim().isNotEmpty)
            TextButton.icon(
              onPressed: () => _callCustomer(phone),
              icon: const Icon(Icons.call_rounded, size: 16, color: _green),
              label: const Text('Call Customer', style: TextStyle(color: _green)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(color: _muted))),
        ],
      ),
    );
  }

  void _showFullImage(String title, String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(child: CachedCloudImage(url, fit: BoxFit.contain)),
            IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    );
  }

  // Pairs a typed number with its own proof photo, line by line — same
  // pattern as hero_approvals_screen.dart's _detailRowWithPhoto.
  Widget _detailRowWithPhoto(String label, String value, String? photoUrl) {
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 11, color: _muted, fontWeight: FontWeight.w600),),
                const SizedBox(height: 2),
                Text(value.isNotEmpty ? value : 'N/A',
                    style: const TextStyle(fontSize: 13, color: _text, fontWeight: FontWeight.w700),),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: hasPhoto ? () => _showFullImage(label, photoUrl) : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: hasPhoto
                  ? CachedCloudImage(
                      // List thumbnail only — the full-screen KYC viewer
                      // above stays un-transformed for verification.
                      CloudinaryUploadService.optimizedUrl(photoUrl, width: 128),
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 64,
                        height: 64,
                        color: _card,
                        child: const Icon(Icons.broken_image_outlined, color: _muted, size: 20),
                      ),
                    )
                  : Container(
                      width: 64,
                      height: 64,
                      color: _card,
                      child: const Icon(Icons.image_not_supported_outlined, color: _muted, size: 20),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 90,
                child: Text(label, style: const TextStyle(fontSize: 11, color: _muted, fontWeight: FontWeight.w600)),),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 12, color: _text))),
          ],
        ),
      );

  Future<void> _approve(String uid, Map<String, dynamic> data) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Approve SOS Activation', style: TextStyle(color: _text, fontWeight: FontWeight.w700)),
        content: Text(
          'Approve "${data['name'] ?? uid}"? Their SOS button will activate permanently.',
          style: const TextStyle(color: _muted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: _muted))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _green),
            child: const Text('Approve', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance.collection('sos_kyc_requests').doc(uid).update({
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('✅ ${data['name'] ?? 'Customer'} SOS activated!'), backgroundColor: _green),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('❌ Approval failed: $e'), backgroundColor: _red));
    }
  }

  Future<void> _reject(String uid, Map<String, dynamic> data) async {
    if (!mounted) return;
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: _surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Reject SOS Verification', style: TextStyle(color: _red, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reject "${data['name'] ?? uid}"? They can resubmit.', style: const TextStyle(color: _muted)),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                autofocus: true,
                maxLines: 2,
                style: const TextStyle(color: _text),
                decoration: const InputDecoration(
                  hintText: 'Reason for rejection (required)',
                  hintStyle: TextStyle(color: _muted),
                  filled: true,
                  fillColor: _card,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: _muted))),
            ElevatedButton(
              onPressed: reasonController.text.trim().isEmpty ? null : () => Navigator.pop(ctx, reasonController.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: _red),
              child: const Text('Reject', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    reasonController.dispose();
    if (reason == null || reason.isEmpty || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance.collection('sos_kyc_requests').doc(uid).update({
        'status': 'rejected',
        'rejectionReason': reason,
        'rejectedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('❌ ${data['name'] ?? 'Customer'} rejected.'), backgroundColor: _red));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('❌ Rejection failed: $e'), backgroundColor: _red));
    }
  }
}

class _SosKycApprovalCard extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> data;
  final VoidCallback onView;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onCall;
  const _SosKycApprovalCard({
    required this.uid,
    required this.data,
    required this.onView,
    required this.onApprove,
    required this.onReject,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? 'Unknown';
    final phone = data['userPhone'] as String? ?? '';
    final address = data['address'] as String? ?? '';
    final submittedAt = data['submittedAt'] as Timestamp?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33FF4FA3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_pink, Color(0xFFB00020)]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w800),),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 15, color: _text, fontWeight: FontWeight.w700)),
                    if (phone.isNotEmpty) Text(phone, style: const TextStyle(fontSize: 11, color: _muted)),
                  ],
                ),
              ),
              if (phone.isNotEmpty)
                IconButton(
                  onPressed: onCall,
                  icon: const Icon(Icons.call_rounded, color: _green, size: 20),
                  tooltip: 'Call to verify',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              if (submittedAt != null)
                Text('${submittedAt.toDate().day}/${submittedAt.toDate().month}',
                    style: const TextStyle(fontSize: 10, color: _muted),),
            ],
          ),
          if (address.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(address, style: const TextStyle(fontSize: 11, color: _muted), overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onView,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _muted,
                    side: const BorderSide(color: _border),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('View Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onApprove,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.check_circle, size: 16),
                  label: const Text('Approve', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                height: 40,
                child: OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _red,
                    side: const BorderSide(color: _red),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Icon(Icons.close, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('uid', uid));
    properties.add(DiagnosticsProperty<Map<String, dynamic>>('data', data));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onView', onView));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onApprove', onApprove));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onReject', onReject));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onCall', onCall));
  }
}

