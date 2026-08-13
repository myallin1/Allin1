// ================================================================
// economic_vision_data.dart — SINGLE SOURCE OF TRUTH for the
// "பொருளாதாரப் புரட்சி" campaign numbers and copy.
// ================================================================
// NEW (Aug 13 2026 — Nizam: "porulathara puratchi content orey place la
// vei atha reuse panniklam, apo than namma innum konjam calculations
// alter pannavendiyathirukku, orey place la iruntha athu aprama alter
// panni update pannita app la orey mari update aidum").
//
// EVERY figure and every Tamil string used by the campaign lives here.
// Change a number in this file and it updates simultaneously in:
//   * Customer app  — home banner + EconomicVisionScreen
//   * Hero app      — login page banner + hero home banner
//   * Any future surface that imports EconomicVisionBanner
//
// ── ONE PLACE THIS FILE CANNOT REACH ────────────────────────────
// landing_page/ is plain static HTML served as its own Firebase
// Hosting target — it does not run Dart, so it cannot import this
// file. Its copy of these numbers must be edited by hand. Both files
// carry a pointer to the other so the pair never silently drifts.
//   -> landing_page/index.html, search for: ECONOMIC-VISION-SYNC
//
// ── FRAMING RULE (legally load-bearing, do not casually reword) ──
// Every figure describes MONEY LEAVING TAMIL NADU — the size of the
// problem. None of it is a promise of what MyAllin1 will save anyone,
// and none of it is a company forecast. Under the Consumer Protection
// Act 2019 the CCPA can penalise misleading ads (₹10 lakh first
// offence, ₹50 lakh repeat). "This is what is being taken from us" is
// defensible. "We will save you ₹X" is not.
//
// Full working and sources: MYALLIN1_SAVINGS_RESEARCH.md (repo root).
import 'package:flutter/material.dart';

/// One row of the sector breakdown.
class VisionSector {
  const VisionSector({
    required this.label,
    required this.icon,
    required this.amount,
    required this.barValue,
  });

  final String label;
  final IconData icon;

  /// Pre-formatted Tamil amount string, e.g. '₹8,540 – 14,940 கோடி'.
  final String amount;

  /// 0.0–1.0, relative to the largest sector in the same group.
  final double barValue;
}

class EconomicVisionData {
  EconomicVisionData._();

  // ── Headline ──────────────────────────────────────────────────
  /// Outer/marketing headline. Deliberately kept BELOW the modelled
  /// 5-year total (₹1.27 lakh cr) — under-promising outside and
  /// over-delivering on the detail page is the stronger position, and
  /// it leaves head-room if a number is ever revised downward.
  static const String bannerTitle =
      'தமிழ்நாட்டின் ₹50,000 கோடி பொருளாதாரப் புரட்சி! 🚀';

  static const String bannerSubtitle =
      'வெளிமாநிலங்களுக்குச் செல்லும் நமது பணத்தை மீட்பதற்கான 5 வருட மாபெரும் '
      'திட்டம். ஈரோட்டிலிருந்து ஒரு சரித்திரத் தொடக்கம்...';

  static const String bannerCta = 'மேலும் அறிய கிளிக் செய்க';
  static const String bannerTag = 'ஈரோடு';

  // ── Detail-screen hero ────────────────────────────────────────
  static const String heroAmount = '₹1 லட்சம் கோடி';
  static const String heroCaption = '5 ஆண்டுகளில் தமிழ்நாட்டை விட்டு வெளியேறும் பணம்';
  static const String heroRally = 'அதை இங்கேயே வைப்போம். ஈரோட்டிலிருந்து ஒரு தொடக்கம்.';
  static const String heroBadge = '5 வருட மாபெரும் திட்டம்';

  // ── Annual drain ──────────────────────────────────────────────
  static const String annualRange = '₹14,400 – ₹23,400';
  static const String annualIntro =
      'டாக்ஸி, உணவு, மளிகை, ஈ-காமர்ஸ், பேமெண்ட், AI, OTT, ஆப் சந்தாக்கள் — '
      'இந்த 8 துறைகள் மூலம் தமிழ்நாட்டிலிருந்து ஒவ்வொரு ஆண்டும்';

