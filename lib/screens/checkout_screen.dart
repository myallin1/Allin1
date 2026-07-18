import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/hive_cache.dart';

// ============================================================
//  CHECKOUT SCREEN — Allin1 Super App
//  Coder 2.0 | Web-Safe | Zero external packages
// ============================================================

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  // ── Theme Constants ──────────────────────────────────────
  static const Color _bgColor = Color(0xFF0D0D0D);
  static const Color _cardColor = Color(0xFF1A1A1A);
  static const Color _accentOrange = Color(0xFFFF6B35);
  static const Color _accentGold = Color(0xFFFFBB00);
  static const Color _textPrimary = Color(0xFFFFFFFF);
  static const Color _textSecondary = Color(0xFF9E9E9E);
  static const Color _dividerColor = Color(0xFF2C2C2C);
  static const Color _successGreen = Color(0xFF4CAF50);

  // ── Dummy Order Data ─────────────────────────────────────
  final List<Map<String, dynamic>> _orderItems = [
    {
      'store': 'Erode Fresh 🥬',
      'name': 'Farm Fresh Vegetables Combo',
      'qty': 1,
      'price': 149.0,
      'emoji': '🥦',
    },
    {
      'store': 'Erode Fresh 🥬',
      'name': 'Organic Toor Dal (1 kg)',
      'qty': 2,
      'price': 89.0,
      'emoji': '🌾',
    },
    {
      'store': 'Tech Store ⚡',
      'name': 'USB-C Fast Charging Cable',
      'qty': 1,
      'price': 299.0,
      'emoji': '🔌',
    },
  ];

  // ── Bill Calculations ────────────────────────────────────
  double get _subtotal => _orderItems.fold<double>(
        0,
        (sum, item) => sum + (item['price'] as num) * (item['qty'] as num),
      );
  double get _deliveryFee => 29;
  double get _platformFee => 5;
  double get _total => _subtotal + _deliveryFee + _platformFee;

  // ── Payment Processing ───────────────────────────────────
  final int _coinsToUse = 0;

  Future<bool> _canRedeemCoins(int requestedCoins) async {
    if (requestedCoins <= 0) {
      return true;
    }

    final todayKey =
        'redeemed_${DateTime.now().toIso8601String().substring(0, 10)}';
    final redeemedToday = (HiveCache.get(todayKey) as int?) ?? 0;

    if (redeemedToday + requestedCoins > 20) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You can only use up to 20 NJ Coins per day.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    return true;
  }

  void _showPaymentSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentSheet(
        total: _total,
        onPaymentSelected: _processPayment,
      ),
    );
  }

  Future<void> _processPayment(String method) async {
    if (!await _canRedeemCoins(_coinsToUse)) {
      return;
    }

    // 1. Close the bottom sheet
    if (mounted) {
      Navigator.of(context).pop();
    }

    // 2. Show full-screen processing overlay
    _showProcessingDialog(method);

    // 3. Simulate network delay
    await Future<void>.delayed(const Duration(seconds: 2));

    // 4. Dismiss processing dialog
    if (mounted) {
      Navigator.of(context).pop();
    }

    // 5. Update daily coin usage counter
    final todayKey =
        'redeemed_${DateTime.now().toIso8601String().substring(0, 10)}';
    final redeemedToday = (HiveCache.get(todayKey) as int?) ?? 0;
    HiveCache.put(todayKey, redeemedToday + _coinsToUse);

    // 6. Show success then navigate
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (mounted) {
      _showSuccessAndNavigate(method);
    }
  }

  void _showProcessingDialog(String method) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: _cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 40,
              horizontal: 32,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(_accentOrange),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Processing Payment...',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'via $method',
                  style: const TextStyle(
                    color: _textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _bgColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_outline,
                        color: _accentGold,
                        size: 14,
                      ),
                      SizedBox(width: 6),
                      Text(
                        '256-bit SSL Secured',
                        style: TextStyle(
                          color: _accentGold,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSuccessAndNavigate(String method) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Animated Success Icon ──
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _successGreen.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: _successGreen,
                  size: 52,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Payment Successful!',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '₹${_total.toStringAsFixed(2)} paid via $method',
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Order ID: #ALN${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
                style: const TextStyle(
                  color: _accentOrange,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Clean navigation stack → Dashboard
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/dashboard',
                      (route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Track My Order →',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── BUILD ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Checkout',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _accentOrange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _accentOrange.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '${_orderItems.length} items',
                  style: const TextStyle(
                    color: _accentOrange,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),

      // ── Sticky Bottom Bar ─────────────────────────────────
      bottomNavigationBar: _buildStickyBottomBar(),

      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Delivery Address ──
            _buildSectionHeader('📍 Delivery Address'),
            const SizedBox(height: 10),
            _buildAddressCard(),
            const SizedBox(height: 24),

            // ── Order Items ──
            _buildSectionHeader('🛒 Order Summary'),
            const SizedBox(height: 10),
            _buildOrderItemsList(),
            const SizedBox(height: 24),

            // ── Bill Details ──
            _buildSectionHeader('🧾 Bill Details'),
            const SizedBox(height: 10),
            _buildBillDetailsCard(),
            const SizedBox(height: 16),

            // ── Safety Badge ──
            _buildSafetyBadge(),
          ],
        ),
      ),
    );
  }

  // ── WIDGETS ──────────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: _textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildAddressCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _accentOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.location_on_rounded,
              color: _accentOrange,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Home',
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '42, Perundurai Road, Erode, Tamil Nadu - 638011',
                  style: TextStyle(color: _textSecondary, fontSize: 12),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: _textSecondary,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItemsList() {
    return DecoratedBox(
      decoration: _cardDecoration(),
      child: Column(
        children: _orderItems.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Item Emoji Icon
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _bgColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          item['emoji'] as String,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Item Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['store'] as String,
                            style: const TextStyle(
                              color: _accentOrange,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item['name'] as String,
                            style: const TextStyle(
                              color: _textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Qty: ${item['qty'] as num}',
                            style: const TextStyle(
                              color: _textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Price
                    Text(
                      '₹${((item['price'] as num) * (item['qty'] as num)).toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (i < _orderItems.length - 1)
                const Divider(
                  color: _dividerColor,
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBillDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          _buildBillRow(
            'Subtotal',
            '₹${_subtotal.toStringAsFixed(2)}',
            false,
          ),
          const SizedBox(height: 12),
          _buildBillRow(
            'Delivery Fee',
            '₹${_deliveryFee.toStringAsFixed(2)}',
            false,
          ),
          const SizedBox(height: 12),
          _buildBillRow(
            'Platform Fee',
            '₹${_platformFee.toStringAsFixed(2)}',
            false,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(color: _dividerColor),
          ),
          _buildBillRow(
            'Total Amount',
            '₹${_total.toStringAsFixed(2)}',
            true,
          ),
        ],
      ),
    );
  }

  Widget _buildBillRow(String label, String value, bool isTotal) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isTotal ? _textPrimary : _textSecondary,
            fontSize: isTotal ? 16 : 14,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: isTotal ? _accentGold : _textPrimary,
            fontSize: isTotal ? 18 : 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildSafetyBadge() {
    return const Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_user_outlined,
            color: _textSecondary,
            size: 14,
          ),
          SizedBox(width: 6),
          Text(
            '100% Safe & Secure Payments | Powered by Allin1',
            style: TextStyle(color: _textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildStickyBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: const BoxDecoration(
        color: _cardColor,
        border: Border(
          top: BorderSide(color: _dividerColor),
        ),
      ),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'To Pay',
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 12,
                ),
              ),
              Text(
                '₹${_total.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: _showPaymentSheet,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Proceed to Pay  →',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _dividerColor),
      );
}

// ============================================================
//  PAYMENT BOTTOM SHEET — Separated Widget (Clean Code)
// ============================================================

class _PaymentSheet extends StatefulWidget {
  final double total;
  final void Function(String method) onPaymentSelected;

  const _PaymentSheet({
    required this.total,
    required this.onPaymentSelected,
  });

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DoubleProperty('total', total))
      ..add(
        ObjectFlagProperty<void Function(String method)>.has(
          'onPaymentSelected',
          onPaymentSelected,
        ),
      );
  }
}

