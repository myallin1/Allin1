// ================================================================
// SellerCard — Allin1 Super App
// Reusable shop card with category-specific metadata
// ================================================================

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/seller_detail_screen.dart';
import '../services/category_gateway_service.dart';

class SellerCard extends StatelessWidget {
  final Map<String, dynamic> seller;
  final Category category;
  final VoidCallback? onTap;

  const SellerCard({
    required this.seller,
    required this.category,
    super.key,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final config = _getCategoryConfig();
    final isOpen = _isOpen();
    final metadata = _getMetadata();

    return GestureDetector(
      onTap: () {
        if (onTap != null) {
          onTap!();
        } else {
          // Default navigation to SellerDetailScreen
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => SellerDetailScreen(
                seller: seller,
                category: category,
              ),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: config.primaryColor.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: config.primaryColor.withValues(alpha: 0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Shop Icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: config.primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  _getShopEmoji(),
                  style: const TextStyle(fontSize: 28),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Shop Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Shop Name + Status
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          seller['shopName'] as String? ?? 'Unknown Shop',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFEEEEF5),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildStatusBadge(isOpen),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Rating + Metadata
                  Row(
                    children: [
                      const Text('⭐', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text(
                        _getRating(),
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: const Color(0xFFEEEEF5),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '•',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7777A0),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          metadata,
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: const Color(0xFF7777A0),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Arrow
            const Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: Color(0xFF7777A0),
            ),
          ],
        ),
      ),
    );
  }

  // ── Category Config ──────────────────────────────────────────
  _SellerCardConfig _getCategoryConfig() {
    switch (category) {
      case Category.food:
        return const _SellerCardConfig(
          primaryColor: Color(0xFFFF5252),
        );
      case Category.grocery:
        return const _SellerCardConfig(
          primaryColor: Color(0xFF00C853),
        );
      case Category.tech:
        return const _SellerCardConfig(
          primaryColor: Color(0xFF6C63FF),
        );
      case Category.pharmacy:
        return const _SellerCardConfig(
          primaryColor: Color(0xFFFF6B35),
        );
      case Category.bikeTaxi:
        return const _SellerCardConfig(
          primaryColor: Color(0xFFFFBB00),
        );
      case Category.carTaxi:
        return const _SellerCardConfig(
          primaryColor: Color(0xFF00BCD4),
        );
    }
  }

  // ── Helper: Shop Emoji ───────────────────────────────────────
  String _getShopEmoji() {
    final emoji = seller['emoji'] as String?;
    if (emoji != null && emoji.isNotEmpty) {
      return emoji;
    }

    // Fallback based on category
    switch (category) {
      case Category.food:
        return '🍽️';
      case Category.grocery:
        return '🥬';
      case Category.tech:
        return '🔌';
      case Category.pharmacy:
        return '💊';
      case Category.bikeTaxi:
        return '🏍️';
      case Category.carTaxi:
        return '🚗';
    }
  }

  // ── Helper: Rating ───────────────────────────────────────────
  String _getRating() {
    final rating = seller['rating'] as num?;
    if (rating == null) {
      return 'New';
    }
    return rating.toStringAsFixed(1);
  }

  // ── Helper: Open/Closed ──────────────────────────────────────
  bool _isOpen() {
    final hours = seller['hours'] as Map<String, dynamic>?;
    if (hours == null) {
      return true;
    }

    final now = DateTime.now();
    final currentTime = now.hour * 60 + now.minute;

    final openTime = hours['open'] as int?;
    final closeTime = hours['close'] as int?;

    if (openTime == null || closeTime == null) {
      return true;
    }

    return currentTime >= openTime && currentTime <= closeTime;
  }

  // ── Helper: Category Metadata ────────────────────────────────
  String _getMetadata() {
    final metadata = seller['metadata'] as Map<String, dynamic>? ?? {};

    switch (category) {
      case Category.food:
        final prepTime = metadata['prepTimeMinutes'] as int? ?? 30;
        return '⏱️ $prepTime min prep';

      case Category.grocery:
        final itemCount = metadata['itemCount'] as int? ?? 0;
        return '📦 $itemCount+ items';

      case Category.tech:
        final brands = (metadata['brands'] as List?)?.length ?? 0;
        return '🏷️ $brands brands';

      case Category.pharmacy:
        final productCount = metadata['productCount'] as int? ?? 0;
        return '💊 $productCount+ products';

      case Category.bikeTaxi:
        final captains = metadata['captainCount'] as int? ?? 0;
        return '🏍️ $captains captains';

      case Category.carTaxi:
        final cars = metadata['carCount'] as int? ?? 0;
        return '🚗 $cars cars';
    }
  }

  // ── Widget: Status Badge ─────────────────────────────────────
  Widget _buildStatusBadge(bool isOpen) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isOpen
            ? const Color(0xFF00C853).withValues(alpha: 0.15)
            : const Color(0xFFFF5252).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isOpen ? 'Open' : 'Closed',
        style: GoogleFonts.outfit(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: isOpen ? const Color(0xFF00C853) : const Color(0xFFFF5252),
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<Map<String, dynamic>>('seller', seller))
      ..add(EnumProperty<Category>('category', category))
      ..add(ObjectFlagProperty<VoidCallback?>.has('onTap', onTap));
  }
}

// ── Category Config for SellerCard ─────────────────────────────
class _SellerCardConfig {
  final Color primaryColor;

  const _SellerCardConfig({
    required this.primaryColor,
  });
}
