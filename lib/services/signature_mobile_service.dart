// ================================================================
// signature_mobile_service.dart — NJ Tech Signature Mobiles E-Commerce Engine
// ================================================================
// Powers catalog browsing, inventory search, instant order placement,
// delivery tracking, and post-delivery customer feedback.
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/signature_mobile_models.dart';
import 'service_request_service.dart';

class SignatureMobileService {
  SignatureMobileService._();
  static final SignatureMobileService instance = SignatureMobileService._();

  static const String productCollection = 'signature_mobile_products';
  static const String orderCollection = 'signature_orders';

  CollectionReference<Map<String, dynamic>> get _productsRef =>
      FirebaseFirestore.instance.collection(productCollection);

  CollectionReference<Map<String, dynamic>> get _ordersRef =>
      FirebaseFirestore.instance.collection(orderCollection);

  /// Curated default catalog for instant offline/zero-wait browsing
  static final List<SignatureProduct> kCuratedSignatureCatalog = [
    // ── NEW MOBILES ───────────────────────────────────────────────
    const SignatureProduct(
      id: 'sig_new_ip15_128',
      name: 'Apple iPhone 15',
      brand: 'Apple',
      category: SignatureCategory.newMobile,
      price: 64999,
      mrp: 69900,
      condition: 'Brand New (Sealed)',
      storage: '128GB',
      ram: '6GB',
      color: 'Black / Blue / Pink',
      warrantyText: '1 Year Apple Official Warranty',
      imageUrl: 'https://res.cloudinary.com/qx5zvm4w/image/upload/v1724000000/mobiles/iphone_15_sealed.jpg',
      highlights: ['Dynamic Island', '48MP Main Camera', 'USB-C Charging', 'A16 Bionic'],
      rating: 4.9,
      reviewCount: 42,
    ),
    const SignatureProduct(
      id: 'sig_new_s24_256',
      name: 'Samsung Galaxy S24 5G',
      brand: 'Samsung',
      category: SignatureCategory.newMobile,
      price: 74999,
      mrp: 79999,
      condition: 'Brand New (Sealed)',
      storage: '256GB',
      ram: '8GB',
      color: 'Onyx Black / Cobalt Violet',
      warrantyText: '1 Year Samsung India Warranty',
      imageUrl: 'https://res.cloudinary.com/qx5zvm4w/image/upload/v1724000000/mobiles/samsung_s24.jpg',
      highlights: ['Galaxy AI Features', '120Hz Dynamic AMOLED', '50MP Triple Camera'],
      rating: 4.8,
      reviewCount: 28,
    ),
    const SignatureProduct(
      id: 'sig_new_op12r_256',
      name: 'OnePlus 12R 5G',
      brand: 'OnePlus',
      category: SignatureCategory.newMobile,
      price: 39999,
      mrp: 42999,
      condition: 'Brand New (Sealed)',
      storage: '256GB',
      ram: '16GB',
      color: 'Cool Blue / Iron Gray',
      warrantyText: '1 Year OnePlus Official Warranty',
      imageUrl: 'https://res.cloudinary.com/qx5zvm4w/image/upload/v1724000000/mobiles/oneplus_12r.jpg',
      highlights: ['Snapdragon 8 Gen 2', '100W SUPERVOOC Charge', '5500mAh Battery'],
      rating: 4.8,
      reviewCount: 35,
    ),
    const SignatureProduct(
      id: 'sig_new_redmi_note13pro',
      name: 'Redmi Note 13 Pro+ 5G',
      brand: 'Xiaomi',
      category: SignatureCategory.newMobile,
      price: 29999,
      mrp: 33999,
      condition: 'Brand New (Sealed)',
      storage: '256GB',
      ram: '8GB',
      color: 'Fusion Purple / Fusion Black',
      warrantyText: '1 Year Xiaomi India Warranty',
      imageUrl: 'https://res.cloudinary.com/qx5zvm4w/image/upload/v1724000000/mobiles/redmi_note13pro.jpg',
      highlights: ['200MP OIS Camera', '120W HyperCharge', 'IP68 Water Resistance'],
      rating: 4.7,
      reviewCount: 19,
    ),

    // ── USED / CERTIFIED PRE-OWNED MOBILES ─────────────────────────
    const SignatureProduct(
      id: 'sig_used_ip13_128_mint',
      name: 'iPhone 13 (Certified Pre-Owned)',
      brand: 'Apple',
      category: SignatureCategory.usedMobile,
      price: 34999,
      mrp: 59900,
      condition: 'Grade A+ (Like New)',
      batteryHealth: 91,
      storage: '128GB',
      ram: '4GB',
      color: 'Midnight Blue / Starlight',
      warrantyText: '6 Months NJ Tech Comprehensive Warranty',
      imageUrl: 'https://res.cloudinary.com/qx5zvm4w/image/upload/v1724000000/mobiles/iphone13_used.jpg',
      highlights: ['32-Point Quality Inspected', 'Original Battery & Display', 'Allin1 Verified'],
      rating: 4.9,
      reviewCount: 42,
    ),
    const SignatureProduct(
      id: 'sig_used_ip14pro_128',
      name: 'iPhone 14 Pro (Certified Pre-Owned)',
      brand: 'Apple',
      category: SignatureCategory.usedMobile,
      price: 64999,
      mrp: 119900,
      condition: 'Super Mint (Flawless)',
      batteryHealth: 88,
      storage: '128GB',
      ram: '6GB',
      color: 'Deep Purple',
      warrantyText: '6 Months NJ Tech Comprehensive Warranty',
      imageUrl: 'https://res.cloudinary.com/qx5zvm4w/image/upload/v1724000000/mobiles/iphone14pro_used.jpg',
      highlights: ['120Hz ProMotion', 'Dynamic Island', 'Original Display & Face ID'],
      rating: 5,
      reviewCount: 31,
    ),
    const SignatureProduct(
      id: 'sig_used_s23ultra_256',
      name: 'Samsung Galaxy S23 Ultra 5G (Certified)',
      brand: 'Samsung',
      category: SignatureCategory.usedMobile,
      price: 58999,
      mrp: 124999,
      condition: 'Grade A+ (Like New)',
      batteryHealth: 94,
      storage: '256GB',
      ram: '12GB',
      color: 'Phantom Black',
      warrantyText: '6 Months NJ Tech Comprehensive Warranty',
      imageUrl: 'https://res.cloudinary.com/qx5zvm4w/image/upload/v1724000000/mobiles/s23ultra_used.jpg',
      highlights: ['200MP 100X Space Zoom', 'S-Pen Included', 'Tested & Verified'],
      rating: 4.9,
      reviewCount: 22,
    ),
    const SignatureProduct(
      id: 'sig_used_op11_128',
      name: 'OnePlus 11 5G (Certified)',
      brand: 'OnePlus',
      category: SignatureCategory.usedMobile,
      price: 28999,
      mrp: 56999,
      condition: 'Grade A (Excellent)',
      batteryHealth: 92,
      storage: '128GB',
      ram: '8GB',
      color: 'Titan Black',
      warrantyText: '6 Months NJ Tech Warranty',
      imageUrl: 'https://res.cloudinary.com/qx5zvm4w/image/upload/v1724000000/mobiles/oneplus11_used.jpg',
      highlights: ['Hasselblad Camera', '100W Charging', 'Original Charger Included'],
      rating: 4.7,
      reviewCount: 18,
    ),

    // ── ACCESSORIES & SPARES ───────────────────────────────────────
    const SignatureProduct(
      id: 'sig_acc_apple_20w_adapter',
      name: 'Apple 20W USB-C Power Adapter (Original)',
      brand: 'Apple',
      category: SignatureCategory.accessory,
      price: 1699,
      mrp: 1900,
      warrantyText: '6 Months Replacement Warranty',
      imageUrl: 'https://res.cloudinary.com/qx5zvm4w/image/upload/v1724000000/mobiles/apple_20w_charger.jpg',
      highlights: ['Fast Charging 0-50% in 30 mins', 'Original Apple Certified'],
      rating: 4.9,
      reviewCount: 88,
    ),
    const SignatureProduct(
      id: 'sig_acc_typec_65w_cable',
      name: 'NJ Tech 65W Braided Fast Charge Cable (Type-C to Type-C)',
      brand: 'NJ Tech Signature',
      category: SignatureCategory.accessory,
      price: 349,
      mrp: 699,
      warrantyText: '1 Year Full Replacement Warranty',
      imageUrl: 'https://res.cloudinary.com/qx5zvm4w/image/upload/v1724000000/mobiles/typec_braided_cable.jpg',
      highlights: ['Heavy Duty Nylon Braided', 'PD 65W Fast Charging', 'Gold Plated Connectors'],
      rating: 4.9,
      reviewCount: 140,
    ),
    const SignatureProduct(
      id: 'sig_spare_ip13_oled_screen',
      name: 'iPhone 13 OEM OLED Display Replacement Panel',
      brand: 'Apple',
      category: SignatureCategory.sparePart,
      price: 5499,
      mrp: 9999,
      condition: 'OEM Tested Grade AAA',
      warrantyText: '3 Months Touch & Display Warranty',
      imageUrl: 'https://res.cloudinary.com/qx5zvm4w/image/upload/v1724000000/mobiles/iphone13_screen_spare.jpg',
      highlights: ['TrueTone Support', 'Original Color Saturation', 'Free Installation at NJ Tech'],
      rating: 4.8,
      reviewCount: 45,
    ),
    const SignatureProduct(
      id: 'sig_acc_9d_tempered_glass',
      name: 'Edge-to-Edge 9D Privacy Tempered Glass (All Models)',
      brand: 'NJ Tech Signature',
      category: SignatureCategory.accessory,
      price: 199,
      mrp: 499,
      warrantyText: 'Scratch & Shatter Proof',
      imageUrl: 'https://res.cloudinary.com/qx5zvm4w/image/upload/v1724000000/mobiles/privacy_tempered_glass.jpg',
      highlights: ['Anti-Spy Privacy Filter', '9H Surface Hardness', 'Oleophobic Coating'],
      rating: 4.9,
      reviewCount: 210,
    ),
  ];