class _PaymentSheetState extends State<_PaymentSheet> {
  static const Color _bgColor = Color(0xFF141414);
  static const Color _cardColor = Color(0xFF1E1E1E);
  static const Color _accentOrange = Color(0xFFFF6B35);
  static const Color _accentGold = Color(0xFFFFBB00);
  static const Color _textPrimary = Color(0xFFFFFFFF);
  static const Color _textSecondary = Color(0xFF9E9E9E);
  static const Color _dividerColor = Color(0xFF2A2A2A);

  String? _selectedMethod;
  bool _cardExpanded = false;

  final _cardController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();

  @override
  void dispose() {
    _cardController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Handle Bar ──
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 20),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _dividerColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),

              // ── Header ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose Payment',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.lock_rounded,
                            color: _accentGold,
                            size: 12,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Secure Checkout',
                            style: TextStyle(
                              color: _accentGold,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _accentOrange.withValues(alpha: 0.2),
                          _accentGold.withValues(alpha: 0.15),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _accentOrange.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      '₹${widget.total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: _accentGold,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── UPI Section ──
              _buildSectionLabel('⚡ UPI — Instant Payment'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildUpiTile(
                      label: 'Google Pay',
                      icon: '🟢',
                      value: 'Google Pay',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildUpiTile(
                      label: 'PhonePe',
                      icon: '🟣',
                      value: 'PhonePe',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildUpiTile(
                      label: 'Paytm',
                      icon: '🔵',
                      value: 'Paytm UPI',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Card Section ──
              _buildSectionLabel('💳 Credit / Debit Card'),
              const SizedBox(height: 10),
              _buildCardSection(),
              const SizedBox(height: 20),

              // ── COD Section ──
              _buildSectionLabel('💵 Other Options'),
              const SizedBox(height: 10),
              _buildPaymentTile(
                icon: Icons.delivery_dining_rounded,
                iconColor: const Color(0xFF4CAF50),
                title: 'Cash on Delivery',
                subtitle: 'Pay when your order arrives',
                value: 'Cash on Delivery',
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Available',
                    style: TextStyle(
                      color: Color(0xFF4CAF50),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // ── Pay Button ──
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selectedMethod == null
                      ? null
                      : () => widget.onPaymentSelected(_selectedMethod!),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentOrange,
                    disabledBackgroundColor:
                        _accentOrange.withValues(alpha: 0.3),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _selectedMethod == null
                        ? 'Select a Payment Method'
                        : 'Pay ₹${widget.total.toStringAsFixed(2)} via $_selectedMethod',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sheet Sub-Widgets ─────────────────────────────────────

  Widget _buildSectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          color: _textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      );

  Widget _buildUpiTile({
    required String label,
    required String icon,
    required String value,
  }) {
    final isSelected = _selectedMethod == value;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedMethod = value;
        _cardExpanded = false;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color:
              isSelected ? _accentOrange.withValues(alpha: 0.12) : _cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? _accentOrange : const Color(0xFF2A2A2A),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 26)),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? _textPrimary : _textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardSection() {
    final isSelected = _selectedMethod == 'Credit/Debit Card';
    return GestureDetector(
      onTap: () => setState(() {
        _selectedMethod = 'Credit/Debit Card';
        _cardExpanded = true;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color:
              isSelected ? _accentOrange.withValues(alpha: 0.08) : _cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? _accentOrange : const Color(0xFF2A2A2A),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.credit_card_rounded,
                    color: isSelected ? _accentOrange : _textSecondary,
                    size: 24,
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Credit / Debit Card',
                          style: TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'Visa, Mastercard, RuPay',
                          style: TextStyle(
                            color: _textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      _miniCardBadge('VISA'),
                      const SizedBox(width: 4),
                      _miniCardBadge('MC'),
                    ],
                  ),
                ],
              ),
            ),
            // ── Expanded Card Form ──
            if (_cardExpanded && isSelected)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    _buildCardField(
                      controller: _cardController,
                      hint: 'Card Number',
                      icon: Icons.dialpad_rounded,
                      keyboard: TextInputType.number,
                      maxLength: 19,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildCardField(
                            controller: _expiryController,
                            hint: 'MM / YY',
                            icon: Icons.date_range_rounded,
                            keyboard: TextInputType.number,
                            maxLength: 5,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildCardField(
                            controller: _cvvController,
                            hint: 'CVV',
                            icon: Icons.lock_rounded,
                            keyboard: TextInputType.number,
                            maxLength: 3,
                            obscure: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required TextInputType keyboard,
    required int maxLength,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      obscureText: obscure,
      maxLength: maxLength,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF555555), fontSize: 13),
        prefixIcon: Icon(icon, color: const Color(0xFF555555), size: 18),
        filled: true,
        fillColor: const Color(0xFF0D0D0D),
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: Color(0xFFFF6B35),
            width: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String value,
    Widget? trailing,
  }) {
    final isSelected = _selectedMethod == value;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedMethod = value;
        _cardExpanded = false;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              isSelected ? _accentOrange.withValues(alpha: 0.08) : _cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? _accentOrange : const Color(0xFF2A2A2A),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing,
            const SizedBox(width: 8),
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: isSelected ? _accentOrange : const Color(0xFF3A3A3A),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniCardBadge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
}
