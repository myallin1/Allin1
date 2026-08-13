// ================================================================
// economic_vision_screen.dart — "பொருளாதாரப் புரட்சி" (8-sector model)
// ================================================================
// NEW (Aug 13 2026 — Nizam's Erode launch campaign). The detail page
// behind the home-screen banner: a premium fintech-report style
// breakdown of how much money leaves Tamil Nadu through corporate
// platform commissions, and what MyAllin1's model does differently.
//
// ── HOW THE NUMBERS ARE FRAMED (important, do not casually reword) ──
// Every figure here describes the SIZE OF THE PROBLEM — money currently
// being extracted from Tamil Nadu — NOT a promise of what MyAllin1 will
// save any individual, and NOT a company forecast.
//
// That distinction is deliberate and legally load-bearing. Under the
// Consumer Protection Act 2019 the CCPA can penalise misleading ads
// (₹10 lakh first offence, ₹50 lakh repeat). "This is what is being
// taken from us" is a defensible statement about the market. "We will
// save you ₹50,000 crore" is a promise we cannot prove. The wording
// below stays firmly on the first side of that line, and the source
// footer at the bottom converts the whole page from a claim into a
// stated calculation. Keep both.
//
// Underlying research + full working: MYALLIN1_SAVINGS_RESEARCH.md at
// the repo root. Figures are from published FY2026 industry reporting
// (Zomato/Swiggy filings, NRAI, quick-commerce and ride-hailing take
// rates); Tamil Nadu's 8-10% share of the national market is an
// estimate, which the footer states plainly.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/economic_vision_data.dart';

const Color _bg = Color(0xFFFFF6FA);
const Color _surface = Color(0xFFFFFFFF);
const Color _pink = Color(0xFFFF4FA3);
const Color _pinkDark = Color(0xFFBE2A7A);
const Color _card = Color(0xFFFFEAF3);
const Color _text = Color(0xFF201A22);
const Color _muted = Color(0xFF8C7A88);
const Color _green = Color(0xFF00A84A);
const Color _amber = Color(0xFFB8860B);

class EconomicVisionScreen extends StatelessWidget {
  const EconomicVisionScreen({this.heroApp = false, super.key});

