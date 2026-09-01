// ================================================================
// admin_gift_coupons_screen.dart — Gift Coupon management.
//
// Reached from Overview > MANAGE on super_admin_home_screen.dart.
//
// This is step 2 of the scratch-card flow (see
// lib/models/gift_coupon_model.dart): a paid service auto-mints a
// LOCKED coupon, and this screen is where an admin decides what's
// actually inside it before the customer's unlock timer runs out.
//
// Deliberately NOT bolted onto admin_service_requests_screen.dart (an
// earlier draft put a "Generate Coupon" button on each completed
// electronics card): coupons are now minted server-side for EVERY paid
// service type, so the admin's job is no longer "issue one against
// this order" but "work a queue of coupons waiting for a gift" — which
// wants its own screen with its own status tabs.
// ================================================================
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/gift_coupon_model.dart';
import '../../services/gift_coupon_service.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _green = Color(0xFF00C853);
const Color _pink = Color(0xFFFF4FA3);
const Color _gold = Color(0xFFFFC107);
const Color _border = Color(0x1AFFFFFF);

class AdminGiftCouponsScreen extends StatefulWidget {
  const AdminGiftCouponsScreen({super.key});

  @override
  State<AdminGiftCouponsScreen> createState() => _AdminGiftCouponsScreenState();
}

class _AdminGiftCouponsScreenState extends State<AdminGiftCouponsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final GiftCouponService _service = GiftCouponService();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        iconTheme: const IconThemeData(color: _text),
        title: Text(
          'Gift Coupons',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _gold,
          labelColor: _gold,
          unselectedLabelColor: _muted,
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 12.5),
          tabs: const [
            Tab(text: 'NEEDS GIFT'),
            Tab(text: 'ARMED'),
            Tab(text: 'OPENED'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _CouponList(
            service: _service,
            status: GiftCouponStatus.awaitingGift,
            emptyMessage:
                'No coupons waiting for a gift.\nOne is created automatically each time a customer pays for a service.',
          ),
          _CouponList(
            service: _service,
            status: GiftCouponStatus.ready,
            emptyMessage:
                'No armed coupons.\nSet a gift on a "Needs Gift" coupon and it moves here until the customer scratches it.',
          ),
          _CouponList(
            service: _service,
            status: GiftCouponStatus.scratched,
            emptyMessage: 'No coupons have been scratched open yet.',
          ),
        ],
      ),
    );
  }
}

class _CouponList extends StatelessWidget {
  const _CouponList({
    required this.service,
    required this.status,
    required this.emptyMessage,
  });

  final GiftCouponService service;
  final String status;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GiftCouponModel>>(
      stream: service.streamCouponsByStatus(status),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load coupons.\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 12.5),
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _gold));
        }
        final coupons = snapshot.data ?? const [];
        if (coupons.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 13, height: 1.5),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: coupons.length,
          itemBuilder: (context, i) => _CouponCard(
            coupon: coupons[i],
            service: service,
          ),
        );
      },
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<GiftCouponService>('service', service));
    properties.add(StringProperty('status', status));
    properties.add(StringProperty('emptyMessage', emptyMessage));
  }
}

class _CouponCard extends StatelessWidget {
  const _CouponCard({required this.coupon, required this.service});

  final GiftCouponModel coupon;
  final GiftCouponService service;

  String _unlockLabel() {
    if (coupon.status == GiftCouponStatus.scratched) {
      return 'Opened by customer';
    }
    if (coupon.isUnlocked) return 'Unlocked — customer can scratch now';
    final remaining = coupon.timeUntilUnlock;
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    return hours > 0
        ? 'Unlocks in ${hours}h ${minutes}m'
        : 'Unlocks in ${minutes}m';
  }

  Future<void> _openSetGiftSheet(BuildContext context) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SetGiftSheet(coupon: coupon, service: service),
    );
    if ((saved ?? false) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gift set — the card is armed.')),
      );
    }
  }

  Future<void> _markHandedOver(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _card,
        title: Text('Mark as handed over?',
            style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800),),
        content: Text(
          'Confirm that "${coupon.giftLabel}" has been given to '
          '${coupon.customerName.isNotEmpty ? coupon.customerName : 'the customer'}. '
          'The coupon will close and disappear from their Rewards page.',
          style: const TextStyle(color: _muted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: _muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _green),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await service.markItemClaimed(coupon.id);
    } catch (e) {
      debugPrint('[AdminGiftCoupons] markItemClaimed failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this coupon.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsGift = coupon.status == GiftCouponStatus.awaitingGift;
    // An item gift that's been revealed still needs a human to hand the
    // thing over; a discount closes itself when it's spent on a bill.
    final needsHandover = coupon.status == GiftCouponStatus.scratched &&
        coupon.giftType == GiftCouponType.item;

    return Card(
      color: _card,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (needsGift ? _pink : _gold).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    needsGift
                        ? 'NEEDS GIFT'
                        : (coupon.giftDescription.isNotEmpty
                            ? coupon.giftDescription.toUpperCase()
                            : 'ARMED'),
                    style: TextStyle(
                      color: needsGift ? _pink : _gold,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _unlockLabel(),
                  style: const TextStyle(color: _muted, fontSize: 10.5),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              coupon.customerName.isNotEmpty ? coupon.customerName : 'Customer',
              style: const TextStyle(
                  color: _text, fontWeight: FontWeight.w700, fontSize: 14,),
            ),
            if (coupon.sourceSummary.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Earned from: ${coupon.sourceSummary}',
                style: const TextStyle(color: _muted, fontSize: 11.5),
              ),
            ],
            if (needsGift) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: _gold),
                  onPressed: () => unawaited(_openSetGiftSheet(context)),
                  icon: const Icon(Icons.card_giftcard_rounded,
                      size: 18, color: Colors.black87,),
                  label: const Text('Set the Gift',
                      style: TextStyle(
                          color: Colors.black87, fontWeight: FontWeight.bold,),),
                ),
              ),
            ] else if (needsHandover) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _green,
                    side: const BorderSide(color: _green),
                  ),
                  onPressed: () => unawaited(_markHandedOver(context)),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: const Text('Mark as Handed Over'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<GiftCouponModel>('coupon', coupon));
    properties.add(DiagnosticsProperty<GiftCouponService>('service', service));
  }
}