  /// 5-year build-up. Base ₹18,917 கோடி compounding at 15%/yr.
  /// (label, ₹ crore, bar 0-1)
  static const List<(String, int, double)> fiveYearBuildUp = [
    ('ஆண்டு 1', 18917, 0.57),
    ('ஆண்டு 2', 21755, 0.66),
    ('ஆண்டு 3', 25018, 0.76),
    ('ஆண்டு 4', 28771, 0.87),
    ('ஆண்டு 5', 33086, 1.0),
  ];

  static const String fiveYearTotal = 'மொத்தம் ≈ ₹1,27,000 கோடி';

  // ── Sector breakdown, in two deliberately separate groups ─────
  //
  // GROUP 1 — trade that HAPPENS HERE, where a platform takes a cut of
  // local commerce. That money could stay in Tamil Nadu, and MyAllin1
  // can genuinely offer an alternative. This is the addressable drain.
  //
  // GROUP 2 — money paid for a product genuinely made elsewhere
  // (Netflix content, OpenAI compute). That is IMPORT SPEND, not
  // extraction. MyAllin1 cannot replace ChatGPT or Netflix and must
  // never imply it will. Shown for scale only, and labelled as such.
  //
  // Merging the two under one "we will save this" banner is the fastest
  // way for a critic to discredit the whole campaign. Keep them apart.
  static const String group1Title = 'நம் வணிகத்தில் இருந்து எடுக்கப்படுவது';
  static const String group1Note = 'இங்கேயே நடக்கும் வியாபாரம் — இதற்கு மாற்று உண்டு';

  static const String group2Title = 'வெளிநாட்டு சேவைகளுக்குச் செல்வது';
  static const String group2Note =
      'வெளியில் உருவாக்கப்படும் சேவைகள் — அளவை உணர்த்த மட்டும்';

  static const List<VisionSector> addressableSectors = [
    VisionSector(
      label: 'ஈ-காமர்ஸ் (Amazon/Flipkart)',
      icon: Icons.shopping_bag_rounded,
      amount: '₹8,540 – 14,940 கோடி',
      barValue: 1.0,
    ),
    VisionSector(
      label: 'மளிகை / குயிக் காமர்ஸ்',
      icon: Icons.local_grocery_store_rounded,
      amount: '₹1,980 – 2,770 கோடி',
      barValue: 0.19,
    ),
    VisionSector(
      label: 'உணவு டெலிவரி',
      icon: Icons.restaurant_rounded,
      amount: '₹1,700 – 2,390 கோடி',
      barValue: 0.16,
    ),
    VisionSector(
      label: 'பைக் டாக்ஸி / ஆட்டோ / கார்',
      icon: Icons.local_taxi_rounded,
      amount: '₹740 – 1,240 கோடி',
      barValue: 0.08,
    ),
    VisionSector(
      label: 'பேமெண்ட் ஆப் கட்டணங்கள்',
      icon: Icons.account_balance_wallet_rounded,
      amount: '₹250 – 600 கோடி',
      barValue: 0.04,
    ),
  ];

  static const List<VisionSector> importSectors = [
    VisionSector(
      label: 'ஆப் பிரீமியம் சந்தாக்கள்',
      icon: Icons.apps_rounded,
      amount: '₹490 – 610 கோடி',
      barValue: 0.04,
    ),
    VisionSector(
      label: 'OTT சந்தாக்கள்',
      icon: Icons.play_circle_fill_rounded,
      amount: '₹420 – 510 கோடி',
      barValue: 0.035,
    ),
    VisionSector(
      label: 'AI சந்தாக்கள்',
      icon: Icons.auto_awesome_rounded,
      amount: '₹320 – 340 கோடி',
      barValue: 0.023,
    ),
  ];

  static const String sectorFootnote =
      'கார்ப்பரேட் ஆப்கள் ஒவ்வொரு ஆர்டரிலும் 8%–35% வரை கமிஷன் எடுக்கின்றன. '
      'மொத்தத்தில் மிகப்பெரிய பங்கு ஈ-காமர்ஸ்.';

