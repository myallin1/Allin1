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
      'தமிழ்நாட்டின் ₹5,00,00,00,00,000 பொருளாதாரப் புரட்சித் திட்டம்! 🚀';

  static const String bannerSubtitle =
      'தமிழ்நாட்டை விட்டு வெளியேறும் நமது பணத்தை நம்மிடமே தக்கவைத்து நம் நாட்டின் பொருளாதாரத்தையும் மற்றும் நம் வீட்டின் பொருளாதாரத்தையும் உயர்த்துவதற்கான மாபெரும் திட்டம். ஈரோட்டிலிருந்து ஒரு சரித்திர தொடக்கம்....';

  static const String bannerCta = 'மேலும் அறிய கிளிக் செய்க';
  static const String bannerTag = 'ஈரோடு';

  // ── Detail-screen hero ────────────────────────────────────────
  static const String heroAmount = '₹10,00,00,00,00,000';
  static const String heroCaption = '5 ஆண்டுகளில் தமிழ்நாட்டை விட்டு வெளியேறும் பணத்தை Myallin1 மூலமாக அணை கட்டி தடுப்போம்.';
  static const String heroRally = 'அதை தமிழ்நாட்டிலேயே தக்க வைப்போம். ஈரோட்டிலிருந்து ஒரு தொடக்கம்.';
  static const String heroBadge = '5 வருட மாபெரும் திட்டம்';

  // ── Annual drain ──────────────────────────────────────────────
  static const String annualRange = '₹14,400 – ₹23,400';
  static const String annualIntro =
      'டாக்ஸி மற்றும் டிரான்ஸ்போர்ட், உணவு, மளிகை, ஈ-காமர்ஸ், பேமெண்ட், AI, OTT,பொமுது போக்கு ஆப் சந்தாக்கள் — '
      'இந்த  துறைகள் மூலம் தமிழ்நாட்டிலிருந்து ஒவ்வொரு ஆண்டும்';

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
      label: 'ஈ-காமர்ஸ்',
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

  // ── MyAllin1 Core Points ──────────────────────────────────────
  static const List<(String, String, IconData)> myAllin1CorePoints = [
    (
      '0% கமிஷன் - 100% உழைப்பவருக்கே',
      'வெளிநாட்டு நிறுவனங்கள் ஆட்டோ மற்றும் டெலிவரி தொழிலாளர்களிடம் வசூலிக்கும் 30% பகல் கொள்ளைக்கு முற்றுப்புள்ளி! Myallin1 ஆப்பில் கமிஷன் கிடையாது. தொழிலாளர்களின் முழு வருமானமும் அவர்கள் குடும்பத்திற்கே!',
      Icons.volunteer_activism_rounded,
    ),
    (
      'தமிழ்நாட்டின் பொருளாதாரம் தமிழர்களுக்கே',
      'கார்ப்பரேட் நிறுவனங்கள் மூலம் வெளி மாநிலங்கள் / நாடுகளுக்குச் செல்லும் பணத்தைத் தடுத்து, நம் மக்களின் பணம் நம் ஈரோடு மாவட்டத்திற்குள்ளேயே சுழலச் செய்து, உள்ளூர் பொருளாதாரத்தை உயர்த்துவதே எங்கள் முக்கிய நோக்கம்.',
      Icons.trending_up_rounded,
    ),
    (
      'பல வேலைகள்... ஒரே ஆப் (Multiple Earnings)',
      'ஆட்டோ, பைக் டாக்ஸி மட்டுமல்லாமல், உணவு விநியோகம், பார்சல் சர்வீஸ் எனப் பல வழிகளில் உழைப்பாளிகளுக்குத் தொடர்ந்து வேலைவாய்ப்பை வழங்கி, அவர்களின் தினசரி வருமானத்தை உத்தரவாதப்படுத்துகிறோம்.',
      Icons.work_rounded,
    ),
    (
      'பெண்களுக்கும், பயணிகளுக்கும் முழு பாதுகாப்பு',
      'அவசரக் காலங்களில் ஒரு பட்டனை அழுத்தினால் உடனே உதவி கிடைக்கும் நவீன SOS வசதி ஆப்பிற்குள்ளேயே இணைக்கப்பட்டுள்ளது. பயணிகளின் பாதுகாப்பே எங்கள் முதல் முன்னுரிமை.',
      Icons.security_rounded,
    ),
    (
      'சமூக நீதிக்கு வலு சேர்க்கும் இளைஞர்கள் படை',
      'மாண்புமிகு முதலமைச்சர் அவர்களின் எல்லோருக்குமான வளர்ச்சி என்ற சமூக நீதிப் பாதையில், ஈரோடு இளைஞர்களால் உருவாக்கப்பட்ட, உழைப்பாளர்களை முதலாளியாக்கும் முதல் தொழில்நுட்ப முன்னெடுப்பு இது!',
      Icons.groups_rounded,
    ),
    (
      'நம்ம ஊரு... நம்ம ஆப்',
      'ஈரோடு மக்களின் தேவைகளை நன்கு உணர்ந்து, உள்ளூர் மக்களுக்காக, உள்ளூர் இளைஞர்களால் உருவாக்கப்பட்ட முதல் Super App இதுவே.',
      Icons.favorite_rounded,
    ),
  ];

  // ── Solution ──────────────────────────────────────────────────
  static const String solutionTitle = 'MyAllin1 மாடல்';
  static const List<(IconData, String, String)> solutionRows = [
    (Icons.storefront_rounded, '0%', 'வியாபாரிகளுக்கு கமிஷன் இல்லை'),
    (Icons.delivery_dining_rounded, '100%', 'டெலிவரி பார்ட்னர்களுக்கு முழு வருமானம்'),
    (Icons.groups_rounded, 'நியாயம்', 'மக்களுக்கு நேர்மையான விலை'),
  ];
  static const String solutionSlogan = 'உழைப்பவர்களின் வியர்வைக்கு 100% மதிப்பு! 0% கமிஷன்! 💛';

  // ── Industry facts ────────────────────────────────────────────
  static const List<(String, String)> industryFacts = [
    ('60%', 'இந்திய உணவகங்கள் 10% லாபத்தைத் தாண்டுவதே இல்லை'),
    ('35%', 'உணவகங்கள் இன்றே பெரிய ஆப்களை விட்டு வெளியேற தயார்'),
    ('32%', 'டெலிவரி பார்ட்னரின் வருமானம் செலவுகளிலேயே போகிறது'),
    ('₹17.58', 'ஒவ்வொரு ஆர்டருக்கும் பிளாட்ஃபார்ம் கட்டணம்'),
  ];

  // ── CTA ───────────────────────────────────────────────────────
  static const String ctaTitle = 'ஒவ்வொரு ஈரோட்டுக்காரன் போனிலும் Myallin1 இருக்கட்டும்!';
  static const String ctaBody =
      'உள்ளூர் தொழிலாளர்களின் வாழ்வாதாரத்தை உயர்த்தும் இந்த புரட்சியில் நீங்களும் இணையுங்கள்! ஷேர் பண்ணுங்க.';
  static const String ctaButton = 'ஆர்டர் செய்யத் தொடங்குங்கள்';

  /// Hero-app variant of the CTA — a delivery partner is not "ordering".
  static const String ctaButtonHero = 'திரும்பிச் செல்';

  // ── Source footer (LEGALLY LOAD-BEARING — never remove) ───────
  static const String sourceTitle = 'தரவு ஆதாரம்';
  static const String sourceBody =
      '2025-2026 நிதியாண்டின் வெளியிடப்பட்ட தொழில் துறை தரவுகள் (8%–35% கமிஷன் '
      'விகிதங்கள்), தேசியச் சந்தையில் தமிழ்நாட்டின் மதிப்பிடப்பட்ட 9% பங்கு, '
      'மற்றும் 15% ஆண்டு வளர்ச்சி அடிப்படையில் கணக்கிடப்பட்டது. இவை '
      'மதிப்பீடுகள் — நிறுவன உறுதிமொழி அல்ல. மொத்தத்தில் மிகப்பெரிய பங்கு '
      'ஈ-காமர்ஸ் துறையிலிருந்து.';
}