  /// Hero app shows a "go back" CTA instead of "start ordering" — a
  /// delivery partner is not placing orders.
  final bool heroApp;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 232,
            backgroundColor: _pinkDark,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              background: _header(),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 34),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _sectionTitle('📊  தமிழ்நாட்டின் 5 வருட சித்திரம்'),
                const SizedBox(height: 10),
                _visionCard(),
                const SizedBox(height: 18),
                _sectionTitle('🏭  எந்தெந்த சேவைகளில் பணம் போகிறது?'),
                const SizedBox(height: 10),
                _categoryBreakdown(),
                const SizedBox(height: 18),
                _sectionTitle('📍  ஈரோட்டின் நிலை'),
                const SizedBox(height: 10),
                _erodeCard(),
                const SizedBox(height: 18),
                _sectionTitle('💡  MyAllin1 தீர்வு'),
                const SizedBox(height: 10),
                _solutionCard(),
                const SizedBox(height: 18),
                _factsCard(),
                const SizedBox(height: 18),
                _ctaCard(context),
                const SizedBox(height: 16),
                _sourceFooter(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────
  Widget _header() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_pink, _pinkDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 46, 20, 18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(EconomicVisionData.heroBadge,
                    style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 10),
              Text(EconomicVisionData.heroAmount,
                  style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      height: 1.05)),
              const SizedBox(height: 4),
              Text(EconomicVisionData.heroCaption,
                  style: GoogleFonts.outfit(
                      color: Colors.white.withValues(alpha: 0.94),
                      fontSize: 13.5,
                      height: 1.35)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.south_west_rounded,
                      color: Colors.white, size: 15),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(EconomicVisionData.heroRally,
                        style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String s) => Text(s,
      style: GoogleFonts.outfit(
          color: _text, fontSize: 15.5, fontWeight: FontWeight.w800));

  Widget _shell({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _card, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: _pink.withValues(alpha: 0.07),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      );

  // ── 5-year vision ─────────────────────────────────────────────
  Widget _visionCard() => _shell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              EconomicVisionData.annualIntro,
              style: GoogleFonts.outfit(color: _muted, fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(EconomicVisionData.annualRange,
                    style: GoogleFonts.outfit(
                        color: _pinkDark,
                        fontSize: 23,
                        fontWeight: FontWeight.w900)),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text('கோடி',
                      style: GoogleFonts.outfit(
                          color: _pinkDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            Text('கோடி வெளியேறுகிறது.',
                style: GoogleFonts.outfit(color: _muted, fontSize: 12.5)),
            const SizedBox(height: 16),
            const Divider(height: 1, color: _card),
            const SizedBox(height: 14),
            Text('5 ஆண்டுகளில் (சந்தை வளர்ச்சியுடன்)',
                style: GoogleFonts.outfit(
                    color: _text, fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ..._yearRows(),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _pink.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.functions_rounded, color: _pinkDark, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(EconomicVisionData.fiveYearTotal,
                        style: GoogleFonts.outfit(
                            color: _pinkDark,
                            fontSize: 15,
                            fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  List<Widget> _yearRows() {
    return EconomicVisionData.fiveYearBuildUp
        .map((y) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 54,
                    child: Text(y.$1,
                        style: GoogleFonts.outfit(color: _muted, fontSize: 11.5)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                        value: y.$3,
                        minHeight: 9,
                        backgroundColor: _card,
                        valueColor: const AlwaysStoppedAnimation(_pink),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 74,
                    child: Text('₹${y.$2} கோடி',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.outfit(
                            color: _text,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ))
        .toList();
  }

  // ── Category breakdown ────────────────────────────────────────
  Widget _categoryBreakdown() {
    // 8 SECTORS, SPLIT INTO TWO HONEST GROUPS (Aug 13 2026).
    //
    // The split is not cosmetic — it is the difference between a claim we
    // can defend and one we cannot:
    //
    //   GROUP 1 (நம் வணிகம்) — commission taken out of trade that HAPPENS
    //   HERE. A local shop sells to a local customer and a platform takes
    //   a cut. That money could stay in Tamil Nadu, and MyAllin1 can
    //   genuinely offer an alternative. This is the addressable drain.
    //
    //   GROUP 2 (வெளிநாட்டு சேவைகள்) — money paid for a product genuinely
    //   made elsewhere (Netflix content, OpenAI compute). That is IMPORT
    //   SPEND, not extraction. MyAllin1 cannot replace ChatGPT or Netflix,
    //   and we must never imply we will. It is shown for scale/context
    //   only, and labelled as such.
    //
    // Merging the two under one "we will save this" banner would be the
    // fastest way for a critic to discredit the whole campaign. Keep the
    // labels.
    return _shell(
      child: Column(
        children: [
          // LAYOUT FIX (Aug 13 2026 — CTO review: amounts were hugging the
          // right edge). The amount used to sit as a trailing widget in the
          // same Row as the icon and bar, competing for whatever width was
          // left. Tamil amount strings like "₹1,800 – 3,640 கோடி" are long,
          // so that slot was always tight — padding alone would only have
          // moved the squeeze around. Restructured instead: the label and
          // amount share the top line (amount right-aligned, with real
          // breathing room), and the bar spans the FULL card width beneath
          // them. Easier to read and it can no longer crowd at any font
          // scale or screen width.
          _groupHeader(EconomicVisionData.group1Title, EconomicVisionData.group1Note, _pinkDark),
          const SizedBox(height: 12),
          ...EconomicVisionData.addressableSectors.map(_catRow),
          const SizedBox(height: 4),
          _groupHeader(EconomicVisionData.group2Title, EconomicVisionData.group2Note, _amber),
          const SizedBox(height: 12),
          ...EconomicVisionData.importSectors.map(_catRow),
          const Divider(height: 1, color: _card),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, color: _amber, size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  EconomicVisionData.sectorFootnote,
                  style: GoogleFonts.outfit(
                      color: _muted, fontSize: 11, height: 1.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _groupHeader(String title, String note, Color color) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 30,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.outfit(
                        color: color,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 1),
                Text(note,
                    style: GoogleFonts.outfit(
                        color: _muted, fontSize: 10, height: 1.35)),
              ],
            ),
          ),
        ],
      );

  Widget _catRow(VisionSector r) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _pink.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(r.icon, color: _pinkDark, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(r.label,
                      style: GoogleFonts.outfit(
                          color: _text,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 12),
                Text(r.amount,
                    style: GoogleFonts.outfit(
                        color: _pinkDark,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: r.barValue,
                minHeight: 7,
                backgroundColor: _card,
                valueColor: const AlwaysStoppedAnimation(_pinkDark),
              ),
            ),
          ],
        ),
      );

  // ── Erode ─────────────────────────────────────────────────────
  Widget _erodeCard() => _shell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_city_rounded, color: _pinkDark, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('ஈரோடு மாவட்டம்',
                      style: GoogleFonts.outfit(
                          color: _text,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Two figures, deliberately separated: the restaurant number is
            // the one a hotel owner can verify on his own statement, so it
            // stays the anchor. The district-wide number gives the real
            // scale across all 8 sectors. Merging them would lose the
            // verifiable one, which is the more persuasive of the two.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: _pink.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(EconomicVisionData.erodeTotalLabel,
                      style: GoogleFonts.outfit(
                          color: _muted, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text(EconomicVisionData.erodeTotalAmount,
                      style: GoogleFonts.outfit(
                          color: _pinkDark,
                          fontSize: 22,
                          fontWeight: FontWeight.w900)),
                  Text(EconomicVisionData.erodeTotalNote,
                      style: GoogleFonts.outfit(color: _muted, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              EconomicVisionData.erodeRestaurantIntro,
              style: GoogleFonts.outfit(color: _muted, fontSize: 12.5),
            ),
            const SizedBox(height: 6),
            Text(EconomicVisionData.erodeRestaurantAmount,
                style: GoogleFonts.outfit(
                    color: _pinkDark, fontSize: 30, fontWeight: FontWeight.w900)),
            Text(EconomicVisionData.erodeRestaurantNote,
                style: GoogleFonts.outfit(color: _muted, fontSize: 12.5)),
            const SizedBox(height: 16),
            // LAYOUT FIX (Aug 13 2026 — CTO review: "the calculation looks
            // scattered"). The old version paired two unrelated values per
            // row (e.g. "× 30% கமிஷன்" next to "× 12 மாதங்கள்"), so the eye
            // had no single path to follow and the arithmetic was not
            // actually legible as arithmetic. Rebuilt as a genuine vertical
            // equation: a fixed operator column on the left, the value, and
            // a plain-language note on the right — then a rule and the
            // total, exactly like a hand-written sum. A layman can now read
            // straight down and see where ₹36 கோடி comes from.
            Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('கணக்கு எப்படி?',
                      style: GoogleFonts.outfit(
                          color: _muted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4)),
                  const SizedBox(height: 12),
                  ...EconomicVisionData.erodeEquation.map((e) => _eqRow(e.$1, e.$2, e.$3)),
                  const SizedBox(height: 10),
                  Container(height: 1.2, color: _pinkDark.withValues(alpha: 0.25)),
                  const SizedBox(height: 10),
                  _eqRow(EconomicVisionData.erodeEquationTotal.$1, EconomicVisionData.erodeEquationTotal.$2,
                      EconomicVisionData.erodeEquationTotal.$3, total: true),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _pink.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.storefront_rounded,
                            color: _pinkDark, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(EconomicVisionData.erodePerShopLabel,
                              style: GoogleFonts.outfit(
                                  color: _text,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                        Text(EconomicVisionData.erodePerShopAmount,
                            style: GoogleFonts.outfit(
                                color: _pinkDark,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  /// One line of the Erode equation: a fixed-width operator gutter, the
  /// value, then a plain-language note. The fixed gutter is what makes
  /// the ×, × , × and = align vertically down the left edge, so the block
  /// reads as a sum rather than as four unrelated rows.
  Widget _eqRow(String op, String value, String note, {bool total = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: total ? 0 : 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            child: Text(op,
                style: GoogleFonts.outfit(
                    color: total ? _pinkDark : _muted,
                    fontSize: total ? 16 : 14,
                    fontWeight: FontWeight.w800)),
          ),
          SizedBox(
            width: 96,
            child: Text(value,
                style: GoogleFonts.outfit(
                    color: total ? _pinkDark : _text,
                    fontSize: total ? 17 : 13.5,
                    fontWeight: total ? FontWeight.w900 : FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(note,
                style: GoogleFonts.outfit(
                    color: _muted,
                    fontSize: total ? 11.5 : 11,
                    fontWeight: total ? FontWeight.w700 : FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  // ── Solution ──────────────────────────────────────────────────
  Widget _solutionCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_pink, _pinkDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(EconomicVisionData.solutionTitle,
                style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            ...EconomicVisionData.solutionRows.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _solutionRow(r.$1, r.$2, r.$3),
            )),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '100% உழைப்பவர் வருமானம் உழைப்பவருக்கே.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );

  Widget _solutionRow(IconData icon, String big, String label) => Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(big,
                    style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900)),
                Text(label,
                    style: GoogleFonts.outfit(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 11.5)),
              ],
            ),
          ),
        ],
      );

  // ── Industry facts ────────────────────────────────────────────
  Widget _factsCard() => _shell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📌  தொழில்துறை உண்மைகள்',
                style: GoogleFonts.outfit(
                    color: _text, fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            ...EconomicVisionData.industryFacts.map((f) => _fact(f.$1, f.$2)),
          ],
        ),
      );

  Widget _fact(String big, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 62,
              child: Text(big,
                  style: GoogleFonts.outfit(
                      color: _pinkDark,
                      fontSize: 16,
                      fontWeight: FontWeight.w900)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(label,
                    style: GoogleFonts.outfit(
                        color: _muted, fontSize: 11.5, height: 1.45)),
              ),
            ),
          ],
        ),
      );

  // ── CTA ───────────────────────────────────────────────────────
  Widget _ctaCard(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _green.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _green.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            const Icon(Icons.volunteer_activism_rounded, color: _green, size: 30),
            const SizedBox(height: 10),
            Text(EconomicVisionData.ctaTitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    color: _text, fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              EconomicVisionData.ctaBody,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  color: _muted, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(heroApp ? EconomicVisionData.ctaButtonHero : EconomicVisionData.ctaButton,
                    style: GoogleFonts.outfit(
                        fontSize: 14, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      );

  // ── Source footer ─────────────────────────────────────────────
  // LEGALLY LOAD-BEARING — see the file header. This is what turns the
  // page from an advertising claim into a stated calculation with its
  // assumptions on display. Do not remove or bury it.
  Widget _sourceFooter() => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _card.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fact_check_outlined, color: _muted, size: 14),
                const SizedBox(width: 6),
                Text(EconomicVisionData.sourceTitle,
                    style: GoogleFonts.outfit(
                        color: _muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              EconomicVisionData.sourceBody,
              style: GoogleFonts.outfit(
                  color: _muted, fontSize: 10, height: 1.55),
            ),
          ],
        ),
      );
}
