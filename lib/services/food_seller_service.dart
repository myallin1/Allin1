// ================================================================
// FoodSellerService — Firestore Food/E-commerce Pipeline
// Allin1 Super App — Completely isolated from Bike Taxi RTDB
// Phase 1: Backend & Data Models
// ================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/food_models.dart';
import 'affiliate_service.dart';
import 'db_usage_tracker.dart';
import './firestore_usage_tracking.dart';

class FoodSellerService {
  factory FoodSellerService() => _instance;
  FoodSellerService._internal();
  static final FoodSellerService _instance = FoodSellerService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── Collection References ─────────────────────────────────────
  CollectionReference get _sellersRef => _firestore.collection('sellers');

  DocumentReference _sellerDocRef(String sellerId) =>
      _sellersRef.doc(sellerId);

  CollectionReference _menuItemsRef(String sellerId) =>
      _sellerDocRef(sellerId).collection('menu_items');

  // ================================================================
  // SELLER OPERATIONS
  // ================================================================

  /// Create a new seller profile in Firestore.
  /// [sellerId] should match the Firebase Auth UID for seller users.
  Future<void> createSellerProfile(SellerModel seller) async {
    try {
      await _sellerDocRef(seller.id).set(seller.toJson());
      debugPrint('[FoodSellerService] Seller profile created: ${seller.id}');
      // NEW (Aug 12 2026 — Affiliate QR Generator): covers ALL seller
      // onboarding flows (food/grocery/electronics) since they all call
      // this one method — increments the referring code's signup
      // counter if this seller came in from an affiliate link.
      unawaited(AffiliateService.instance.completeConversion(
        uid: seller.id,
        name: seller.name,
        phone: seller.phone,
        email: _auth.currentUser?.email ?? '',
        city: seller.city,
        role: 'seller',
      ));
    } catch (e) {
      debugPrint('[FoodSellerService] Failed to create seller profile: $e');
      rethrow;
    }
  }

  /// Update an existing seller's profile fields.
  Future<void> updateSellerProfile(
      String sellerId, Map<String, dynamic> updates,) async {
    try {
      updates['updatedAt'] = FieldValue.serverTimestamp();
      await _sellerDocRef(sellerId).update(updates);
      DbUsageTracker.instance.recordWrite(1, 'seller_profile', 'profile_update');
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
      if (!doc.exists) return null;
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
        // FIX (post-fix audit — silent-data-loss risk): orderBy added
        // alongside the .limit(50) cap below — without it, once there
        // are 50+ matching sellers platform-wide, Firestore's limit()
        // picks an unspecified subset, so a seller who just went active/
        // open could be permanently excluded from this list rather than
        // simply appearing at the end of it. REQUIRES a composite index
        // (status ASC, isOpen ASC, createdAt DESC) on `sellers` — added
        // to firestore.indexes.json; must be deployed
        // (`firebase deploy --only firestore:indexes`) or this throws
        // failed-precondition.
        .orderBy('createdAt', descending: true)
        // FIX (zero-cost Firestore audit): was fully uncapped across
        // every active seller platform-wide. Matches the cap
        // category_gateway_service.dart's loadCategoryData() already
        // uses for the same kind of seller-listing query.
        .limit(50)
        .trackedSnapshots()
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
          '[FoodSellerService] Menu item added: ${item.id} for seller: $sellerId',);
    } catch (e) {
      debugPrint('[FoodSellerService] Failed to add menu item: $e');
      rethrow;
    }
  }

  /// Update an existing menu item.
  Future<void> updateMenuItem(
      String sellerId, String itemId, Map<String, dynamic> updates,) async {
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
      String sellerId, List<MenuItemModel> items,) async {
    try {
      final batch = _firestore.batch();
      for (final item in items) {
        batch.set(_menuItemsRef(sellerId).doc(item.id), item.toJson(),
            SetOptions(merge: true),);
      }
      await batch.commit();
      debugPrint(
          '[FoodSellerService] Batch upserted ${items.length} menu items',);
    } catch (e) {
      debugPrint('[FoodSellerService] Batch upsert failed: $e');
      rethrow;
    }
  }

  /// Reactive stream of all menu items for a seller.
  Stream<List<MenuItemModel>> listenToMenuItems(String sellerId) {
    return _menuItemsRef(sellerId).trackedSnapshots().map((snapshot) {
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
  // CATEGORY DISCOVERY
  // ================================================================

  /// Get all unique subCategories from active sellers.
  Future<List<String>> getAvailableSubCategories() async {
    try {
      final snapshot = await _sellersRef
          .where('status', isEqualTo: 'active')
          .get();
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
          '[FoodSellerService] Failed to get available categories: $e',);
      return [];
    }
  }
}
