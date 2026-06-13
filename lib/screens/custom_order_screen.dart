// ================================================================
// CUSTOM ORDER CONCIERGE — Ultra-Premium Rewrite
// dart:ui required for ImageFilter (glassmorphism)
// Dark purple/pink theme · NJ Tech Super App
// ================================================================
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'biriyani_menu_screen.dart';

// ── Theme tokens ─────────────────────────────────────────────────
const Color _coBg      = Color(0xFF0C0A14);
const Color _coSurface = Color(0xFF15121F);
const Color _coPink    = Color(0xFFFF4FA3);
const Color _coPinkDark= Color(0xFFCC2070);
const Color _coWhite   = Colors.white;
const Color _coMuted   = Color(0xFF7A6E96);
const Color _coBorder  = Color(0x33FF4FA3);
const Color _coGold    = Color(0xFFFFBB33);

// ── Contact ───────────────────────────────────────────────────────
const String _phone    = '919597879191';
const String _phoneDisplay = '+91 9597879191';

// ── Hero banner slides ────────────────────────────────────────────
class _Slide {
  final String title, subtitle, emoji, imageUrl;
  final List<Color> colors;
  const _Slide(this.title, this.subtitle, this.emoji, this.imageUrl, this.colors);
}

const List<_Slide> _slides = [
  _Slide(
    'Manpower Booking',
    'Quick helpers for urgent local work',
    '👷',
    'https://images.unsplash.com/photo-1504307651254-35680f356dfd?w=800&q=80&fit=crop',
    [Color(0xFFFF4FA3), Color(0xFF7A5CFF)],
  ),
  _Slide(
    'Midnight Food Delivery',
    'Late-night cravings across Erode',
    '🌙',
    'https://images.unsplash.com/photo-1476224203421-9ac39bcb3327?w=800&q=80&fit=crop',
    [Color(0xFF7A5CFF), Color(0xFF00C4FF)],
  ),
  _Slide(
    'Fresh Catch Daily',
    'Farm-to-table seafood, Erode fresh',
    '🐟',
    'https://images.unsplash.com/photo-1534787238916-9ba6764efd4f?w=800&q=80&fit=crop',
    [Color(0xFF0090D4), Color(0xFF00E5A0)],
  ),
];

// ── Category data ─────────────────────────────────────────────────
class _Category {
  final String key, emoji, title, subtitle, imageUrl, whatsAppMsg;
  final List<Color> grad;
  final bool isBiriyani;
  const _Category({
    required this.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.grad,
    this.whatsAppMsg = '',
    this.isBiriyani = false,
  });
}

const List<_Category> _categories = [
  _Category(
    key: 'manpower',
    emoji: '👷',
    title: 'Manpower Support',
    subtitle: 'Helpers for any urgent work',
    imageUrl: 'https://images.unsplash.com/photo-1504307651254-35680f356dfd?w=600&q=80&fit=crop',
    grad: [Color(0xFFFF4FA3), Color(0xFF9B30FF)],
    whatsAppMsg: 'Hi NJ Tech! I need Manpower Support. Please help me book helpers urgently.',
  ),
  _Category(
    key: 'medicine',
    emoji: '💊',
    title: 'Medicine Delivery',
    subtitle: 'Medicines to your doorstep',
    imageUrl: 'https://images.unsplash.com/photo-1584308666744-24d5c474f2ae?w=600&q=80&fit=crop',
    grad: [Color(0xFF7A5CFF), Color(0xFF00C4FF)],
    whatsAppMsg: 'Hi NJ Tech! I need Medicine Delivery to my home. Please assist.',
  ),
  _Category(
    key: 'fish',
    emoji: '🐟',
    title: 'Fresh Fishes',
    subtitle: 'Daily fresh catch, Erode',
    imageUrl: 'https://images.unsplash.com/photo-1534787238916-9ba6764efd4f?w=600&q=80&fit=crop',
    grad: [Color(0xFF0090D4), Color(0xFF00E5A0)],
    whatsAppMsg: 'Hi NJ Tech! I want to order Fresh Fish. Please confirm today\'s catch and price.',
  ),
  _Category(
    key: 'meat',
    emoji: '🥩',
    title: 'Fresh Meats',
    subtitle: 'Quality cuts, same-day delivery',
    imageUrl: 'https://images.unsplash.com/photo-1607623814075-e51df1bdc82f?w=600&q=80&fit=crop',
    grad: [Color(0xFFE53935), Color(0xFFFF8A65)],
    whatsAppMsg: 'Hi NJ Tech! I want to order Fresh Meat. Please share today\'s cuts and pricing.',
  ),
  _Category(
    key: 'biriyani',
    emoji: '🍛',
    title: 'Variety Biriyani',
    subtitle: 'Bulk & party orders welcome',
    imageUrl: 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=600&q=80&fit=crop',
    grad: [Color(0xFFFF8A00), Color(0xFFFFBB44)],
    isBiriyani: true,
  ),
];

