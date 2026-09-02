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
  final double walletBalance;

  /// Lifetime sum of every ₹5 platform usage fee ever debited from this
  /// seller (seller-earnings audit, Phase 2 — Earnings screen). Written
  /// alongside walletBalance's own -5.0 decrement, inside the same
  /// Firestore Transaction, by ServiceRequestService.advanceSellerStage()
  /// — see that method's fee-debit branch. Purely additive/informational;
  /// nothing else in the app derives a decision from this value.
  final double totalFeesDeducted;

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

  // ── Direct-to-seller payment collection (Sep 2026 — merchant-account-
  // free UPI flow) ──────────────────────────────────────────────────
  // Lets a hotel collect food payment straight into their OWN UPI
  // account instead of a company merchant account — no gateway, no T+1
  // settlement delay, cash reaches them same-day. Set by the seller
  // themselves in seller_settings_screen.dart; read by
  // food_checkout_screen.dart to build a "Pay <Hotel> directly" option.
  //
  // Deliberately NOT stored via the same local-only pattern as a hero's
  // own payment QR (hero_payment_qr_service.dart) — that pattern only
  // works because the customer scans the HERO's phone screen in person
  // after a ride/task. A food order is placed remotely: the customer's
  // OWN phone needs this at checkout time, so it must live in Firestore
  // (small text/base64 fields, no Cloudinary needed — see this field's
  // own size guard in seller_settings_screen.dart).
  /// The seller's own UPI VPA (e.g. 'hotelname@ybl'), used to build a
  /// `upi://pay` deep link pre-filled with the order amount. Null if the
  /// seller hasn't set one — food_checkout_screen.dart then falls back
  /// to whichever OTHER payment options the seller/customer have.
  final String? sellerUpiVpa;

  /// Base64-encoded PNG of the seller's own payment QR, for a customer
  /// who prefers scanning over a deep link (e.g. checking out on a
  /// different device than the one they'll pay from). Capped small at
  /// upload time (see seller_settings_screen.dart's size guard) so this
  /// never meaningfully grows the seller doc.
  final String? sellerPaymentQrBase64;

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
    this.walletBalance = 0.0,
    this.totalFeesDeducted = 0.0,
    this.sellerUpiVpa,
    this.sellerPaymentQrBase64,
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
      walletBalance: (json['walletBalance'] as num?)?.toDouble() ?? 0.0,
      totalFeesDeducted: (json['totalFeesDeducted'] as num?)?.toDouble() ?? 0.0,
      sellerUpiVpa: json['sellerUpiVpa'] as String?,
      sellerPaymentQrBase64: json['sellerPaymentQrBase64'] as String?,
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
      'walletBalance': walletBalance,
      'totalFeesDeducted': totalFeesDeducted,
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
    double? totalFeesDeducted,
    double? walletBalance,
    String? sellerUpiVpa,
    String? sellerPaymentQrBase64,
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
      totalFeesDeducted: totalFeesDeducted ?? this.totalFeesDeducted,
      // FIX (Task 2 — Earnings screen data reliability): pre-existing
      // bug, unrelated to this feature but directly affects it —
      // walletBalance was missing from this return entirely, so it fell
      // back to the constructor's `= 0.0` default on EVERY copyWith()
      // call. seller_dashboard_screen.dart's online/offline toggle calls
      // `_seller!.copyWith(isOpen: newStatus)` on every tap, which was
      // silently zeroing the in-memory wallet balance shown on screen
      // (never written to Firestore, but visibly wrong until the next
      // full profile reload) — exactly the kind of stale/wrong financial
      // number this whole audit exists to eliminate.
      walletBalance: walletBalance ?? this.walletBalance,
      // FIX (same class of bug as walletBalance above, caught while
      // adding these two fields): without an explicit ?? fallback here,
      // seller_dashboard_screen.dart's `_seller!.copyWith(isOpen: ...)`
      // (the online/offline toggle) would silently wipe the seller's own
      // payment VPA/QR out of the in-memory model — not Firestore, but
      // visibly gone from Settings until the next full profile reload.
      sellerUpiVpa: sellerUpiVpa ?? this.sellerUpiVpa,
      sellerPaymentQrBase64: sellerPaymentQrBase64 ?? this.sellerPaymentQrBase64,
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

  // ── Universal catalog (Sep 2026) ────────────────────────────────
  // This model already fit grocery items perfectly (name/price/stock/
  // isAvailable) — these four fields are the only additions needed to
  // extend it beyond food, rather than building a parallel model.
  /// Which vertical this item belongs to — 'food' (default, matches
  /// every item written before this field existed) or 'grocery'. Not
  /// strictly required for filtering (a seller's businessVertical
  /// already fixes them to one type) but keeps items self-describing.
  final String department;

  /// Links back to the `master_catalog/{itemId}` doc this item was
  /// toggled ON from (seller_grocery_products_screen.dart), if any.
  /// Null for a seller-authored item with no shared-catalog origin
  /// (every existing food dish, and any grocery item a seller adds
  /// that isn't in the master catalog).
  final String? sourceCatalogItemId;

  /// Lifetime count of units sold through an app order (incremented
  /// ONLY by functions/reserveMenuItemStock.ts's server-side
  /// transaction — never client-writable in practice, since that's the
  /// only code path that touches it). Kept separate from
  /// [directSaleCount] per Nizam's explicit request: a seller's
  /// dashboard needs to show app-driven vs. walk-in-shop sales as two
  /// distinct numbers, not one merged total.
  final int appOrderSoldCount;

  /// Lifetime count of units the seller recorded as sold to a walk-in
  /// customer in their physical shop (seller_grocery_products_screen
  /// .dart's "Record Direct Sale" action) — money and stock that never
  /// touched this app's order pipeline at all.
  final int directSaleCount;

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
    this.department = 'food',
    this.sourceCatalogItemId,
    this.appOrderSoldCount = 0,
    this.directSaleCount = 0,
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
      department: (json['department'] as String?) ?? 'food',
      sourceCatalogItemId: json['sourceCatalogItemId'] as String?,
      appOrderSoldCount: (json['appOrderSoldCount'] as num?)?.toInt() ?? 0,
      directSaleCount: (json['directSaleCount'] as num?)?.toInt() ?? 0,
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
      'department': department,
      if (sourceCatalogItemId != null) 'sourceCatalogItemId': sourceCatalogItemId,
      'appOrderSoldCount': appOrderSoldCount,
      'directSaleCount': directSaleCount,
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
    int? stockQuantity,
    List<String>? tags,
    String? imageUrl,
    String? categoryName,
    List<ItemVariant>? variants,
    String? imageShape,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? department,
    String? sourceCatalogItemId,
    int? appOrderSoldCount,
    int? directSaleCount,
  }) {
    return MenuItemModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      discountedPrice: discountedPrice ?? this.discountedPrice,
      isVeg: isVeg ?? this.isVeg,
      isAvailable: isAvailable ?? this.isAvailable,
      // FIX (found while adding grocery stock fields): copyWith() never
      // took/returned stockQuantity at all — any caller doing
      // `item.copyWith(isAvailable: false)` silently wiped stock back to
      // null. Nothing used copyWith() on this model before now, so this
      // was latent rather than an active bug, but the new seller
      // products screen calls it constantly (toggling on/off, editing
      // stock inline) and would have hit it immediately.
      stockQuantity: stockQuantity ?? this.stockQuantity,
      tags: tags ?? this.tags,
      imageUrl: imageUrl ?? this.imageUrl,
      categoryName: categoryName ?? this.categoryName,
      variants: variants ?? this.variants,
      imageShape: imageShape ?? this.imageShape,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      department: department ?? this.department,
      sourceCatalogItemId: sourceCatalogItemId ?? this.sourceCatalogItemId,
      appOrderSoldCount: appOrderSoldCount ?? this.appOrderSoldCount,
      directSaleCount: directSaleCount ?? this.directSaleCount,
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

// NOTE (Issue 4 cleanup — dead FoodSellerService/food_orders pipeline):
// OrderItem and FoodOrderModel (the `food_orders` collection's shape)
// were removed here. Nothing writes to `food_orders` — every order the
// seller/customer apps actually create goes through
// ServiceRequestService.createServiceRequest() into `service_requests`
// (requestType catalog_food_order / custom_hotel_order), read via
// ServiceRequestModel. See seller_dashboard_screen.dart's
// _buildCatalogOrderCard / _buildCustomHotelOrderCard.
