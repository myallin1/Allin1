// ================================================================
// catalog_order_service.dart — places a catalog order (grocery, and
// any future department) using the stock HOLD system (Sep 2026).
// ================================================================
// STRUCTURAL GUARANTEE: a customer can never pay for an out-of-stock
// item. Stock is decremented at HOLD time — the moment checkout
// starts, BEFORE any payment method is even shown — not after payment
// succeeds. If the hold fails, the caller's checkout screen must never
// open at all (see grocery_seller_detail_screen.dart's _checkout()),
// so no payment method, including PhonePe, is ever presented for a
// cart that can't be fulfilled.
//
// Full flow, in order:
//   1. holdStock()    — BEFORE opening the checkout screen. Reserves
//      the items (atomic, all-or-nothing, server-side — see
//      functions/holdMenuItemStock.ts) and decrements stock
//      immediately. Throws StockUnavailableException if anything is
//      short; the caller must not proceed to payment on that path.
//   2. Customer picks a payment method and completes (or backs out of)
//      the checkout screen.
//   3a. If completed: confirmAndCreateOrder() — makes the hold
//       permanent and creates the actual service_requests order,
//       using the SAME server-resolved prices the hold locked in.
//   3b. If backed out: releaseHold() — restores the stock immediately
//       instead of leaving it locked for the full hold TTL.
// A scheduled Cloud Function sweeps and releases anything abandoned
// without an explicit 3a/3b ever happening (app killed mid-payment,
// network drop) — see functions/releaseExpiredStockHoldsScheduled.ts.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'service_request_service.dart';

class CatalogOrderItem {
  final String itemId;
  final int quantity;
  const CatalogOrderItem({required this.itemId, required this.quantity});
}

/// Thrown when the gateway function rejects a hold — always because one
/// or more items ran out of stock (or the customer already has too many
/// pending checkouts open) between browsing and checkout.
class StockUnavailableException implements Exception {
  final String message;
  const StockUnavailableException(this.message);
  @override
  String toString() => message;
}

/// What holdStock() returns — carried by the caller through the entire
/// checkout screen and handed back to confirmAndCreateOrder()/
/// releaseHold() once the customer finishes or backs out.
class StockHoldResult {
  final String holdId;
  final List<Map<String, dynamic>> itemsDetail; // server-resolved name/price/quantity/total
  final double subtotal;
  const StockHoldResult({
    required this.holdId,
    required this.itemsDetail,
    required this.subtotal,
  });
}

class CatalogOrderService {
  CatalogOrderService._();
  static final CatalogOrderService instance = CatalogOrderService._();

  /// Phase 1 — call this the INSTANT checkout starts, before showing
  /// any payment option. See this file's header for why the ordering
  /// matters: this is the call that makes "pay for an out-of-stock
  /// item" structurally impossible, not just unlikely.
  Future<StockHoldResult> holdStock({
    required String sellerId,
    required List<CatalogOrderItem> items,
  }) async {
    final callable = FirebaseFunctions.instance.httpsCallable('holdMenuItemStock');
    late final Map<String, dynamic> result;
    try {
      final response = await callable.call<Map<String, dynamic>>({
        'sellerId': sellerId,
        'items': items.map((i) => {'itemId': i.itemId, 'quantity': i.quantity}).toList(),
      });
      result = response.data;
    } on FirebaseFunctionsException catch (e) {
      // 'failed-precondition' (out of stock) and 'resource-exhausted'
      // (too many open holds) are both holdMenuItemStock.ts's own
      // customer-readable messages — surface as-is.
      throw StockUnavailableException(e.message ?? 'Some items are out of stock.');
    }

    final holdId = result['holdId'] as String;
    final resolvedItems = (result['items'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final subtotal = (result['subtotal'] as num).toDouble();

    final itemsDetail = resolvedItems.map((it) {
      final qty = it['quantity'] as num;
      final price = it['price'] as num;
      return {
        'itemId': it['itemId'],
        'name': it['name'],
        'price': price,
        'quantity': qty,
        'total': price * qty,
      };
    }).toList();

    return StockHoldResult(holdId: holdId, itemsDetail: itemsDetail, subtotal: subtotal);
  }

  /// Phase 3a — call once the customer has completed checkout (any
  /// payment method, COD included). Makes the hold's stock decrement
  /// permanent and creates the real order, using the price/quantity
  /// [hold] already locked in — never re-reads live prices, so a seller
  /// changing a price mid-checkout can never retroactively change what
  /// this specific customer pays for this specific order.
  Future<String> confirmAndCreateOrder({
    required StockHoldResult hold,
    required String sellerId,
    required String sellerName,
    required String department, // 'grocery' for now
    required String customerId,
    required String customerName,
    required String customerPhone,
    required String deliveryAddress,
    double? deliveryLat,
    double? deliveryLng,
    String? paymentMethod,
    /// Set when [paymentMethod] is 'phonepe_upi' — FoodCheckoutScreen
    /// reserves this id and creates the PhonePe payment record against
    /// it BEFORE this order doc exists (see phonepe_payment_service
    /// .dart's confirmLink() doc comment). Passing it through here
    /// keeps the payment and the order doc joined on the same id, the
    /// same way seller_detail_screen.dart's food flow already does.
    String? preGeneratedRequestId,
  }) async {
    final requestId = await ServiceRequestService().createServiceRequest(
      requestType: 'catalog_grocery_order',
      preGeneratedRequestId: preGeneratedRequestId,
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      deferBroadcast: true, // seller packs the order before a hero is pinged, same as food
      details: {
        'sellerId': sellerId,
        'sellerName': sellerName,
        'department': department,
        'items': hold.itemsDetail,
        'subtotal': hold.subtotal,
        'deliveryAddress': deliveryAddress,
        if (deliveryLat != null) 'deliveryLat': deliveryLat,
        if (deliveryLng != null) 'deliveryLng': deliveryLng,
        if (paymentMethod != null) 'paymentMethod': paymentMethod,
      },
    );

    // The order now genuinely exists — make the hold's decrement
    // permanent and credit the real app-sold counter. If THIS call
    // fails (network blip right after the order write succeeded), the
    // hold is left 'held' with a real order already pointing at its
    // stock — worst case the scheduled sweep restores stock that's
    // already correctly gone, a seller-visible stock-count anomaly, not
    // a customer-facing failure; the order itself is unaffected either
    // way, which is the guarantee that actually matters here.
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('confirmMenuItemStockHold');
      await callable.call<Map<String, dynamic>>({
        'holdId': hold.holdId,
        'requestId': requestId,
      });
    } catch (e) {
      debugPrint('[CatalogOrderService] confirmMenuItemStockHold failed (non-fatal, order already created): $e');
    }

    return requestId;
  }

  /// Phase 3b — call when the customer backs out of checkout without
  /// completing any payment method (FoodCheckoutScreen returned null).
  /// Best-effort: if this fails, the scheduled sweep restores the stock
  /// within HOLD_TTL_MINUTES regardless — this call only exists to make
  /// the item available to OTHER customers sooner than that.
  Future<void> releaseHold(String holdId) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('releaseMenuItemStockHold');
      await callable.call<Map<String, dynamic>>({'holdId': holdId});
    } catch (e) {
      debugPrint('[CatalogOrderService] releaseMenuItemStockHold failed (non-fatal, scheduled sweep will catch it): $e');
    }
  }
}
