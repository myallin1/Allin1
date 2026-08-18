// ================================================================
// HeroApprovalsScreen — Admin Panel
// Approve / Reject pending hero registrations
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/city_config.dart';
import 'admin_hero_details_screen.dart';

// ── Theme (matches admin dashboard) ────────────────────────────
const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _green = Color(0xFF00C853);
const Color _gold = Color(0xFFFFBB00);
const Color _red = Color(0xFFFF5252);
const Color _purple = Color(0xFF6C63FF);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x1AFFFFFF);

class HeroApprovalsScreen extends StatefulWidget {
  const HeroApprovalsScreen({super.key});

  @override
  State<HeroApprovalsScreen> createState() => _HeroApprovalsScreenState();
}

class _HeroApprovalsScreenState extends State<HeroApprovalsScreen> {
  // NEW (Aug 8 2026 — "rejected hero has nowhere to be re-approved"):
  // this screen used to ONLY ever query approvalStatus == 'pending'.
  // The moment admin rejected a hero, that hero's doc had
  // approvalStatus: 'rejected' and simply vanished from view forever —
  // there was no "undo" anywhere in the admin app. Meanwhile
  // hero_pending_screen.dart signs a rejected hero straight out with a
  // "Contact Admin" message and no in-app path back in either. Added a
  // second tab here so admin can find that hero again and reverse the
  // decision, without touching the existing Pending tab/flow at all.
  int _selectedTab = 0; // 0 = Pending, 1 = Rejected

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
            const Text('🦸', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              'Hero Approvals',
              style: GoogleFonts.outfit(
                color: _text,
                fontWeight: FontWeight.w800,
                fontSize: 18, // FIX (UI standardization, Aug 11 2026): app-bar titles are 18sp app-wide
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(53),
          child: Column(
            children: [
              // NEW: Pending / Rejected segmented toggle — Rejected tab
              // is the "undo" section requested above. Everything below
              // (query, list, card, buttons) is 100% shared with the
              // existing Pending flow; only the `where` clause changes.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _ApprovalTabChip(
                        label: 'Pending',
                        icon: Icons.hourglass_top_rounded,
                        selected: _selectedTab == 0,
                        onTap: () => setState(() => _selectedTab = 0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ApprovalTabChip(
                        label: 'Rejected',
                        icon: Icons.block_rounded,
                        selected: _selectedTab == 1,
                        onTap: () => setState(() => _selectedTab = 1),
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: _border),
            ],
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('heroes')
            .where(
              'approvalStatus',
              isEqualTo: _selectedTab == 0 ? 'pending' : 'rejected',
            )
            .snapshots(),
        builder: (context, snap) {
          // Handle errors FIRST — missing Firestore index causes blank screen
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
                      'Error loading pending heroes',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _red,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snap.error}',
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => setState(() {}),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _gold,
                      ),
                      child: const Text(
                        'Retry',
                        style: TextStyle(color: Colors.black),
                      ),
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
          final docs = _sortByTimestampDesc(
            snap.data?.docs ?? const [],
            'createdAt',
          );
          if (docs.isEmpty) {
            final isPendingTab = _selectedTab == 0;
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(isPendingTab ? '✅' : '🗂️', style: const TextStyle(fontSize: 56)),
                  const SizedBox(height: 16),
                  Text(
                    isPendingTab ? 'No pending hero requests' : 'No rejected heroes',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isPendingTab ? 'All heroes are approved!' : 'Nobody has been rejected — nothing to review here.',
                    style: GoogleFonts.notoSansTamil(
                      fontSize: 12,
                      color: _muted,
                    ),
                  ),
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
              return _HeroApprovalCard(
                uid: doc.id,
                data: data,
                onView: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => AdminHeroDetailsScreen(
                        uid: doc.id,
                        data: data,
                        onApprove: () => _approveHero(doc.id, data),
                        onReject: () => _rejectHero(doc.id, data),
                        onCall: () => _callHero(data['phone'] as String? ?? ''),
                        getCityLabel: cityLabelFor,
                      ),
                    ),
                  );
                },
                onApprove: () => _approveHero(doc.id, data),
                onReject: () => _rejectHero(doc.id, data),
                onCall: () => _callHero(data['phone'] as String? ?? ''),
              );
            },
          );
        },
      ),
    );
  }

  // FIX: admin had no way to call a hero straight from this screen to
  // verify their identity before approving — Nizam explicitly asked for
  // a call button that dials whatever phone number the hero themselves
  // typed at registration (not a placeholder admin number).
  Future<void> _callHero(String phone) async {
    final digits = phone.replaceAll(RegExp('[^0-9+]'), '');
    if (digits.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No phone number on file for this hero'),
          backgroundColor: _red,
        ),
      );
      return;
    }
    final url = Uri.parse('tel:$digits');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open phone dialer'),
          backgroundColor: _red,
        ),
      );
    }
  }

  // REMOVED (Aug 18 2026 audit — Gemini's later AdminHeroDetailsScreen
  // replaced this entirely): _showDetailDialog / _showFullImage /
  // _detailRow / _detailRowWithPhoto used to be the paragraph-style
  // popup this screen's "View Details" button opened. onView (see the
  // ListView.builder above) now pushes AdminHeroDetailsScreen instead —
  // a proper full page with labeled field rows, one photo card per KYC
  // document (with its typed number), tap-to-zoom, and Approve/Reject
  // pinned at the bottom. Nothing in this file called the old dialog
  // anymore (verified — zero call sites), so removing it is a pure
  // dead-code deletion with no behaviour change.
  // TASK 3 (Aug 8 2026) — KYC & Selfie Guard.
  // There's no single stored "kycComplete" boolean on the hero doc, so
  // completeness is derived from the actual required fields written by
  // hero_register_screen.dart at registration: the selfie photo plus
  // the 3 KYC documents, plus the core identity fields the approvals
  // list already displays. Returns the list of missing item labels —
  // empty list means the hero is fully complete and safe to approve.
  // MUST be kept in sync with the identical check duplicated in
  // AdminKycWriteService.approveHero() (admin_kyc_write_service.dart),
  // which that file's own header comment calls a "byte-for-byte
  // mirror" of this screen's approve logic.
  List<String> _missingKycItems(Map<String, dynamic> data) {
    bool empty(String key) {
      final v = data[key];
      return v == null || (v is String && v.trim().isEmpty);
    }

    final missing = <String>[];
    if (empty('selfieUrl')) missing.add('Selfie photo');
    if (empty('aadhaarDocUrl')) missing.add('Aadhaar document');
    if (empty('panDocUrl')) missing.add('PAN document');
    if (empty('licenseDocUrl')) missing.add('License document');
    if (empty('name')) missing.add('Name');
    if (empty('phone')) missing.add('Phone number');
    return missing;
  }

  // ── Approve ────────────────────────────────────────────────────
  Future<void> _approveHero(String uid, Map<String, dynamic> data) async {
    if (!mounted) return;

    // TASK 3: hard block — an admin cannot even reach the confirm
    // dialog if the hero's selfie or KYC form isn't complete. This is
    // a strict guard per Nizam's explicit "must NOT be able to
    // approve" requirement, not a warning that can be dismissed.
    final missing = _missingKycItems(data);
    if (missing.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Cannot Approve — Incomplete KYC',
            style: TextStyle(color: _red, fontWeight: FontWeight.w700),
          ),
          content: Text(
            '"${data['name'] ?? uid}" is missing:\n\n'
            '${missing.map((m) => '• $m').join('\n')}\n\n'
            'Ask the hero to complete these in the app/PWA before approving.',
            style: const TextStyle(color: _muted),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: _gold),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Approve Hero',
          style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Approve "${data['name'] ?? uid}"? This will create/merge their captain profile.',
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
            child: const Text(
              'Approve',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Show loading state
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Approving "${data['name'] ?? 'Hero'}"...'),
        backgroundColor: _gold,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 5),
      ),
    );

    try {
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();
      final heroRef = firestore.collection('heroes').doc(uid);
      final pendingRef = firestore.collection('heroes_pending').doc(uid);
      final updateData = {
        'approvalStatus': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      batch.set(heroRef, updateData, SetOptions(merge: true));

      if ((await pendingRef.get()).exists) {
        batch.set(pendingRef, updateData, SetOptions(merge: true));
      }

      await batch.commit();

      // Best-effort RTDB mirror — mirrors the hero_pings notification
      // pattern (RTDB + flutter_local_notifications) rather than FCM,
      // since Cloud Functions/Blaze billing aren't available. Failure
      // here must not block the Firestore approval itself.
      try {
        await FirebaseDatabase.instance.ref('hero_status_updates/$uid').set({
          'type': 'approval',
          'timestamp': ServerValue.timestamp,
        });
      } catch (e) {
        debugPrint('[HeroApprovals] hero_status_updates write failed: $e');
      }

      // Allow stream to settle before showing success message
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '✅ ${data['name'] ?? 'Hero'} approved successfully!',
            style: GoogleFonts.notoSansTamil(color: Colors.white),
          ),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  // ── Reject ─────────────────────────────────────────────────────
  Future<void> _rejectHero(String uid, Map<String, dynamic> data) async {
    if (!mounted) return;

    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: _surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Reject Hero',
            style: TextStyle(color: _red, fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reject "${data['name'] ?? uid}"? They will be notified.',
                style: const TextStyle(color: _muted),
              ),
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
              onPressed: reasonController.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, reasonController.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: _red),
              child: const Text(
                'Reject',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
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
        content: Text('Rejecting "${data['name'] ?? 'Hero'}"...'),
        backgroundColor: _gold,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 5),
      ),
    );

    try {
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();
      final heroRef = firestore.collection('heroes').doc(uid);
      final pendingRef = firestore.collection('heroes_pending').doc(uid);
      final updateData = {
        'approvalStatus': 'rejected',
        'rejectionReason': reason,
        'rejectedAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      batch.set(heroRef, updateData, SetOptions(merge: true));

      if ((await pendingRef.get()).exists) {
        batch.set(pendingRef, updateData, SetOptions(merge: true));
      }

      await batch.commit();

      // Best-effort RTDB mirror — see matching comment in _approveHero().
      try {
        await FirebaseDatabase.instance.ref('hero_status_updates/$uid').set({
          'type': 'rejection',
          'reason': reason,
          'timestamp': ServerValue.timestamp,
        });
      } catch (e) {
        debugPrint('[HeroApprovals] hero_status_updates write failed: $e');
      }

      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ ${data['name'] ?? 'Hero'} rejected.'),
          backgroundColor: _red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }
}

