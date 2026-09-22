// lib/config/category_shortcuts.dart
// ================================================================
// Shared label/icon lookup for the customer home screen's top-level
// service categories, keyed by the SAME tapId strings
// _CategorySlidingBannerState (dashboard_screen.dart) already uses for
// navigation (see its own _titles/_tapIds/_slideIcons).
//
// NEW (Sep 22 2026 — Nizam: "ovvoru feature and option-um shortcut app
// mari veliya vaikka option venum, athu long-press pannuna Hive cache-la
// save aagi, main screen widget-la irukum"). Deliberately its own small
// file rather than exporting the slider's private statics: those are
// intentionally duplicated against the bottom BannerAdsSlider already
// (see that class's own header comment), so a third short-label copy
// for the compact "My Shortcuts" chips follows the same established
// precedent instead of forcing a risky refactor of working carousel code.
import 'package:colorful_iconify_flutter/icons/fluent_emoji_flat.dart';

class CategoryShortcut {
  const CategoryShortcut({required this.label, required this.icon});

  /// Short chip label — NOT the full marquee title (which carries a
  /// trailing emoji and, for food, a partner-shop list) since this
  /// renders in a ~64px-wide compact chip, not a wide banner slide.
  final String label;

  /// SVG markup from FluentEmojiFlat, rendered via SvgPicture.string.
  final String icon;
}

/// One entry per tapId _CategorySlidingBannerState/_handleTap already
/// knows how to route — adding a new home-screen category means adding
/// it here too, or it simply won't be pin-able (fails safe: an unknown
/// id is never shown in the shortcuts bar, never a crash).
const Map<String, CategoryShortcut> kCategoryShortcuts = {
  'route:eseva': CategoryShortcut(
    label: 'E-Seva',
    icon: FluentEmojiFlat.card_index,
  ),
  'route:printing': CategoryShortcut(
    label: 'Printing',
    icon: FluentEmojiFlat.printer,
  ),
  'route:electronics': CategoryShortcut(
    label: 'Electronics',
    icon: FluentEmojiFlat.mobile_phone,
  ),
  'broadband': CategoryShortcut(
    label: 'Broadband',
    icon: FluentEmojiFlat.antenna_bars,
  ),
  'construction': CategoryShortcut(
    label: 'Construction',
    icon: FluentEmojiFlat.building_construction,
  ),
  'carwash': CategoryShortcut(
    label: 'Car Wash',
    icon: FluentEmojiFlat.sweat_droplets,
  ),
  'route:hero': CategoryShortcut(
    label: 'Book a Hero',
    icon: FluentEmojiFlat.man_superhero,
  ),
  'grocery': CategoryShortcut(
    label: 'Grocery',
    icon: FluentEmojiFlat.shopping_cart,
  ),
  'food': CategoryShortcut(
    label: 'Food',
    icon: FluentEmojiFlat.hamburger,
  ),
  'taxi': CategoryShortcut(
    label: 'Taxi',
    icon: FluentEmojiFlat.oncoming_taxi,
  ),
};
