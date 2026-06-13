import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color _promoPink = Color(0xFFFF4FA3);
const Color _promoPinkSoft = Color(0xFFFF7ABA);
const Color _promoWhite = Color(0xFFFFFBFE);
const Color _promoTextDark = Color(0xFF4A1030);

class PromoOfferItem {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool claimed;
  final String buttonLabel;
  final String claimedButtonLabel;
  final String statusLabel;

  const PromoOfferItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.claimed,
    this.buttonLabel = 'Claim Now',
    this.claimedButtonLabel = 'Claimed',
    this.statusLabel = 'Limited Offer',
  });
}

class PromoOverlay extends StatelessWidget {
  final List<PromoOfferItem> offers;
  final ValueChanged<String> onClaim;
  final VoidCallback onClose;

  const PromoOverlay({
    required this.offers, required this.onClaim, required this.onClose, super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  decoration: BoxDecoration(
                    color: _promoWhite,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66FF4FA3),
                        blurRadius: 30,
                        spreadRadius: 2,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [_promoPink, _promoPinkSoft],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.local_activity_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'NJ Tech Special Offers',
                                  style: GoogleFonts.outfit(
                                    color: _promoTextDark,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Claim your launch offers and unlock extra value across Allin1.',
                                  style: GoogleFonts.outfit(
                                    color: _promoTextDark.withValues(alpha: 0.68),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: onClose,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: _promoTextDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      ...offers.map(
                        (offer) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _PromoOfferCard(
                            offer: offer,
                            onClaim: () => onClaim(offer.id),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pink & white NJ Tech launch specials',
                        style: GoogleFonts.outfit(
                          color: _promoTextDark.withValues(alpha: 0.52),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(IterableProperty<PromoOfferItem>('offers', offers));
    properties.add(ObjectFlagProperty<ValueChanged<String>>.has('onClaim', onClaim));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onClose', onClose));
  }
}

class _PromoOfferCard extends StatelessWidget {
  final PromoOfferItem offer;
  final VoidCallback onClaim;

  const _PromoOfferCard({
    required this.offer,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = offer.claimed
        ? const [Color(0xFFFFD7E8), Color(0xFFFFECF5)]
        : const [Color(0xFFFF4FA3), Color(0xFFFF9BC9)];

    final buttonColor = offer.claimed ? const Color(0xFFE7C5D6) : _promoWhite;
    final buttonTextColor =
        offer.claimed ? _promoTextDark.withValues(alpha: 0.7) : _promoPink;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: _promoWhite.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x29FFFFFF),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(
              offer.icon,
              color: _promoPink,
              size: 40,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _promoWhite.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    offer.claimed ? 'Requested' : offer.statusLabel,
                    style: GoogleFonts.outfit(
                      color: _promoPink,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  offer.title,
                  style: GoogleFonts.outfit(
                    color: _promoWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  offer.subtitle,
                  style: GoogleFonts.outfit(
                    color: _promoWhite.withValues(alpha: 0.88),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: ElevatedButton(
              onPressed: offer.claimed ? null : onClaim,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: buttonColor,
                disabledBackgroundColor: buttonColor,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Text(
                offer.claimed ? offer.claimedButtonLabel : offer.buttonLabel,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: buttonTextColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<PromoOfferItem>('offer', offer));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onClaim', onClaim));
  }
}
