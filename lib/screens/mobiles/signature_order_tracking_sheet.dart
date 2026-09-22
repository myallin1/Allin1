// ================================================================
// signature_order_tracking_sheet.dart — Live Order Tracking for Signature Mobiles
// ================================================================
// Shows live order status stepper, rider dispatch information,
// and 1-tap post-delivery review trigger.
// ================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/signature_mobile_models.dart';
import '../../services/signature_mobile_service.dart';
import 'signature_feedback_dialog.dart';

const Color _bg = Color(0xFF0F0F1E);
const Color _surface = Color(0xFF18182E);
const Color _card = Color(0xFF22223D);
const Color _pink = Color(0xFFFF4FA3);
const Color _green = Color(0xFF00E676);
const Color _gold = Color(0xFFFFD600);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF8888AA);

class SignatureOrderTrackingSheet extends StatelessWidget {
  final String orderId;

  const SignatureOrderTrackingSheet({super.key, required this.orderId});

  static void show(BuildContext context, {required String orderId}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SignatureOrderTrackingSheet(orderId: orderId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: StreamBuilder<SignatureOrder?>(
        stream: SignatureMobileService.instance.streamOrder(orderId),
        builder: (context, snapshot) {
          final order = snapshot.data;
          if (order == null) {
            return const Center(
              child: CircularProgressIndicator(color: _pink),
            );
          }

          return Column(
            children: [
              // Header Drag Handle & Title
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _muted.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _pink.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.local_shipping_rounded, color: _pink, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Order Tracking',
                                style: GoogleFonts.outfit(
                                  color: _text,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'ID: ${order.orderId}',
                                style: GoogleFonts.inter(color: _muted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: _muted),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Divider(color: _card, height: 1),

              // Body Content
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Status Stepper Card
                    _buildStatusStepper(order),

                    const SizedBox(height: 18),

                    // Order Items Card
                    _buildItemsCard(order),

                    const SizedBox(height: 18),

                    // Delivery & Payment Info
                    _buildDeliveryInfoCard(order),

                    const SizedBox(height: 20),

                    // Review & Feedback Button if Delivered
                    if (order.status == SignatureOrderStatus.delivered) ...[
                      if (order.rating != null)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _green.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.star_rounded, color: _gold, size: 24),
                              const SizedBox(width: 8),
                              Text(
                                'Rated ${order.rating}/5 Stars',
                                style: GoogleFonts.inter(color: _text, fontWeight: FontWeight.w700),
                              ),
                              const Spacer(),
                              const Icon(Icons.check_circle_rounded, color: _green, size: 18),
                            ],
                          ),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: () {
                            SignatureFeedbackDialog.show(
                              context,
                              orderId: order.orderId,
                              productName: order.items.isNotEmpty
                                  ? order.items.first.productName
                                  : 'Signature Mobile',
                            );
                          },
                          icon: const Icon(Icons.rate_review_rounded, color: Colors.white),
                          label: Text(
                            'Leave 5-Star Feedback',
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _pink,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusStepper(SignatureOrder order) {
    int currentStep = 0;
    switch (order.status) {
      case SignatureOrderStatus.placed:
        currentStep = 1;
        break;
      case SignatureOrderStatus.confirmed:
        currentStep = 2;
        break;
      case SignatureOrderStatus.dispatched:
        currentStep = 3;
        break;
      case SignatureOrderStatus.delivered:
        currentStep = 4;
        break;
      case SignatureOrderStatus.cancelled:
        currentStep = 0;
        break;
    }

    final steps = [
      {'title': 'Order Placed', 'sub': 'Received by NJ Tech Signature Hub'},
      {'title': 'Quality Verified', 'sub': 'Packed with warranty certificate'},
      {'title': 'Out for Delivery', 'sub': 'Assigned to Hero Rider'},
      {'title': 'Delivered', 'sub': 'Successfully handed over'},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order Progress',
            style: GoogleFonts.outfit(color: _text, fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < steps.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: (i + 1) <= currentStep ? _green : _card,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: (i + 1) <= currentStep ? _green : _muted.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Center(
                        child: (i + 1) <= currentStep
                            ? const Icon(Icons.check_rounded, color: Colors.black, size: 14)
                            : Text('${i + 1}',
                                style: GoogleFonts.inter(color: _muted, fontSize: 10)),
                      ),
                    ),
                    if (i < steps.length - 1)
                      Container(
                        width: 2,
                        height: 28,
                        color: (i + 1) < currentStep ? _green : _card,
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        steps[i]['title']!,
                        style: GoogleFonts.inter(
                          color: (i + 1) <= currentStep ? _text : _muted,
                          fontSize: 13,
                          fontWeight: (i + 1) <= currentStep ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      Text(
                        steps[i]['sub']!,
                        style: GoogleFonts.inter(color: _muted, fontSize: 11),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemsCard(SignatureOrder order) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Purchased Items (${order.items.length})',
            style: GoogleFonts.outfit(color: _text, fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ...order.items.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.phone_android_rounded, color: _pink, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.productName,
                          style: GoogleFonts.inter(
                            color: _text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${item.brand} • Qty: ${item.quantity}',
                          style: GoogleFonts.inter(color: _muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '₹${item.total.toStringAsFixed(0)}',
                    style: GoogleFonts.outfit(
                      color: _text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDeliveryInfoCard(SignatureOrder order) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                order.deliveryMode == SignatureDeliveryMode.storePickup
                    ? Icons.storefront_rounded
                    : Icons.home_rounded,
                color: _gold,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                order.deliveryMode == SignatureDeliveryMode.storePickup
                    ? 'Store Self-Pickup'
                    : 'Doorstep Delivery',
                style: GoogleFonts.inter(color: _text, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            order.deliveryAddress.isEmpty
                ? 'NJ Tech Service & Gadget Flagship, Erode'
                : order.deliveryAddress,
            style: GoogleFonts.inter(color: _muted, fontSize: 12),
          ),
          const Divider(color: _card, height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Amount Paid', style: GoogleFonts.inter(color: _muted, fontSize: 13)),
              Text(
                '₹${order.totalAmount.toStringAsFixed(0)}',
                style: GoogleFonts.outfit(color: _green, fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
