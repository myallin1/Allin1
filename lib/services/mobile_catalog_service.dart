// ================================================================
// MobileCatalogService — Allin1 Mobile Hub
// ================================================================
// The "0-cost production" half of the Mobile Hub (Nizam's mandate,
// cross-checked with Gemini — Aug 18 2026).
//
// WHY THIS EXISTS / the cost reasoning, so nobody "optimizes" it back:
//
//   Browsing a phone catalog is the single highest-frequency read in
//   this feature — every customer who opens Mobiles scrolls it, most
//   without ever buying. If that catalog lived in Firestore, every
//   scroll would burn document reads on the Spark plan for data that
//   changes maybe once a month. So the catalog METADATA (brand, model
//   name, variants) ships as a bundled JSON asset instead: it costs
//   ZERO Firestore reads, works fully offline, and renders instantly
//   with no spinner.
//
//   The model PHOTOS are deliberately NOT bundled. Bundling a few
//   hundred phone images would add tens of MB to the APK for every
//   single user — including the ones who never tap Mobiles — which is
//   exactly the trade-off Gemini correctly flagged. Instead each model
//   carries ONE shared Cloudinary URL, reused by every seller who
//   lists that model (100 shops selling a Galaxy S24 all point at the
//   same image, not 100 uploads), and CachedCloudImage caches it on
//   the device for ~30 days, so a given customer downloads it once and
//   never again.
//
//   Net effect: catalog browse = 0 DB reads + 0 repeat bandwidth.
//   Only a genuinely NEW/uncommon phone a seller adds themselves costs
//   an upload — see MobileListingService.
//
// Adding models later needs no database write and no schema change —
// edit the JSON, ship via Shorebird.
// ================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/mobile_models.dart';

class MobileCatalogService {
  MobileCatalogService._();
  static final MobileCatalogService instance = MobileCatalogService._();

  static const String _assetPath = 'assets/data/mobile_catalog.json';

  List<CatalogPhone>? _models;
  List<String>? _brands;
  String _cloudinaryFolder = 'common_mobiles';

  /// In-flight guard so two widgets building at once don't each decode
  /// the JSON. Whoever gets there first does the work; the rest await
  /// the same future.
  Future<void>? _loading;

  bool get isLoaded => _models != null;

  /// Loads and decodes the bundled catalog exactly once per app
  /// session. Safe to call from every build() — after the first call
  /// it returns an already-completed future and does no work.
  Future<void> ensureLoaded() {
    if (_models != null) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;

      _cloudinaryFolder =
          (json['cloudinaryFolder'] as String?) ?? 'common_mobiles';

      _brands = ((json['brands'] as List<dynamic>?) ?? const [])
          .map((b) => b.toString())
          .toList();

      _models = ((json['models'] as List<dynamic>?) ?? const [])
          .map((m) => CatalogPhone.fromJson(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // A malformed/missing asset must never hard-crash the Mobiles
      // tab — degrade to an empty catalog. Sellers can still add
      // custom entries by hand, and customers still see real listings
      // (listings carry their own denormalized brand/model text, they
      // do NOT depend on this catalog being present — see
      // MobileListing).
      debugPrint('[MobileCatalog] failed to load $_assetPath: $e');
      _models = const [];
      _brands = const [];
    }
  }

  String get cloudinaryFolder => _cloudinaryFolder;

  /// All catalog models. Empty until [ensureLoaded] completes.
  List<CatalogPhone> get models => _models ?? const [];

  /// Brand list for filter chips, in the JSON's curated order (roughly
  /// by local popularity) rather than alphabetical.
  List<String> get brands => _brands ?? const [];

  /// Look up a model by its stable key. Returns null for custom/
  /// off-catalog listings, which is expected and handled by callers.
  CatalogPhone? byKey(String? modelKey) {
    if (modelKey == null || modelKey.isEmpty) return null;
    for (final m in models) {
      if (m.modelKey == modelKey) return m;
    }
    return null;
  }

  List<CatalogPhone> byBrand(String brand) =>
      models.where((m) => m.brand == brand).toList();

  /// Substring search across brand + model, for the seller's "find
  /// your phone" picker. Case-insensitive, no external dependency.
  List<CatalogPhone> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return models;
    return models.where((m) {
      return m.model.toLowerCase().contains(q) ||
          m.brand.toLowerCase().contains(q) ||
          '${m.brand} ${m.model}'.toLowerCase().contains(q);
    }).toList();
  }

  /// The shared image for a model, or null if no admin has uploaded
  /// one yet. Callers must handle null by showing a free local icon —
  /// never a broken-image box, and never a scraped third-party URL.
  String? sharedImageUrlFor(String? modelKey) {
    final url = byKey(modelKey)?.imageUrl;
    if (url == null || url.isEmpty) return null;
    return url;
  }
}
