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

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/hero_wallet_model.dart';
import '../../services/cloudinary_upload_service.dart';
import '../../services/hero_wallet_service.dart';

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
          Text(
            '₹${wallet.balance.toStringAsFixed(2)}',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
            ),
          ),
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
        targetBytes: 200 * 1024,
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
