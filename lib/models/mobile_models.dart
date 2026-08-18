// ================================================================
// Mobile Hub models — Allin1 (Aug 18 2026)
// ================================================================
// Two distinct things live here, deliberately kept separate:
//
//   CatalogPhone  — a MODEL that exists in the world (Galaxy S24).
//                   Comes from the bundled JSON asset. Costs nothing,
//                   shared by every seller. No price, no stock, no
//                   owner — it's a reference entry, not a for-sale item.
//
//   MobileListing — a specific phone a specific SELLER is selling, at
//                   their price. Lives in Firestore under
//                   sellers/{sellerId}/mobile_listings/{listingId}.
//
// The listing denormalizes `brand` and `model` as plain text rather
// than only storing modelKey. That's intentional: it means a listing
// still renders correctly if the catalog JSON is older than the
// listing (customer hasn't updated the app yet) or if the seller
// entered an off-catalog phone. The catalog is an accelerator, never
// a hard dependency.
// ================================================================

/// A phone model from the shared bundled catalog. Reference data only.
class CatalogPhone {
  final String modelKey;
  final String brand;
  final String model;

  /// Common RAM/storage variants, e.g. ['8/128', '8/256'] or, for
  /// iPhones, ['128GB', '256GB']. Free-text — sellers may type their own.
  final List<String> variants;

  /// ONE shared Cloudinary URL reused by every seller listing this
  /// model. Empty string when no admin has uploaded it yet — callers
  /// must fall back to a local icon rather than rendering a broken image.
  final String imageUrl;

  const CatalogPhone({
    required this.modelKey,
    required this.brand,
    required this.model,
    this.variants = const [],
    this.imageUrl = '',
  });

  String get displayName => '$brand $model';

  factory CatalogPhone.fromJson(Map<String, dynamic> json) {
    return CatalogPhone(
      modelKey: (json['modelKey'] as String?) ?? '',
      brand: (json['brand'] as String?) ?? '',
      model: (json['model'] as String?) ?? '',
      variants: ((json['variants'] as List<dynamic>?) ?? const [])
          .map((v) => v.toString())
          .toList(),
      imageUrl: (json['imageUrl'] as String?) ?? '',
    );
  }
}

/// Condition of a listed phone. Stored as the raw string in Firestore
/// so a future condition never breaks an old client's parse.
class MobileCondition {
  static const String isNew = 'new';
  static const String used = 'used';
}

/// Grades offered for used phones. Kept short and honest — this is
/// what a customer judges a second-hand purchase on.
const List<String> kUsedConditionGrades = <String>[
  'Like New',
  'Excellent',
  'Good',
  'Fair',
];

/// A phone a seller is actually selling.
class MobileListing {
  final String id;
  final String sellerId;

  /// Denormalized so a listing renders without a seller lookup in the
  /// browse grid — that lookup would be an N+1 read per card.
  final String sellerName;
  final String sellerPhone;

  /// 'new' or 'used' — see MobileCondition.
  final String condition;

  final String brand;
  final String model;

  /// Links to the shared catalog when the seller picked a known model.
  /// Empty for off-catalog/custom entries.
  final String modelKey;

  /// e.g. '8/128'. Free text.
  final String variant;
  final String color;

  final double price;

  /// Original/strike-through price, for showing a discount. Null when
  /// there's no offer. Must be > price to be meaningful.
  final double? mrp;

  /// Per-listing photo. For USED phones this is the actual device
  /// photo (uploaded by the seller, ~100 KB via CloudinaryUploadService)
  /// — a customer must see the real unit's condition, so a shared stock
  /// image would be misleading here.
  ///
  /// For NEW phones this is normally null and the UI falls back to the
  /// shared catalog image, which is the whole cost saving: no upload,
  /// no per-seller storage. A seller CAN still override with their own
  /// photo if they want.
  final String? imageUrl;

  /// Used-only. One of kUsedConditionGrades.
  final String? conditionGrade;

  /// Used-only, free text: 'Bill + box available', '2 yr old', etc.
  final String? notes;

  /// Warranty remaining/offered, in months. 0 = none.
  final int warrantyMonths;

  final bool inStock;

  // ── VIDEO (Aug 18 2026, Nizam: "mobile-ku video") ─────────────
  // A YouTube URL the seller pastes. We store ONLY the URL string —
  // YouTube does the hosting, transcoding, streaming and CDN, so
  // video costs us literally zero storage and zero bandwidth. That
  // is what makes video viable at all on the Spark plan; hosting
  // even short clips ourselves would blow the free tier instantly.
  //
  // Deliberately mobile-only: a phone's real condition, screen and
  // touch response are exactly what a still photo cannot prove and
  // video can. Food stays photo-only, per Nizam.
  final String? youtubeUrl;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const MobileListing({
    required this.id,
    required this.sellerId,
    required this.sellerName,
    required this.condition,
    required this.brand,
    required this.model,
    required this.price,
    this.sellerPhone = '',
    this.modelKey = '',
    this.variant = '',
    this.color = '',
    this.mrp,
    this.imageUrl,
    this.conditionGrade,
    this.notes,
    this.warrantyMonths = 0,
    this.inStock = true,
    this.youtubeUrl,
    this.createdAt,
    this.updatedAt,
  });

  bool get isUsed => condition == MobileCondition.used;

  String get displayName {
    final base = '$brand $model'.trim();
    return variant.isEmpty ? base : '$base ($variant)';
  }

  /// Whole-rupee discount percentage, or null when there's no valid
  /// offer. Guarded so a bad mrp (<= price) never renders "-0% OFF" or
  /// a negative badge.
  int? get discountPercent {
    final m = mrp;
    if (m == null || m <= price || price <= 0) return null;
    return (((m - price) / m) * 100).round();
  }

