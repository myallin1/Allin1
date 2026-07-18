// ================================================================
// FoodSellerService — Firestore Food/E-commerce Pipeline
// Allin1 Super App — Completely isolated from Bike Taxi RTDB
// Phase 1: Backend & Data Models
// ================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/food_models.dart';

class FoodSellerService {
  factory FoodSellerService() => _instance;
  FoodSellerService._internal();
  static final FoodSellerService _instance = FoodSellerService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── Collection References ─────────────────────────────────────
  CollectionReference get _sellersRef => _firestore.collection('sellers');
  CollectionReference get _ordersRef => _firestore.collection('food_orders');

  DocumentReference _sellerDocRef(String sellerId) => _sellersRef.doc(sellerId);

  CollectionReference _menuItemsRef(String sellerId) =>
      _sellerDocRef(sellerId).collection('menu_items');

  // ================================================================
  // SELLER OPERATIONS
  // ================================================================

  /// Create a new seller profile in Firestore.
  /// `sellerId` should match the Firebase Auth UID for seller users.
  Future<void> createSellerProfile(SellerModel seller) async {
    try {
      await _sellerDocRef(seller.id).set(seller.toJson());
      debugPrint('[FoodSellerService] Seller profile created: ${seller.id}');
    } catch (e) {
      debugPrint('[FoodSellerService] Failed to create seller profile: $e');
      rethrow;
    }
  }

  /// Update an existing seller's profile fields.
  Future<void> updateSellerProfile(
    String sellerId,
    Map<String, dynamic> updates,
  ) async {
    try {
      updates['updatedAt'] = FieldValue.serverTimestamp();
      await _sellerDocRef(sellerId).update(updates);
      debugPrint('[FoodSellerService] Seller profile updated: $sellerId');
    } catch (e) {
      debugPrint('[FoodSellerService] Failed to update seller profile: $e');
      rethrow;
    }
  }

  /// Fetch a single seller by ID.
  Future<SellerModel?> getSeller(String sellerId) async {
    try {
      final doc = await _sellerDocRef(sellerId).get();
      if (!doc.exists) {
        return null;
      }
      final data = doc.data()! as Map<String, dynamic>;
      return SellerModel.fromJson(data);
    } catch (e) {
      debugPrint('[FoodSellerService] Failed to get seller: $e');
      return null;
    }
  }

