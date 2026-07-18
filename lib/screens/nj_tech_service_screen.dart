import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

const Color _njSurface = Color(0xFF12121E);
const Color _njCard = Color(0xFF1A1A2A);
const Color _njPink = Color(0xFFFF4FA3);
const Color _njWhite = Color(0xFFFFFBFE);
const Color _njMuted = Color(0xFFB89AB0);
const Color _njBorder = Color(0x1AFFFFFF);
const Color _njGreen = Color(0xFF00C853);
const Color _njRed = Color(0xFFFF5252);

class _ServiceCarouselItem {
  final String title;
  final String subtitle;
  final String emoji;
  final List<Color> colors;

  const _ServiceCarouselItem({
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.colors,
  });
}

const List<_ServiceCarouselItem> _carouselItems = [
  _ServiceCarouselItem(
    title: 'Broken Screen Fix!',
    subtitle: 'Display Replacement',
    emoji: '📱',
    colors: [Color(0xFFFF4FA3), Color(0xFFFF8FC6)],
  ),
  _ServiceCarouselItem(
    title: 'New Battery in 30 Mins!',
    subtitle: 'Battery Change',
    emoji: '🔋',
    colors: [Color(0xFFFF7A59), Color(0xFFFFB199)],
  ),
  _ServiceCarouselItem(
    title: 'Deep Board Diagnosis',
    subtitle: 'IC Repair',
    emoji: '🧰',
    colors: [Color(0xFF6C63FF), Color(0xFFA79BFF)],
  ),
];

class NjTechServiceScreen extends StatefulWidget {
  const NjTechServiceScreen({super.key});

  @override
  State<NjTechServiceScreen> createState() => _NjTechServiceScreenState();
}

class _NjTechServiceScreenState extends State<NjTechServiceScreen> {
  final PageController _pageController = PageController(viewportFraction: 0.92);
  Timer? _carouselTimer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _carouselTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_pageController.hasClients) {
        return;
      }
      final nextIndex = (_currentIndex + 1) % _carouselItems.length;
      _pageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _openWhatsApp() async {
    final uri = Uri.parse(
      'whatsapp://send?phone=+919597879191&text=Hi NJ Tech, I need mobile service.',
    );
    final launched = await launchUrl(uri);
    if (!mounted) {
      return;
    }
    if (!launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open WhatsApp right now.'),
          backgroundColor: _njRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _callNjTech() async {
    final launched = await launchUrl(Uri.parse('tel:+919597879191'));
    if (!mounted) {
      return;
    }
    if (!launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to start the call right now.'),
          backgroundColor: _njRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _njSurface,
      appBar: AppBar(
        backgroundColor: _njSurface,
        elevation: 0,
        leading: const BackButton(color: _njWhite),
        title: Text(
          'NJ Tech Services',
          style: GoogleFonts.outfit(
            color: _njWhite,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 252,
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _carouselItems.length,
                        onPageChanged: (index) {
                          setState(() => _currentIndex = index);
                        },
                        itemBuilder: (context, index) {
                          final item = _carouselItems[index];
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: item.colors,
                                ),
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: item.colors.first
                                        .withValues(alpha: 0.32),
                                    blurRadius: 28,
                                    offset: const Offset(0, 14),
                                  ),
                                ],
                              ),
                              child: Stack(
                                children: [
                                  Positioned(
                                    right: -12,
                                    top: -10,
                                    child: Text(
                                      item.emoji,
                                      style: const TextStyle(fontSize: 108),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(28),
                                        gradient: LinearGradient(
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.topCenter,
                                          colors: [
                                            Colors.black
                                                .withValues(alpha: 0.42),
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 20,
                                    right: 20,
                                    bottom: 22,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.18),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            item.subtitle,
                                            style: GoogleFonts.outfit(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          item.title,
                                          style: GoogleFonts.outfit(
                                            color: Colors.white,
                                            fontSize: 28,
                                            fontWeight: FontWeight.w800,
                                            height: 1.05,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _carouselItems.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentIndex == index ? 22 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _currentIndex == index
                                ? _njPink
                                : Colors.white24,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: _njCard,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: _njBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Get your mobile serviced directly by NJ Tech expert technicians!',
                            style: GoogleFonts.outfit(
                              color: _njWhite,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              height: 1.18,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Display replacement, battery change, IC-level troubleshooting, software fixes, and custom service requests — all handled through one conversion-ready support line.',
                            style: GoogleFonts.outfit(
                              color: _njMuted,
                              fontSize: 14,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 22),
                          _leadButton(
                            label: 'WhatsApp Us',
                            subtitle:
                                'Fast lead capture with a pre-filled service message',
                            icon: Icons.chat_bubble_rounded,
                            color: _njGreen,
                            onTap: _openWhatsApp,
                          ),
                          const SizedBox(height: 14),
                          _leadButton(
                            label: 'Call Us',
                            subtitle: 'Talk directly to NJ Tech support now',
                            icon: Icons.call_rounded,
                            color: _njPink,
                            onTap: _callNjTech,
                          ),
                        ],
                      ),
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

  Widget _topButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: _njCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _njBorder),
        ),
        child: Icon(icon, color: _njWhite, size: 18),
      ),
    );
  }

  Widget _leadButton({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color,
              color.withValues(alpha: 0.78),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(
                      color: Colors.white.withValues(alpha: 0.84),
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(
              Icons.arrow_forward_rounded,
              color: Colors.white,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
