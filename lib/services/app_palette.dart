// ================================================================
// app_palette.dart — shared, theme-reactive color palette
// ================================================================
// Per Nizam's decision (CTO-reviewed, full Option 2 rollout): every
// screen used to declare its OWN local `const Color kBg/kText/...`
// constants, hardcoded to whatever palette that screen's author
// picked at the time (some pink&white, most an older dark palette).
// Switching theme in Settings updated MaterialApp's ThemeData, but
// none of these screens ever read from it -- so screens kept showing
// their frozen hardcoded colors no matter what theme was selected.
//
// Fix: one shared set of mutable Color variables here, refreshed from
// the active ThemeService theme by syncAppPalette() -- every screen
// that used to declare its own local kBg etc. now imports this file
// instead and calls syncAppPalette(context.watch<ThemeService>()) at
// the top of its build() method (same pattern as dashboard_screen.dart,
// which keeps its own already-working local copy -- not touched here).
//
// Decorative/status accent colors (green/teal/blue/gold/orange/purple/
// purple2/red) are intentionally left theme-independent, same
// reasoning as dashboard_screen.dart: they mean "success"/"warning"/
// "info" regardless of theme, only brand + surface + text colors
// should follow the customer's selected theme.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'theme_service.dart';
export 'theme_service.dart';

Color kPink     = const Color(0xFFFF4FA3);
Color kPinkDark = const Color(0xFFBE2A7A);
Color kPinkBg   = const Color(0xFFFFF0F7);
Color kBg       = const Color(0xFFFFFFFF);
Color kSurface  = const Color(0xFFF8F8FF);
Color kCard     = const Color(0xFFF8F8FF);
Color kCard2    = const Color(0xFFF0F0FA);
Color kText     = const Color(0xFF1A1A2E);
Color kMuted    = const Color(0xFF9999BB);
Color kBorder   = const Color(0xFFEEEEF5);

// Status / accent colors — theme-independent by design.
const Color kGreen   = Color(0xFF00C853);
const Color kTeal    = Color(0xFF00BFA5);
const Color kBlue    = Color(0xFF1565C0);
const Color kGold    = Color(0xFFFFBB00);
const Color kOrange  = Color(0xFFE07C6F);
const Color kPurple  = Color(0xFF7B6FE0);
const Color kPurple2 = Color(0xFF9B8FF0);
const Color kRed     = Color(0xFFFF5252);

/// Refreshes the shared palette variables above from whichever theme is
/// currently active in [ThemeService]. Call this at the top of a
/// screen's build() method: `syncAppPalette(context);`. Uses `watch` so
/// the screen repaints whenever the customer changes theme in Settings.
///
/// Some screens (login_screen.dart, settings_screen.dart) are shared
/// across Customer/Hero AND Admin/Seller apps -- but ThemeService is
/// only provided in the Customer + Hero app trees (Admin/Seller keep
/// their own separate fixed dark palette, per Nizam's earlier scoping
/// decision). So this is deliberately defensive: if ThemeService isn't
/// found above this widget in the tree (Admin/Seller case), it silently
/// does nothing and the screen just keeps its default palette values
/// above -- no crash, no exception surfaced to the caller.
void syncAppPalette(BuildContext context) {
  ThemeService ts;
  try {
    ts = Provider.of<ThemeService>(context);
  } catch (_) {
    return;
  }
  final theme = ts.currentTheme;
  final cs = theme.colorScheme;
  kPink = cs.primary;
  kPinkDark = cs.secondary;
  kPinkBg = cs.primary.withValues(alpha: 0.06);
  kBg = theme.scaffoldBackgroundColor;
  kSurface = cs.surface;
  kCard = cs.surface;
  kCard2 = Color.alphaBlend(cs.primary.withValues(alpha: 0.05), cs.surface);
  kText = cs.onSurface;
  kMuted = cs.onSurface.withValues(alpha: 0.55);
  kBorder = theme.dividerColor;
}
