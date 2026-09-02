// ================================================================
// phonepe_checkout_screen.dart — hosts PhonePe's checkout page in a
// WebView and waits for the SERVER-VERIFIED result before reporting
// success/failure. Never reads the WebView's own navigation/URL state
// to decide the outcome — see phonepe_payment_service.dart's header
// for why (client-side UPI-intent/redirect signals are spoofable;
// only phonepeWebhook.ts's checksum-verified callback counts).
// ================================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/phonepe_payment_service.dart';

/// What the caller gets back once the WebView closes. [merchantTransactionId]
/// is populated whenever an order was actually created here — even on
/// failure, since a caller may want it for support/reconciliation — and is
/// what a "pay before the order doc exists" caller (food checkout) later
/// passes to PhonePePaymentService.confirmLink() once it has created that doc.
class PhonePeCheckoutOutcome {
  final bool success;
  final String? merchantTransactionId;
  const PhonePeCheckoutOutcome({required this.success, this.merchantTransactionId});
}

class PhonePeCheckoutScreen extends StatefulWidget {
  final String requestId;
  final double amount;
  final String collection;

  const PhonePeCheckoutScreen({
    required this.requestId,
    required this.amount,
    this.collection = 'service_requests',
    super.key,
  });

  @override
  State<PhonePeCheckoutScreen> createState() => _PhonePeCheckoutScreenState();
}

class _PhonePeCheckoutScreenState extends State<PhonePeCheckoutScreen> {
  WebViewController? _controller;
  StreamSubscription<PhonePeOrderStatus>? _statusSub;
  Timer? _reconcileTimer;
  String? _merchantTransactionId;
  String? _error;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _startOrder();
  }

  Future<void> _startOrder() async {
    try {
      final order = await PhonePePaymentService.instance.createOrder(
        requestId: widget.requestId,
        amount: widget.amount,
        collection: widget.collection,
      );
      _merchantTransactionId = order.merchantTransactionId;

      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(Uri.parse(order.redirectUrl));

      _statusSub = PhonePePaymentService.instance
          .watchOrderStatus(order.merchantTransactionId)
          .listen(_onStatus);

      // If the customer backs out of the checkout page before the
      // webhook lands, this fallback forces a direct check against
      // PhonePe a few seconds later instead of leaving the screen
      // stuck on "waiting".
      _reconcileTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_merchantTransactionId != null && !_resolved) {
          PhonePePaymentService.instance.reconcile(_merchantTransactionId!);
        }
      });

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start payment: $e');
    }
  }

  void _onStatus(PhonePeOrderStatus status) {
    if (_resolved || !mounted) return;
    if (status == PhonePeOrderStatus.paid) {
      _resolved = true;
      Navigator.of(context).pop(
        PhonePeCheckoutOutcome(success: true, merchantTransactionId: _merchantTransactionId),
      );
    } else if (status == PhonePeOrderStatus.failed) {
      _resolved = true;
      Navigator.of(context).pop(
        PhonePeCheckoutOutcome(success: false, merchantTransactionId: _merchantTransactionId),
      );
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _reconcileTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete Payment')),
      body: _error != null
          ? Center(child: Text(_error!))
          : _controller == null
              ? const Center(child: CircularProgressIndicator())
              : WebViewWidget(controller: _controller!),
    );
  }
}
