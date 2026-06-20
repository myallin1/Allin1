import 'dart:async';
import 'package:flutter/material.dart';

class BannerAdsSlider extends StatefulWidget {
  final List<String> imageUrls;
  final double height;
  final double viewportFraction;

  const BannerAdsSlider({
    super.key,
    required this.imageUrls,
    this.height = 140,
    this.viewportFraction = 0.95,
  });

  @override
  State<BannerAdsSlider> createState() => _BannerAdsSliderState();
}

class _BannerAdsSliderState extends State<BannerAdsSlider> {
  late final PageController _pageController;
  Timer? _timer;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: widget.viewportFraction);
    _timer = Timer.periodic(const Duration(seconds: 3), (Timer timer) {
      if (!mounted) return;
      setState(() {
        _currentPage = (_currentPage < widget.imageUrls.length - 1) ? _currentPage + 1 : 0;
        if (_pageController.hasClients) {
          _pageController.animateToPage(
            _currentPage,
            duration: const Duration(milliseconds: 400),
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
        onPageChanged: (int page) => setState(() => _currentPage = page),
        itemCount: widget.imageUrls.length,
        itemBuilder: (context, index) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 6.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 5))
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.network(
                widget.imageUrls[index],
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFFFFECF6),
                  child: const Center(child: Icon(Icons.broken_image, color: Color(0xFFFF4FA3))),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