// ── Pending / Rejected tab chip ──────────────────────────────────
class _ApprovalTabChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ApprovalTabChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _gold.withValues(alpha: 0.18) : _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? _gold : _border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: selected ? _gold : _muted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? _gold : _muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('label', label));
    properties.add(DiagnosticsProperty<IconData>('icon', icon));
    properties.add(DiagnosticsProperty<bool>('selected', selected));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}

// ── Hero Approval Card ───────────────────────────────────────────
class _HeroApprovalCard extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> data;
  final VoidCallback onView;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onCall;
  const _HeroApprovalCard({
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
    final phone = data['phone'] as String? ?? '';
    final vehicleNumber = data['vehicleNumber'] as String? ?? '';
    final vehicleType = data['vehicleType'] as String? ?? '';
    final email = data['email'] as String? ?? '';
    final createdAt = data['createdAt'] as Timestamp?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33FFBB00)),
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
                  gradient: const LinearGradient(
                    colors: [_gold, Color(0xFFFF6B35)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        color: _text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (phone.isNotEmpty)
                      Text(
                        phone,
                        style: const TextStyle(fontSize: 11, color: _muted),
                      ),
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
                Text(
                  '${createdAt.toDate().day}/${createdAt.toDate().month}',
                  style: const TextStyle(fontSize: 10, color: _muted),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Vehicle info
          Row(
            children: [
              const Icon(Icons.directions_bike, size: 14, color: _purple),
              const SizedBox(width: 6),
              Text(
                vehicleType.isNotEmpty ? vehicleType : 'N/A',
                style: const TextStyle(fontSize: 11, color: _muted),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.pin, size: 14, color: _muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  vehicleNumber.isNotEmpty ? vehicleNumber : 'N/A',
                  style: const TextStyle(fontSize: 11, color: _muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              email,
              style: const TextStyle(fontSize: 10, color: _muted),
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 14),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onView,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _muted,
                    side: const BorderSide(color: _border),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'View Details',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.check_circle, size: 16),
                  label: const Text(
                    'Approve',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
