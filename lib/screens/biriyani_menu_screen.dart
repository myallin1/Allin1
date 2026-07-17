// ================================================================
// BIRIYANI MENU SCREEN
// Ultra-premium mouth-watering experience for the Super App
// ================================================================
import 'dart:async';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

// ── Theme tokens (dark) ─────────────────────────────────────────
const Color _bBg = Color(0xFF0C0A14);
const Color _bSurface = Color(0xFF15121F);
const Color _bPink = Color(0xFFFF4FA3);
const Color _bGold = Color(0xFFFFBB33);
const Color _bOrange = Color(0xFFFF8A00);
const Color _bGreen = Color(0xFF00E5A0);

// ── Contact ──────────────────────────────────────────────────────
const String _bPhone = '+918681869091';

// ── Biriyani data model ──────────────────────────────────────────
class _BiriyaniItem {
  final String name;
  final String tagline;
  final String emoji;
  final String imageUrl; // Unsplash CDN
  final String price;
  final Color accent;

  const _BiriyaniItem({
    required this.name,
    required this.tagline,
    required this.emoji,
    required this.imageUrl,
    required this.price,
    required this.accent,
  });
}

const List<_BiriyaniItem> _biriyanis = [
  _BiriyaniItem(
    name: 'Chicken Biriyani',
    tagline: 'Tender juicy chicken, aged basmati',
    emoji: '🍗',
    imageUrl:
        'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=900&q=85&fit=crop',
    price: '₹180 / plate',
    accent: Color(0xFFFF8A00),
  ),
  _BiriyaniItem(
    name: 'Mutton Biriyani',
    tagline: 'Slow-cooked dum, 4-hour marination',
    emoji: '🥩',
    imageUrl:
        'https://images.unsplash.com/photo-1701579231349-d7459eba1fd1?w=900&q=85&fit=crop',
    price: '₹250 / plate',
    accent: Color(0xFFE53935),
  ),
  _BiriyaniItem(
    name: 'Fish Biriyani',
    tagline: 'Coastal spices, fresh catch of the day',
    emoji: '🐟',
    imageUrl:
        'https://images.unsplash.com/photo-1603133872878-684f208fb84b?w=900&q=85&fit=crop',
    price: '₹200 / plate',
    accent: Color(0xFF0090D4),
  ),
  _BiriyaniItem(
    name: 'Prawn Biriyani',
    tagline: 'Jumbo prawns, aromatic seeraga samba',
    emoji: '🦐',
    imageUrl:
        'https://images.unsplash.com/photo-1589302168068-964664d93dc0?w=900&q=85&fit=crop',
    price: '₹280 / plate',
    accent: Color(0xFFFF4FA3),
  ),
  _BiriyaniItem(
    name: 'Veg Biriyani',
    tagline: 'Garden-fresh veggies, ghee-roasted nuts',
    emoji: '🥦',
    imageUrl:
        'https://images.unsplash.com/photo-1645177628172-a94c1f96e6db?w=900&q=85&fit=crop',
    price: '₹130 / plate',
    accent: Color(0xFF00E5A0),
  ),
];

// ── Screen ───────────────────────────────────────────────────────
class BiriyaniMenuScreen extends StatefulWidget {
  const BiriyaniMenuScreen({super.key});

  @override
  State<BiriyaniMenuScreen> createState() => _BiriyaniMenuScreenState();
}

