import 'package:cloud_firestore/cloud_firestore.dart';

class SellerModel {
  final String id;
  final String name;
  final String category;
  final String subCategory;
  final String hotelType;
  final String address;
  final double latitude;
  final double longitude;
  final String phone;
  final double rating;
  final bool isOpen;
  final int estimatedPrepTimeMin;
  final String status;
  final String? imageUrl;
  final String? coverImageUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String role;
  final double pendingPayouts;
  final double totalSettled;

  /// Which seller product line this account belongs to: 'hotel',
  /// 'grocery', or 'electronics'. Distinct from [category] on purpose —
  /// [category] has been hardcoded to 'food' for every seller since this
  /// model was created (seller_onboarding_screen.dart never let a seller
  /// pick anything else), so it can't be reused as the vertical switch
  /// without breaking every existing reader that assumes category=='food'
  /// means "this is the hotel/food pipeline." Defaults to 'hotel' so
  /// every seller doc written before this field existed reads back
  /// exactly as it always has — none of them silently become "grocery."
  final String businessVertical;

  // Multi-city: which city this seller operates in -- feeds the same
  // city-based dispatch/filtering as heroes/rides. Defaults to 'erode'
  // for backward compatibility with sellers created before this field
  // existed.
  final String city;

  SellerModel({
    required this.id,
    required this.name,
    required this.subCategory, required this.address, required this.latitude, required this.longitude, required this.phone, this.category = 'food',
    this.hotelType = 'both',
    this.rating = 0.0,
    this.isOpen = true,
    this.estimatedPrepTimeMin = 20,
    this.status = 'active',
    this.imageUrl,
    this.coverImageUrl,
    this.createdAt,
    this.updatedAt,
    this.businessVertical = 'hotel',
    this.city = 'erode',
    this.role = 'owner',
    this.pendingPayouts = 0.0,
    this.totalSettled = 0.0,
  });

