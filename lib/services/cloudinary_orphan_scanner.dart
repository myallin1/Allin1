// ================================================================
// cloudinary_orphan_scanner.dart — cross-checks Cloudinary media
// against the Firestore collections that actually reference images,
// so Admin isn't deleting blind from AdminCloudinaryDashboardScreen.
// ================================================================
// NEW (Aug 18 2026 — Nizam: "cloudinary usage,anga iruka images ah
// yevlo size iruku,unwanted images ah delete pandrathu... admin ku oru
// option vachu... freedom irukamari"). The Cloudinary dashboard (built
// by Gemini) already lets admin browse and multi-select delete, but had
// no way to tell WHICH images are still in use vs safe orphans (a menu
// item that got deleted, a rejected hero's old KYC photos, a
// swapped-out offer banner) — so every delete was a guess.
//
// This is a deliberately EXPLICIT, admin-triggered scan (a button, not
// a background listener) — it reads every doc in a handful of
// known image-holding collections once, which is a real, visible
// Firestore read cost on the Spark plan, so it must never run
// automatically. Same "fetch only when the admin actually asks"
// discipline as CachedAnalyticsView elsewhere in the admin app.
//
// Deliberately scoped to the collections actually proven (by grep) to
// store Cloudinary URLs today — heroes, sos_kyc_requests,
// sellers/*/menu_items, custom_hotels/*/items, erode_offers, ads. If a
// future screen adds a new Cloudinary-backed image field, add its
// collection/field pair to _collectReferencedPublicIds() below or this
// scan will start flagging live images as "unused".
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import './firestore_usage_tracking.dart';

class CloudinaryOrphanScanner {
  /// Reads every known image-URL field across the app's Cloudinary
  /// consumers and returns the set of Cloudinary public_ids still
  /// referenced by at least one live Firestore document.
  Future<Set<String>> collectReferencedPublicIds() async {
    final fs = FirebaseFirestore.instance;
    final referenced = <String>{};

    void addUrl(Object? url) {
      final id = publicIdFromUrl(url as String?);
      if (id != null) referenced.add(id);
    }

    // Heroes — 4 KYC/selfie photo fields per hero.
    final heroes = await fs.collection('heroes').trackedGet();
    for (final d in heroes.docs) {
      final data = d.data();
      addUrl(data['aadhaarDocUrl']);
      addUrl(data['panDocUrl']);
      addUrl(data['licenseDocUrl']);
      addUrl(data['selfieUrl']);
    }

    // SOS KYC verification — same 3 document fields, separate flow.
    final sos = await fs.collection('sos_kyc_requests').trackedGet();
    for (final d in sos.docs) {
      final data = d.data();
      addUrl(data['aadhaarDocUrl']);
      addUrl(data['panDocUrl']);
      addUrl(data['licenseDocUrl']);
    }

    // Seller dish photos — 'menu_items' is a unique subcollection name
    // across the codebase (verified), safe for a single collectionGroup
    // read instead of listing every seller then every seller's items.
    final menuItems = await fs.collectionGroup('menu_items').get();
    for (final d in menuItems.docs) {
      addUrl(d.data()['imageUrl']);
    }

    // Custom hotel dish photos — 'items' is NOT a unique subcollection
    // name app-wide, so collectionGroup would risk pulling in unrelated
    // subcollections. custom_hotels is a small collection (one doc per
    // seller running a custom hotel), so listing hotels then each
    // hotel's own items is a bounded, small N+1 rather than a blind
    // cross-collection query.
    final hotels = await fs.collection('custom_hotels').trackedGet();
    for (final hotelDoc in hotels.docs) {
      final items = await hotelDoc.reference.collection('items').trackedGet();
      for (final item in items.docs) {
        addUrl(item.data()['photoUrl']);
      }
    }

    // Admin-managed Erode Offers banners.
    final offers = await fs.collection('erode_offers').trackedGet();
    for (final d in offers.docs) {
      addUrl(d.data()['imageUrl']);
    }

    // Admin-managed ad banners.
    final ads = await fs.collection('ads').trackedGet();
    for (final d in ads.docs) {
      addUrl(d.data()['imageUrl']);
    }

    return referenced;
  }

  /// Extracts a Cloudinary `public_id` (folder/filename, no extension,
  /// no version, no transform segment) from a delivered URL — matches
  /// the exact `public_id` shape CloudinaryAdminService.getResources()
  /// returns, so the two sets are directly comparable.
  @visibleForTesting
  String? publicIdFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (!url.contains('res.cloudinary.com')) return null;
    const marker = '/image/upload/';
    final idx = url.indexOf(marker);
    if (idx == -1) return null;
    var tail = url.substring(idx + marker.length);
    final qIdx = tail.indexOf('?');
    if (qIdx != -1) tail = tail.substring(0, qIdx);

    final cleaned = <String>[];
    for (final seg in tail.split('/')) {
      // Drop a version segment (v1723...) and any transform segment
      // (f_auto,q_auto / w_300,c_limit / etc — always contains a comma
      // or starts with a known transform-parameter prefix).
      if (RegExp(r'^v\d+$').hasMatch(seg)) continue;
      if (seg.contains(',') || RegExp(r'^(f_|q_|w_|h_|c_)').hasMatch(seg)) {
        continue;
      }
      cleaned.add(seg);
    }
    var publicId = cleaned.join('/');
    final dotIdx = publicId.lastIndexOf('.');
    if (dotIdx != -1) publicId = publicId.substring(0, dotIdx);
    return publicId.isEmpty ? null : publicId;
  }
}