  factory MobileListing.fromJson(Map<String, dynamic> json, {String? docId}) {
    double toDouble(Object? v) => (v as num?)?.toDouble() ?? 0.0;
    DateTime? toDate(Object? v) {
      if (v == null) return null;
      // Accepts a Firestore Timestamp (has toDate()) or an ISO string,
      // so cached/Hive-roundtripped copies parse too.
      try {
        final dynamic dyn = v;
        if (dyn is String) return DateTime.tryParse(dyn);
        return dyn.toDate() as DateTime;
      } catch (_) {
        return null;
      }
    }

    return MobileListing(
      id: docId ?? (json['id'] as String?) ?? '',
      sellerId: (json['sellerId'] as String?) ?? '',
      sellerName: (json['sellerName'] as String?) ?? '',
      sellerPhone: (json['sellerPhone'] as String?) ?? '',
      condition: (json['condition'] as String?) ?? MobileCondition.isNew,
      brand: (json['brand'] as String?) ?? '',
      model: (json['model'] as String?) ?? '',
      modelKey: (json['modelKey'] as String?) ?? '',
      variant: (json['variant'] as String?) ?? '',
      color: (json['color'] as String?) ?? '',
      price: toDouble(json['price']),
      mrp: json['mrp'] == null ? null : toDouble(json['mrp']),
      imageUrl: json['imageUrl'] as String?,
      conditionGrade: json['conditionGrade'] as String?,
      notes: json['notes'] as String?,
      warrantyMonths: (json['warrantyMonths'] as num?)?.toInt() ?? 0,
      inStock: (json['inStock'] as bool?) ?? true,
      youtubeUrl: json['youtubeUrl'] as String?,
      createdAt: toDate(json['createdAt']),
      updatedAt: toDate(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'sellerId': sellerId,
        'sellerName': sellerName,
        'sellerPhone': sellerPhone,
        'condition': condition,
        'brand': brand,
        'model': model,
        'modelKey': modelKey,
        'variant': variant,
        'color': color,
        'price': price,
        if (mrp != null) 'mrp': mrp,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (conditionGrade != null) 'conditionGrade': conditionGrade,
        if (notes != null) 'notes': notes,
        'warrantyMonths': warrantyMonths,
        'inStock': inStock,
        if (youtubeUrl != null) 'youtubeUrl': youtubeUrl,
      };

  MobileListing copyWith({
    String? id,
    String? sellerId,
    String? sellerName,
    String? sellerPhone,
    String? condition,
    String? brand,
    String? model,
    String? modelKey,
    String? variant,
    String? color,
    double? price,
    double? mrp,
    String? imageUrl,
    String? conditionGrade,
    String? notes,
    int? warrantyMonths,
    bool? inStock,
    String? youtubeUrl,
  }) {
    return MobileListing(
      id: id ?? this.id,
      sellerId: sellerId ?? this.sellerId,
      sellerName: sellerName ?? this.sellerName,
      sellerPhone: sellerPhone ?? this.sellerPhone,
      condition: condition ?? this.condition,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      modelKey: modelKey ?? this.modelKey,
      variant: variant ?? this.variant,
      color: color ?? this.color,
      price: price ?? this.price,
      mrp: mrp ?? this.mrp,
      imageUrl: imageUrl ?? this.imageUrl,
      conditionGrade: conditionGrade ?? this.conditionGrade,
      notes: notes ?? this.notes,
      warrantyMonths: warrantyMonths ?? this.warrantyMonths,
      inStock: inStock ?? this.inStock,
      youtubeUrl: youtubeUrl ?? this.youtubeUrl,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

// ================================================================
// YouTube helpers
// ================================================================
/// Extracts the 11-character video ID from any common YouTube URL
/// shape, or returns null if the string isn't a recognisable YouTube
/// link.
///
/// Sellers paste whatever their phone's share sheet produced, so this
/// accepts all of: youtu.be/ID, /watch?v=ID, /shorts/ID, /embed/ID,
/// /live/ID, with or without extra query params, http or https, with
/// or without www or m. subdomains. Anything unrecognised returns null
/// so the UI can reject it at entry rather than rendering a dead
/// player later.
String? youtubeVideoId(String? raw) {
  if (raw == null) return null;
  final input = raw.trim();
  if (input.isEmpty) return null;

  // A bare ID pasted on its own.
  final bare = RegExp(r'^[A-Za-z0-9_-]{11}$');
  if (bare.hasMatch(input)) return input;

  Uri? uri;
  try {
    uri = Uri.parse(input.startsWith('http') ? input : 'https://$input');
  } catch (_) {
    return null;
  }

  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^(www\.|m\.)'), '');
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

  String? candidate;
  if (host == 'youtu.be') {
    candidate = segments.isNotEmpty ? segments.first : null;
  } else if (host == 'youtube.com' || host == 'youtube-nocookie.com') {
    if (uri.queryParameters['v'] != null) {
      candidate = uri.queryParameters['v'];
    } else if (segments.length >= 2 &&
        {'shorts', 'embed', 'live', 'v'}.contains(segments.first)) {
      candidate = segments[1];
    }
  }

  if (candidate == null) return null;
  return bare.hasMatch(candidate) ? candidate : null;
}

/// True when [raw] is a usable YouTube link. Used by the seller editor
/// to block a bad paste at save time instead of shipping a listing with
/// a video button that leads nowhere.
bool isValidYoutubeUrl(String? raw) => youtubeVideoId(raw) != null;
