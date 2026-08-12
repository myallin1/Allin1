// ================================================================
// ErodeOffersSection — "Erode Offers" tab inside the Rewards screen
// ================================================================
// Shows a live list of local shop offers (managed by admin via
// AdminErodeOffersScreen, stored in Firestore `erode_offers`
// collection). Tapping a card opens OfferDetailScreen with full
// shop details, a Call button, and a Location button that opens
// Google Maps in street-view mode at the shop's coordinates.
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/hive_cache.dart';

const Color _offerInk = Color(0xFF121A3D);
const Color _offerPink = Color(0xFFFF4FA3);
const Color _offerPurple = Color(0xFFB21FFF);
const Color _offerMuted = Color(0xFF6B7280);

/// A cached offer row. Firestore's own QueryDocumentSnapshot can't be
/// stored in Hive (it holds a live reference), so offers are flattened
/// to plain id+map pairs on the way into the cache and rehydrated on the
/// way out.
class _OfferRecord {
  const _OfferRecord({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;
}

class ErodeOffersSection extends StatelessWidget {
  const ErodeOffersSection({super.key});

  /// Cache-first offers load. See the comment in [build] for the cost
  /// rationale. Sorting stays client-side (newest first) exactly as
  /// before — that was already required to avoid a composite index.
  Future<List<_OfferRecord>?> _loadOffers() async {
    final raw = await HiveCache.cachedFetch<List<dynamic>>(
      HiveCache.kErodeOffers,
      () async {
        final snap = await FirebaseFirestore.instance
            .collection('erode_offers')
            .where('active', isEqualTo: true)
            .get();
        // Stored as a plain List<Map> so it survives Hive serialization.
        // createdAt (a Timestamp) is converted to epoch millis for the
        // same reason, and used only for sorting.
        return snap.docs.map((d) {
          final data = Map<String, dynamic>.from(d.data());
          final ts = data['createdAt'];
          return <String, dynamic>{
            '__id': d.id,
            '__createdAtMs':
                ts is Timestamp ? ts.millisecondsSinceEpoch : 0,
            ...data..remove('createdAt'),
          };
        }).toList();
      },
      ttl: HiveCache.ttlErodeOffers,
    );
    if (raw == null) return null;

    final records = raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList()
      ..sort((a, b) => ((b['__createdAtMs'] as int?) ?? 0)
          .compareTo((a['__createdAtMs'] as int?) ?? 0));

    return records
        .map((m) => _OfferRecord(
              id: (m['__id'] as String?) ?? '',
              data: Map<String, dynamic>.from(m)
                ..remove('__id')
                ..remove('__createdAtMs'),
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    // CACHE-FIRST (Aug 11 2026 — Nizam's Spark read-budget hardening):
    // this was a live .snapshots() stream on a collection rendered on
    // the customer dashboard, i.e. loaded by every customer on nearly
    // every app open. A live stream bills per document delivered AND
    // re-bills whenever anything changes, so N offers x every open x
    // every customer came straight out of the 50K reads/day Spark
    // budget — for content that realistically changes once a week.
    // Now a one-shot .get() behind a 1-hour Hive cache: a customer
    // opening the app ten times in an hour costs ONE read instead of
    // ten streams. HiveCache.cachedFetch also serves stale data if the
    // fetch throws, so offers still render if we ever hit the daily
    // read ceiling. Admin edits show up within the hour (acceptable
    // for promo content — and admins can pull-to-refresh the dashboard
    // to force it sooner).
    return FutureBuilder<List<_OfferRecord>?>(
      future: _loadOffers(),
      // FIX (root cause of "Could not load offers, please try again
      // later" — live bug, security rules were already correctly
      // deployed by this point): a Firestore query combining an
      // equality filter (.where('active', isEqualTo: true)) with an
      // .orderBy() on a DIFFERENT field (createdAt) requires a
      // composite index — Firestore does NOT auto-create these, unlike
      // single-field indexes. No such index existed for erode_offers
      // (confirmed: zero entries in firestore.indexes.json), so this
      // stream was throwing `[cloud_firestore/failed-precondition] The
      // query requires an index...` on every single load — surfacing
      // as snapshot.hasError below, which is exactly this UI's "Could
      // not load offers" message. This is a DIFFERENT failure mode
      // from the earlier rules-deployment bug (permission-denied vs.
      // failed-precondition) that happened to produce the identical
      // symptom. Dropping .orderBy() here — keeping only the
      // single-field .where('active', ...) filter, which Firestore
      // always auto-indexes — removes the composite-index requirement
      // entirely, so this feature can never break this way again
      // regardless of whether an index gets deployed. Sorting is done
      // client-side instead, right after the docs list is built below.
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator(color: _offerPink)),
          );
        }
        if (snapshot.hasError) {
          // Was previously silent — no debugPrint at all — so a future
          // regression here would be just as invisible as this one was.
          debugPrint('ErodeOffersSection: stream error -> ${snapshot.error}');
          return _emptyState(
            icon: Icons.error_outline_rounded,
            title: 'Could not load offers',
            subtitle: 'Please try again in a moment.',
          );
        }
        final docs = snapshot.data ?? const <_OfferRecord>[];
        if (docs.isEmpty) {
          return _emptyState(
            icon: Icons.storefront_rounded,
            title: 'No offers right now',
            subtitle: 'Check back soon — Erode shop offers appear here.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_offerPurple, _offerPink],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_offer_rounded, color: Colors.white, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Live offers from shops around Erode',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...docs.map((doc) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _OfferCard(offerId: doc.id, data: doc.data),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _offerPink.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Icon(icon, color: _offerMuted, size: 40),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.outfit(color: _offerInk, fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(color: _offerMuted, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final String offerId;
  final Map<String, dynamic> data;

  const _OfferCard({required this.offerId, required this.data});

  @override
  Widget build(BuildContext context) {
    final shopName = (data['shopName'] as String?) ?? 'Shop';
    final offerPercent = data['offerPercent'];
    final validTill = data['validTill'];
    final imageUrl = data['imageUrl'] as String?;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => OfferDetailScreen(offerId: offerId, data: data)),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _offerPink.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(color: _offerPink.withValues(alpha: 0.10), blurRadius: 16, offset: const Offset(0, 8)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_offerPink, _offerPurple]),
                borderRadius: BorderRadius.circular(16),
                image: (imageUrl != null && imageUrl.isNotEmpty)
                    ? DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover)
                    : null,
              ),
              alignment: Alignment.center,
              child: (imageUrl != null && imageUrl.isNotEmpty)
                  ? null
                  : Text(
                      offerPercent != null ? '$offerPercent%' : 'OFFER',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: _offerPink,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatValidTill(validTill),
                    style: GoogleFonts.outfit(color: _offerMuted, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _offerMuted),
          ],
        ),
      ),
    );
  }

  String _formatValidTill(validTill) {
    if (validTill is Timestamp) {
      final d = validTill.toDate();
      return 'Valid till ${d.day}/${d.month}/${d.year}';
    }
    if (validTill is String && validTill.isNotEmpty) {
      return 'Valid till $validTill';
    }
    return 'Limited period offer';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('offerId', offerId));
    properties.add(DiagnosticsProperty<Map<String, dynamic>>('data', data));
  }
}

