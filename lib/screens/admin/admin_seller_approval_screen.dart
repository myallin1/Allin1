// ================================================================
// AdminSellerApprovalScreen — Admin Panel
// Approve / Reject pending seller registrations
// Mirrors hero_approvals_screen.dart's pattern (per Nizam/CTO's
// request — sellers must no longer go live instantly; a franchise
// model across 5 cities means an unverified/fake seller going live
// instantly is a brand risk).
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../services/chitti/chitti_voice_service.dart';

import '../../config/city_config.dart';
import '../../services/firestore_usage_tracking.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _green = Color(0xFF00C853);
const Color _gold = Color(0xFFFFBB00);
const Color _red = Color(0xFFFF5252);
const Color _teal = Color(0xFF11998E);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x1AFFFFFF);

class AdminSellerApprovalScreen extends StatefulWidget {
  const AdminSellerApprovalScreen({super.key});

  @override
  State<AdminSellerApprovalScreen> createState() => _AdminSellerApprovalScreenState();
}

class _AdminSellerApprovalScreenState extends State<AdminSellerApprovalScreen> {
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _text, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const Text('🏪', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              'Seller Approvals',
              style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800, fontSize: 18), // FIX (UI standardization, Aug 11 2026): app-bar titles are 18sp app-wide
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('sellers')
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
                    Text(
                      'Error loading pending sellers',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: _red),
                    ),
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
          final docs = _sortByTimestampDesc(snap.data?.docs ?? const [], 'createdAt');
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('✅', style: TextStyle(fontSize: 56)),
                  const SizedBox(height: 16),
                  Text(
                    'No pending seller requests',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: _text),
                  ),
                  const SizedBox(height: 6),
                  Text('All sellers are reviewed!', style: GoogleFonts.outfit(fontSize: 12, color: _muted)),
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
              return _SellerApprovalCard(
                sellerId: doc.id,
                data: data,
                onView: () => _showDetailDialog(doc.id, data),
                onApprove: () => _approveSeller(doc.id, data),
                onReject: () => _rejectSeller(doc.id, data),
                onCall: () => _callSeller(data['phone'] as String? ?? ''),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _callSeller(String phone) async {
    final digits = phone.replaceAll(RegExp('[^0-9+]'), '');
    if (digits.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number on file for this seller'), backgroundColor: _red),
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

  // ── Detail Dialog ──────────────────────────────────────────────
  void _showDetailDialog(String sellerId, Map<String, dynamic> data) {
    final name = data['name'] as String? ?? 'N/A';
    final phone = data['phone'] as String? ?? 'N/A';
    final address = data['address'] as String? ?? 'N/A';
    final category = data['category'] as String? ?? 'N/A';
    final subCategory = data['subCategory'] as String? ?? 'N/A';
    final hotelType = data['hotelType'] as String? ?? '';
    final businessVertical = data['businessVertical'] as String? ?? 'hotel';
    final city = cityLabelFor(data['city'] as String? ?? kDefaultCity);
    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();
    final createdAt = data['createdAt'] as Timestamp?;

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
              _detailRow('City', city),
              _detailRow('Address', address),
              _detailRow('Vertical', businessVertical),
              _detailRow('Category', category),
              _detailRow('Sub-category', subCategory),
              if (hotelType.trim().isNotEmpty) _detailRow('Shop Type', hotelType),
              if (lat != null && lng != null)
                _detailRow('GPS', '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'),
              _detailRow(
                'Submitted',
                createdAt != null
                    ? '${createdAt.toDate().day}/${createdAt.toDate().month}/${createdAt.toDate().year} '
                        '${createdAt.toDate().hour}:${createdAt.toDate().minute.toString().padLeft(2, '0')}'
                    : 'N/A',
              ),
              const SizedBox(height: 14),
              Text('Menu Items', style: GoogleFonts.outfit(color: _muted, fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _MenuItemsPreview(sellerId: sellerId),
              const SizedBox(height: 8),
              Text(
                'Seller ID: $sellerId',
                style: const TextStyle(fontSize: 9, color: _muted, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        actions: [
          if (phone != 'N/A' && phone.trim().isNotEmpty)
            TextButton.icon(
              onPressed: () => _callSeller(phone),
              icon: const Icon(Icons.call_rounded, size: 16, color: _green),
              label: const Text('Call Seller', style: TextStyle(color: _green)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: _muted)),
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
              width: 100,
              child: Text(label, style: const TextStyle(fontSize: 11, color: _muted, fontWeight: FontWeight.w600)),
            ),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 12, color: _text))),
          ],
        ),
      );

  // ── Approve ────────────────────────────────────────────────────
  Future<void> _approveSeller(String sellerId, Map<String, dynamic> data) async {
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Approve Seller', style: TextStyle(color: _text, fontWeight: FontWeight.w700)),
        content: Text(
          'Approve "${data['name'] ?? sellerId}"? They will immediately become visible to customers in '
          '${cityLabelFor(data['city'] as String? ?? kDefaultCity)}.',
          style: const TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: _muted)),
          ),
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
    messenger.showSnackBar(
      SnackBar(
        content: Text('Approving "${data['name'] ?? 'Seller'}"...'),
        backgroundColor: _gold,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 5),
      ),
    );

    try {
      await FirebaseFirestore.instance.collection('sellers').doc(sellerId).set(
        {
          'status': 'active',
          // FIX (Issue 1 — "seller adds menu but customer can't see it"):
          // seller_onboarding_screen.dart writes isOpen:false at
          // registration (a brand-new seller shouldn't appear "open"
          // before they're even approved). This dialog explicitly tells
          // the admin the seller "will immediately become visible to
          // customers" on approval, but without this the seller stayed
          // isOpen:false — invisible to any discovery path that checks
          // isOpen (e.g. FoodSellerService.listenToActiveSellers) — until
          // the seller separately found and tapped the "Shop is Open"
          // toggle on their own dashboard, which most never knew existed.
          'isOpen': true,
          'approvedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // Auto-WhatsApp welcome draft (CEO Feature)
      try {
        final tts = FlutterTts();
        await ChittiVoiceService.apply(tts, 'ta-IN');
        await tts.speak("செல்லர் ${data['name'] ?? ''} அப்ரூவ் செய்யப்பட்டார். வாட்ஸ்அப் மெசேஜ் தயார் செய்யப்படுகிறது பாஸ்.");
      } catch (_) {}

      try {
        final String phone = (data['phone'] as String? ?? '').trim();
        final String name = (data['name'] as String? ?? 'Seller').trim();
        if (phone.isNotEmpty) {
          final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
          final formattedPhone = cleanPhone.startsWith('91') ? cleanPhone : '91$cleanPhone';
          final welcomeMsg = "Vanakkam $name! Allin1 app-il ungal store profile approve seyyapattathu. Welcome aboard! - NJ Tech Team.";
          final url = Uri.parse("https://wa.me/$formattedPhone?text=${Uri.encodeComponent(welcomeMsg)}");
          if (await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
          }
        }
      } catch (e) {
        debugPrint('[SellerApproval] WhatsApp launch failed: $e');
      }

      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('✅ ${data['name'] ?? 'Seller'} approved successfully!'),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ Approval failed: $e'),
          backgroundColor: _red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  // ── Reject ─────────────────────────────────────────────────────
  Future<void> _rejectSeller(String sellerId, Map<String, dynamic> data) async {
    if (!mounted) return;

    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: _surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Reject Seller', style: TextStyle(color: _red, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reject "${data['name'] ?? sellerId}"? They will be notified.', style: const TextStyle(color: _muted)),
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
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: _muted)),
            ),
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
    messenger.showSnackBar(
      SnackBar(
        content: Text('Rejecting "${data['name'] ?? 'Seller'}"...'),
        backgroundColor: _gold,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 5),
      ),
    );

    try {
      await FirebaseFirestore.instance.collection('sellers').doc(sellerId).set(
        {
          'status': 'rejected',
          'rejectionReason': reason,
          'rejectedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ ${data['name'] ?? 'Seller'} rejected.'),
          backgroundColor: _red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ Rejection failed: $e'),
          backgroundColor: _red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }
}

