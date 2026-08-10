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

import '../services/auth_service.dart';
import '../services/service_request_service.dart';
import '../widgets/location_capture_field.dart';
import '../widgets/server_busy_dialog.dart';
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
  // NEW (per Nizam's request — "yella service request kum intha
  // location and navigation system than irukanum"): this form used to
  // collect zero location data, so a hero assigned here had no address
  // or coordinates to go to at all. Optional (not blocking submit) since
  // some custom orders are pure "buy and deliver to my usual address"
  // asks where the customer may prefer to just describe it in text —
  // but filling it in gives the hero a real, tappable navigation target.
  final _deliveryAddressCtrl = TextEditingController();
  double? _deliveryLat;
  double? _deliveryLng;
  bool _submitting = false;

  @override
  void dispose() {
    _orderCtrl.dispose();
    _deliveryAddressCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_orderCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe your order first!'), backgroundColor: Colors.red),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      final resolvedCustomerPhone = await AuthService().resolveCustomerPhone(user);
      final requestId = await ServiceRequestService().createServiceRequest(
        requestType: 'custom_order',
        customerId: user.uid,
        customerName: user.displayName ?? 'Customer',
        customerPhone: resolvedCustomerPhone,
        details: {
          'orderDescription': _orderCtrl.text.trim(),
          if (_deliveryAddressCtrl.text.trim().isNotEmpty)
            'deliveryAddress': _deliveryAddressCtrl.text.trim(),
          if (_deliveryLat != null) 'locationLat': _deliveryLat,
          if (_deliveryLng != null) 'locationLng': _deliveryLng,
        },
      );

      unawaited(Future.delayed(
        const Duration(seconds: kServiceRequestPingExpirySeconds),
        () => ServiceRequestService().markTimeoutIfStillPending(requestId),
      ),);

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
        showServerBusyDialog(context);
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Custom Order', style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 18)),
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
                        Text('Order anything, from anywhere', style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 14)),
                        const SizedBox(height: 2),
                        const Text('Manpower, medicine, fresh fish, meat, or anything else — describe it and a Hero will handle it.', style: TextStyle(color: _kMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('What do you want to order?', style: GoogleFonts.outfit(color: _kText, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _orderCtrl,
              maxLines: 5,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'e.g., 2kg fresh chicken from any shop on Perundurai Road',
                hintStyle: TextStyle(color: _kMuted.withValues(alpha: 0.6), fontSize: 13),
                filled: true,
                fillColor: _kSurface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 20),
            Text('Delivery location (optional but recommended)',
                style: GoogleFonts.outfit(color: _kText, fontSize: 13, fontWeight: FontWeight.w700),),
            const SizedBox(height: 8),
            TextField(
              controller: _deliveryAddressCtrl,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Where should the Hero deliver this?',
                hintStyle: TextStyle(color: _kMuted.withValues(alpha: 0.6), fontSize: 13),
                filled: true,
                fillColor: _kSurface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 10),
            LocationCaptureField(
              addressController: _deliveryAddressCtrl,
              pickerTitle: 'Delivery location',
              onLocationPicked: (lat, lng) {
                setState(() {
                  _deliveryLat = lat;
                  _deliveryLng = lng;
                });
              },
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Send Order', style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
