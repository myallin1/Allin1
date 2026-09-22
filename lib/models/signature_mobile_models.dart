// ================================================================
// signature_mobile_models.dart — Models for NJ Tech Signature Mobiles
// ================================================================
// Supports:
// 1. New Mobile Sales (Sealed, Brand Warranty)
// 2. Used / Pre-Owned Certified Phones (Grade A+, Battery Health %, 6-Month Warranty)
// 3. Mobile Accessories & Spares (Fast Chargers, Displays, Glass, Cases, Batteries)
// 4. Order tracking & customer feedback review models
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

enum SignatureCategory {
  newMobile,
  usedMobile,
  accessory,
  sparePart,
}

enum SignatureDeliveryMode {
  doorstep,
  storePickup,
}

enum SignatureOrderStatus {
  placed,
  confirmed,
  dispatched,
  delivered,
  cancelled,
}

class SignatureProduct {
  final String id;
  final String name;
  final String brand;
  final SignatureCategory category;
  final double price;
  final double mrp;
  final String condition; // 'Brand New', 'Like New / Mint', 'Good', 'Fair'
  final int? batteryHealth; // e.g. 96 (%)
  final String? storage; // '128GB', '256GB'
  final String? ram; // '8GB', '12GB'
  final String? color;
  final String warrantyText;
  final String imageUrl;
  final List<String> galleryImages;
  final bool inStock;
  final int stockCount;
  final double rating;
  final int reviewCount;
  final List<String> highlights;
  final Map<String, dynamic> extraSpecs;

  const SignatureProduct({
    required this.id,
    required this.name,
    required this.brand,
    required this.category,
    required this.price,
    required this.mrp,
    this.condition = 'Brand New',
    this.batteryHealth,
    this.storage,
    this.ram,
    this.color,
    this.warrantyText = '1 Year Official Warranty',
    required this.imageUrl,
    this.galleryImages = const [],
    this.inStock = true,
    this.stockCount = 10,
    this.rating = 4.8,
    this.reviewCount = 24,
    this.highlights = const [],
    this.extraSpecs = const {},
  });

  double get discountPercent =>
      mrp > price ? (((mrp - price) / mrp) * 100).roundToDouble() : 0.0;

