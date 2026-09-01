// ================================================================
// CustomHotelService — real-time data layer for the Custom Hotel
// Integration System.
// ================================================================
// NEW (CTO mandate — Custom Hotel Integration System). Strictly
// additive and deliberately ISOLATED from the existing seller
// login/menu system (FoodSellerService, sellers/{uid}/menu_items) —
// same "completely isolated" philosophy that file already uses to keep
// itself separate from the Bike Taxi RTDB system, applied here to keep
// this NEW system separate from the OLD menu system per the CTO's
// explicit "do not modify or remove the existing seller menu system"
// instruction.
//
// SCHEMA (Firestore, not RTDB — see note below):
//   custom_hotels/{sellerId}                     (doc, one per seller)
//     - ownerId: string (== sellerId, the seller's Firebase Auth uid)
//     - hotelName: string
//     - phoneNumber: string                       (seller's contact number
//       — see FIX note on ensureHotelDoc below; this was missing entirely
//       until the "custom menu phone not wiring to customer" bug fix)
//     - isOpen: bool                              (global Open/Close)
//     - createdAt / updatedAt: Timestamp
//   custom_hotels/{sellerId}/items/{itemId}       (subcollection)
//     - name: string
//     - price: number
//     - description: string
//     - photoUrl: string (Cloudinary, same pattern as every other
//       image upload in this app — see CloudinaryUploadService)
//     - isVisible: bool                           (per-item toggle)
//     - createdAt / updatedAt: Timestamp
//
// WHY FIRESTORE, NOT REALTIME DATABASE: this app already has
// firebase_database (RTDB) as a dependency, but ONLY for the
// Hero/dispatch live-location subsystem (see main_hero.dart, admin
// dispatch screens) — food_seller_service.dart explicitly keeps itself
// off RTDB. Firestore's own .snapshots() listeners are already this
// app's established real-time mechanism for everything food/seller
// related (see admin_seller_approval_screen.dart's StreamBuilder over
// .snapshots()) and satisfy the CTO's "Real-time listeners (Firebase
// RTDB OR Firestore streams)" requirement exactly as written —
// introducing RTDB for this one feature would be a second real-time
// system for the same domain FoodSellerService already keeps on
// Firestore, for zero benefit.
//
// Every write here touches ONLY the top-level custom_hotels
// collection — zero writes to `sellers` or `sellers/{uid}/menu_items`
// anywhere in this file, so the existing seller flow cannot be
// affected even by a bug in this new one.
import 'package:cloud_firestore/cloud_firestore.dart';
import './firestore_usage_tracking.dart';

class CustomHotelItem {
  const CustomHotelItem({
    required this.id,
    required this.name,
    required this.price,
    required this.description,
    required this.photoUrl,
    required this.isVisible,
  });

  final String id;
  final String name;
  final double price;
  final String description;
  final String photoUrl;
  final bool isVisible;

