// ================================================================
// delivery_challan_card.dart — Shared "Delivery Challan" (DC) card,
// embedded inside service_request_tracking_screen.dart so Customer,
// Hero, AND Admin see the exact same view (that screen is already
// shared across all three roles). Reads details['items'] as the new
// structured line-item list (see quick_order_line_items.dart) when
// present, falling back to legacy free-text fields (listText /
// items-as-String / taskDescription) for OLD documents so nothing
// existing renders blank. All colors from context.colors.* only.
// ================================================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/service_request_model.dart';
import '../services/theme_context_extensions.dart';
import 'tracking_timeline.dart';

// FIX (CTO mandate — Model Adoption, Phase 3): this widget now reads
// from a typed ServiceRequestModel instead of a raw
// Map<String, dynamic> — same rendering logic and same field-fallback
// order as before (structured items > legacy text; root amount >
// details amount > subtotal), just sourced from the model's typed
// properties (request.items, request.rawDetails, request.displayAmount)
// instead of map['key'] lookups.
class DeliveryChallanCard extends StatelessWidget {
  const DeliveryChallanCard({
    super.key,
    required this.request,
  });

  final ServiceRequestModel request;

  String get _shortId => request.requestId.length > 6
      ? request.requestId.substring(request.requestId.length - 6).toUpperCase()
      : request.requestId.toUpperCase();

  String _formatDate(DateTime? createdAt) {
    if (createdAt == null) return '';
    final dt = createdAt;
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y at $h:$min';
  }

  /// Legacy fallback text — first non-empty of listText / items(String) /
  /// taskDescription, so an old document still shows something even
  /// when it predates the structured `items` list.
  String? _legacyText(Map<String, dynamic> details) {
    final listText = (details['listText'] as String?)?.trim();
    if (listText != null && listText.isNotEmpty) return listText;

    final itemsRaw = details['items'];
    if (itemsRaw is String && itemsRaw.trim().isNotEmpty) return itemsRaw.trim();

    final taskDesc = (details['taskDescription'] as String?)?.trim();
    if (taskDesc != null && taskDesc.isNotEmpty) return taskDesc;

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final details = request.rawDetails;
    final status = request.status;
    final requestType = request.requestType.isNotEmpty ? request.requestType : 'hero_booking';
    final createdAt = request.createdAt;
    final structuredItems = request.items;
    final legacyText = structuredItems.isEmpty ? _legacyText(details) : null;
    final amount = request.displayAmount?.toDouble();
    final deliveryAddress = request.deliveryAddress;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.text.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.receipt_long_rounded, color: colors.accent, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Delivery Challan',
                  style: GoogleFonts.outfit(color: colors.text, fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '#$_shortId',
                  style: GoogleFonts.outfit(color: colors.accent, fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (createdAt != null)
            Padding(
              padding: const EdgeInsets.only(left: 44),
              child: Text(
                _formatDate(createdAt),
                style: TextStyle(color: colors.mutedText, fontSize: 11.5),
              ),
            ),
          const SizedBox(height: 16),
          Divider(color: colors.border, height: 1),
          const SizedBox(height: 14),

          // ── Itemized table ──────────────────────────────────────
          Text(
            'Items',
            style: GoogleFonts.outfit(color: colors.mutedText, fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (structuredItems.isNotEmpty) ...[
            for (var i = 0; i < structuredItems.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${structuredItems[i].sNo ?? i + 1}.',
                        style: TextStyle(color: colors.mutedText, fontSize: 12.5),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        structuredItems[i].name,
                        style: TextStyle(color: colors.text, fontSize: 13),
                      ),
                    ),
                    // Defensive: custom_hotel_order (and
                    // catalog_food_order) write real priced-cart line
                    // items with a `price`/`quantity` shape rather than
                    // the {sNo, name, qty} shape the other 3 request
                    // types use — ServiceRequestLineItem carries both
                    // shapes' fields, so this renders correctly either
                    // way without any per-requestType branching here.
                    if (structuredItems[i].price != null) ...[
                      Text(
                        '₹${structuredItems[i].price!.toStringAsFixed(0)} × ',
                        style: TextStyle(color: colors.mutedText, fontSize: 11.5),
                      ),
                    ],
                    Text(
                      (structuredItems[i].qty ?? structuredItems[i].quantity ?? '').toString(),
                      style: TextStyle(color: colors.text, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
          ] else if (legacyText != null) ...[
            Text(
              legacyText,
              style: TextStyle(color: colors.text, fontSize: 13, height: 1.4),
            ),
          ] else ...[
            Text(
              'No item details provided.',
              style: TextStyle(color: colors.mutedText, fontSize: 12.5, fontStyle: FontStyle.italic),
            ),
          ],

          if (amount != null) ...[
            const SizedBox(height: 12),
            Divider(color: colors.border, height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  (request.status == 'completed' && request.finalAmount != null)
                      ? 'Final Amount'
                      : 'Estimated Amount',
                  style: GoogleFonts.outfit(color: colors.mutedText, fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                Text(
                  '₹${amount.toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(color: colors.accent, fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ],

          if (deliveryAddress != null) ...[
            const SizedBox(height: 12),
            Divider(color: colors.border, height: 1),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on_outlined, color: colors.accentSecondary, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    deliveryAddress,
                    style: TextStyle(color: colors.text, fontSize: 12.5, height: 1.4),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),
          Divider(color: colors.border, height: 1),
          const SizedBox(height: 14),
          TrackingTimeline(currentStatus: status, requestType: requestType),
        ],
      ),
    );
  }
}