// ================================================================
// "What's inside?" — the admin picks either a ₹ discount usable on a
// future bill, or a gift item collected in person, and optionally
// shortens/extends the customer's unlock timer.
// ================================================================
class _SetGiftSheet extends StatefulWidget {
  const _SetGiftSheet({required this.coupon, required this.service});

  final GiftCouponModel coupon;
  final GiftCouponService service;

  @override
  State<_SetGiftSheet> createState() => _SetGiftSheetState();
}

class _SetGiftSheetState extends State<_SetGiftSheet> {
  bool _isDiscount = true;
  final TextEditingController _valueCtrl = TextEditingController();
  final TextEditingController _labelCtrl = TextEditingController();
  int? _unlockHoursOverride;
  bool _saving = false;

  @override
  void dispose() {
    _valueCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = num.tryParse(_valueCtrl.text.trim());
    final label = _labelCtrl.text.trim();
    if (_isDiscount && (value == null || value <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a discount amount greater than 0.')),
      );
      return;
    }
    if (!_isDiscount && label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Describe the gift the customer will collect.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.service.setGift(
        couponId: widget.coupon.id,
        discountValue: _isDiscount ? value : null,
        giftLabel: _isDiscount ? null : label,
        unlockAt: _unlockHoursOverride == null
            ? null
            : DateTime.now().add(Duration(hours: _unlockHoursOverride!)),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('[AdminGiftCoupons] setGift failed: $e');
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not set the gift. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("What's inside the card?",
                  style: GoogleFonts.outfit(
                      color: _text, fontSize: 18, fontWeight: FontWeight.w800,),),
              const SizedBox(height: 4),
              Text(
                'For ${widget.coupon.customerName.isNotEmpty ? widget.coupon.customerName : 'this customer'}'
                '${widget.coupon.sourceSummary.isNotEmpty ? ' — earned from ${widget.coupon.sourceSummary}' : ''}',
                style: const TextStyle(color: _muted, fontSize: 12.5),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _typeButton(
                      label: '₹ Discount',
                      subtitle: 'Used on a future bill',
                      selected: _isDiscount,
                      onTap: () => setState(() => _isDiscount = true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _typeButton(
                      label: 'Gift Item',
                      subtitle: 'Collected in person',
                      selected: !_isDiscount,
                      onTap: () => setState(() => _isDiscount = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_isDiscount)
                TextField(
                  controller: _valueCtrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: _text),
                  decoration: const InputDecoration(
                    labelText: 'Discount amount',
                    labelStyle: TextStyle(color: _muted),
                    prefixText: '₹ ',
                    prefixStyle: TextStyle(color: _text),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: _border),),
                  ),
                )
              else
                TextField(
                  controller: _labelCtrl,
                  autofocus: true,
                  maxLength: 60,
                  style: const TextStyle(color: _text),
                  decoration: const InputDecoration(
                    labelText: 'Gift the customer will collect',
                    hintText: 'e.g. Free mobile cover',
                    labelStyle: TextStyle(color: _muted),
                    hintStyle: TextStyle(color: _muted),
                    counterStyle: TextStyle(color: _muted),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: _border),),
                  ),
                ),
              const SizedBox(height: 14),
              Text('WHEN CAN THEY SCRATCH IT?',
                  style: TextStyle(
                    color: _muted.withValues(alpha: 0.9),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _unlockChip(label: 'Keep timer', hours: null),
                  _unlockChip(label: 'Now', hours: 0),
                  _unlockChip(label: 'In 1h', hours: 1),
                  _unlockChip(label: 'In 24h', hours: 24),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _saving ? null : () => unawaited(_save()),
                  child: _saving
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black87,),)
                      : const Text('Arm this card',
                          style: TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,),),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeButton({
    required String label,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _gold.withValues(alpha: 0.16) : _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? _gold : _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: GoogleFonts.outfit(
                  color: selected ? _gold : _text,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(color: _muted, fontSize: 11),),
          ],
        ),
      ),
    );
  }

  Widget _unlockChip({required String label, required int? hours}) {
    final selected = _unlockHoursOverride == hours;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _unlockHoursOverride = hours),
      backgroundColor: _card,
      selectedColor: _gold.withValues(alpha: 0.2),
      side: BorderSide(color: selected ? _gold : _border),
      labelStyle: TextStyle(
        color: selected ? _gold : _muted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
