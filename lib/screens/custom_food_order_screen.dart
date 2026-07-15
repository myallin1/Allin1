import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/service_request_service.dart';
import '../utils/service_request_labels.dart';
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
      // Clear the form so the just-placed order shows cleanly in the
      // "My Orders" list when the user taps back from tracking.
      _shopCtrl.clear();
      _itemsCtrl.clear();
      _addressCtrl.clear();
      // `push` (not `pushReplacement`) so pressing back returns to this
      // Food Genie page and the live "My Orders" list below.
      await Navigator.push(
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
            const SizedBox(height: 32),
            _buildMyOrders(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // ── My Orders — live status list for this customer ───────────────
  Widget _buildMyOrders() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    final stream = FirebaseFirestore.instance
        .collection('service_requests')
        .where('customerId', isEqualTo: user.uid)
        .where('requestType', isEqualTo: 'custom_food_order')
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('My Orders', style: GoogleFonts.outfit(color: kText, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator(color: kPink, strokeWidth: 2)),
              );
            }
            if (snapshot.hasError) {
              return const Text('Could not load your orders.', style: TextStyle(color: kMuted, fontSize: 12));
            }
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'No orders yet. Place your first order above! 🍔',
                  style: TextStyle(color: kMuted, fontSize: 13),
                ),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _orderCard(docs[i]),
            );
          },
        ),
      ],
    );
  }

  Widget _orderCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final details = (data['details'] as Map<String, dynamic>?) ?? const {};
    final shop = (details['restaurantOrPreference'] as String?)?.trim();
    final items = (details['items'] as String?)?.trim();
    final status = (data['status'] as String?) ?? 'pending';
    final statusColor = serviceRequestStatusColor(status);
    final statusLabel = serviceRequestStatusLabel('custom_food_order', status);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ServiceRequestTrackingScreen(
            requestId: doc.id,
            requestType: 'custom_food_order',
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEEEF5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (shop != null && shop.isNotEmpty) ? shop : 'Custom food order',
                    style: GoogleFonts.outfit(color: kText, fontSize: 14, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (items != null && items.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      items,
                      style: const TextStyle(color: kMuted, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