// ================================================================
// MAIN SCREEN
// ================================================================
class CustomOrderScreen extends StatefulWidget {
  const CustomOrderScreen({super.key});
  @override
  State<CustomOrderScreen> createState() => _CustomOrderScreenState();
}

class _CustomOrderScreenState extends State<CustomOrderScreen> {
  final PageController _pageCtrl = PageController(viewportFraction: 0.90);
  Timer? _timer;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_pageCtrl.hasClients) return;
      final next = (_current + 1) % _slides.length;
      _pageCtrl.animateToPage(next,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _openWhatsApp() async {
    final msg = Uri.encodeComponent(
        'Hi NJ Tech! I need a custom order. My location is: [Please attach]. Listening for my voice note...');
    final uri = Uri.parse('https://wa.me/$_phone?text=$msg');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Unable to open WhatsApp right now.'),
          backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _callNow() async {
    if (!await launchUrl(Uri.parse('tel:+$_phone')) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Unable to start the call right now.'),
          backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _coBg,
      appBar: AppBar(
        backgroundColor: _coBg,
        elevation: 0,
        leading: const BackButton(color: _coWhite),
        title: Text('Custom Order Concierge',
            style: GoogleFonts.outfit(
                color: _coWhite, fontWeight: FontWeight.w800)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _coPink.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _coBorder),
            ),
            child: Text('LIVE',
                style: GoogleFonts.outfit(
                    color: _coPink, fontSize: 10, fontWeight: FontWeight.w800)),
          )
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Hero Carousel ────────────────────────────────
              SizedBox(
                height: 240,
                child: PageView.builder(
                  controller: _pageCtrl,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _current = i),
                  itemBuilder: (ctx, i) {
                    final s = _slides[i];
                    return Padding(
                      padding: const EdgeInsets.only(right: 12, left: 16),
                      child: _HeroBannerCard(slide: s),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),
              // Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_slides.length, (i) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _current == i ? 26 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _current == i
                          ? _coPink
                          : _coPink.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 24),

              // ── Headline tagline ─────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _coSurface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: _coBorder),
                  ),
                  child: Text(
                    'We deliver anything in Erode.\nJust ask — we\'ll handle it. 🚀',
                    style: GoogleFonts.outfit(
                        color: _coWhite,
                        fontSize: 19,
                        height: 1.4,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Action CTAs ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Expanded(
                    child: _ActionBtn(
                      emoji: '💬',
                      label: 'WhatsApp',
                      sublabel: 'Send voice note',
                      grad: const LinearGradient(
                          colors: [Color(0xFF25D366), Color(0xFF128C7E)]),
                      onTap: _openWhatsApp,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionBtn(
                      emoji: '📞',
                      label: 'Call Now',
                      sublabel: _phoneDisplay,
                      grad: LinearGradient(colors: [_coPink, _coPinkDark]),
                      onTap: _callNow,
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 28),

              // ── Categories header ────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Our Special Categories',
                        style: GoogleFonts.outfit(
                            color: _coWhite,
                            fontSize: 18,
                            fontWeight: FontWeight.w900)),
                    const Spacer(),
                    Text('Tap to order',
                        style: GoogleFonts.outfit(
                            color: _coMuted, fontSize: 12)),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ── Premium Category Cards ────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // Row 1 — Manpower + Medicine
                    Row(children: [
                      Expanded(child: _PremiumCategoryCard(cat: _categories[0])),
                      const SizedBox(width: 12),
                      Expanded(child: _PremiumCategoryCard(cat: _categories[1])),
                    ]),
                    const SizedBox(height: 12),
                    // Row 2 — Fish + Meat
                    Row(children: [
                      Expanded(child: _PremiumCategoryCard(cat: _categories[2])),
                      const SizedBox(width: 12),
                      Expanded(child: _PremiumCategoryCard(cat: _categories[3])),
                    ]),
                    const SizedBox(height: 12),
                    // Row 3 — Biriyani full-width
                    _PremiumCategoryCard(cat: _categories[4], fullWidth: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
// HERO BANNER CARD
// ================================================================
class _HeroBannerCard extends StatelessWidget {
  final _Slide slide;
  const _HeroBannerCard({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
              color: slide.colors.first.withValues(alpha: 0.3),
              blurRadius: 24,
              offset: const Offset(0, 14))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(children: [
          // Bg image
          Positioned.fill(
            child: Image.network(
              slide.imageUrl,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, p) => p == null
                  ? child
                  : Container(
                      color: _coSurface,
                      child: Center(
                          child: Text(slide.emoji,
                              style: const TextStyle(fontSize: 64)))),
              errorBuilder: (_, __, ___) => Container(
                color: _coSurface,
                child: Center(
                    child:
                        Text(slide.emoji, style: const TextStyle(fontSize: 64))),
              ),
            ),
          ),
          // Gradient overlay
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    slide.colors.first.withValues(alpha: 0.5),
                    slide.colors.last.withValues(alpha: 0.85),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          // Content
          Positioned(
            left: 20, right: 20, bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text('Concierge Service',
                      style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
                Text(slide.title,
                    style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        height: 1.1)),
                const SizedBox(height: 4),
                Text(slide.subtitle,
                    style: GoogleFonts.outfit(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 13)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ================================================================
// ACTION BUTTON
// ================================================================
class _ActionBtn extends StatelessWidget {
  final String emoji, label, sublabel;
  final Gradient grad;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.emoji,
      required this.label,
      required this.sublabel,
      required this.grad,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: grad,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 8))
          ],
        ),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(height: 4),
          Text(label,
              style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
          Text(sublabel,
              style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 10)),
        ]),
      ),
    );
  }
}

// ================================================================
// PREMIUM CATEGORY CARD — StatefulWidget with image + tap logic
// ================================================================
class _PremiumCategoryCard extends StatefulWidget {
  final _Category cat;
  final bool fullWidth;
  const _PremiumCategoryCard({required this.cat, this.fullWidth = false});
  @override
  State<_PremiumCategoryCard> createState() => _PremiumCategoryCardState();
}

class _PremiumCategoryCardState extends State<_PremiumCategoryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.96)
        .animate(CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  Future<void> _tap(BuildContext context) async {
    await _scaleCtrl.forward();
    await _scaleCtrl.reverse();

    if (!context.mounted) return;

    if (widget.cat.isBiriyani) {
      // Navigate to dedicated Biriyani Menu Screen
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BiriyaniMenuScreen()),
      );
      return;
    }

    // All other categories → pre-filled WhatsApp
    final msg = Uri.encodeComponent(widget.cat.whatsAppMsg);
    final uri = Uri.parse('https://wa.me/$_phone?text=$msg');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)
        && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Unable to open WhatsApp right now.'),
          backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.cat;
    final double height = widget.fullWidth ? 175 : 160;
    final double glassHeight = widget.fullWidth ? 80 : 70;

    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTap: () => _tap(context),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              // Deep ambient shadow
              BoxShadow(
                  color: cat.grad.first.withValues(alpha: 0.40),
                  blurRadius: 24,
                  spreadRadius: 1,
                  offset: const Offset(0, 10)),
              // Subtle dark base
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.30),
                  blurRadius: 8,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(children: [

              // ── Layer 1: Background photo ──────────────────
              Positioned.fill(
                child: Image.network(
                  cat.imageUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, p) => p == null
                      ? child
                      : Container(
                          color: _coSurface,
                          child: Center(
                            child: Text(cat.emoji,
                                style: const TextStyle(fontSize: 48)),
                          )),
                  errorBuilder: (_, __, ___) => Container(
                    color: _coSurface,
                    child: Center(
                      child: Text(cat.emoji,
                          style: const TextStyle(fontSize: 48)),
                    ),
                  ),
                ),
              ),

              // ── Layer 2: Top accent shimmer strip ──────────
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        cat.grad.first.withValues(alpha: 0.0),
                        cat.grad.first,
                        cat.grad.last,
                        cat.grad.last.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.3, 0.7, 1.0],
                    ),
                  ),
                ),
              ),

              // ── Layer 3: Biriyani 4-image collage ──────────
              if (cat.isBiriyani) const _BiriyaniCollageOverlay(),

              // ── Layer 4: Scrim — darkens bg for glass panel ─
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.10),
                        Colors.black.withValues(alpha: 0.55),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),

              // ── Layer 5: Glassmorphism info panel (bottom) ─
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      height: glassHeight,
                      decoration: BoxDecoration(
                        // frosted glass tint
                        color: cat.grad.first.withValues(alpha: 0.18),
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 1,
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Emoji avatar bubble
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  width: 1),
                            ),
                            child: Center(
                              child: Text(cat.emoji,
                                  style: TextStyle(
                                      fontSize: widget.fullWidth ? 20 : 17)),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Text block
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  cat.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: widget.fullWidth ? 16 : 13,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.1),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  cat.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                      color: Colors.white.withValues(alpha: 0.72),
                                      fontSize: 10),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 8),

                          // CTA badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  cat.grad.first,
                                  cat.grad.last,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(99),
                              boxShadow: [
                                BoxShadow(
                                    color:
                                        cat.grad.first.withValues(alpha: 0.5),
                                    blurRadius: 10)
                              ],
                            ),
                            child: Text(
                              cat.isBiriyani ? 'MENU ›' : 'ORDER ›',
                              style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ================================================================
// BIRIYANI COLLAGE OVERLAY — frosted-glass 4-image mini grid
// ================================================================
class _BiriyaniCollageOverlay extends StatelessWidget {
  static const _imgs = [
    'https://images.unsplash.com/photo-1701579231349-d7459eba1fd1?w=200&q=60&fit=crop',
    'https://images.unsplash.com/photo-1589302168068-964664d93dc0?w=200&q=60&fit=crop',
    'https://images.unsplash.com/photo-1603133872878-684f208fb84b?w=200&q=60&fit=crop',
    'https://images.unsplash.com/photo-1645177628172-a94c1f96e6db?w=200&q=60&fit=crop',
  ];

  const _BiriyaniCollageOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12, right: 12,
      child: Container(
        // Outer glass ring
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [Color(0x55FFFFFF), Color(0x11FFFFFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 12,
                spreadRadius: 1),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: SizedBox(
              width: 72, height: 72,
              child: GridView.count(
                crossAxisCount: 2,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                mainAxisSpacing: 1.5,
                crossAxisSpacing: 1.5,
                children: _imgs
                    .map((url) => Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(color: const Color(0xFFFF8A00)),
                        ))
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
