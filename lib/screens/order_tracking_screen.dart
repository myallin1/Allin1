// ================================================================
// order_tracking_screen.dart — Real Order Tracking
// Super App · Dark/Pink premium theme · May 2026
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _kBg     = Color(0xFF0C0A14);
const _kCard   = Color(0xFF1C1929);
const _kPink   = Color(0xFFFF4FA3);
const _kPinkD  = Color(0xFFBE2A7A);
const _kText   = Color(0xFFFFFFFF);
const _kMuted  = Color(0xFF7A7890);
const _kBorder = Color(0xFF2E2845);

class CartItem {
  final String name;
  final int qty;
  final double price;
  const CartItem({required this.name, required this.qty, required this.price});
  Map<String, dynamic> toMap() =>
      {'name': name, 'qty': qty, 'price': price, 'subtotal': qty * price};
}

class OrderTrackingScreen extends StatefulWidget {
  final List<CartItem> items;
  final double total;
  final String storeType;
  const OrderTrackingScreen({
    super.key,
    required this.items,
    required this.total,
    required this.storeType,
  });
  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  String? _orderId;
  bool _uploading = true;
  String? _error;
  Stream<DocumentSnapshot>? _orderStream;

  @override
  void initState() {
    super.initState();
    _pushOrderToFirebase();
  }

  Future<void> _pushOrderToFirebase() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
      final ref = await FirebaseFirestore.instance.collection('orders').add({
        'customerId': uid,
        'storeType': widget.storeType,
        'items': widget.items.map((e) => e.toMap()).toList(),
        'total': widget.total,
        'status': 'placed',
        'heroId': null,
        'heroName': null,
        'heroPhone': null,
        'placedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() {
        _orderId = ref.id;
        _uploading = false;
        _orderStream = ref.snapshots();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = e.toString();
      });
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
        title: Text('Order Tracking',
            style: GoogleFonts.outfit(
                color: _kText, fontSize: 18, fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: _uploading
          ? _buildUploading()
          : _error != null
              ? _buildError()
              : _buildTracking(),
    );
  }

