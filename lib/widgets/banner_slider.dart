import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A text-only promo slide (e.g. "Internet Offers") rendered as a
/// gradient card, mixed into the same auto-scrolling PageView as the
/// image slides below. Kept separate from [imageUrls] so callers don't
/// need a hosted image just to advertise a text-only offer.
class BannerTextSlide {
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final IconData icon;
  // NEW (per Nizam's request — "internet offer option thotta nammaloda
  // internet option kulla poganum"): optional tap target so a text
  // slide (e.g. "Internet Offers 🌐") can actually navigate somewhere.
  // Purely additive — slides that don't pass this stay non-interactive,
  // same as before.
  final VoidCallback? onTap;

  const BannerTextSlide({
    required this.title,
    this.subtitle = '',
    this.gradient = const [Color(0xFFFF4FA3), Color(0xFF7B2FF7)],
    this.icon = Icons.local_offer_rounded,
    this.onTap,
  });
}

class BannerAdsSlider extends StatefulWidget {
  final List<String> imageUrls;
  final List<BannerTextSlide> textSlides;
  final double height;
  final double viewportFraction;

  const BannerAdsSlider({
    required this.imageUrls, super.key,
    this.textSlides = const [],
    this.height = 140,
    this.viewportFraction = 0.95,
  });

  @override
  State<BannerAdsSlider> createState() => _BannerAdsSliderState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(IterableProperty<String>('imageUrls', imageUrls));
    properties.add(DoubleProperty('height', height));
    properties.add(DoubleProperty('viewportFraction', viewportFraction));
  }
}

class _BannerAdsSliderState extends State<BannerAdsSlider> {
  late final PageController _pageController;
  Timer? _timer;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: widget.viewportFraction);
    // FIX (Aug 12 2026 — Nizam: "one by one ah slow va move aaguramari set
    // pannlam" for the new 10-slide promo set): slowed the auto-scroll from
    // 3s/400ms to 5s/700ms so each slide sits on screen long enough to
    // actually read before it moves on, with a gentler glide between slides.
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) return;
      final total = widget.textSlides.length + widget.imageUrls.length;
      if (total <= 1) return;
      setState(() {
        _currentPage = (_currentPage < total - 1) ? _currentPage + 1 : 0;
        if (_pageController.hasClients) {
          _pageController.animateToPage(
            _currentPage,
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeInOut,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: (page) => setState(() => _currentPage = page),
        itemCount: widget.textSlides.length + widget.imageUrls.length,
        itemBuilder: (context, index) {
          if (index < widget.textSlides.length) {
            final slide = widget.textSlides[index];
            final card = Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: slide.gradient,
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 5)),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Icon(slide.icon, color: Colors.white, size: 34),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            slide.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (slide.subtitle.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              slide.subtitle,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
            return slide.onTap == null
                ? card
                : GestureDetector(onTap: slide.onTap, child: card);
          }
          final imageIndex = index - widget.textSlides.length;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 5)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.network(
                widget.imageUrls[imageIndex],
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: Color(0xFFFFECF6),
                  child: Center(child: Icon(Icons.broken_image, color: Color(0xFFFF4FA3))),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