  factory SignatureProduct.fromMap(String id, Map<String, dynamic> data) {
    SignatureCategory cat;
    switch ((data['category'] as String?)?.toLowerCase()) {
      case 'used_mobile':
      case 'usedmobile':
      case 'used':
        cat = SignatureCategory.usedMobile;
        break;
      case 'accessory':
      case 'accessories':
        cat = SignatureCategory.accessory;
        break;
      case 'spare_part':
      case 'spare':
      case 'sparepart':
        cat = SignatureCategory.sparePart;
        break;
      case 'new_mobile':
      case 'newmobile':
      case 'new':
      default:
        cat = SignatureCategory.newMobile;
        break;
    }

    final rawGallery = data['galleryImages'];
    List<String> gallery = [];
    if (rawGallery is List) {
      gallery = rawGallery.map((e) => e.toString()).toList();
    }

    final rawHighlights = data['highlights'];
    List<String> highlightsList = [];
    if (rawHighlights is List) {
      highlightsList = rawHighlights.map((e) => e.toString()).toList();
    }

    return SignatureProduct(
      id: id,
      name: (data['name'] as String?) ?? 'Smartphone',
      brand: (data['brand'] as String?) ?? 'Brand',
      category: cat,
      price: (data['price'] as num?)?.toDouble() ?? 0.0,
      mrp: (data['mrp'] as num?)?.toDouble() ?? 0.0,
      condition: (data['condition'] as String?) ?? 'Brand New',
      batteryHealth: (data['batteryHealth'] as num?)?.toInt(),
      storage: data['storage'] as String?,
      ram: data['ram'] as String?,
      color: data['color'] as String?,
      warrantyText: (data['warrantyText'] as String?) ?? '1 Year Warranty',
      imageUrl: (data['imageUrl'] as String?) ?? '',
      galleryImages: gallery,
      inStock: (data['inStock'] as bool?) ?? true,
      stockCount: (data['stockCount'] as num?)?.toInt() ?? 10,
      rating: (data['rating'] as num?)?.toDouble() ?? 4.8,
      reviewCount: (data['reviewCount'] as num?)?.toInt() ?? 10,
      highlights: highlightsList,
      extraSpecs: (data['extraSpecs'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toMap() {
    String catStr;
    switch (category) {
      case SignatureCategory.usedMobile:
        catStr = 'used_mobile';
        break;
      case SignatureCategory.accessory:
        catStr = 'accessory';
        break;
      case SignatureCategory.sparePart:
        catStr = 'spare_part';
        break;
      case SignatureCategory.newMobile:
        catStr = 'new_mobile';
        break;
    }

    return {
      'name': name,
      'brand': brand,
      'category': catStr,
      'price': price,
      'mrp': mrp,
      'condition': condition,
      if (batteryHealth != null) 'batteryHealth': batteryHealth,
      if (storage != null) 'storage': storage,
      if (ram != null) 'ram': ram,
      if (color != null) 'color': color,
      'warrantyText': warrantyText,
      'imageUrl': imageUrl,
      'galleryImages': galleryImages,
      'inStock': inStock,
      'stockCount': stockCount,
      'rating': rating,
      'reviewCount': reviewCount,
      'highlights': highlights,
      'extraSpecs': extraSpecs,
    };
  }
}

class SignatureOrderItem {
  final String productId;
  final String productName;
  final String brand;
  final double price;
  final int quantity;
  final String? storage;
  final String? color;
  final String imageUrl;

  const SignatureOrderItem({
    required this.productId,
    required this.productName,
    required this.brand,
    required this.price,
    this.quantity = 1,
    this.storage,
    this.color,
    required this.imageUrl,
  });

  double get total => price * quantity;

  factory SignatureOrderItem.fromMap(Map<String, dynamic> map) {
    return SignatureOrderItem(
      productId: (map['productId'] as String?) ?? '',
      productName: (map['productName'] as String?) ?? 'Product',
      brand: (map['brand'] as String?) ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      storage: map['storage'] as String?,
      color: map['color'] as String?,
      imageUrl: (map['imageUrl'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'brand': brand,
      'price': price,
      'quantity': quantity,
      if (storage != null) 'storage': storage,
      if (color != null) 'color': color,
      'imageUrl': imageUrl,
    };
  }
}

class SignatureOrder {
  final String orderId;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final List<SignatureOrderItem> items;
  final double subtotal;
  final double deliveryFee;
  final double totalAmount;
  final SignatureDeliveryMode deliveryMode;
  final String deliveryAddress;
  final String paymentMethod; // 'upi', 'cod', 'store_pay'
  final String paymentStatus; // 'paid', 'pending'
  final SignatureOrderStatus status;
  final String? serviceRequestId;
  final int? rating;
  final String? feedback;
  final List<String> feedbackTags;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SignatureOrder({
    required this.orderId,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.items,
    required this.subtotal,
    this.deliveryFee = 0.0,
    required this.totalAmount,
    this.deliveryMode = SignatureDeliveryMode.doorstep,
    this.deliveryAddress = '',
    this.paymentMethod = 'upi',
    this.paymentStatus = 'pending',
    this.status = SignatureOrderStatus.placed,
    this.serviceRequestId,
    this.rating,
    this.feedback,
    this.feedbackTags = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory SignatureOrder.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return SignatureOrder.fromMap(doc.id, data);
  }

  factory SignatureOrder.fromMap(String orderId, Map<String, dynamic> data) {
    final rawItems = data['items'];
    List<SignatureOrderItem> itemList = [];
    if (rawItems is List) {
      itemList = rawItems
          .map((i) => SignatureOrderItem.fromMap(Map<String, dynamic>.from(i as Map)))
          .toList();
    }

    SignatureDeliveryMode delMode =
        (data['deliveryMode'] == 'store_pickup' || data['deliveryMode'] == 'pickup')
            ? SignatureDeliveryMode.storePickup
            : SignatureDeliveryMode.doorstep;

    SignatureOrderStatus orderStatus;
    switch ((data['status'] as String?)?.toLowerCase()) {
      case 'confirmed':
        orderStatus = SignatureOrderStatus.confirmed;
        break;
      case 'dispatched':
      case 'out_for_delivery':
        orderStatus = SignatureOrderStatus.dispatched;
        break;
      case 'delivered':
      case 'completed':
        orderStatus = SignatureOrderStatus.delivered;
        break;
      case 'cancelled':
        orderStatus = SignatureOrderStatus.cancelled;
        break;
      case 'placed':
      default:
        orderStatus = SignatureOrderStatus.placed;
        break;
    }

    final rawCreatedAt = data['createdAt'];
    DateTime createdAt = DateTime.now();
    if (rawCreatedAt is Timestamp) {
      createdAt = rawCreatedAt.toDate();
    } else if (rawCreatedAt is String) {
      createdAt = DateTime.tryParse(rawCreatedAt) ?? DateTime.now();
    }

    final rawUpdatedAt = data['updatedAt'];
    DateTime updatedAt = DateTime.now();
    if (rawUpdatedAt is Timestamp) {
      updatedAt = rawUpdatedAt.toDate();
    } else if (rawUpdatedAt is String) {
      updatedAt = DateTime.tryParse(rawUpdatedAt) ?? DateTime.now();
    }

    final rawTags = data['feedbackTags'];
    List<String> tagsList = [];
    if (rawTags is List) {
      tagsList = rawTags.map((e) => e.toString()).toList();
    }

    return SignatureOrder(
      orderId: orderId,
      customerId: (data['customerId'] as String?) ?? '',
      customerName: (data['customerName'] as String?) ?? 'Customer',
      customerPhone: (data['customerPhone'] as String?) ?? '',
      items: itemList,
      subtotal: (data['subtotal'] as num?)?.toDouble() ?? 0.0,
      deliveryFee: (data['deliveryFee'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (data['totalAmount'] as num?)?.toDouble() ?? 0.0,
      deliveryMode: delMode,
      deliveryAddress: (data['deliveryAddress'] as String?) ?? '',
      paymentMethod: (data['paymentMethod'] as String?) ?? 'upi',
      paymentStatus: (data['paymentStatus'] as String?) ?? 'pending',
      status: orderStatus,
      serviceRequestId: data['serviceRequestId'] as String?,
      rating: (data['rating'] as num?)?.toInt(),
      feedback: data['feedback'] as String?,
      feedbackTags: tagsList,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'items': items.map((i) => i.toMap()).toList(),
      'subtotal': subtotal,
      'deliveryFee': deliveryFee,
      'totalAmount': totalAmount,
      'deliveryMode': deliveryMode == SignatureDeliveryMode.storePickup
          ? 'store_pickup'
          : 'doorstep',
      'deliveryAddress': deliveryAddress,
      'paymentMethod': paymentMethod,
      'paymentStatus': paymentStatus,
      'status': status.name,
      if (serviceRequestId != null) 'serviceRequestId': serviceRequestId,
      if (rating != null) 'rating': rating,
      if (feedback != null) 'feedback': feedback,
      'feedbackTags': feedbackTags,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}
