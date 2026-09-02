// ================================================================
// order_precaution_banner.dart — the hero-side "stay nearby, an order
// is coming" heads-up.
// ================================================================
// Sep 2026 — Nizam: "order accept pandratrhu... precaution messege
// kudukanum... riders anga irunthu vera yengayum move agama wait
// panni... ride delay agurathu kurayum." Fired by
// ServiceRequestService's advanceSellerStage() the moment a seller
// accepts an order — well BEFORE the real dispatch ping (which only
// fires later, at "Book Delivery Partner"). Tapping "I'll Wait" here
// gives this hero first crack at that real ping instead of a cold
// city-wide broadcast — see requestDeliveryBroadcast()'s own comment
// for how that priority works, and why it can never bypass the
// existing atomic first-accept-wins safety.
//
// Modeled directly on stranded_orders_banner.dart's own shape: a
// self-contained StatefulWidget with its own RTDB listener, renders
// nothing on the normal day. Deliberately independent of
// hero_home_screen.dart's own ping/dialog state machine
// (_isShowingServiceDialog, _shownServicePingIds, ringtones) — this is
// informational only, never a claimable job, so it has no business
// touching that already-intricate logic.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/service_request_service.dart';

class _PrecautionItem {
  final String requestId;
  final String requestType;
  final String sellerName;
  final int etaMinutes;
  final int expiresAt;

  const _PrecautionItem({
    required this.requestId,
    required this.requestType,
    required this.sellerName,
    required this.etaMinutes,
    required this.expiresAt,
  });
}

class OrderPrecautionBanner extends StatefulWidget {
  const OrderPrecautionBanner({super.key});

  @override
  State<OrderPrecautionBanner> createState() => _OrderPrecautionBannerState();
}

class _OrderPrecautionBannerState extends State<OrderPrecautionBanner> {
  static const Color _pink = Color(0xFFFF4FA3);
  static const Color _deep = Color(0xFF4A1236);
  static const Color _teal = Color(0xFF11998E);

  StreamSubscription<DatabaseEvent>? _sub;
  final List<_PrecautionItem> _items = [];
  final Set<String> _willing = <String>{};
  final Set<String> _dismissed = <String>{};

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _sub = FirebaseDatabase.instance.ref('hero_precaution_pings/$uid').onValue.listen((event) {
      final raw = event.snapshot.value;
      final next = <_PrecautionItem>[];
      if (raw is Map) {
        final now = DateTime.now().toUtc().millisecondsSinceEpoch;
        raw.forEach((key, value) {
          if (value is! Map) return;
          final expiresAt = (value['expiresAt'] as num?)?.toInt() ?? 0;
          if (expiresAt <= now) {
            // Self-clean, same convention as every other ping node in
            // this app — no reason to make the hero see stale precaution
            // notices for an order that's long since resolved.
            FirebaseDatabase.instance.ref('hero_precaution_pings/$uid/$key').remove();
            return;
          }
          if (_dismissed.contains(key.toString())) return;
          next.add(_PrecautionItem(
            requestId: key.toString(),
            requestType: (value['requestType'] as String?) ?? '',
            sellerName: (value['sellerName'] as String?) ?? 'A seller',
            etaMinutes: (value['etaMinutes'] as num?)?.toInt() ?? 20,
            expiresAt: expiresAt,
          ));
        });
      }
      if (mounted) {
        setState(() {
          _items
            ..clear()
            ..addAll(next);
        });
      }
    }, onError: (Object e) {
      debugPrint('[OrderPrecautionBanner] listener error: $e');
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _markWilling(_PrecautionItem item) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _willing.add(item.requestId));
    try {
      await ServiceRequestService().markWillingForPrecaution(
        requestId: item.requestId,
        heroId: user.uid,
        heroName: user.displayName ?? 'Hero',
        heroPhone: user.phoneNumber ?? '',
      );
    } catch (e) {
      debugPrint('[OrderPrecautionBanner] markWilling failed: $e');
      if (mounted) setState(() => _willing.remove(item.requestId));
    }
  }

  void _dismiss(_PrecautionItem item) {
    setState(() {
      _dismissed.add(item.requestId);
      _items.removeWhere((i) => i.requestId == item.requestId);
    });
  }

  String _typeLabel(String requestType) {
    switch (requestType) {
      case 'catalog_food_order':
      case 'custom_hotel_order':
        return 'food order';
      case 'catalog_grocery_order':
        return 'grocery order';
      default:
        return 'order';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _teal.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _items.take(3).map((item) {
          final isWilling = _willing.contains(item.requestId);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.notifications_active_rounded, color: _teal, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A ${_typeLabel(item.requestType)} from ${item.sellerName} will be ready in ~${item.etaMinutes} min',
                        style: GoogleFonts.outfit(color: _deep, fontWeight: FontWeight.w700, fontSize: 12.5),
                      ),
                      Text(
                        isWilling ? "You're marked as waiting — first alert when it's ready" : 'Stay nearby to get it first',
                        style: GoogleFonts.outfit(color: _teal, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (!isWilling)
                  TextButton(
                    onPressed: () => _markWilling(item),
                    style: TextButton.styleFrom(
                      backgroundColor: _pink,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text("I'll Wait", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
                    onPressed: () => _dismiss(item),
                    tooltip: 'Dismiss',
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
