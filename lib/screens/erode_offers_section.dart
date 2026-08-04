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

const Color _offerInk = Color(0xFF121A3D);
const Color _offerPink = Color(0xFFFF4FA3);
const Color _offerPurple = Color(0xFFB21FFF);
const Color _offerMuted = Color(0xFF6B7280);

class ErodeOffersSection extends StatelessWidget {
  const ErodeOffersSection({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('erode_offers')
          .where('active', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator(color: _offerPink)),
          );
        }
        if (snapshot.hasError) {
          return _emptyState(
            icon: Icons.error_outline_rounded,
            title: 'Could not load offers',
            subtitle: 'Please try again in a moment.',
          );
        }
        final docs = snapshot.data?.docs ?? [];
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
              final data = doc.data();
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _OfferCard(offerId: doc.id, data: data),
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
              ),
              alignment: Alignment.center,
              child: Text(
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
