// ================================================================
// economic_vision_banner.dart — the tappable campaign banner
// ================================================================
// NEW (Aug 13 2026 — Nizam: reuse the பொருளாதாரப் புரட்சி content in
// the Hero app too, on the sign-in page and the hero home page, exactly
// as it appears in the Customer app).
//
// ONE widget, used by every surface. All copy comes from
// EconomicVisionData, so editing a number there updates the customer
// home, the hero login page and the hero home page at the same time —
// which is the whole point of centralising it.
//
// Deliberately NOT a slide inside any auto-rotating carousel: the
// subtitle is two sentences, and a 4s rotation would sweep it away
// before anyone finished reading. A campaign message nobody can finish
// reading is worse than none.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/economic_vision_data.dart';
import '../screens/economic_vision_screen.dart';

class EconomicVisionBanner extends StatelessWidget {
  const EconomicVisionBanner({
    this.horizontalPadding = 16,
    this.compact = false,
    this.heroApp = false,
    super.key,
  });

  /// Outer horizontal padding. Screens that already pad their content
  /// pass 0 so the banner does not get double-inset.
  final double horizontalPadding;

  /// Tighter type/spacing for dense surfaces (e.g. the hero login page,
  /// which already carries a logo, a title and a 3-step guide card).
  final bool compact;

  /// Hero app uses a "go back" CTA on the detail screen instead of
  /// "start ordering", since a delivery partner is not placing orders.
  final bool heroApp;

  @override
  Widget build(BuildContext context) {
    final titleSize = compact ? 15.0 : 17.0;
    final subSize = compact ? 11.5 : 12.5;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => EconomicVisionScreen(heroApp: heroApp),
            ),
          ),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(compact ? 15 : 18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF4FA3), Color(0xFF7B1E52)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF4FA3).withValues(alpha: 0.32),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(EconomicVisionData.bannerTag,
                          style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800)),
                    ),
                    const Spacer(),
                    Icon(Icons.trending_up_rounded,
                        color: Colors.white.withValues(alpha: 0.85), size: 20),
                  ],
                ),
                SizedBox(height: compact ? 10 : 12),
                Text(
                  EconomicVisionData.bannerTitle,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: titleSize,
                    fontWeight: FontWeight.w900,
                    height: 1.28,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  EconomicVisionData.bannerSubtitle,
                  maxLines: compact ? 3 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white.withValues(alpha: 0.93),
                    fontSize: subSize,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: compact ? 12 : 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(EconomicVisionData.bannerCta,
                          style: GoogleFonts.outfit(
                              color: const Color(0xFF7B1E52),
                              fontSize: 12,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward_rounded,
                          color: Color(0xFF7B1E52), size: 15),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
