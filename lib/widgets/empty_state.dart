// ================================================================
// EmptyState — Allin1 Super App
// Beautiful fallback UI for empty category screens
// ================================================================

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/category_gateway_service.dart';

class EmptyState extends StatelessWidget {
  final Category category;

  const EmptyState({
    required this.category,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final config = _getCategoryConfig();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              config.emoji,
              style: const TextStyle(fontSize: 64),
            ),
            const SizedBox(height: 24),
            Text(
              'Coming Soon!',
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: const Color(0xFFEEEEF5),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              config.emptyMessage,
              style: GoogleFonts.outfit(
                fontSize: 16,
                color: const Color(0xFFEEEEF5).withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              config.emptySubmessage,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: const Color(0xFFEEEEF5).withValues(alpha: 0.54),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── Category Config ──────────────────────────────────────────
  _EmptyStateCfg _getCategoryConfig() {
    switch (category) {
      case Category.food:
        return const _EmptyStateCfg(
          emoji: '🍔',
          emptyMessage: 'No restaurants in your area yet!',
          emptySubmessage: "We're bringing Food Delivery to Erode soon!",
        );
      case Category.grocery:
        return const _EmptyStateCfg(
          emoji: '🛒',
          emptyMessage: 'No grocery stores nearby!',
          emptySubmessage: 'Fresh Groceries coming to your area soon!',
        );
      case Category.tech:
        return const _EmptyStateCfg(
          emoji: '📱',
          emptyMessage: 'Tech Store is under construction!',
          emptySubmessage: 'Browse NJ TECH products coming soon!',
        );
      case Category.pharmacy:
        return const _EmptyStateCfg(
          emoji: '💊',
          emptyMessage: 'Pharmacy services unavailable!',
          emptySubmessage: 'Medicine delivery coming to Erode soon!',
        );
      case Category.bikeTaxi:
        return const _EmptyStateCfg(
          emoji: '🏍️',
          emptyMessage: 'No bike taxi captains available!',
          emptySubmessage: 'More captains joining soon!',
        );
      case Category.carTaxi:
        return const _EmptyStateCfg(
          emoji: '🚗',
          emptyMessage: 'Car Taxi not available yet!',
          emptySubmessage: 'Book comfortable car rides soon!',
        );
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<Category>('category', category));
  }
}

// ── Empty State Config ─────────────────────────────────────────
class _EmptyStateCfg {
  final String emoji;
  final String emptyMessage;
  final String emptySubmessage;

  const _EmptyStateCfg({
    required this.emoji,
    required this.emptyMessage,
    required this.emptySubmessage,
  });
}
