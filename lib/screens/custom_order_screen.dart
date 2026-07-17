// ================================================================
// custom_order_screen.dart — Broadcast Order System: Custom Order
// Renovated: the previous version was a pure WhatsApp-redirect stub
// with no backend. Now a simple order-description form that creates
// a service_requests doc (requestType: custom_order) and broadcasts
// to all online + available heroes, then hands off to the shared
// tracking screen.
// ================================================================
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/service_request_service.dart';
import 'service_request_tracking_screen.dart';

const Color _kPink = Color(0xFFFF4FA3);
const Color _kBg = Color(0xFFFFFFFF);
const Color _kSurface = Color(0xFFF8F8FF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF9999BB);

class CustomOrderScreen extends StatefulWidget {
  const CustomOrderScreen({super.key});
  @override
  State<CustomOrderScreen> createState() => _CustomOrderScreenState();
}

class _CustomOrderScreenState extends State<CustomOrderScreen> {
  final _orderCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _orderCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_orderCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe your order first!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      final requestId = await ServiceRequestService().createServiceRequest(
        requestType: 'custom_order',
        customerId: user.uid,
        customerName: user.displayName ?? 'Customer',
        customerPhone: user.phoneNumber ?? '',
        details: {'orderDescription': _orderCtrl.text.trim()},
      );

      unawaited(
        Future.delayed(
          const Duration(seconds: kServiceRequestPingExpirySeconds),
          () => ServiceRequestService().markTimeoutIfStillPending(requestId),
        ),
      );

      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ServiceRequestTrackingScreen(
            requestId: requestId,
            requestType: 'custom_order',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: _kText,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Custom Order',
          style: GoogleFonts.outfit(
            color: _kText,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kPink.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kPink.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Text('📦', style: TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order anything, from anywhere',
                          style: GoogleFonts.outfit(
                            color: _kText,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Manpower, medicine, fresh fish, meat, or anything else — describe it and a Hero will handle it.',
                          style: TextStyle(color: _kMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'What do you want to order?',
              style: GoogleFonts.outfit(
                color: _kText,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _orderCtrl,
              maxLines: 5,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText:
                    'e.g., 2kg fresh chicken from any shop on Perundurai Road',
                hintStyle: TextStyle(
                  color: _kMuted.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
                filled: true,
                fillColor: _kSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPink,
                  elevation: 4,
                  shadowColor: _kPink.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Send Order',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
