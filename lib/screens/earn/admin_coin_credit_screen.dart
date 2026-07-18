// ================================================================
// AdminCoinCreditScreen — HQ Admin Tool
// Manually move coin transactions: pending → verified
// Hidden from normal users — Admin only
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color _bg = Color(0xFF0A0A12);
const Color _card = Color(0xFF1A1A2A);
const Color _green = Color(0xFF00C853);
const Color _gold = Color(0xFFFFBB00);
const Color _red = Color(0xFFFF5252);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x1AFFFFFF);

class AdminCoinCreditScreen extends StatefulWidget {
  const AdminCoinCreditScreen({super.key});
  @override
  State<AdminCoinCreditScreen> createState() => _AdminCoinCreditScreenState();
}

class _AdminCoinCreditScreenState extends State<AdminCoinCreditScreen> {
  String _filterStatus = 'initiated';
  bool _processing = false;

  // ── Verify a transaction: pending → verified ─────────────────
  // ================================================================
  // VERIFY TRANSACTION — Manual Admin Credit (Zero-Blaze S2S bridge)
  // Atomically: pending_coins↓ + verified_coins↑ + status='verified'
  // With guards: prevent double-credit, prevent negative balance
  // ================================================================
  Future<void> _verifyTransaction(
    String txnId,
    String userId,
    int coins,
  ) async {
    setState(() => _processing = true);
    try {
      final db = FirebaseFirestore.instance;
      await db.runTransaction((txn) async {
        final txnRef = db.collection('coin_transactions').doc(txnId);
        final userRef = db.collection('users').doc(userId);

        // Read both docs inside transaction
        final txnSnap = await txn.get(txnRef);
        final userSnap = await txn.get(userRef);

        // Guard 1: Transaction must exist
        if (!txnSnap.exists) {
          throw Exception('Transaction not found!');
        }

        // Guard 2: Prevent double-verification
        final currentStatus = txnSnap.data()?['status'] as String? ?? '';
        if (currentStatus == 'verified') {
          throw Exception('Already verified! Double-credit prevented.');
        }
        if (currentStatus == 'failed') {
          throw Exception('Transaction was rejected — cannot verify.');
        }

        // Guard 3: pending_coins must cover this amount
        final pendingCoins = (userSnap.data()?['pending_coins'] as int?) ?? 0;
        if (pendingCoins < coins) {
          throw Exception(
              'User pending_coins ($pendingCoins) < coins to verify ($coins). '
              'Run "Move to Pending" first!');
        }

        // All guards passed — atomic credit:
        // 1. Mark transaction verified
        // 2. Move coins: pending → verified (cannot go negative)
        txn
          ..update(txnRef, {
            'status': 'verified',
            'verifiedAt': FieldValue.serverTimestamp(),
            'verifiedBy': 'admin_manual',
          })
          ..set(
            userRef,
            {
              'pending_coins': FieldValue.increment(-coins),
              'verified_coins': FieldValue.increment(coins),
              'lifetime_coins': FieldValue.increment(coins),
            },
            SetOptions(merge: true),
          );
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Verified! $coins coins credited to $userId',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: $e',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
    if (mounted) {
      setState(() => _processing = false);
    }
  }

  Future<void> _moveToPending(String txnId, String userId, int coins) async {
    try {
      final db = FirebaseFirestore.instance;
      await db.runTransaction((txn) async {
        txn
          ..update(db.collection('coin_transactions').doc(txnId), {
            'status': 'pending',
          })
          ..set(
            db.collection('users').doc(userId),
            {
              'pending_coins': FieldValue.increment(coins),
            },
            SetOptions(merge: true),
          );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '⏳ $coins coins moved to PENDING',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: _gold,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Move pending error: $e');
    }
  }

  // ── Reject a transaction ──────────────────────────────────────
  Future<void> _rejectTransaction(String txnId) async {
    await FirebaseFirestore.instance
        .collection('coin_transactions')
        .doc(txnId)
        .update(
      {'status': 'failed', 'rejectedAt': FieldValue.serverTimestamp()},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF12121E),
        title: Text(
          'Admin — NJ Coins Credit',
          style: GoogleFonts.outfit(
            color: _text,
            fontWeight: FontWeight.w700,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                for (final s in ['initiated', 'pending', 'verified', 'failed'])
                  GestureDetector(
                    onTap: () => setState(() => _filterStatus = s),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _filterStatus == s
                            ? _gold
                            : const Color(0xFF1A1A2A),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _filterStatus == s ? _gold : _border,
                        ),
                      ),
                      child: Text(
                        s.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          color: _filterStatus == s ? Colors.black : _muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('coin_transactions')
            .where('status', isEqualTo: _filterStatus)
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots(),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _gold));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Text(
                'No $_filterStatus transactions',
                style: GoogleFonts.outfit(color: _muted, fontSize: 14),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d = docs[i].data()! as Map<String, dynamic>;
              final txnId = docs[i].id;
              final userId = d['userId'] as String? ?? '';
              final coins = d['coins'] as int? ?? 0;
              final task = d['taskName'] as String? ?? 'Task';
              final source = d['source'] as String? ?? '';
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task,
                            style: const TextStyle(
                              fontSize: 13,
                              color: _text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '🪙 $coins',
                          style: const TextStyle(
                            fontSize: 14,
                            color: _gold,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'User: $userId',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        color: _muted,
                      ),
                    ),
                    Text(
                      'Source: $source',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        color: _muted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Action buttons based on current status
                    Row(
                      children: [
                        if (_filterStatus == 'initiated') ...[
                          _actionBtn(
                            'Move to Pending',
                            _gold,
                            Colors.black,
                            () => _moveToPending(txnId, userId, coins),
                          ),
                          const SizedBox(width: 8),
                          _actionBtn(
                            'Reject',
                            _red,
                            Colors.white,
                            () => _rejectTransaction(txnId),
                          ),
                        ],
                        if (_filterStatus == 'pending') ...[
                          _actionBtn(
                            '✅ Verify & Credit',
                            _green,
                            Colors.white,
                            _processing
                                ? null
                                : () =>
                                    _verifyTransaction(txnId, userId, coins),
                          ),
                          const SizedBox(width: 8),
                          _actionBtn(
                            'Reject',
                            _red,
                            Colors.white,
                            () => _rejectTransaction(txnId),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _actionBtn(String label, Color bg, Color fg, VoidCallback? onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: onTap == null ? bg.withValues(alpha: 0.4) : bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
}