  Widget _buildUploading() => const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: _kPink),
          SizedBox(height: 16),
          Text('Placing your order…', style: TextStyle(color: _kMuted, fontSize: 14)),
        ]),
      );

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, color: _kPink, size: 48),
            const SizedBox(height: 12),
            Text('Failed to place order',
                style: GoogleFonts.outfit(
                    color: _kText, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(_error ?? '',
                style: GoogleFonts.outfit(color: _kMuted, fontSize: 12),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kPink),
              onPressed: () {
                setState(() { _uploading = true; _error = null; });
                _pushOrderToFirebase();
              },
              child: Text('Retry',
                  style: GoogleFonts.outfit(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      );

  Widget _buildTracking() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _orderStream,
      builder: (ctx, snap) {
        final data     = snap.data?.data() as Map<String, dynamic>?;
        final status   = data?['status']   as String? ?? 'placed';
        final heroName = data?['heroName'] as String?;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildBanner(status, heroName),
            const SizedBox(height: 20),
            _buildTimeline(status),
            const SizedBox(height: 20),
            _buildSummary(),
            const SizedBox(height: 20),
            _buildSoundbox(),
            const SizedBox(height: 20),
            if (status != 'delivered') _buildOrderId(),
          ]),
        );
      },
    );
  }

  Widget _buildBanner(String status, String? heroName) {
    final assigned = status != 'placed';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: assigned
              ? [const Color(0xFF1A3A2A), const Color(0xFF0F2A1A)]
              : [_kPink.withValues(alpha: 0.18), _kPinkD.withValues(alpha: 0.10)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: assigned
                ? Colors.green.withValues(alpha: 0.4)
                : _kPink.withValues(alpha: 0.35),
            width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (assigned ? Colors.green : _kPink).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              assigned
                  ? Icons.delivery_dining_rounded
                  : Icons.check_circle_outline_rounded,
              color: assigned ? Colors.greenAccent : _kPink,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                assigned ? 'Hero Assigned! 🎉' : 'Order Confirmed ✅',
                style: GoogleFonts.outfit(
                    color: _kText, fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                assigned
                    ? '${heroName ?? 'Your Hero'} is on the way!'
                    : 'Waiting for a Parcel Hero to accept…',
                style: GoogleFonts.outfit(color: _kMuted, fontSize: 12),
              ),
            ]),
          ),
        ]),
        if (!assigned) ...[
          const SizedBox(height: 14),
          LinearProgressIndicator(
            backgroundColor: _kBorder,
            color: _kPink,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Text('This usually takes 1–3 minutes',
              style: GoogleFonts.outfit(color: _kMuted, fontSize: 11)),
        ],
      ]),
    );
  }

  Widget _buildTimeline(String status) {
    const steps = [
      _Step('placed',    'Order Placed',     Icons.shopping_bag_outlined),
      _Step('assigned',  'Hero Assigned',    Icons.person_pin_circle_rounded),
      _Step('picked',    'Parcel Picked Up', Icons.inventory_2_rounded),
      _Step('delivered', 'Delivered',        Icons.home_rounded),
    ];
    const ord = {'placed': 0, 'assigned': 1, 'picked': 2, 'delivered': 3};
    final cur  = ord[status] ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: List.generate(steps.length, (i) {
          final done   = i <= cur;
          final active = i == cur;
          final isLast = i == steps.length - 1;
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? (active ? _kPink : Colors.green.withValues(alpha: 0.8))
                      : _kBorder,
                  boxShadow: active
                      ? [BoxShadow(
                            color: _kPink.withValues(alpha: 0.45),
                            blurRadius: 12, spreadRadius: 1)]
                      : [],
                ),
                child: Icon(
                  done ? (active ? steps[i].icon : Icons.check_rounded)
                       : steps[i].icon,
                  color: done ? Colors.white : _kMuted, size: 18),
              ),
              if (!isLast)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: 2, height: 36,
                  color: i < cur
                      ? Colors.green.withValues(alpha: 0.6)
                      : _kBorder,
                ),
            ]),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(steps[i].label,
                      style: GoogleFonts.outfit(
                          color: done ? _kText : _kMuted,
                          fontSize: 13,
                          fontWeight: active ? FontWeight.w800 : FontWeight.w500)),
                  if (active && status == 'placed')
                    Text('Searching for nearby heroes…',
                        style: GoogleFonts.outfit(color: _kPink, fontSize: 11)),
                ]),
              ),
            ),
          ]);
        }),
      ),
    );
  }

  Widget _buildSummary() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Order Summary',
            style: GoogleFonts.outfit(
                color: _kText, fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        ...widget.items.map((item) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Text('${item.qty}×',
                style: GoogleFonts.outfit(
                    color: _kPink, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Expanded(child: Text(item.name,
                style: GoogleFonts.outfit(color: _kText, fontSize: 13))),
            Text('₹${(item.qty * item.price).toStringAsFixed(0)}',
                style: GoogleFonts.outfit(color: _kMuted, fontSize: 13)),
          ]),
        )),
        const Divider(color: _kBorder, height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Total',
              style: GoogleFonts.outfit(
                  color: _kText, fontSize: 15, fontWeight: FontWeight.w800)),
          Text('₹${widget.total.toStringAsFixed(0)}',
              style: GoogleFonts.outfit(
                  color: _kPink, fontSize: 16, fontWeight: FontWeight.w900)),
        ]),
      ]),
    );
  }

  Widget _buildSoundbox() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          _kPink.withValues(alpha: 0.14),
          _kPinkD.withValues(alpha: 0.08),
        ]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kPink.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _kPink.withValues(alpha: 0.18), shape: BoxShape.circle,
          ),
          child: const Icon(Icons.volume_up_rounded, color: _kPink, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Soundbox Payment',
                style: GoogleFonts.outfit(
                    color: _kText, fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              "Pay via UPI/QR to our Soundbox when the Hero arrives. "
              "You'll hear a voice confirmation on delivery.",
              style: GoogleFonts.outfit(color: _kMuted, fontSize: 11),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildOrderId() => Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text('Order ID: ${_orderId ?? "—"}',
              style: GoogleFonts.outfit(color: _kMuted, fontSize: 11)),
        ),
      );
}

class _Step {
  final String id, label;
  final IconData icon;
  const _Step(this.id, this.label, this.icon);
}
