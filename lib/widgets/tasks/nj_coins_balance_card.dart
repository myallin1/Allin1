// ================================================================
// NJCoinsBalanceCard — Allin1 Super App
// Modular Widget: Displays NJ Coins Balance with Breakdown
// ================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class NJCoinsBalanceCard extends StatelessWidget {
  final int balance;
  final int expiring;
  final int pending;
  final VoidCallback? onSpendTap;

  const NJCoinsBalanceCard({
    required this.balance,
    required this.expiring,
    required this.pending,
    super.key,
    this.onSpendTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A1035),
            Color(0xFF0D0D1E),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFFBB00).withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFBB00).withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFBB00).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text('🪙', style: TextStyle(fontSize: 24)),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'NJ Coins Balance',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF7777A0),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C853).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Active',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF00C853),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '₹$balance',
            style: GoogleFonts.outfit(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: const Color(0xFFEEEEF5),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildBalanceChip('Expiring', expiring, Colors.orange),
              const SizedBox(width: 8),
              _buildBalanceChip('Pending', pending, Colors.blue),
              const Spacer(),
              if (onSpendTap != null)
                ElevatedButton.icon(
                  onPressed: onSpendTap,
                  icon: const Icon(Icons.shopping_cart, size: 16),
                  label: const Text('Spend'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFBB00),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceChip(String label, int amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF7777A0),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '₹$amount',
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(IntProperty('balance', balance))
      ..add(IntProperty('expiring', expiring))
      ..add(IntProperty('pending', pending))
      ..add(ObjectFlagProperty<VoidCallback?>.has('onSpendTap', onSpendTap));
  }
}
