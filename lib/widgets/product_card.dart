// ================================================================
// ProductCard — Allin1 Super App
// Product card with Add to Cart button
// ================================================================

import 'package:colorful_iconify_flutter/icons/fluent_emoji_flat.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:erode_superapp/services/cloudinary_upload_service.dart';
import 'package:erode_superapp/widgets/cached_cloud_image.dart';

class ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onAddToCart;

  const ProductCard({
    required this.product,
    required this.onAddToCart,
    super.key,
  });

  /// Dish photo, rendered in the shape the seller cropped for and with
  /// Cloudinary's delivery-time food enhancement applied.
  ///
  /// The enhancement (see CloudinaryUploadService.kFoodEnhanceTransform)
  /// is a URL parameter, so it costs one derived asset per unique URL —
  /// generated once, then CDN-cached for every subsequent viewer — and
  /// can be tuned or removed globally by editing one constant.
  Widget _buildDishImage(String image, {required bool isRound}) {
    final img = CachedCloudImage(
      CloudinaryUploadService.foodImageUrl(image, width: 400),
      fit: BoxFit.cover,
      errorWidget: Center(
        child: SvgPicture.string(
          FluentEmojiFlat.hamburger,
          width: 40,
          height: 40,
        ),
      ),
    );

    if (isRound) {
      // Inset slightly so the circle reads as deliberate rather than as
      // a photo that got clipped by the card edge.
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Center(child: ClipOval(child: AspectRatio(aspectRatio: 1, child: img))),
      );
    }
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      child: img,
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = product['name'] as String? ?? 'Unknown';
    final price = (product['price'] as num?)?.toDouble() ?? 0.0;
    final image = product['image'] as String?;
    final unit = product['unit'] as String? ?? '';
    // Shape the seller framed this dish for (Aug 18 2026). Read from the
    // raw map because this card consumes menu_items documents directly,
    // not MenuItemModel. Absent on every pre-existing item -> 'square',
    // which is exactly how they render today.
    final isRoundPhoto = product['imageShape'] == 'circle';

    // Seller-set offer price (Phase 3). Same `> 0 && < price` guard as
    // seller_detail_screen._addToCart and the seller-side editor, so a
    // stale or malformed value can never present as a "discount" that
    // is actually higher than the normal price.
    final offerPrice = (product['discountedPrice'] as num?)?.toDouble();
    final hasOffer = offerPrice != null && offerPrice > 0 && offerPrice < price;

    return GestureDetector(
      onTap: onAddToCart,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFFFBB00).withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image Placeholder
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFF12121E),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                ),
                child: image != null && image.isNotEmpty
                    ? _buildDishImage(image, isRound: isRoundPhoto)
                    : Center(
                        // No photo saved for this dish (e.g. a Hotel
                        // seller's preset-catalog item — see
                        // seller_menu_setup_screen.dart, which never
                        // sets imageUrl). A colourful placeholder reads
                        // much better than the old flat grey icon.
                        child: SvgPicture.string(
                          FluentEmojiFlat.hamburger,
                          width: 40,
                          height: 40,
                        ),
                      ),
              ),
            ),

            // Product Info
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name
                  Text(
                    name,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFEEEEF5),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),

                  // Unit
                  if (unit.isNotEmpty)
                    Text(
                      unit,
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        color: const Color(0xFF7777A0),
                      ),
                    ),
                  const SizedBox(height: 6),

                  // Price + Add Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // PHASE 3 (Aug 17 2026): show a seller's offer
                      // price as the live price with the original struck
                      // through. seller_detail_screen._addToCart applies
                      // the same `offer < base` guard, so what is shown
                      // here is always what gets charged.
                      if (hasOffer)
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '₹${offerPrice!.toStringAsFixed(0)}',
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  color: const Color(0xFFFFBB00),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '₹${price.toStringAsFixed(0)}',
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    color: Colors.white38,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Text(
                          '₹${price.toStringAsFixed(0)}',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            color: const Color(0xFFFFBB00),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFBB00),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.add,
                          size: 14,
                          color: Colors.black,
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

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
        .add(DiagnosticsProperty<Map<String, dynamic>>('product', product));
    properties
        .add(ObjectFlagProperty<VoidCallback>.has('onAddToCart', onAddToCart));
  }
}