  /// Fetch a stream of all active sellers (reactive).
  Stream<List<SellerModel>> listenToActiveSellers() {
    return _sellersRef
        .where('status', isEqualTo: 'active')
        .where('isOpen', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data()! as Map<String, dynamic>;
        data['id'] = doc.id;
        return SellerModel.fromJson(data);
      }).toList();
    });
  }

  /// Fetch sellers by subCategory (e.g., 'biriyani', 'parotta').
  Future<List<SellerModel>> getSellersBySubCategory(String subCategory) async {
    try {
      final snapshot = await _sellersRef
          .where('subCategory', isEqualTo: subCategory)
          .where('status', isEqualTo: 'active')
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data()! as Map<String, dynamic>;
        data['id'] = doc.id;
        return SellerModel.fromJson(data);
      }).toList();
    } catch (e) {
      debugPrint('[FoodSellerService] Failed to get sellers by category: $e');
      return [];
    }
  }

  // ================================================================
  // MENU ITEM OPERATIONS
  // ================================================================

  /// Add a new menu item to a seller's menu.
  Future<void> addMenuItem(String sellerId, MenuItemModel item) async {
    try {
      await _menuItemsRef(sellerId).doc(item.id).set(item.toJson());
      debugPrint(
        '[FoodSellerService] Menu item added: ${item.id} for seller: $sellerId',
      );
    } catch (e) {
      debugPrint('[FoodSellerService] Failed to add menu item: $e');
      rethrow;
    }
  }

  /// Update an existing menu item.
  Future<void> updateMenuItem(
    String sellerId,
    String itemId,
    Map<String, dynamic> updates,
  ) async {
    try {
      updates['updatedAt'] = FieldValue.serverTimestamp();
      await _menuItemsRef(sellerId).doc(itemId).update(updates);
      debugPrint('[FoodSellerService] Menu item updated: $itemId');
    } catch (e) {
      debugPrint('[FoodSellerService] Failed to update menu item: $e');
      rethrow;
    }
  }

  /// Delete a menu item from a seller's menu.
  Future<void> deleteMenuItem(String sellerId, String itemId) async {
    try {
      await _menuItemsRef(sellerId).doc(itemId).delete();
      debugPrint('[FoodSellerService] Menu item deleted: $itemId');
    } catch (e) {
      debugPrint('[FoodSellerService] Failed to delete menu item: $e');
      rethrow;
    }
  }

  /// Batch upsert menu items (useful for seller bulk menu uploads).
  Future<void> batchUpsertMenuItems(
    String sellerId,
    List<MenuItemModel> items,
  ) async {
    try {
      final batch = _firestore.batch();
      for (final item in items) {
        batch.set(
          _menuItemsRef(sellerId).doc(item.id),
          item.toJson(),
          SetOptions(merge: true),
        );
      }
      await batch.commit();
      debugPrint(
        '[FoodSellerService] Batch upserted ${items.length} menu items',
      );
    } catch (e) {
      debugPrint('[FoodSellerService] Batch upsert failed: $e');
      rethrow;
    }
  }

  /// Reactive stream of all menu items for a seller.
  Stream<List<MenuItemModel>> listenToMenuItems(String sellerId) {
    return _menuItemsRef(sellerId).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data()! as Map<String, dynamic>;
        data['id'] = doc.id;
        return MenuItemModel.fromJson(data);
      }).toList();
    });
  }

  /// Fetch available menu items only (isAvailable == true).
  Future<List<MenuItemModel>> getAvailableMenuItems(String sellerId) async {
    try {
      final snapshot = await _menuItemsRef(sellerId)
          .where('isAvailable', isEqualTo: true)
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data()! as Map<String, dynamic>;
        data['id'] = doc.id;
        return MenuItemModel.fromJson(data);
      }).toList();
    } catch (e) {
      debugPrint('[FoodSellerService] Failed to get menu items: $e');
      return [];
    }
  }

  // ================================================================
  // FOOD ORDER OPERATIONS
  // ================================================================

  /// Place a new food order.
  Future<String> placeOrder(FoodOrderModel order) async {
    try {
      final docRef = _ordersRef.doc(order.orderId);
      await docRef.set(order.toJson());
      debugPrint('[FoodSellerService] Order placed: ${order.orderId}');
      return order.orderId;
    } catch (e) {
      debugPrint('[FoodSellerService] Failed to place order: $e');
      rethrow;
    }
  }

  /// Update the status of an order and record the timestamp in the timeline.
  Future<void> updateOrderStatus(
    String orderId,
    String newStatus,
  ) async {
    try {
      final timelineField = 'statusTimeline.$newStatus';
      await _ordersRef.doc(orderId).update({
        'status': newStatus,
        timelineField: FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint(
        '[FoodSellerService] Order $orderId status updated to: $newStatus',
      );
    } catch (e) {
      debugPrint('[FoodSellerService] Failed to update order status: $e');
      rethrow;
    }
  }

  /// Reactive stream of incoming orders for a specific seller.
  Stream<List<FoodOrderModel>> listenToIncomingOrders(String sellerId) {
    return _ordersRef
        .where('sellerId', isEqualTo: sellerId)
        .where('status', whereIn: ['placed', 'accepted', 'preparing', 'ready'])
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data()! as Map<String, dynamic>;
            return FoodOrderModel.fromJson(data);
          }).toList();
        });
  }

  /// Reactive stream of all orders for a specific seller (including completed/cancelled).
  Stream<List<FoodOrderModel>> listenToSellerOrderHistory(String sellerId) {
    return _ordersRef
        .where('sellerId', isEqualTo: sellerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data()! as Map<String, dynamic>;
        return FoodOrderModel.fromJson(data);
      }).toList();
    });
  }

  /// Reactive stream of orders for a specific customer.
  Stream<List<FoodOrderModel>> listenToCustomerOrders(String customerId) {
    return _ordersRef
        .where('customerId', isEqualTo: customerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data()! as Map<String, dynamic>;
        return FoodOrderModel.fromJson(data);
      }).toList();
    });
  }

  /// Fetch a single order by order ID.
  Future<FoodOrderModel?> getOrderById(String orderId) async {
    try {
      final doc = await _ordersRef.doc(orderId).get();
      if (!doc.exists) {
        return null;
      }
      final data = doc.data()! as Map<String, dynamic>;
      return FoodOrderModel.fromJson(data);
    } catch (e) {
      debugPrint('[FoodSellerService] Failed to get order: $e');
      return null;
    }
  }

  /// Fetch active orders for a seller (one-time read).
  Future<List<FoodOrderModel>> getActiveOrders(String sellerId) async {
    try {
      final snapshot = await _ordersRef
          .where('sellerId', isEqualTo: sellerId)
          .where(
            'status',
            whereIn: ['placed', 'accepted', 'preparing', 'ready', 'pickedUp'],
          )
          .orderBy('createdAt', descending: true)
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data()! as Map<String, dynamic>;
        return FoodOrderModel.fromJson(data);
      }).toList();
    } catch (e) {
      debugPrint('[FoodSellerService] Failed to get active orders: $e');
      return [];
    }
  }

  /// Cancel an order (only if status is 'placed').
  Future<bool> cancelOrder(String orderId, {String? reason}) async {
    try {
      final orderDoc = await _ordersRef.doc(orderId).get();
      if (!orderDoc.exists) {
        return false;
      }

      final data = orderDoc.data()! as Map<String, dynamic>;
      if (data['status'] != 'placed') {
        return false;
      }

      await _ordersRef.doc(orderId).update({
        'status': 'cancelled',
        'statusTimeline.cancelled': FieldValue.serverTimestamp(),
        'note': reason,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('[FoodSellerService] Cancel order failed: $e');
      return false;
    }
  }

  // ================================================================
  // CATEGORY DISCOVERY
  // ================================================================

  /// Get all unique subCategories from active sellers.
  Future<List<String>> getAvailableSubCategories() async {
    try {
      final snapshot =
          await _sellersRef.where('status', isEqualTo: 'active').get();
      final categories = <String>{};
      for (final doc in snapshot.docs) {
        final data = doc.data()! as Map<String, dynamic>;
        final subCat = data['subCategory'] as String?;
        if (subCat != null && subCat.isNotEmpty) {
          categories.add(subCat);
        }
      }
      return categories.toList()..sort();
    } catch (e) {
      debugPrint(
        '[FoodSellerService] Failed to get available categories: $e',
      );
      return [];
    }
  }
}
