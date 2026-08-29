// ================================================================
// FoodCheckoutScreen — delivery details + payment, BEFORE the order
// is created.
// ================================================================
// NEW (Aug 18 2026 — Nizam: "customer order book pannunathum udane
// order aiduchu cart la potta... namma food order form open agi namma
// potta hotel athula fetch agi delevery details nammakita ketu fill
// pannunathum, payment pannitu than order confirm aganum" — "the shop
// menu checkout was creating the order the instant Place Order was
// tapped, with no delivery-details form and no payment step at all").
//
// ROOT CAUSE (seller_detail_screen.dart's _CartBottomSheet._checkout,
// verified by reading it end to end): "Place Order" ran the stock
// transaction and called ServiceRequestService().createServiceRequest()
// directly, in the same tap — zero screens in between. Compare against
// custom_hotel_view_screen.dart's _CheckoutSheet, which at least asks
// for a delivery address first (still no payment step though — every
// order path in this app today is effectively Cash/UPI-on-delivery,
// there is no payment gateway on the Spark plan). Neither shop-menu
// nor custom-hotel checkout ever asked to CONFIRM payment before the
// order reached the kitchen.
//
// This screen is the missing middle step, reused by BOTH: it does NOT
// write anything to Firestore itself (single-writer principle — order
// creation, the stock-reservation transaction, and hero-dispatch all
// stay exactly where they already live in each caller). It only
// collects delivery details and a payment decision, then hands a
// [FoodCheckoutResult] back via Navigator.pop for the caller to act on.
//
// Two payment paths, matching the UPI pattern already proven in
// payment_screen.dart / PaymentConfig (no new payment infra invented):
//   - Cash on Delivery: no UPI intent, order confirms immediately.
//   - Pay via UPI now: opens the same intent:// / upi:// deep link
//     PaymentConfig already builds for rides, pre-filled with the
//     order total. The customer manually confirms "I've Paid" after —
//     exactly the honesty-preserving pattern the rest of the app uses
//     for UPI (there is no server here to verify a webhook on Spark).
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/payment_config.dart';
import '../services/auth_service.dart';
import '../widgets/location_capture_field.dart';

const Color _kBg = Color(0xFFFFF6FA);
const Color _kSurface = Color(0xFFFFFFFF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF8C7A88);
const Color _kPink = Color(0xFFFF4FA3);
const Color _kPinkDark = Color(0xFFBE2A7A);
const Color _kGreen = Color(0xFF00A86B);

/// What the caller gets back once the customer has filled delivery
/// details and made a payment decision. The order itself is NOT
/// created by this screen — the caller (seller_detail_screen.dart etc.)
/// still owns the stock-reservation transaction and
/// ServiceRequestService().createServiceRequest() call, unchanged.
class FoodCheckoutResult {
  final String address;
  final double? lat;
  final double? lng;
  final String customerName;
  final String customerPhone;
  final String paymentMethod; // 'cod' | 'upi'

  const FoodCheckoutResult({
    required this.address,
    required this.customerName,
    required this.customerPhone,
    required this.paymentMethod,
    this.lat,
    this.lng,
  });
}

class FoodCheckoutScreen extends StatefulWidget {
  const FoodCheckoutScreen({
    required this.hotelName,
    required this.items, // [{name, price, quantity, total}]
    required this.subtotal,
    super.key,
  });

  final String hotelName;
  final List<Map<String, dynamic>> items;
  final double subtotal;

  @override
  State<FoodCheckoutScreen> createState() => _FoodCheckoutScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('hotelName', hotelName))
      ..add(DoubleProperty('subtotal', subtotal));
  }
}

class _FoodCheckoutScreenState extends State<FoodCheckoutScreen> {
  // Step 0 = delivery details, Step 1 = payment.
  int _step = 0;

  final _addressCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  double? _lat;
  double? _lng;