  // ── Erode ─────────────────────────────────────────────────────
  static const String erodeTotalLabel =
      'ஈரோடு மாவட்டம் — மொத்த டிஜிட்டல் பொருளாதாரம்';
  static const String erodeTotalAmount = '≈ ₹300 கோடி / ஆண்டு';
  static const String erodeTotalNote = '8 துறைகளிலும் சேர்த்து வெளியேறுகிறது.';

  static const String erodeRestaurantIntro = 'இதில், உணவக துறை மட்டும் ஆண்டுக்கு';
  static const String erodeRestaurantAmount = '₹36 கோடி';
  static const String erodeRestaurantNote =
      '30% கமிஷனாக இழக்கிறது. அந்தக் கணக்கு கீழே:';

  /// The Erode equation, as (operator, value, note).
  static const List<(String, String, String)> erodeEquation = [
    ('', '500', 'உணவகங்கள் (ஆன்லைனில்)'),
    ('×', '₹2,00,000', 'ஒன்றின் மாத விற்பனை'),
    ('×', '30%', 'கார்ப்பரேட் கமிஷன்'),
    ('×', '12', 'மாதங்கள்'),
  ];

  static const (String, String, String) erodeEquationTotal =
      ('=', '₹36 கோடி', 'ஆண்டுக்கு இழப்பு');

  static const String erodePerShopLabel = 'ஒரு உணவகத்திற்கு மட்டும்';
  static const String erodePerShopAmount = '₹60,000 / மாதம்';

  // ── Solution ──────────────────────────────────────────────────
  static const String solutionTitle = 'MyAllin1 மாடல்';
  static const List<(IconData, String, String)> solutionRows = [
    (Icons.storefront_rounded, '0%', 'வியாபாரிகளுக்கு கமிஷன் இல்லை'),
    (Icons.delivery_dining_rounded, '100%', 'டெலிவரி பார்ட்னர்களுக்கு முழு வருமானம்'),
    (Icons.groups_rounded, 'நியாயம்', 'மக்களுக்கு நேர்மையான விலை'),
  ];
  static const String solutionSlogan = '100% உழைப்பவர் வருமானம் உழைப்பவருக்கே.';

  // ── Industry facts ────────────────────────────────────────────
  static const List<(String, String)> industryFacts = [
    ('60%', 'இந்திய உணவகங்கள் 10% லாபத்தைத் தாண்டுவதே இல்லை'),
    ('35%', 'உணவகங்கள் இன்றே பெரிய ஆப்களை விட்டு வெளியேற தயார்'),
    ('32%', 'டெலிவரி பார்ட்னரின் வருமானம் செலவுகளிலேயே போகிறது'),
    ('₹17.58', 'ஒவ்வொரு ஆர்டருக்கும் பிளாட்ஃபார்ம் கட்டணம்'),
  ];

  // ── CTA ───────────────────────────────────────────────────────
  static const String ctaTitle = 'இந்த மாற்றம் நம்மிடமிருந்தே தொடங்குகிறது';
  static const String ctaBody =
      'நீங்கள் MyAllin1-ல் ஆர்டர் செய்யும் ஒவ்வொரு முறையும், அந்தப் பணம் '
      'ஈரோட்டிலேயே தங்குகிறது.';
  static const String ctaButton = 'ஆர்டர் செய்யத் தொடங்குங்கள்';

  /// Hero-app variant of the CTA — a delivery partner is not "ordering".
  static const String ctaButtonHero = 'திரும்பிச் செல்';

  // ── Source footer (LEGALLY LOAD-BEARING — never remove) ───────
  static const String sourceTitle = 'தரவு ஆதாரம்';
  static const String sourceBody =
      '2026 நிதியாண்டின் வெளியிடப்பட்ட தொழில்துறைத் தரவுகள் (8%–35% கமிஷன் '
      'விகிதங்கள்), தேசியச் சந்தையில் தமிழ்நாட்டின் மதிப்பிடப்பட்ட 9% பங்கு, '
      'மற்றும் 15% ஆண்டு வளர்ச்சி அடிப்படையில் கணக்கிடப்பட்டது. இவை '
      'மதிப்பீடுகள் — நிறுவன உறுதிமொழி அல்ல. மொத்தத்தில் மிகப்பெரிய பங்கு '
      'ஈ-காமர்ஸ் துறையிலிருந்து.';
}