// ── Menu items preview (read-only, inside the detail dialog) ─────
class _MenuItemsPreview extends StatelessWidget {
  final String sellerId;
  const _MenuItemsPreview({required this.sellerId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('sellers')
          .doc(sellerId)
          .collection('menu_items')
          .limit(20)
          .trackedGet(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: _teal),
            ),
          );
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return Text(
            'No menu items added yet',
            style: GoogleFonts.outfit(color: _muted, fontSize: 11.5, fontStyle: FontStyle.italic),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: docs.map((doc) {
            final d = doc.data();
            final name = (d['name'] as String?) ?? 'Unnamed';
            final price = (d['price'] as num?)?.toDouble() ?? 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.circle, size: 4, color: _muted),
                  const SizedBox(width: 6),
                  Expanded(child: Text(name, style: const TextStyle(fontSize: 12, color: _text))),
                  Text('₹${price.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, color: _muted)),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('sellerId', sellerId));
  }
}

// ── Seller Approval Card ──────────────────────────────────────────
class _SellerApprovalCard extends StatelessWidget {
  final String sellerId;
  final Map<String, dynamic> data;
  final VoidCallback onView;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onCall;

  const _SellerApprovalCard({
    required this.sellerId,
    required this.data,
    required this.onView,
    required this.onApprove,
    required this.onReject,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? 'Unknown';
    final phone = data['phone'] as String? ?? '';
    final category = data['category'] as String? ?? '';
    final subCategory = data['subCategory'] as String? ?? '';
    final city = cityLabelFor(data['city'] as String? ?? kDefaultCity);
    final createdAt = data['createdAt'] as Timestamp?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x3311998E)),
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
                  gradient: const LinearGradient(colors: [_teal, Color(0xFF38EF7D)]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 15, color: _text, fontWeight: FontWeight.w700)),
                    if (phone.isNotEmpty)
                      Text(phone, style: const TextStyle(fontSize: 11, color: _muted)),
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
              if (createdAt != null)
                Text('${createdAt.toDate().day}/${createdAt.toDate().month}', style: const TextStyle(fontSize: 10, color: _muted)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _teal.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$category${subCategory.isNotEmpty ? ' · $subCategory' : ''}',
                  style: const TextStyle(fontSize: 10, color: _teal, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.location_city, size: 14, color: _gold),
              const SizedBox(width: 4),
              Text(city, style: const TextStyle(fontSize: 11, color: _gold, fontWeight: FontWeight.w700)),
            ],
          ),
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
    properties.add(StringProperty('sellerId', sellerId));
    properties.add(DiagnosticsProperty<Map<String, dynamic>>('data', data));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onView', onView));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onApprove', onApprove));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onReject', onReject));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onCall', onCall));
  }
}
