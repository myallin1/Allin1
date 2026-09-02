// ================================================================
// HeroWalletScreen — Prepaid Commission Wallet UI (Allin1 Super App)
// ================================================================
// Hero-facing screen for the Revenue Master Plan wallet: shows the
// live prepaid balance, a low-balance warning banner (heroes below
// threshold stop receiving new trip requests -- see
// HeroWalletService/hero_ride_screen.dart), a Recharge dialog (amount +
// UPI reference + screenshot upload, auto-credited immediately, admin
// verifies afterward), and the transaction ledger (recharges, commission
// debits, any admin claw-backs).
// ================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/hero_wallet_model.dart';
import '../../services/cloudinary_upload_service.dart';
import '../../services/hero_wallet_service.dart';
import '../../services/firestore_usage_tracking.dart';

const Color _kPink = Color(0xFFFF4FA3);
const Color _kPurple = Color(0xFF6C63FF);
const Color _kGreen = Color(0xFF2ECC71);
const Color _kRed = Color(0xFFE05555);

class HeroWalletScreen extends StatefulWidget {
  const HeroWalletScreen({super.key});

  @override
  State<HeroWalletScreen> createState() => _HeroWalletScreenState();
}

class _HeroWalletScreenState extends State<HeroWalletScreen> {
  String? get _heroId => FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    final heroId = _heroId;
    if (heroId == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view your wallet')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        title: Text(
          'Hero Wallet',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: StreamBuilder<HeroWalletModel>(
        stream: HeroWalletService().watchWallet(heroId),
        builder: (context, walletSnap) {
          final wallet = walletSnap.data ?? HeroWalletModel(heroId: heroId);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildBalanceCard(wallet),
                const SizedBox(height: 12),
                _buildValueCard(heroId, wallet),
                if (wallet.isLowBalance) ...[
                  const SizedBox(height: 12),
                  _buildLowBalanceBanner(wallet),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPink,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () => _openRechargeSheet(heroId),
                    icon: const Icon(Icons.add_card_rounded),
                    label: Text(
                      'Recharge Wallet',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Transaction History',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                _buildTransactionList(heroId),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBalanceCard(HeroWalletModel wallet) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kPurple, _kPink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Wallet Balance',
            style: GoogleFonts.outfit(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          // MINUS BALANCE (Aug 17 2026 — Nizam: "top up pannatha heros
          // ku minus la kaatatum... athu poite irukatum").
          //
          // A negative balance is NOT an error state here and must not
          // be dressed as one — by explicit decision there is no limit
          // and work is never blocked. So it is shown plainly, with a
          // leading minus and a one-line explanation that the hero can
          // keep working. Hiding it (or clamping to ₹0) would mean a
          // hero discovers the debt only when we ask them to pay it.
          Text(
            wallet.balance < 0
                ? '− ₹${wallet.balance.abs().toStringAsFixed(2)}'
                : '₹${wallet.balance.toStringAsFixed(2)}',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (wallet.balance < 0) ...[
            const SizedBox(height: 4),
            Text(
              'Pending app usage — you can keep working. Top up when convenient.',
              style: GoogleFonts.outfit(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _statChip(
                  'Recharged',
                  '₹${wallet.lifetimeRecharged.toStringAsFixed(0)}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statChip(
                  'App Usage Fees Paid',
                  '₹${wallet.lifetimeCommissionPaid.toStringAsFixed(0)}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // WHAT THIS APP IS WORTH TO THE HERO  (Aug 17 2026)
  // ================================================================
  // Nizam: "hero vera work amount pay panni work pandrathukum namma app
  // la join panni amount kattaama minus la yevlo use pannaru athunala
  // namma app la work pandrathunala yevlo save panirukkarunu theriyanum
  // avaruku."
  //
  // A hero staring at "− ₹47" has only half the picture, and it is the
  // discouraging half. The number that matters is the RATIO: what they
  // earned through the app against what the app cost them. On this
  // codebase's own published position — 0% commission, 100% of delivery
  // income to the hero — that ratio is overwhelming, and showing it is
  // simply showing the truth.
  //
  // Read cost: ONE aggregate count-style read of this hero's own
  // earnings rows, and only while this screen is open. Deliberately not
  // a live listener — the comparison does not need to tick in realtime.
  Widget _buildValueCard(String heroId, HeroWalletModel wallet) {
    return FutureBuilder<double>(
      future: _lifetimeEarned(heroId),
      builder: (context, snap) {
        final earned = snap.data ?? 0;
        final spent = wallet.lifetimeCommissionPaid;
        // Guard the divide: a brand-new hero has spent nothing, and
        // "earned ÷ 0" must not render as infinity on their first day.
        final ratio = spent > 0 ? earned / spent : 0;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1B5E20).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: const Color(0xFF3DBA6F).withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.savings_rounded,
                      color: Color(0xFF3DBA6F), size: 18),
                  const SizedBox(width: 8),
                  Text('What MyAllin1 has been worth to you',
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w800, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('You earned',
                            style: GoogleFonts.outfit(
                                fontSize: 11, color: Colors.black54)),
                        Text('₹${earned.toStringAsFixed(0)}',
                            style: GoogleFonts.outfit(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF1B5E20))),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('App usage cost',
                            style: GoogleFonts.outfit(
                                fontSize: 11, color: Colors.black54)),
                        Text('₹${spent.toStringAsFixed(2)}',
                            style: GoogleFonts.outfit(
                                fontSize: 20, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                ],
              ),
              if (ratio > 1) ...[
                const SizedBox(height: 10),
                Text(
                  'For every ₹1 of app usage, you earned about '
                  '₹${ratio.toStringAsFixed(0)}.',
                  style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1B5E20)),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'We take 0% commission on your rides — every rupee a '
                'customer pays you is yours. This small usage fee is only '
                'for running the app.',
                style: GoogleFonts.outfit(
                    fontSize: 11.5, height: 1.4, color: Colors.black54),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Total credited to this hero through the app, ever.
  ///
  /// Same `heroId` equality-only shape (no orderBy, bounded limit) that
  /// hero_earnings_screen.dart uses, so it needs no composite index. The
  /// same defensive numeric coercion is used too: these rows can carry
  /// an int where a double is expected, which throws on native Android
  /// under a plain `as double` cast.
  Future<double> _lifetimeEarned(String heroId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('wallet_transactions')
          .where('heroId', isEqualTo: heroId)
          .limit(500)
          .trackedGet();
      var total = 0.0;
      for (final d in snap.docs) {
        final raw = d.data()['amount'];
        final a = raw is num
            ? raw.toDouble()
            : (raw is String ? (double.tryParse(raw) ?? 0) : 0);
        final type = (d.data()['type'] as String? ?? '').toLowerCase();
        if (a > 0 && type != 'debit') total += a;
      }
      return total;
    } catch (e) {
      debugPrint('[HeroWallet] lifetime earned lookup failed: $e');
      return 0;
    }
  }

  Widget _buildLowBalanceBanner(HeroWalletModel wallet) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kRed.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _kRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your balance is below ₹${wallet.lowBalanceThreshold.toStringAsFixed(0)}. '
              'You will not receive new trip requests until you recharge.',
              style: GoogleFonts.outfit(
                color: _kRed,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionList(String heroId) {
    return StreamBuilder<List<HeroWalletTransactionModel>>(
      stream: HeroWalletService().watchTransactions(heroId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final txns = snap.data!;
        if (txns.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No transactions yet',
                style: GoogleFonts.outfit(color: Colors.black45),
              ),
            ),
          );
        }
        return Column(
          children: txns.map(_buildTxnTile).toList(),
        );
      },
    );
  }

  Widget _buildTxnTile(HeroWalletTransactionModel txn) {
    final isCredit = txn.amount >= 0;
    final color = isCredit ? _kGreen : _kRed;
    String title;
    switch (txn.type) {
      case HeroWalletTxnType.recharge:
        title = 'Wallet Recharge';
        break;
      case HeroWalletTxnType.infraUsageFee:
        final parts = <String>[];
        if (txn.activeMinutes != null && txn.activeMinutes! > 0) {
          parts.add('${txn.activeMinutes!.toStringAsFixed(0)} min online');
        }
        if (txn.ridesHandled != null && txn.ridesHandled! > 0) {
          parts.add('${txn.ridesHandled} ride${txn.ridesHandled == 1 ? '' : 's'}');
        }
        title = parts.isEmpty
            ? 'App Usage Fee'
            : 'App Usage Fee (${parts.join(', ')})';
        break;
      case HeroWalletTxnType.clawback:
        title = 'Recharge Rejected — Claw-back';
        break;
      case HeroWalletTxnType.adjustment:
        title = 'Balance Adjustment';
        break;
    }
    final dateStr = txn.createdAt != null
        ? DateFormat('dd MMM, hh:mm a').format(txn.createdAt!)
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                Text(
                  dateStr,
                  style: GoogleFonts.outfit(color: Colors.black45, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : ''}₹${txn.amount.toStringAsFixed(2)}',
            style: GoogleFonts.outfit(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openRechargeSheet(String heroId) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RechargeSheet(heroId: heroId),
    );
  }
}

class _RechargeSheet extends StatefulWidget {
  final String heroId;
  const _RechargeSheet({required this.heroId});

  @override
  State<_RechargeSheet> createState() => _RechargeSheetState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('heroId', heroId));
  }
}

class _RechargeSheetState extends State<_RechargeSheet> {
  final _amountCtrl = TextEditingController();
  final _upiRefCtrl = TextEditingController();
  PlatformFile? _pickedFile;
  bool _submitting = false;
  String? _error;

  static const List<int> _quickAmounts = [100, 200, 500, 1000];

  @override
  void dispose() {
    _amountCtrl.dispose();
    _upiRefCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickScreenshot() async {
    try {
      final result = await FilePicker.platform
          .pickFiles(type: FileType.image, withData: true);
      if (result != null && result.files.isNotEmpty) {
        setState(() => _pickedFile = result.files.first);
      }
    } catch (e) {
      setState(() => _error = 'Could not pick screenshot: $e');
    }
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    final upiRef = _upiRefCtrl.text.trim();

    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid recharge amount');
      return;
    }
    if (upiRef.isEmpty) {
      setState(() => _error = 'Enter your UPI transaction reference number');
      return;
    }
    if (_pickedFile == null || _pickedFile!.bytes == null) {
      setState(() => _error = 'Upload a screenshot of the payment');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final screenshotUrl = await CloudinaryUploadService().uploadImageBytes(
        _pickedFile!.bytes!,
        fileName: _pickedFile!.name,
        folder: 'hero_wallet_recharge/${widget.heroId}',
        targetBytes: CloudinaryUploadService.kDocumentTargetBytes,
      );

      final heroName = FirebaseAuth.instance.currentUser?.displayName;
      await HeroWalletService().submitRechargeRequest(
        heroId: widget.heroId,
        heroName: heroName,
        amount: amount,
        upiRefNumber: upiRef,
        screenshotUrl: screenshotUrl,
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Recharge added! ₹${amount.toStringAsFixed(0)} is available now — '
              'admin will verify shortly.',
            ),
            backgroundColor: _kGreen,
          ),
        );
      }
    } catch (e) {
      setState(() => _error = 'Recharge failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Recharge Wallet',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Pay via UPI, then enter the reference number and upload a screenshot. '
                'Your balance updates instantly — our team verifies it shortly after.',
                style: GoogleFonts.outfit(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount (₹)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _quickAmounts
                    .map((a) => ActionChip(
                          label: Text('₹$a'),
                          onPressed: () => _amountCtrl.text = a.toString(),
                        ),)
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _upiRefCtrl,
                decoration: InputDecoration(
                  labelText: 'UPI Transaction Reference No.',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickScreenshot,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _pickedFile != null
                            ? Icons.check_circle_rounded
                            : Icons.upload_rounded,
                        color: _pickedFile != null ? _kGreen : Colors.black45,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _pickedFile?.name ?? 'Upload payment screenshot',
                          style: GoogleFonts.outfit(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: GoogleFonts.outfit(color: _kRed, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Submit Recharge',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