class OfferDetailScreen extends StatelessWidget {
  final String offerId;
  final Map<String, dynamic> data;

  const OfferDetailScreen({required this.offerId, required this.data, super.key});

  @override
  Widget build(BuildContext context) {
    final shopName = (data['shopName'] as String?) ?? 'Shop';
    final offerPercent = data['offerPercent'];
    final validTill = data['validTill'];
    final address = (data['address'] as String?) ?? '';
    final phone = (data['phone'] as String?) ?? '';
    final lat = data['lat'];
    final lng = data['lng'];
    final imageUrl = data['imageUrl'] as String?;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF6FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF6FA),
        elevation: 0,
        iconTheme: const IconThemeData(color: _offerInk),
        title: Text('Offer Details', style: GoogleFonts.outfit(color: _offerInk, fontWeight: FontWeight.w800)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // NEW (CTO mandate — Erode Offers image + map pin): shows
            // the shop photo admin uploaded, so the customer can
            // recognise the shop's storefront on sight. Only rendered
            // when an offer actually has one — older offers created
            // before this feature simply skip straight to the gradient
            // banner below.
            if (imageUrl != null && imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.network(
                  imageUrl,
                  width: double.infinity,
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            if (imageUrl != null && imageUrl.isNotEmpty) const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_offerPurple, _offerPink]),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shopName,
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      offerPercent != null ? '$offerPercent% OFF' : 'SPECIAL OFFER',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _detailTile(
              icon: Icons.event_available_rounded,
              label: 'Valid Till',
              value: _formatValidTillFull(validTill),
            ),
            const SizedBox(height: 12),
            _detailTile(
              icon: Icons.location_on_rounded,
              label: 'Address',
              value: address.isNotEmpty ? address : 'Not provided',
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                if (phone.isNotEmpty)
                  Expanded(
                    child: _actionButton(
                      icon: Icons.call_rounded,
                      label: 'Call Shop',
                      colors: const [Color(0xFF00C853), Color(0xFF00A843)],
                      onTap: () => _launchPhone(phone),
                    ),
                  ),
                if (phone.isNotEmpty && lat != null && lng != null) const SizedBox(width: 12),
                if (lat != null && lng != null)
                  Expanded(
                    child: _actionButton(
                      icon: Icons.map_rounded,
                      label: 'View Location',
                      colors: const [_offerPurple, _offerPink],
                      onTap: () => _launchStreetView(lat, lng),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatValidTillFull(validTill) {
    if (validTill is Timestamp) {
      final d = validTill.toDate();
      return '${d.day}/${d.month}/${d.year}';
    }
    if (validTill is String && validTill.isNotEmpty) return validTill;
    return 'Limited period offer';
  }

  Widget _detailTile({required IconData icon, required String label, required String value}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _offerPink.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _offerPink, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.outfit(color: _offerMuted, fontSize: 11.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(value, style: GoogleFonts.outfit(color: _offerInk, fontSize: 14.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 6),
            Text(label, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Future<void> _launchPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _launchStreetView(lat, lng) async {
    final uri = Uri.parse('https://www.google.com/maps?layer=c&cbll=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('offerId', offerId));
    properties.add(DiagnosticsProperty<Map<String, dynamic>>('data', data));
  }
}