class _BiriyaniMenuScreenState extends State<BiriyaniMenuScreen>
    with TickerProviderStateMixin {
  int _current = 0;
  final CarouselSliderController _carouselCtrl = CarouselSliderController();
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 1, end: 1.04)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _call() async {
    final uri = Uri.parse('tel:$_bPhone');
    if (!await launchUrl(uri) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not launch dialer'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _whatsApp() async {
    final item = _biriyanis[_current];
    final msg = Uri.encodeComponent(
      'Hi NJ Tech! I want to order ${item.name} (${item.price}). '
      'Please confirm availability and delivery slot. 🍛',
    );
    final uri =
        Uri.parse('https://wa.me/${_bPhone.replaceAll('+', '')}?text=$msg');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open WhatsApp'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _biriyanis[_current];

    return Scaffold(
      backgroundColor: _bBg,
      body: CustomScrollView(
        slivers: [
          // ── SliverAppBar with parallax hero ──────────────────
          SliverAppBar(
            expandedHeight: 130,
            pinned: true,
            backgroundColor: _bBg,
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1A0A2E), Color(0xFF0C0A14)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      const Text('🍛', style: TextStyle(fontSize: 36)),
                      const SizedBox(height: 6),
                      Text(
                        'Variety Biriyani Menu',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Bulk & Party Orders Welcome · Erode',
                        style: GoogleFonts.outfit(
                          color: _bGold,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 20),

                // ── CAROUSEL ────────────────────────────────────
                CarouselSlider.builder(
                  carouselController: _carouselCtrl,
                  itemCount: _biriyanis.length,
                  options: CarouselOptions(
                    height: 360,
                    viewportFraction: 0.85,
                    autoPlay: true,
                    autoPlayInterval: const Duration(seconds: 3),
                    autoPlayAnimationDuration:
                        const Duration(milliseconds: 700),
                    autoPlayCurve: Curves.easeInOutCubic,
                    enlargeCenterPage: true,
                    enlargeFactor: 0.22,
                    onPageChanged: (i, _) => setState(() => _current = i),
                  ),
                  itemBuilder: (ctx, i, realIdx) {
                    final b = _biriyanis[i];
                    final isActive = i == _current;
                    return _BiriyaniCarouselCard(
                      item: b,
                      isActive: isActive,
                    );
                  },
                ),

                const SizedBox(height: 16),

                // ── Dot indicators ───────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _biriyanis.asMap().entries.map((e) {
                    final active = e.key == _current;
                    return GestureDetector(
                      onTap: () => _carouselCtrl.animateToPage(e.key),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: active
                              ? item.accent
                              : Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 28),

                // ── Active item info ─────────────────────────────
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _BiriyaniInfoPanel(
                    key: ValueKey(_current),
                    item: item,
                  ),
                ),

                const SizedBox(height: 32),

                // ── CTA Buttons ──────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      // WhatsApp
                      ScaleTransition(
                        scale: _pulse,
                        child: _BiriyaniCTAButton(
                          label: '💬  WhatsApp to Order',
                          sublabel: 'Pre-filled with your selection',
                          gradient: const LinearGradient(
                            colors: [Color(0xFF25D366), Color(0xFF128C7E)],
                          ),
                          onTap: _whatsApp,
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Call Now
                      _BiriyaniCTAButton(
                        label: '📞  Call Now',
                        sublabel: _bPhone,
                        gradient: const LinearGradient(
                          colors: [
                            _bPink,
                            Color(0xFFFF8AC4),
                          ],
                        ),
                        onTap: _call,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Why Choose us strip ──────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _WhyChooseStrip(),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Carousel Card ────────────────────────────────────────────────
class _BiriyaniCarouselCard extends StatelessWidget {
  final _BiriyaniItem item;
  final bool isActive;
  const _BiriyaniCarouselCard({required this.item, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: isActive ? 1.0 : 0.95,
      duration: const Duration(milliseconds: 300),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            if (isActive)
              BoxShadow(
                color: item.accent.withValues(alpha: 0.45),
                blurRadius: 32,
                spreadRadius: 2,
                offset: const Offset(0, 16),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: [
              // Background image
              Positioned.fill(
                child: Image.network(
                  item.imageUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : ColoredBox(
                          color: _bSurface,
                          child: Center(
                            child: CircularProgressIndicator(
                              color: item.accent,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                  errorBuilder: (_, __, ___) => ColoredBox(
                    color: _bSurface,
                    child: Center(
                      child: Text(
                        item.emoji,
                        style: const TextStyle(fontSize: 72),
                      ),
                    ),
                  ),
                ),
              ),
              // Gradient overlay
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.35),
                        Colors.black.withValues(alpha: 0.85),
                      ],
                      stops: const [0.35, 0.60, 1.0],
                    ),
                  ),
                ),
              ),
              // Price badge top-right
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: item.accent,
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: [
                      BoxShadow(
                        color: item.accent.withValues(alpha: 0.5),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Text(
                    item.price,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              // Bottom content
              Positioned(
                left: 20,
                right: 20,
                bottom: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.emoji,
                      style: const TextStyle(fontSize: 38),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.name,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.tagline,
                      style: GoogleFonts.outfit(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<_BiriyaniItem>('item', item));
    properties.add(DiagnosticsProperty<bool>('isActive', isActive));
  }
}

// ── Info Panel ───────────────────────────────────────────────────
class _BiriyaniInfoPanel extends StatelessWidget {
  final _BiriyaniItem item;
  const _BiriyaniInfoPanel({required this.item, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _bSurface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: item.accent.withValues(alpha: 0.28)),
          boxShadow: [
            BoxShadow(
              color: item.accent.withValues(alpha: 0.08),
              blurRadius: 20,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: item.accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  item.emoji,
                  style: const TextStyle(fontSize: 28),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.tagline,
                    style: GoogleFonts.outfit(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: item.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: item.accent.withValues(alpha: 0.5)),
              ),
              child: Text(
                item.price,
                style: GoogleFonts.outfit(
                  color: item.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<_BiriyaniItem>('item', item));
  }
}

// ── CTA Button ───────────────────────────────────────────────────
class _BiriyaniCTAButton extends StatelessWidget {
  final String label;
  final String sublabel;
  final Gradient gradient;
  final VoidCallback onTap;

  const _BiriyaniCTAButton({
    required this.label,
    required this.sublabel,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              label,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: GoogleFonts.outfit(
                color: Colors.white.withValues(alpha: 0.80),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('label', label));
    properties.add(StringProperty('sublabel', sublabel));
    properties.add(DiagnosticsProperty<Gradient>('gradient', gradient));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}

// ── Why Choose Strip ────────────────────────────────────────────
class _WhyChooseStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = [
      ('🔥', 'Freshly\nCooked'),
      ('🏠', 'Home\nDelivery'),
      ('🎉', 'Bulk &\nParty Orders'),
      ('⚡', 'Same Day\nDelivery'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: _bSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _bGold.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items
            .map(
              (e) => Column(
                children: [
                  Text(e.$1, style: const TextStyle(fontSize: 26)),
                  const SizedBox(height: 6),
                  Text(
                    e.$2,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}
