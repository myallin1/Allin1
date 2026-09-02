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
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/payment_config.dart';
import '../services/auth_service.dart';
import '../services/food_seller_service.dart';
import '../services/service_request_service.dart';
import '../widgets/location_capture_field.dart';
import 'phonepe_checkout_screen.dart';

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
  final String paymentMethod; // 'cod' | 'upi' | 'phonepe_upi'

  // NEW (PhonePe gateway integration, Sep 2026): populated ONLY when
  // paymentMethod == 'phonepe_upi'. Payment for a gateway order is
  // collected BEFORE the service_requests doc exists (see
  // phonepe_payment_service.dart's confirmLink() doc comment), so the
  // caller MUST create that doc with `preGeneratedRequestId:
  // reservedRequestId` — using any other id would create an order the
  // payment can never be linked to — and then call
  // PhonePePaymentService.instance.confirmLink(merchantTransactionId,
  // requestId: reservedRequestId) right after, to close the loop.
  final String? reservedRequestId;
  final String? merchantTransactionId;

  const FoodCheckoutResult({
    required this.address,
    required this.customerName,
    required this.customerPhone,
    required this.paymentMethod,
    this.lat,
    this.lng,
    this.reservedRequestId,
    this.merchantTransactionId,
  });
}

class FoodCheckoutScreen extends StatefulWidget {
  const FoodCheckoutScreen({
    required this.hotelName,
    required this.items, // [{name, price, quantity, total}]
    required this.subtotal,
    this.sellerId,
    super.key,
  });

  final String hotelName;
  final List<Map<String, dynamic>> items;
  final double subtotal;

  /// When set, this screen fetches the seller's own UPI VPA/QR (Sep
  /// 2026 — merchant-account-free direct payment) and offers "Pay
  /// [hotelName] directly" alongside Cash/UPI-now/PhonePe. Null for any
  /// caller that hasn't wired a sellerId through yet — that caller
  /// simply never sees the extra option, no other behavior changes.
  final String? sellerId;

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
  bool _phonePeStarting = false;

  // Seller's own direct-payment details (Sep 2026) — fetched ONCE (a
  // plain get(), not a stream; this screen is a one-shot checkout, not
  // a live view) when [FoodCheckoutScreen.sellerId] is set.
  String? _sellerUpiVpa;
  Uint8List? _sellerQrBytes;
  bool _sellerPaymentLoaded = false;
  bool _confirmingSellerDirect = false;
  bool _sellerUpiOpened = false;

