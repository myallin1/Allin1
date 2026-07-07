import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/service_request_service.dart';
import 'service_request_tracking_screen.dart';

const Color kPink = Color(0xFFFF4FA3);
const Color kBg = Color(0xFFFFFFFF);
const Color kSurface = Color(0xFFF8F8FF);
const Color kText = Color(0xFF1A1A2E);
const Color kMuted = Color(0xFF9999BB);
const Color kGold = Color(0xFFFFBB00);

class CustomFoodOrderScreen extends StatefulWidget {
  const CustomFoodOrderScreen({super.key});
  @override
  State<CustomFoodOrderScreen> createState() => _CustomFoodOrderScreenState();
}

class _CustomFoodOrderScreenState extends State<CustomFoodOrderScreen> {
  final _shopCtrl = TextEditingController();
  final _itemsCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _shopCtrl.dispose();
    _itemsCtrl.dispose();
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    if (_shopCtrl.text.isEmpty || _itemsCtrl.text.isEmpty || _addressCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in the required details 🍔'), backgroundColor: Colors.red),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      final requestId = await ServiceRequestService().createServiceRequest(
        requestType: 'custom_food_order',
        customerId: user.uid,
        customerName: _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : (user.displayName ?? 'Customer'),
        customerPhone: user.phoneNumber ?? '',
        details: {
          'items': _itemsCtrl.text.trim(),
          'restaurantOrPreference': _shopCtrl.text.trim(),
          'deliveryAddress': _addressCtrl.text.trim(),
        },
      );

      unawaited(Future.delayed(
        const Duration(seconds: kServiceRequestPingExpirySeconds),
        () => ServiceRequestService().markTimeoutIfStillPending(requestId),
      ));

      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ServiceRequestTrackingScreen(
            requestId: requestId,
            requestType: 'custom_food_order',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send order: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildField({required String label, required String hint, required TextEditingController ctrl, int lines = 1, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.outfit(color: kText, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            maxLines: lines,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: kMuted.withValues(alpha: 0.6), fontSize: 13),
              prefixIcon: icon != null ? Icon(icon, color: kPink, size: 20) : null,
              filled: true,
              fillColor: kSurface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: kText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Food Genie 🧞‍♂️', style: GoogleFonts.outfit(color: kText, fontWeight: FontWeight.w800, fontSize: 18)),
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
                color: kGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kGold.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Text('🤤', style: TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Order from ANY Shop!', style: GoogleFonts.outfit(color: Colors.orange[800], fontWeight: FontWeight.w800, fontSize: 14)),
                        const SizedBox(height: 2),
                        const Text('Just tell us what you want and from where. We will deliver it to you.', style: TextStyle(color: kText, fontSize: 11)),
                      ],
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildField(label: 'Restaurant / Shop Name', hint: 'e.g., Erode Amman Mess, 16th Road', ctrl: _shopCtrl, icon: Icons.storefront_rounded),
            _buildField(label: 'What do you want to eat?', hint: 'e.g., 2 Chicken Biryani, 1 Coke...', ctrl: _itemsCtrl, lines: 3),
            _buildField(label: 'Your Name', hint: 'Enter your name', ctrl: _nameCtrl, icon: Icons.person_outline_rounded),
            _buildField(label: 'Delivery Location', hint: 'Enter your full address & landmark', ctrl: _addressCtrl, lines: 2, icon: Icons.location_on_outlined),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPink,
                  elevation: 4,
                  shadowColor: kPink.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _isLoading ? null : _placeOrder,
                child: _isLoading
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Place Order', style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
