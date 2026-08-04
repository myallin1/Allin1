// ================================================================
// AdminWalletApprovalsScreen — Admin Panel
// Post-verify pending Hero Wallet recharge requests (Revenue Master
// Plan, per Nizam's approved architecture: Auto-Credit + Post-Verify /
// Claw-back). Heroes are auto-credited the moment they submit a
// recharge -- this screen is where admin reviews the UPI reference +
// screenshot afterward. Approve just marks it verified (balance was
// already credited). Reject claws back the exact amount via
// HeroWalletService.rejectRechargeRequest(), which is a client-side
// Firestore transaction (no Cloud Functions -- Spark plan constraint).
//
// Deliberately mirrors admin_sos_kyc_approvals_screen.dart's structure
// and dark theme (same review pattern already proven in production).
// ================================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/hero_wallet_model.dart';
import '../../services/hero_wallet_service.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _green = Color(0xFF00C853);
const Color _red = Color(0xFFFF5252);
const Color _pink = Color(0xFFFF4FA3);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x1AFFFFFF);

class AdminWalletApprovalsScreen extends StatefulWidget {
  const AdminWalletApprovalsScreen({super.key});

  @override
  State<AdminWalletApprovalsScreen> createState() =>
      _AdminWalletApprovalsScreenState();
}

class _AdminWalletApprovalsScreenState
    extends State<AdminWalletApprovalsScreen> {
  final Set<String> _processing = {};

  Future<void> _approve(WalletRechargeRequestModel request) async {
    final adminId = FirebaseAuth.instance.currentUser?.uid ?? 'unknown_admin';
    setState(() => _processing.add(request.id));
    try {
      await HeroWalletService().approveRechargeRequest(
        requestId: request.id,
        adminId: adminId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verified ₹${request.amount.toStringAsFixed(0)} recharge'),
            backgroundColor: _green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Approve failed: $e'), backgroundColor: _red),
        );
      }
    } finally {
      if (mounted) setState(() => _processing.remove(request.id));
    }
  }

  Future<void> _reject(WalletRechargeRequestModel request) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _card,
        title: Text(
          'Reject & Claw Back',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will remove ₹${request.amount.toStringAsFixed(0)} from '
              '${request.heroName ?? request.heroId}\'s wallet and flag them for review.',
              style: GoogleFonts.outfit(color: _muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              style: GoogleFonts.outfit(color: _text),
              decoration: InputDecoration(
                hintText: 'Reason (optional)',
                hintStyle: GoogleFonts.outfit(color: _muted),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: _border),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: _muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Reject & Claw Back',
                style: GoogleFonts.outfit(color: _red, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final adminId = FirebaseAuth.instance.currentUser?.uid ?? 'unknown_admin';
    setState(() => _processing.add(request.id));
    try {
      await HeroWalletService().rejectRechargeRequest(
        requestId: request.id,
        adminId: adminId,
        reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rejected — balance clawed back'), backgroundColor: _red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reject failed: $e'), backgroundColor: _red),
        );
      }
    } finally {
      if (mounted) setState(() => _processing.remove(request.id));
    }
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
            const Text('💰', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              'Wallet Recharge Approvals',
              style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800, fontSize: 17),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: StreamBuilder<List<WalletRechargeRequestModel>>(
        stream: HeroWalletService().watchPendingRechargeRequests(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(
                'Error: ${snap.error}',
                style: GoogleFonts.outfit(color: _red),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: _pink));
          }
          final requests = snap.data!;
          if (requests.isEmpty) {
            return Center(
              child: Text(
                'No pending recharge requests',
                style: GoogleFonts.outfit(color: _muted, fontSize: 14),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            itemBuilder: (context, index) => _buildRequestCard(requests[index]),
          );
        },
      ),
    );
  }

  Widget _buildRequestCard(WalletRechargeRequestModel request) {
    final isProcessing = _processing.contains(request.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  request.heroName?.isNotEmpty == true
                      ? request.heroName!
                      : 'Hero ${request.heroId.substring(0, 6)}',
                  style: GoogleFonts.outfit(
                    color: _text,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                '₹${request.amount.toStringAsFixed(0)}',
                style: GoogleFonts.outfit(
                  color: _green,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'UPI Ref: ${request.upiRefNumber}',
            style: GoogleFonts.outfit(color: _muted, fontSize: 12.5),
          ),
          if (request.requestedAt != null)
            Text(
              'Submitted: ${request.requestedAt}',
              style: GoogleFonts.outfit(color: _muted, fontSize: 11),
            ),
          const SizedBox(height: 10),
          if (request.screenshotUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                request.screenshotUrl,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 100,
                  alignment: Alignment.center,
                  color: _surface,
                  child: Text(
                    'Screenshot unavailable',
                    style: GoogleFonts.outfit(color: _muted),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isProcessing ? null : () => _reject(request),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _red,
                    side: const BorderSide(color: _red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text('Reject', style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isProcessing ? null : () => _approve(request),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: isProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text('Approve', style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