  @override
  void initState() {
    super.initState();
    if (widget.sellerId != null) {
      unawaited(_loadSellerPaymentInfo(widget.sellerId!));
    }
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

  Future<void> _loadSellerPaymentInfo(String sellerId) async {
    try {
      final seller = await FoodSellerService().getSeller(sellerId);
      if (!mounted) return;
      final qrB64 = seller?.sellerPaymentQrBase64;
      setState(() {
        _sellerUpiVpa = seller?.sellerUpiVpa;
        _sellerQrBytes = (qrB64 != null && qrB64.isNotEmpty) ? base64Decode(qrB64) : null;
        _sellerPaymentLoaded = true;
      });
    } catch (e) {
      debugPrint('[FoodCheckoutScreen] seller payment info load failed: $e');
      if (mounted) setState(() => _sellerPaymentLoaded = true);
    }
  }

  /// Opens whichever the seller configured — a UPI deep link if they set
  /// a VPA, or just shows the QR image for the customer to scan/screenshot
  /// if they only set a QR. Mirrors PaymentConfig.buildUpiIntentUri's own
  /// platform split, generalized to an arbitrary VPA instead of the
  /// company one.
  Future<void> _openSellerUpi() async {
    final vpa = _sellerUpiVpa;
    if (vpa == null || vpa.isEmpty) return;
    final encodedPn = Uri.encodeComponent(widget.hotelName);
    final fallback = Uri.encodeComponent('https://www.npci.org.in/what-we-do/upi/product-overview');
    final uri = kIsWeb
        ? Uri.parse(
            'intent://pay?pa=$vpa&pn=$encodedPn&am=${widget.subtotal.toStringAsFixed(2)}&cu=INR'
            '#Intent;scheme=upi;action=android.intent.action.VIEW;'
            'S.browser_fallback_url=$fallback;end',
          )
        : Uri.parse(
            'upi://pay?pa=$vpa&pn=$encodedPn&am=${widget.subtotal.toStringAsFixed(2)}&cu=INR',
          );
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted) setState(() => _sellerUpiOpened = opened || _sellerUpiOpened);
    } catch (e) {
      if (mounted) setState(() => _sellerUpiOpened = true);
    }
  }

  Future<void> _confirmSellerDirectPaid() async {
    setState(() => _confirmingSellerDirect = true);
    // Same honesty-preserving pattern as _confirmUpiPaid — there is
    // deliberately no gateway in this path (that's the whole point of
    // paying the seller directly instead of a merchant account), so the
    // seller themselves re-verifies this against their own bank/UPI app
    // before booking a hero — see seller_dashboard_screen.dart's
    // "Confirm Payment Received" gate.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _confirmingSellerDirect = false);
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
        paymentMethod: 'seller_direct_upi',
      ),
    );
  }

  /// Full gateway path: reserve an id, collect payment against it via a
  /// WebView checkout, and only pop this screen once PhonePe's own
  /// webhook has SERVER-VERIFIED the payment — the caller then creates
  /// the order with that exact reserved id and calls confirmLink().
  Future<void> _payWithPhonePe() async {
    setState(() => _phonePeStarting = true);
    try {
      // Free — allocates a Firestore doc id without writing anything.
      final reservedRequestId = ServiceRequestService().reserveRequestId();

      final outcome = await Navigator.push<PhonePeCheckoutOutcome>(
        context,
        MaterialPageRoute<PhonePeCheckoutOutcome>(
          builder: (_) => PhonePeCheckoutScreen(
            requestId: reservedRequestId,
            amount: widget.subtotal,
          ),
        ),
      );

      if (!mounted) return;
      setState(() => _phonePeStarting = false);

      if (outcome == null || !outcome.success) {
        // Cancelled, backed out, or the gateway itself reported failure
        // — stay on this screen exactly like a cancelled UPI-intent
        // attempt does. Nothing was ever created, so there is nothing to
        // roll back.
        if (outcome != null && !outcome.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Payment was not completed.')),
          );
        }
        return;
      }

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
          paymentMethod: 'phonepe_upi',
          reservedRequestId: reservedRequestId,
          merchantTransactionId: outcome.merchantTransactionId,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _phonePeStarting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start PhonePe checkout: $e')),
        );
      }
    }
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
        // NEW (PhonePe gateway, Sep 2026 — Blaze plan confirmed):
        // server-verified UPI, unlike the "Pay via UPI now" card below,
        // which is a self-attested manual flow kept only as a fallback
        // if the gateway itself is ever unreachable. Shown first since
        // it's now the recommended path.
        _paymentOptionCard(
          icon: Icons.verified_rounded,
          title: 'Pay via UPI (Recommended)',
          subtitle: 'GPay / PhonePe / Paytm — instantly verified, no manual confirmation.',
          busy: _phonePeStarting,
          onTap: _phonePeStarting ? null : _payWithPhonePe,
        ),
        const SizedBox(height: 12),
        // Cash on Delivery
        _paymentOptionCard(
          icon: Icons.payments_rounded,
          title: 'Cash on Delivery',
          subtitle: 'Pay the delivery hero when your order arrives.',
          onTap: _confirmCod,
        ),
        // NEW (Sep 2026 — merchant-account-free direct payment): only
        // rendered once seller payment info has loaded AND the seller
        // actually configured a VPA or QR — a seller who hasn't set
        // either up in Settings simply never shows this card, same
        // "additive, never a dead end" pattern as every other card here.
        if (_sellerPaymentLoaded &&
            ((_sellerUpiVpa?.isNotEmpty ?? false) || _sellerQrBytes != null)) ...[
          const SizedBox(height: 12),
          _buildSellerDirectCard(),
        ],
        const SizedBox(height: 12),
        // Manual UPI (fallback — kept for when the gateway is unreachable)
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

  /// "Pay [hotelName] directly" — the seller's own UPI VPA/QR, set by
  /// them in seller_settings_screen.dart. Cash reaches the seller
  /// same-day with no merchant account; the trade-off is the same one
  /// the manual "Pay via UPI now" card below already accepts — no
  /// server verification, self-attested (by the SELLER, not the
  /// customer, this time — see seller_dashboard_screen.dart's "Confirm
  /// Payment Received" gate before a hero can be booked).
  Widget _buildSellerDirectCard() {
    return Container(
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
              const Icon(Icons.storefront_rounded, color: _kPink, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Pay ${widget.hotelName} directly',
                    style: GoogleFonts.outfit(
                        color: _kText, fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              Text('₹${widget.subtotal.toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(
                      color: _kPinkDark, fontWeight: FontWeight.w800, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          if (_sellerQrBytes != null) ...[
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(_sellerQrBytes!, width: 160, height: 160, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 10),
            Text('Scan with any UPI app, or use the button below.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(color: _kMuted, fontSize: 11.5)),
            const SizedBox(height: 10),
          ],
          if (_sellerUpiVpa?.isNotEmpty ?? false)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await _openSellerUpi();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kPink,
                  side: const BorderSide(color: _kPink),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.qr_code_rounded, size: 18),
                label: Text(_sellerUpiOpened ? 'Open UPI App Again' : 'Open UPI App',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ),
          if ((_sellerUpiOpened) || (_sellerQrBytes != null && (_sellerUpiVpa?.isEmpty ?? true))) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _confirmingSellerDirect ? null : _confirmSellerDirectPaid,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _confirmingSellerDirect
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),)
                    : const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                label: Text("I've Paid — Confirm Order",
                    style: GoogleFonts.outfit(
                        color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _paymentOptionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool busy = false,
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
            busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _kPink),
                  )
                : const Icon(Icons.chevron_right_rounded, color: _kMuted),
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
