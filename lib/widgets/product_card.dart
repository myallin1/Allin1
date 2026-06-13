// ================================================================
// ProductCard — Allin1 Super App
// Product card with Add to Cart button
// ================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onAddToCart;

  const ProductCard({
    required this.product,
    required this.onAddToCart,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final name = product['name'] as String? ?? 'Unknown';
    final price = (product['price'] as num?)?.toDouble() ?? 0.0;
    final image = product['image'] as String?;
    final unit = product['unit'] as String? ?? '';

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
                    ? ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(14),
                        ),
                        child: Image.network(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(
                              Icons.restaurant,
                              color: Color(0xFF7777A0),
                              size: 32,
                            ),
                          ),
                        ),
                      )
                    : const Center(
                        child: Icon(
                          Icons.restaurant,
                          color: Color(0xFF7777A0),
                          size: 32,
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