  factory SellerModel.fromJson(Map<String, dynamic> json) {
    return SellerModel(
      id: json['id'] as String,
      name: json['name'] as String,
      category: (json['category'] as String?) ?? 'food',
      subCategory: json['subCategory'] as String? ?? '',
      hotelType: json['hotelType'] as String? ?? 'both',
      address: json['address'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      phone: json['phone'] as String? ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      isOpen: (json['isOpen'] as bool?) ?? true,
      estimatedPrepTimeMin: (json['estimatedPrepTimeMin'] as num?)?.toInt() ?? 20,
      status: json['status'] as String? ?? 'active',
      imageUrl: json['imageUrl'] as String?,
      coverImageUrl: json['coverImageUrl'] as String?,
      createdAt: json['createdAt'] != null
          ? (json['createdAt'] as Timestamp).toDate()
          : null,
      updatedAt: json['updatedAt'] != null
          ? (json['updatedAt'] as Timestamp).toDate()
          : null,
      businessVertical: (json['businessVertical'] as String?) ?? 'hotel',
      city: (json['city'] as String?) ?? 'erode',
      role: (json['role'] as String?) ?? 'owner',
      pendingPayouts: (json['pendingPayouts'] as num?)?.toDouble() ?? 0.0,
      totalSettled: (json['totalSettled'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      // 'shopName' is a display-layer alias of 'name'. SellerCard,
      // SellerDetailScreen, and the emoji/hours lookups below all read
      // these card-display keys directly off the raw seller map (they
      // don't go through SellerModel.fromJson) — without these aliases
      // every registered seller showed as "Unknown Shop" with no
      // emoji, since Firestore never had these keys written. Writing
      // them here, once, fixes every reader at once.
      'shopName': name,
      'category': category,
      'subCategory': subCategory,
      'hotelType': hotelType,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'phone': phone,
      'rating': rating,
      'isOpen': isOpen,
      'estimatedPrepTimeMin': estimatedPrepTimeMin,
      'status': status,
      'imageUrl': imageUrl,
      'coverImageUrl': coverImageUrl,
      // Emoji shown on the seller card — derived from the sub-category
      // catalog so it always matches the icon used on the sidebar.
      'emoji': _emojiForSubCategory(subCategory),
      // SellerCard/_isOpen() reads 'hours' (open/close minute-of-day)
      // to decide the Open/Closed badge; onboarding doesn't collect
      // hours yet, so omit the key entirely — every reader already
      // treats a missing 'hours' as "always open", which matches the
      // 'isOpen' flag being seller-toggled elsewhere.
      // SellerCard's metadata line ("⏱️ NN min prep") reads
      // metadata.prepTimeMinutes — map it from estimatedPrepTimeMin so
      // the prep-time the seller actually set is what's displayed.
      'metadata': {'prepTimeMinutes': estimatedPrepTimeMin},
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'businessVertical': businessVertical,
      'city': city,
      'role': role,
      'pendingPayouts': pendingPayouts,
      'totalSettled': totalSettled,
    };
  }

  static String _emojiForSubCategory(String subCategory) {
    switch (subCategory) {
      case 'biriyani':
        return '🍛';
      case 'home_made':
        return '🍲';
      case 'parotta':
        return '🫓';
      case 'south_indian':
        return '🥘';
      case 'fast_food':
        return '🍟';
      case 'multi_cuisine':
        return '🍽️';
      default:
        return '🍽️';
    }
  }

  SellerModel copyWith({
    String? id,
    String? name,
    String? category,
    String? subCategory,
    String? hotelType,
    String? address,
    double? latitude,
    double? longitude,
    String? phone,
    double? rating,
    bool? isOpen,
    int? estimatedPrepTimeMin,
    String? status,
    String? imageUrl,
    String? coverImageUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? businessVertical,
    String? city,
    String? role,
    double? pendingPayouts,
    double? totalSettled,
  }) {
    return SellerModel(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      subCategory: subCategory ?? this.subCategory,
      hotelType: hotelType ?? this.hotelType,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      phone: phone ?? this.phone,
      rating: rating ?? this.rating,
      isOpen: isOpen ?? this.isOpen,
      estimatedPrepTimeMin: estimatedPrepTimeMin ?? this.estimatedPrepTimeMin,
      status: status ?? this.status,
      imageUrl: imageUrl ?? this.imageUrl,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      city: city ?? this.city,
      businessVertical: businessVertical ?? this.businessVertical,
      role: role ?? this.role,
      pendingPayouts: pendingPayouts ?? this.pendingPayouts,
      totalSettled: totalSettled ?? this.totalSettled,
    );
  }
}

class MenuItemModel {
  final String id;
  final String name;
  final String? description;
  final double price;
  final double? discountedPrice;
  final bool isVeg;
  final bool isAvailable;
  final int? stockQuantity;
  final List<String> tags;
  final String? imageUrl;
  final String? categoryName;
  final List<ItemVariant>? variants;
  /// How this dish photo was framed by the seller: 'square' or
  /// 'circle' (Aug 18 2026, CTO image-quality review). The crop UI
  /// and the customer-facing card MUST render the same shape — if a
  /// seller frames a dish inside a circle and the card draws a
  /// rounded square, the corners they deliberately left empty get
  /// shown. Defaults to 'square', which is what every pre-existing
  /// item was effectively cropped as.
  final String imageShape;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  MenuItemModel({
    required this.id,
    required this.name,
    required this.price, this.description,
    this.discountedPrice,
    this.isVeg = false,
    this.isAvailable = true,
    this.stockQuantity,
    this.tags = const [],
    this.imageUrl,
    this.categoryName,
    this.variants,
    this.imageShape = 'square',
    this.createdAt,
    this.updatedAt,
  });

  factory MenuItemModel.fromJson(Map<String, dynamic> json) {
    return MenuItemModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      price: (json['price'] as num).toDouble(),
      discountedPrice: (json['discountedPrice'] as num?)?.toDouble(),
      isVeg: (json['isVeg'] as bool?) ?? false,
      isAvailable: (json['isAvailable'] as bool?) ?? true,
      stockQuantity: (json['stockQuantity'] as num?)?.toInt(),
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      imageUrl: json['imageUrl'] as String?,
      categoryName: json['categoryName'] as String?,
      variants: (json['variants'] as List<dynamic>?)
          ?.map((e) => ItemVariant.fromJson(e as Map<String, dynamic>))
          .toList(),
      // Legacy items have no imageShape -> 'square', matching how
      // they already render today. No migration needed.
      imageShape: (json['imageShape'] as String?) ?? 'square',
      createdAt: json['createdAt'] != null
          ? (json['createdAt'] as Timestamp).toDate()
          : null,
      updatedAt: json['updatedAt'] != null
          ? (json['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'discountedPrice': discountedPrice,
      'isVeg': isVeg,
      'isAvailable': isAvailable,
      'stockQuantity': stockQuantity,
      'tags': tags,
      'imageUrl': imageUrl,
      // 'image'/'category' are display-layer aliases read directly by
      // ProductCard and SellerDetailScreen's grouping/cart logic
      // (they consume the raw menu_items map, not MenuItemModel).
      // Without these the product grid showed the fallback icon for
      // every item and grouped everything under "All Items".
      'image': imageUrl,
      'categoryName': categoryName,
      'category': categoryName,
      'imageShape': imageShape,
      'variants': variants?.map((e) => e.toJson()).toList(),
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  MenuItemModel copyWith({
    String? id,
    String? name,
    String? description,
    double? price,
    double? discountedPrice,
    bool? isVeg,
    bool? isAvailable,
    List<String>? tags,
    String? imageUrl,
    String? categoryName,
    List<ItemVariant>? variants,
    String? imageShape,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MenuItemModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      discountedPrice: discountedPrice ?? this.discountedPrice,
      isVeg: isVeg ?? this.isVeg,
      isAvailable: isAvailable ?? this.isAvailable,
      tags: tags ?? this.tags,
      imageUrl: imageUrl ?? this.imageUrl,
      categoryName: categoryName ?? this.categoryName,
      variants: variants ?? this.variants,
      imageShape: imageShape ?? this.imageShape,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class ItemVariant {
  final String name;
  final double price;
  final bool isDefault;

  ItemVariant({
    required this.name,
    required this.price,
    this.isDefault = false,
  });

  factory ItemVariant.fromJson(Map<String, dynamic> json) {
    return ItemVariant(
      name: json['name'] as String,
      price: (json['price'] as num).toDouble(),
      isDefault: (json['isDefault'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'price': price,
      'isDefault': isDefault,
    };
  }
}

class OrderItem {
  final String itemId;
  final String name;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
  final String? variantName;
  final String? note;

  OrderItem({
    required this.itemId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.variantName,
    this.note,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      itemId: json['itemId'] as String,
      name: json['name'] as String,
      quantity: (json['quantity'] as num).toInt(),
      unitPrice: (json['unitPrice'] as num).toDouble(),
      totalPrice: (json['totalPrice'] as num).toDouble(),
      variantName: json['variantName'] as String?,
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'itemId': itemId,
      'name': name,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'totalPrice': totalPrice,
      'variantName': variantName,
      'note': note,
    };
  }
}

class FoodOrderModel {
  final String orderId;
  final String sellerId;
  final String customerId;
  final String? customerName;
  final String? customerPhone;
  final String? deliveryAddress;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final List<OrderItem> items;
  final double subtotal;
  final double deliveryFee;
  final double platformFee;
  final double totalAmount;
  final String? couponCode;
  final double? discountAmount;
  final String paymentMethod;
  final String paymentStatus;
  final String status;
  final Map<String, DateTime?> statusTimeline;
  final String? note;
  final int? estimatedPrepTimeMin;
  final DateTime createdAt;
  final DateTime? updatedAt;

  FoodOrderModel({
    required this.orderId,
    required this.sellerId,
    required this.customerId,
    required this.items,
    required this.subtotal,
    required this.totalAmount,
    required this.createdAt,
    this.customerName,
    this.customerPhone,
    this.deliveryAddress,
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.deliveryFee = 0,
    this.platformFee = 0,
    this.couponCode,
    this.discountAmount,
    this.paymentMethod = 'cash',
    this.paymentStatus = 'pending',
    this.status = 'placed',
    this.note,
    this.estimatedPrepTimeMin,
    this.updatedAt,
    Map<String, DateTime?>? statusTimeline,
  }) : statusTimeline = statusTimeline ?? _defaultTimeline();

  static Map<String, DateTime?> _defaultTimeline() {
    final now = DateTime.now();
    return {
      'placed': now,
      'accepted': null,
      'preparing': null,
      'ready': null,
      'pickedUp': null,
      'delivered': null,
      'cancelled': null,
    };
  }

  factory FoodOrderModel.fromJson(Map<String, dynamic> json) {
    final rawTimeline = json['statusTimeline'] as Map<String, dynamic>?;
    final parsedTimeline = <String, DateTime?>{};
    if (rawTimeline != null) {
      for (final entry in rawTimeline.entries) {
        parsedTimeline[entry.key] = entry.value != null
            ? (entry.value as Timestamp).toDate()
            : null;
      }
    }

    return FoodOrderModel(
      orderId: json['orderId'] as String,
      sellerId: json['sellerId'] as String,
      customerId: json['customerId'] as String,
      items: (json['items'] as List<dynamic>)
          .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      subtotal: (json['subtotal'] as num).toDouble(),
      totalAmount: (json['totalAmount'] as num).toDouble(),
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      customerName: json['customerName'] as String?,
      customerPhone: json['customerPhone'] as String?,
      deliveryAddress: json['deliveryAddress'] as String?,
      deliveryLatitude: (json['deliveryLatitude'] as num?)?.toDouble(),
      deliveryLongitude: (json['deliveryLongitude'] as num?)?.toDouble(),
      deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0,
      platformFee: (json['platformFee'] as num?)?.toDouble() ?? 0,
      couponCode: json['couponCode'] as String?,
      discountAmount: (json['discountAmount'] as num?)?.toDouble(),
      paymentMethod: json['paymentMethod'] as String? ?? 'cash',
      paymentStatus: json['paymentStatus'] as String? ?? 'pending',
      status: json['status'] as String? ?? 'placed',
      statusTimeline: parsedTimeline,
      note: json['note'] as String?,
      estimatedPrepTimeMin: (json['estimatedPrepTimeMin'] as num?)?.toInt(),
      updatedAt: json['updatedAt'] != null
          ? (json['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final rawTimeline = <String, dynamic>{};
    for (final entry in statusTimeline.entries) {
      rawTimeline[entry.key] =
          entry.value != null ? Timestamp.fromDate(entry.value!) : null;
    }

    return {
      'orderId': orderId,
      'sellerId': sellerId,
      'customerId': customerId,
      'items': items.map((e) => e.toJson()).toList(),
      'subtotal': subtotal,
      'deliveryFee': deliveryFee,
      'platformFee': platformFee,
      'totalAmount': totalAmount,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'deliveryAddress': deliveryAddress,
      'deliveryLatitude': deliveryLatitude,
      'deliveryLongitude': deliveryLongitude,
      'couponCode': couponCode,
      'discountAmount': discountAmount,
      'paymentMethod': paymentMethod,
      'paymentStatus': paymentStatus,
      'status': status,
      'statusTimeline': rawTimeline,
      'note': note,
      'estimatedPrepTimeMin': estimatedPrepTimeMin,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  bool get isActive => status != 'delivered' && status != 'cancelled';

  String get statusDisplay {
    switch (status) {
      case 'placed':
        return 'Order Placed';
      case 'accepted':
        return 'Order Accepted';
      case 'preparing':
        return 'Preparing';
      case 'ready':
        return 'Ready for Pickup';
      case 'pickedUp':
        return 'Picked Up';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }
}