  factory CustomHotelItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return CustomHotelItem(
      id: doc.id,
      name: (data['name'] as String?)?.trim() ?? '',
      price: (data['price'] as num?)?.toDouble() ?? 0.0,
      description: (data['description'] as String?)?.trim() ?? '',
      photoUrl: (data['photoUrl'] as String?)?.trim() ?? '',
      isVisible: data['isVisible'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'price': price,
        'description': description,
        'photoUrl': photoUrl,
        'isVisible': isVisible,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

class CustomHotelService {
  CustomHotelService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _hotelsRef =>
      _firestore.collection('custom_hotels').withConverter<Map<String, dynamic>>(
            fromFirestore: (snap, _) => snap.data() ?? const {},
            toFirestore: (data, _) => data,
          );

  DocumentReference<Map<String, dynamic>> _hotelDoc(String sellerId) => _hotelsRef.doc(sellerId);
  CollectionReference<Map<String, dynamic>> _itemsRef(String sellerId) => _hotelDoc(sellerId).collection('items');

  // ---- Seller-side (write) ------------------------------------------

  /// Idempotent — safe to call every time the seller opens the builder.
  /// Starts closed (isOpen: false) by design: a brand-new "empty
  /// canvas" shop should never appear open to customers until the
  /// seller has actually added something and explicitly opened it.
  ///
  /// FIX (audit: "Seller custom-menu phone not wiring to customer side"):
  /// this doc never carried a phone number at all — the customer's Call
  /// button (custom_hotel_view_screen.dart) had nothing to read even
  /// though the seller had a real number on file. `sellerPhone` is
  /// resolved by the caller via AuthService.resolveSellerPhone() (same
  /// Firestore-first, Auth-object-fallback pattern as
  /// resolveCustomerPhone/resolveHeroPhone) and written here as
  /// 'phoneNumber'. Also backfills the field on an EXISTING doc that
  /// predates this fix (previously this method did nothing once
  /// `doc.exists`, so sellers who built their menu before this fix
  /// would otherwise stay phoneless forever).
  Future<void> ensureHotelDoc({
    required String sellerId,
    required String hotelName,
    String sellerPhone = '',
  }) async {
    final doc = await _hotelDoc(sellerId).get();
    if (doc.exists) {
      final existingPhone = (doc.data()?['phoneNumber'] as String?)?.trim() ?? '';
      if (existingPhone.isEmpty && sellerPhone.trim().isNotEmpty) {
        await _hotelDoc(sellerId).set(
          {'phoneNumber': sellerPhone.trim(), 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
      }
      return;
    }
    await _hotelDoc(sellerId).set({
      'ownerId': sellerId,
      'hotelName': hotelName,
      'phoneNumber': sellerPhone.trim(),
      'logoUrl': '',
      'isOpen': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update the hotel's profile logo.
  Future<void> updateHotelLogo(String sellerId, String logoUrl) async {
    await _hotelDoc(sellerId).set(
      {'logoUrl': logoUrl, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<void> setHotelOpen({required String sellerId, required bool isOpen}) {
    return _hotelDoc(sellerId).set(
      {'isOpen': isOpen, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<void> saveItem({required String sellerId, required CustomHotelItem item}) {
    final isNew = item.id.isEmpty;
    final ref = isNew ? _itemsRef(sellerId).doc() : _itemsRef(sellerId).doc(item.id);
    if (isNew) {
      // Brand-new item — full write including createdAt (needed for the
      // orderBy('createdAt') sort both stream methods below use).
      return ref.set({...item.toJson(), 'createdAt': FieldValue.serverTimestamp()});
    }
    // Editing an existing item — merge only the mutable fields
    // (item.toJson() itself never includes createdAt), so the item's
    // original createdAt is never touched/overwritten.
    return ref.set(item.toJson(), SetOptions(merge: true));
  }

  /// Separate, minimal write for the item's own On/Off switch — so
  /// flipping visibility never touches (or risks clobbering) the rest
  /// of the item's fields, same "one focused write per toggle" pattern
  /// used everywhere else this app has a live toggle (e.g.
  /// _toggleOnlineStatus / setHotelOpen above).
  Future<void> setItemVisible({required String sellerId, required String itemId, required bool isVisible}) {
    return _itemsRef(sellerId).doc(itemId).set(
      {'isVisible': isVisible, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<void> deleteItem({required String sellerId, required String itemId}) {
    return _itemsRef(sellerId).doc(itemId).delete();
  }

  /// Seller's own management view — ALL items regardless of visibility
  /// (they need to see and re-enable hidden items too).
  Stream<QuerySnapshot<Map<String, dynamic>>> sellerItemsStream(String sellerId) {
    return _itemsRef(sellerId).orderBy('createdAt', descending: true).trackedSnapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> hotelStream(String sellerId) {
    return _hotelDoc(sellerId).trackedSnapshots();
  }

  // ---- Customer-side (read-only) -------------------------------------

  /// Every hotel with isOpen == true, live. A seller flipping the
  /// global toggle off removes their hotel from this stream on the
  /// very next snapshot — no polling, no manual refresh needed by the
  /// customer screen.
  Stream<QuerySnapshot<Map<String, dynamic>>> openHotelsStream() {
    return _hotelsRef.where('isOpen', isEqualTo: true).trackedSnapshots();
  }

  /// Every item with isVisible == true for one hotel, live — same
  /// instant-disappear guarantee per item as openHotelsStream gives per
  /// hotel.
  Stream<QuerySnapshot<Map<String, dynamic>>> visibleItemsStream(String sellerId) {
    return _itemsRef(sellerId).where('isVisible', isEqualTo: true).orderBy('createdAt', descending: true).trackedSnapshots();
  }

  // ---- Ordering & Checkout (CTO mandate — Custom Hotel Ordering &
  // Checkout Pipeline) --------------------------------------------------
  // NEW. Writes the definitive order/receipt record to its OWN isolated
  // `custom_hotel_orders` collection — completely separate from the
  // legacy `orders` / grocery checkout write paths, touching neither.
  // Dispatch (hero broadcast + admin visibility) is handled by calling
  // the EXISTING, unmodified ServiceRequestService.createServiceRequest
  // — the same shared dispatch utility custom_food_order_screen.dart
  // already uses for its own 'custom_food_order' requestType — rather
  // than reinventing hero-broadcast/RTDB logic here. This service file
  // still never imports or touches anything under
  // lib/services/food_seller_service.dart or the legacy order screens.
  CollectionReference<Map<String, dynamic>> get _ordersRef =>
      _firestore.collection('custom_hotel_orders');

  /// Writes the order record. Returns the new custom_hotel_orders doc
  /// ID. The caller (custom_hotel_view_screen.dart) is responsible for
  /// ALSO calling ServiceRequestService().createServiceRequest(...) with
  /// requestType 'custom_hotel_order' right after this, so the order
  /// reaches the seller/admin/hero dispatch pipeline — kept as two
  /// separate calls (not merged into this method) so this service file
  /// has zero dependency on ServiceRequestService/RTDB, staying a pure
  /// Firestore data-layer file like the rest of it.
  Future<String> placeOrder({
    required String sellerId,
    required String hotelName,
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    required String customerId,
    required String customerName,
    required String customerPhone,
    required String deliveryAddress,
  }) async {
    final ref = _ordersRef.doc();
    await ref.set({
      'sellerId': sellerId,
      'hotelName': hotelName,
      'items': items,
      'totalAmount': totalAmount,
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'deliveryAddress': deliveryAddress,
      'status': 'pending',
      'serviceRequestId': null, // filled in by linkServiceRequest() below
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> linkServiceRequest({required String orderId, required String serviceRequestId}) {
    return _ordersRef.doc(orderId).set(
      {'serviceRequestId': serviceRequestId, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }
}
