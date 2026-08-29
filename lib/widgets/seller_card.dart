// ================================================================
// SellerCard — Allin1 Super App
// Reusable shop card with category-specific metadata
// ================================================================

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../screens/seller_detail_screen.dart';
import '../services/category_gateway_service.dart';
import '../services/theme_service.dart';
import 'cached_cloud_image.dart';

// ── Brand palette (Aug 20 2026 — Global Food Theme Overhaul) ───────
// Shop cards were dark (0xFF1A1A2A) — recolored for the white/pink
// category screen; food accent switched from red to hot pink.
const Color _kPink = Color(0xFFFF4FA3);
const Color _kSurface = Color(0xFFF8F8FF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF9999BB);

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

    // NEW (Nizam: "photo realistic theme la intha mari tiles varanum" —
    // reference was a Swiggy/Zomato-style big-photo restaurant card).
    // Reuses this SAME card's existing data (seller['imageUrl'] /
    // ['coverImageUrl'], both already written by SellerModel.toJson() —
    // no backend change) and existing tap-through to SellerDetailScreen
    // (which already has live menu + cart). Falls back to the normal
    // small-icon row below whenever the theme isn't Photo Realistic OR
    // this particular seller has no photo yet, so nothing regresses for
    // sellers who haven't uploaded one.
    final iconTheme = context.watch<ThemeService>().iconThemeKey;
    final photoUrl = (seller['coverImageUrl'] as String?)?.trim().isNotEmpty == true
        ? seller['coverImageUrl'] as String
        : (seller['imageUrl'] as String?)?.trim().isNotEmpty == true
            ? seller['imageUrl'] as String
            : null;
    if (iconTheme == 'photo_realistic' && photoUrl != null) {
      return _buildPhotoCard(context, config, isOpen, metadata, photoUrl);
    }

    return GestureDetector(
      onTap: () => _handleTap(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kSurface,
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
                            color: _kText,
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
                          color: _kText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '•',
                        style: TextStyle(
                          fontSize: 12,
                          color: _kMuted,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          metadata,
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: _kMuted,
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
              color: _kMuted,
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
          primaryColor: Color(0xFFFF4FA3),
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

  // Shared by both card layouts (small-icon row and photo card) so the
  // named-route/RouteBreadcrumbObserver behaviour stays identical
  // regardless of which theme drew the card that was tapped.
  void _handleTap(BuildContext context) {
    if (onTap != null) {
      onTap!();
      return;
    }
    // Default navigation to SellerDetailScreen. Named route + primitive
    // arguments (Aug 19 2026) so RouteBreadcrumbObserver can
    // persist/restore this on cold start — see main_customer.dart
    // '/food_shop_detail' onGenerateRoute.
    final sellerId = seller['id'] as String?;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        settings: RouteSettings(
          name: '/food_shop_detail',
          arguments: sellerId == null
              ? null
              : <String, dynamic>{
                  'sellerId': sellerId,
                  'categoryName': category.name,
                },
        ),
        builder: (_) => SellerDetailScreen(
          seller: seller,
          category: category,
        ),
      ),
    );
  }

  // ── Photo Realistic theme: big-photo card (Swiggy/Zomato-style
  // reference, reimplemented in our own pink/white brand rather than
  // copied) ───────────────────────────────────────────────────────
  Widget _buildPhotoCard(BuildContext context, _SellerCardConfig config,
      bool isOpen, String metadata, String photoUrl) {
    return GestureDetector(
      onTap: () => _handleTap(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: config.primaryColor.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: config.primaryColor.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CachedCloudImage(
                  photoUrl,
                  width: double.infinity,
                  height: 140,
                  fit: BoxFit.cover,
                  cacheWidth: 480,
                  errorWidget: Container(
                    width: double.infinity,
                    height: 140,
                    color: config.primaryColor.withValues(alpha: 0.1),
                    child: Center(
                      child: Text(_getShopEmoji(), style: const TextStyle(fontSize: 40)),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: _buildStatusBadge(isOpen),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    seller['shopName'] as String? ?? 'Unknown Shop',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _kText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Text('⭐', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text(
                        _getRating(),
                        style: GoogleFonts.outfit(fontSize: 12, color: _kText, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      const Text('•', style: TextStyle(fontSize: 12, color: _kMuted)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          metadata,
                          style: GoogleFonts.outfit(fontSize: 11, color: _kMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helper: Shop Emoji ───────────────────────────────────────
  String _getShopEmoji() {
    final emoji = seller['emoji'] as String?;
    if (emoji != null && emoji.isNotEmpty) return emoji;

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
    if (rating == null) return 'New';
    return rating.toStringAsFixed(1);
  }

  // ── Helper: Open/Closed ──────────────────────────────────────
  bool _isOpen() {
    final hours = seller['hours'] as Map<String, dynamic>?;
    if (hours == null) return true;

    final now = DateTime.now();
    final currentTime = now.hour * 60 + now.minute;

    final openTime = hours['open'] as int?;
    final closeTime = hours['close'] as int?;

    if (openTime == null || closeTime == null) return true;

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
    properties.add(DiagnosticsProperty<Map<String, dynamic>>('seller', seller));
    properties.add(EnumProperty<Category>('category', category));
    properties.add(ObjectFlagProperty<VoidCallback?>.has('onTap', onTap));
  }
}

// ── Category Config for SellerCard ─────────────────────────────
class _SellerCardConfig {
  final Color primaryColor;

  const _SellerCardConfig({
    required this.primaryColor,
  });
}
