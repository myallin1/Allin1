// ================================================================
// PrintingServiceScreen — "Allin1 Designing and Printing"
// ================================================================
// Restores the Designing & Printing feature (previously wired to a
// "temporarily unavailable" snackbar in dashboard_screen.dart because
// this file had gone missing). Shows an auto-sliding showcase of the
// 5 print categories Nizam listed, then Call + WhatsApp buttons that
// jump straight to the shop's number for customers to place their
// order directly — no in-app order form, this is a lead-generation /
// contact page, not a catalog checkout flow.
// ================================================================
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

const Color _kPink = Color(0xFFFF4FA3);
const Color _kPurple = Color(0xFF7B6FE0);
const Color _kBg = Color(0xFFFFFFFF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF9999BB);
const String _kPhoneNumber = '8681869091';

class _PrintCategory {
  final String label;
  final String imageAsset;
  final List<Color> colors;

  const _PrintCategory({required this.label, required this.imageAsset, required this.colors});
}

// Per-category sample images (assets/images/printing/*.png) — replaces
// the earlier single-color-gradient + generic icon cards per Nizam's
// feedback: he wants each slide to show an actual sample image of that
// particular product, not one flat color repeated across all 5 tiles.
const List<_PrintCategory> _kPrintCategories = [
  _PrintCategory(label: 'Visiting Cards', imageAsset: 'assets/images/printing/visiting_cards.png', colors: [Color(0xFFFF4FA3), Color(0xFF7B6FE0)]),
  _PrintCategory(label: 'Bill Book', imageAsset: 'assets/images/printing/bill_book.png', colors: [Color(0xFFFF8A3D), Color(0xFFFF4FA3)]),
  _PrintCategory(label: 'Brochures', imageAsset: 'assets/images/printing/brochures.png', colors: [Color(0xFF3DBA6F), Color(0xFF11998E)]),
  _PrintCategory(label: 'Flex Printing', imageAsset: 'assets/images/printing/flex_printing.png', colors: [Color(0xFF2979FF), Color(0xFF7B6FE0)]),
  _PrintCategory(label: 'Stickers', imageAsset: 'assets/images/printing/stickers.png', colors: [Color(0xFFFFBB00), Color(0xFFFF8A3D)]),
];

class PrintingServiceScreen extends StatefulWidget {
  const PrintingServiceScreen({super.key});

  @override
  State<PrintingServiceScreen> createState() => _PrintingServiceScreenState();
}

class _PrintingServiceScreenState extends State<PrintingServiceScreen> {
  late final PageController _pageController;
  Timer? _timer;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.82);
    _timer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (!mounted || !_pageController.hasClients) return;
      setState(() {
        _currentPage = (_currentPage + 1) % _kPrintCategories.length;
      });
      _pageController.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _launchCall() async {
    final uri = Uri(scheme: 'tel', path: _kPhoneNumber);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _launchWhatsApp() async {
    final uri = Uri.parse(
      'https://wa.me/91$_kPhoneNumber?text=${Uri.encodeComponent("Hi, I want to place a printing order.")}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Allin1 Designing and Printing',
            style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 16),),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Text('What we print for you',
                style: GoogleFonts.outfit(color: _kMuted, fontSize: 13, fontWeight: FontWeight.w600),),
            const SizedBox(height: 14),
            SizedBox(
              height: 220,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _kPrintCategories.length,
                itemBuilder: (context, i) => _CategoryCard(category: _kPrintCategories[i]),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_kPrintCategories.length, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? _kPink : _kMuted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  Text('Ready to order? Reach us directly:',
                      style: GoogleFonts.outfit(color: _kText, fontSize: 13, fontWeight: FontWeight.w700),),
                  const SizedBox(height: 6),
                  Text(_kPhoneNumber,
                      style: GoogleFonts.outfit(color: _kPink, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1),),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00C853),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: _launchCall,
                            icon: const Icon(Icons.call_rounded, color: Colors.white, size: 20),
                            label: Text('Call Now',
                                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF25D366),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: _launchWhatsApp,
                            icon: const Icon(Icons.chat_rounded, color: Colors.white, size: 20),
                            label: Text('WhatsApp',
                                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final _PrintCategory category;

  const _CategoryCard({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: category.colors.first.withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 10)),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Actual per-category sample image, not a flat color — per
          // Nizam's feedback that all 5 slides looked identical.
          Image.asset(
            category.imageAsset,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: category.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
            ),
          ),
          // Bottom gradient overlay purely for label legibility over the
          // photo — doesn't hide the image itself.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                stops: const [0.55, 1.0],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
              child: Text(
                category.label,
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
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
    properties.add(DiagnosticsProperty<_PrintCategory>('category', category));
  }
}