  /// Retrieves signature products with filtering
  Future<List<SignatureProduct>> getProducts({
    SignatureCategory? category,
    String? brand,
    String? query,
  }) async {
    try {
      final snap = await _productsRef.limit(50).get();
      List<SignatureProduct> products = [];

      if (snap.docs.isNotEmpty) {
        products = snap.docs
            .map((doc) => SignatureProduct.fromMap(doc.id, doc.data()))
            .toList();
      } else {
        // Return rich initial catalog if remote collection is empty
        products = List.from(kCuratedSignatureCatalog);
      }

      if (category != null) {
        products = products.where((p) => p.category == category).toList();
      }
      if (brand != null && brand.isNotEmpty && brand != 'All') {
        products = products.where((p) => p.brand.toLowerCase() == brand.toLowerCase()).toList();
      }
      if (query != null && query.trim().isNotEmpty) {
        final q = query.trim().toLowerCase();
        products = products.where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.brand.toLowerCase().contains(q) ||
            (p.storage?.toLowerCase().contains(q) ?? false)).toList();
      }

      return products;
    } catch (e) {
      debugPrint('[SignatureMobileService] getProducts error: $e');
      return List.from(kCuratedSignatureCatalog);
    }
  }

  /// Places a Signature Mobile / Accessories Order
  Future<SignatureOrder> placeOrder({
    required String customerId,
    required String customerName,
    required String customerPhone,
    required List<SignatureOrderItem> items,
    required double deliveryFee,
    required SignatureDeliveryMode deliveryMode,
    String? deliveryAddress,
    required String paymentMethod,
    String paymentStatus = 'pending',
  }) async {
    final now = DateTime.now();
    final orderId = 'SIG_${now.millisecondsSinceEpoch}';
    final subtotal = items.fold<double>(0, (sum, it) => sum + it.total);
    final totalAmount = subtotal + (deliveryMode == SignatureDeliveryMode.doorstep ? deliveryFee : 0.0);

    // Create linked Service Request so Hero can deliver if Doorstep
    String? serviceRequestId;
    if (deliveryMode == SignatureDeliveryMode.doorstep) {
      try {
        final itemsSummary = items.map((i) => '${i.quantity}x ${i.productName}').join(', ');
        serviceRequestId = await ServiceRequestService().createServiceRequest(
          requestType: 'signature_mobile_delivery',
          customerId: customerId,
          customerName: customerName,
          customerPhone: customerPhone,
          details: {
            'orderId': orderId,
            'itemsSummary': itemsSummary,
            'totalAmount': totalAmount,
            'deliveryAddress': deliveryAddress ?? 'Customer Address',
            'shopAddress': 'NJ Tech Mobile Service Center, Erode',
            'deliveryMode': deliveryMode.name,
            'paymentMethod': paymentMethod,
            'paymentStatus': paymentStatus,
          },
        );
      } catch (e) {
        debugPrint('[SignatureMobileService] createServiceRequest error: $e');
      }
    }

    final order = SignatureOrder(
      orderId: orderId,
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      items: items,
      subtotal: subtotal,
      deliveryFee: deliveryFee,
      totalAmount: totalAmount,
      deliveryMode: deliveryMode,
      deliveryAddress: deliveryAddress ?? '',
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      serviceRequestId: serviceRequestId,
      createdAt: now,
      updatedAt: now,
    );

    await _ordersRef.doc(orderId).set(order.toMap());
    return order;
  }

  /// Submits post-delivery customer feedback and 5-star rating
  Future<void> submitFeedback({
    required String orderId,
    required int rating,
    String? feedback,
    List<String> tags = const [],
  }) async {
    await _ordersRef.doc(orderId).update({
      'rating': rating,
      if (feedback != null) 'feedback': feedback,
      'feedbackTags': tags,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stream of customer's Signature Mobile orders
  Stream<List<SignatureOrder>> streamOrdersForCustomer(String customerId) {
    return _ordersRef
        .where('customerId', isEqualTo: customerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map(SignatureOrder.fromFirestore).toList(),
        );
  }

  /// Stream single order for tracking
  Stream<SignatureOrder?> streamOrder(String orderId) {
    return _ordersRef.doc(orderId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return SignatureOrder.fromFirestore(doc);
    });
  }
}