  bool _upiOpened = false;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _nameCtrl.text = user?.displayName ?? '';
    _phoneCtrl.text = user?.phoneNumber ?? '';
    if (user != null) {
      unawaited(
        AuthService().resolveCustomerPhone(user).then((phone) {
          if (mounted && _phoneCtrl.text.trim().isEmpty && phone.isNotEmpty) {
            _phoneCtrl.text = phone;
          }
        }),
      );
    }
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _continueToPayment() {
    if (_addressCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a delivery address.')),
      );
      return;
    }
    if (_phoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a contact phone number.')),
      );
      return;
    }
    setState(() => _step = 1);
  }

  void _confirmCod() {
    Navigator.pop(
      context,
      FoodCheckoutResult(
        address: _addressCtrl.text.trim(),
        lat: _lat,
        lng: _lng,
        customerName: _nameCtrl.text.trim().isNotEmpty
            ? _nameCtrl.text.trim()
            : (FirebaseAuth.instance.currentUser?.displayName ?? 'Customer'),
        customerPhone: _phoneCtrl.text.trim(),
        paymentMethod: 'cod',
      ),
    );
  }

  Future<void> _openUpi() async {
    // Mirrors payment_screen.dart's _launchUpi() split exactly: on web
    // a bare `upi://` scheme has no browser handler at all, so the
    // Android `intent://` form is used there (Chrome-on-Android
    // resolves it into the native app chooser); native app builds use
    // the plain scheme, which url_launcher already handles directly.
    final uri = kIsWeb
        ? PaymentConfig.buildUpiIntentUri(amount: widget.subtotal, note: 'FoodOrder')
        : PaymentConfig.buildUpiUri(amount: widget.subtotal, note: 'FoodOrder');
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted) setState(() => _upiOpened = opened || _upiOpened);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open a UPI app automatically.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _upiOpened = true); // let them confirm manually anyway
    }
  }

  Future<void> _confirmUpiPaid() async {
    setState(() => _confirming = true);
    // No server-side verification path exists on the Spark plan (no
    // Cloud Functions) — this mirrors payment_screen.dart's own manual
    // "I've Paid" pattern used for ride payments. The seller/admin can
    // already see paymentMethod on the order and follow up if needed.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _confirming = false);
    Navigator.pop(
      context,
      FoodCheckoutResult(
        address: _addressCtrl.text.trim(),
        lat: _lat,
        lng: _lng,
        customerName: _nameCtrl.text.trim().isNotEmpty
            ? _nameCtrl.text.trim()
            : (FirebaseAuth.instance.currentUser?.displayName ?? 'Customer'),
        customerPhone: _phoneCtrl.text.trim(),
        paymentMethod: 'upi',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _kText),
        title: Text(
          _step == 0 ? 'Delivery Details' : 'Payment',
          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: _kText),
        ),
      ),
      body: SafeArea(
        child: _step == 0 ? _buildDetailsStep() : _buildPaymentStep(),
      ),
    );
  }

  Widget _buildDetailsStep() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _hotelCard(),
        const SizedBox(height: 16),
        _sectionLabel('Delivery Address'),
        const SizedBox(height: 8),
        LocationCaptureField(
          addressController: _addressCtrl,
          pickerTitle: 'Select delivery location',
          onLocationPicked: (lat, lng) {
            _lat = lat;
            _lng = lng;
          },
        ),
        const SizedBox(height: 10),
        _textField(_addressCtrl, 'Delivery address', Icons.location_on_rounded, maxLines: 2),
        const SizedBox(height: 18),
        _sectionLabel('Contact Details'),
        const SizedBox(height: 8),
        _textField(_nameCtrl, 'Your name', Icons.person_rounded),
        const SizedBox(height: 10),
        _textField(_phoneCtrl, 'Phone number', Icons.call_rounded,
            keyboardType: TextInputType.phone),
        const SizedBox(height: 24),
        _orderSummaryCard(),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _continueToPayment,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPink,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text('Continue to Payment',
                style: GoogleFonts.outfit(
                    color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5)),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildPaymentStep() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _orderSummaryCard(),
        const SizedBox(height: 20),
        _sectionLabel('Choose Payment Method'),
        const SizedBox(height: 10),
        // Cash on Delivery
        _paymentOptionCard(
          icon: Icons.payments_rounded,
          title: 'Cash on Delivery',
          subtitle: 'Pay the delivery hero when your order arrives.',
          onTap: _confirmCod,
        ),
        const SizedBox(height: 12),
        // UPI now
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFFEAF3), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: _kPink, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Pay via UPI now',
                        style: GoogleFonts.outfit(
                            color: _kText, fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                  Text('₹${widget.subtotal.toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(
                          color: _kPinkDark, fontWeight: FontWeight.w800, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openUpi,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kPink,
                    side: const BorderSide(color: _kPink),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.qr_code_rounded, size: 18),
                  label: Text(_upiOpened ? 'Open UPI App Again' : 'Open UPI App',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
              if (_upiOpened) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _confirming ? null : _confirmUpiPaid,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGreen,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _confirming
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                    label: Text("I've Paid — Confirm Order",
                        style: GoogleFonts.outfit(
                            color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5)),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () => setState(() => _step = 0),
          icon: const Icon(Icons.arrow_back_rounded, size: 16, color: _kMuted),
          label: Text('Edit delivery details',
              style: GoogleFonts.outfit(color: _kMuted, fontSize: 12.5)),
        ),
      ],
    );
  }

  Widget _paymentOptionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFEAF3), width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: _kPink, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.outfit(
                          color: _kText, fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: GoogleFonts.outfit(color: _kMuted, fontSize: 11.5)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _kMuted),
          ],
        ),
      ),
    );
  }

  Widget _hotelCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_kPink, _kPinkDark]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.storefront_rounded, color: Colors.white, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ordering from',
                      style: GoogleFonts.outfit(
                          color: Colors.white.withValues(alpha: 0.85), fontSize: 11)),
                  Text(widget.hotelName,
                      style: GoogleFonts.outfit(
                          color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15.5)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _orderSummaryCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFEAF3), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Order Summary',
                style: GoogleFonts.outfit(
                    color: _kText, fontWeight: FontWeight.w800, fontSize: 13.5)),
            const SizedBox(height: 10),
            ...widget.items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('${item['name']} x${item['quantity']}',
                            style: GoogleFonts.outfit(color: _kText, fontSize: 12.5)),
                      ),
                      Text('₹${(item['total'] as num).toStringAsFixed(0)}',
                          style: GoogleFonts.outfit(
                              color: _kText, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ],
                  ),
                )),
            const Divider(height: 20, color: Color(0xFFFFEAF3)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total',
                    style: GoogleFonts.outfit(
                        color: _kText, fontWeight: FontWeight.w800, fontSize: 14)),
                Text('₹${widget.subtotal.toStringAsFixed(0)}',
                    style: GoogleFonts.outfit(
                        color: _kPinkDark, fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
          ],
        ),
      );

  Widget _sectionLabel(String text) => Text(text,
      style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 13.5));

  Widget _textField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: GoogleFonts.outfit(color: _kText, fontSize: 13.5),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.outfit(color: _kMuted, fontSize: 12.5),
        prefixIcon: Icon(icon, color: _kPink, size: 18),
        filled: true,
        fillColor: _kSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFFEAF3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFFEAF3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kPink, width: 1.5),
        ),
      ),
    );
  }
}
