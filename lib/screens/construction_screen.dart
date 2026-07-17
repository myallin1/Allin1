// ================================================================
// construction_screen.dart — Usha Constructions
// Premium NJ Tech Pink Dark Theme — May 2026
// ================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

// ── Brand constants ───────────────────────────────────────────────
const Color _kPink = Color(0xFFFF4FA3);
const Color _kDark = Color(0xFF130B28);
const Color _kDark2 = Color(0xFF1E0E3E);
const Color _kCard = Color(0xFF1E1040);
const Color _kMuted = Color(0xFF9999BB);
const Color _kGold = Color(0xFFFFBB00);
const Color _kGreen = Color(0xFF00C853);

const String _phone = '+918681869091';
const String _telUri = 'tel:+918681869091';
const String _waUri = 'https://wa.me/918681869091';

// ── Service data ─────────────────────────────────────────────────
const _services = [
  _ConstructionService(
    title: 'Building Planning',
    subtitle:
        'Expert architectural planning, 3D blueprints & structural design for your dream home',
    price: 'Free Quote',
    badge: 'MOST BOOKED',
    badgeColor: _kGold,
    imageUrl:
        'https://images.unsplash.com/photo-1503387762-592deb58ef4e?w=800&q=80',
    features: [
      '3D Blueprint',
      'Vastu Compliance',
      'Govt Approval Help',
      'Timeline Plan',
    ],
  ),
  _ConstructionService(
    title: 'Renovation & Repair',
    subtitle:
        'Full home renovation, crack repair, waterproofing & structural strengthening',
    price: 'Call for Quotation',
    badge: 'BEST VALUE',
    badgeColor: _kGreen,
    imageUrl:
        'https://images.unsplash.com/photo-1581578731548-c64695cc6952?w=800&q=80',
    features: ['Waterproofing', 'Wall Repair', 'Flooring', 'Painting'],
  ),
  _ConstructionService(
    title: 'Interior Design',
    subtitle:
        'Premium modular kitchen, false ceiling, wardrobes & complete home styling',
    price: 'Call for Quotation',
    badge: 'PREMIUM',
    badgeColor: _kPink,
    imageUrl:
        'https://images.unsplash.com/photo-1600210492486-724fe5c67fb0?w=800&q=80',
    features: [
      'Modular Kitchen',
      'False Ceiling',
      'Wardrobes',
      '3D Walkthrough',
    ],
  ),
];

// ── Data model ───────────────────────────────────────────────────
class _ConstructionService {
  final String title, subtitle, price, badge, imageUrl;
  final Color badgeColor;
  final List<String> features;
  const _ConstructionService({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.badge,
    required this.badgeColor,
    required this.imageUrl,
    required this.features,
  });
}

// ================================================================
// SCREEN
// ================================================================
class ConstructionScreen extends StatelessWidget {
  const ConstructionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kDark,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildAppBar(context),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _ServiceCard(service: _services[i]),
                childCount: _services.length,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomContactBar(),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: _kDark,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: Colors.white,
          size: 20,
        ),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
        title: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Usha',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            Text(
              'Constructions 🏗️',
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _kPink,
              ),
            ),
          ],
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              'https://images.unsplash.com/photo-1503387762-592deb58ef4e?w=800&q=80',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: _kDark2),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    _kDark.withValues(alpha: 0.95),
                  ],
                ),
              ),
            ),
            // Gold glow accent (construction = gold feel)
            Positioned(
              top: 20,
              right: 20,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kGold.withValues(alpha: 0.12),
                  boxShadow: [
                    BoxShadow(
                      color: _kGold.withValues(alpha: 0.25),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// SERVICE CARD
// ================================================================
class _ServiceCard extends StatelessWidget {
  final _ConstructionService service;
  const _ServiceCard({required this.service});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kPink.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: _kPink.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Image with badge + price overlay ─────────────────
          Stack(
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                child: Image.network(
                  service.imageUrl,
                  height: 190,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : Container(
                          height: 190,
                          color: _kDark2,
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: _kPink,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                  errorBuilder: (_, __, ___) => Container(
                    height: 190,
                    color: _kDark2,
                    child: const Center(
                      child: Icon(
                        Icons.construction_rounded,
                        color: _kPink,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),
              // Badge
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: service.badgeColor,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: service.badgeColor.withValues(alpha: 0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Text(
                    service.badge,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              // Price
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _kDark.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kPink.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    service.price,
                    style: GoogleFonts.outfit(
                      color: _kPink,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              // Bottom fade
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        _kCard.withValues(alpha: 0.7),
                      ],
                      stops: const [0.55, 1.0],
                    ),
                  ),
                ),
              ),
            ],
          ),
          // ── Text content ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.title,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  service.subtitle,
                  style: const TextStyle(
                    color: _kMuted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: service.features
                      .map(
                        (f) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _kPink.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _kPink.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            f,
                            style: const TextStyle(
                              color: _kPink,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        label: '📞  Call Now',
                        color: _kPink,
                        onTap: () => _launch(_telUri),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionButton(
                        label: '💬  WhatsApp',
                        color: const Color(0xFF25D366),
                        onTap: () => _launch(_waUri),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
        .add(DiagnosticsProperty<_ConstructionService>('service', service));
  }
}

// ================================================================
// SHARED WIDGETS & HELPERS (construction_screen.dart)
// ================================================================
class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('label', label))
      ..add(ColorProperty('color', color))
      ..add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}

class _BottomContactBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: _kCard,
        border: Border(top: BorderSide(color: _kPink.withValues(alpha: 0.2))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.construction_rounded, color: _kPink, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Get a Quote',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text(
                _phone,
                style: TextStyle(color: _kMuted, fontSize: 10),
              ),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => _launch(_telUri),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _kPink,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: _kPink.withValues(alpha: 0.4),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Text(
                '📞  Call',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _launch(_waUri),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF25D366),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF25D366).withValues(alpha: 0.4),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Text(
                '💬  WA',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _launch(String uriStr) async {
  final uri = Uri.parse(uriStr);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
