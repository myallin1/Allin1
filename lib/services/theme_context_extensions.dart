// ================================================================
// Theme context extensions — shorthand for migrating screens off
// hardcoded local Color constants and onto ThemeService's already
// dynamic-contrast-correct ColorScheme + universal typography.
// ================================================================
// NEW (CTO mandate — Task 3: Dynamic Text Color & Universal
// Typography). theme_service.dart's ThemeData definitions already do
// the hard part correctly: each theme sets ColorScheme.onSurface (and
// AppBarTheme.foreground, etc.) to a properly-contrasting color for
// its own brightness — light themes get dark text, dark themes get
// light text, automatically, per theme — and every theme already
// shares the exact same brandTextTheme() (Outfit + NotoSansTamil
// fallback) typography scale. The problem this file addresses isn't
// that system; it's that ~70 screens across this app declare their
// OWN local `const Color _bg = Color(0xFF...)` / `const Color _text =
// Color(0xFF...)` constants at the top of the file instead of reading
// Theme.of(context) — so those screens simply never see a theme
// change at all, regardless of how correct the underlying theme
// system is.
//
// These extensions exist to make retrofitting a screen fast and low-
// risk: swap `_bg` for `context.colors.background`, `_text` for
// `context.colors.text`, etc. — one string-replace per file, same
// semantics as the hardcoded constant it replaces, but now reactive.
// This file is additive infrastructure only; it does not itself
// change any screen's rendered output. See PR/patch notes for which
// screens have been migrated so far — a full 70-file sweep was judged
// out of safe scope for a single pass and is a recommended follow-up,
// tackled in prioritized batches (highest-traffic screens first).
import 'package:flutter/material.dart';

/// Semantic color shortcuts. Named for what they MEAN (background,
/// text, muted text, accent) rather than a specific hex value, so a
/// screen using these automatically looks correct in all 5 themes
/// without knowing which one is active.
class AppSemanticColors {
  const AppSemanticColors(this._scheme, this._appBarForeground);
  final ColorScheme _scheme;
  final Color _appBarForeground;

  Color get background => _scheme.surface;
  Color get surface => _scheme.surfaceContainerHighest;
  Color get text => _scheme.onSurface;
  Color get mutedText => _scheme.onSurface.withValues(alpha: 0.6);
  Color get accent => _scheme.primary;
  Color get accentSecondary => _scheme.secondary;
  // NEW (Batch 1 retrofit — guru_chat_screen.dart needed a 3rd accent
  // slot; ThemeData already gives every theme a `tertiary` color, so
  // this maps onto that rather than inventing a new theme concept).
  Color get accentTertiary => _scheme.tertiary;
  Color get border => _scheme.outline;
  Color get appBarForeground => _appBarForeground;
  // NEW (Batch 1 retrofit): a step "up" from `surface` for cards/
  // panels/floating elements that need to sit visually above the
  // scaffold background (e.g. a modal sheet, an elevated icon button
  // background) — distinct from `surface` (already mapped to
  // surfaceContainerHighest) so nested elevation levels stay
  // distinguishable, matching what per-screen `_surfaceElevated` /
  // `_kSurface` constants were doing manually before.
  Color get elevatedSurface => Color.alphaBlend(_scheme.onSurface.withValues(alpha: 0.06), _scheme.surface);
  // A muted, low-contrast fill for things like the customer's own chat
  // bubble — was a fixed dark-purple hex before; this keeps the same
  // "slightly tinted surface" feel across all 5 themes instead of one
  // hardcoded color that could clash with light themes.
  Color get subtleFill => Color.alphaBlend(_scheme.onSurface.withValues(alpha: 0.08), _scheme.surface);
}

extension AppThemeContext on BuildContext {
  AppSemanticColors get colors {
    final theme = Theme.of(this);
    return AppSemanticColors(theme.colorScheme, theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface);
  }

  /// Shorthand for the already-unified brandTextTheme() scale — e.g.
  /// `context.text.bodyMedium` instead of re-declaring a local
  /// GoogleFonts.outfit(...) call with a guessed size/weight.
  TextTheme get textStyles => Theme.of(this).textTheme;
}
