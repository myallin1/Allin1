// ================================================================
// ThemeService — 5-way app theme switcher
// ================================================================
// Per Nizam's request: instead of the old 2-option (Purple/NJ Tech)
// dropdown, customers can now pick from 5 distinct themes:
//   1. pink_white    — brand pink & white, always light
//   2. dark_purple   — brand purple, always dark
//   3. system_dark   — neutral Material dark (no brand pink), always dark
//   4. system_light  — neutral Material light (no brand pink), always light
//   5. multicolor    — vibrant multi-hue accent theme, light background
// "system_dark"/"system_light" are neutral (non-branded) looks for
// people who want a plain dark/light UI instead of the pink branding
// — they are fixed choices in this dropdown, not tied to the phone's
// OS dark-mode setting (kept simple/predictable, same as the other 3).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// currentAppVariant — the Seller app defaults to a light theme.
import '../config/app_variant.dart';

@immutable
class AppBrandGradients extends ThemeExtension<AppBrandGradients> {
  const AppBrandGradients({
    required this.primary,
    required this.hero,
    required this.surface,
  });

  final LinearGradient primary;
  final LinearGradient hero;
  final LinearGradient surface;

  @override
  AppBrandGradients copyWith({
    LinearGradient? primary,
    LinearGradient? hero,
    LinearGradient? surface,
  }) {
    return AppBrandGradients(
      primary: primary ?? this.primary,
      hero: hero ?? this.hero,
      surface: surface ?? this.surface,
    );
  }

  @override
  AppBrandGradients lerp(ThemeExtension<AppBrandGradients>? other, double t) {
    if (other is! AppBrandGradients) {
      return this;
    }
    return t < 0.5 ? this : other;
  }
}

class AppBrandTheme {
  static const Color white = Color(0xFFFFFBFE);
  static const Color softWhite = Color(0xFFFFF3FA);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color pink = Color(0xFFFF4FA3);
  static const Color magenta = Color(0xFFFF2D92);
  static const Color purple = Color(0xFF9C27FF);
  static const Color deepText = Color(0xFF4A1236);
  static const Color mutedText = Color(0xFF8A4E72);
  static const Color borderPink = Color(0x33FF4FA3);

  // ── Global typography (Font Audit) ──────────────────────────────
  // FIX (Nizam's typography audit): this used to be 'NotoSansTamil' as
  // the ONLY global font, but ~1,150+ screens across the app never
  // actually read Theme.of(context).textTheme -- they bypass it with
  // their own inline GoogleFonts.outfit(...) calls (the overwhelming
  // majority pattern, 1000+ call sites), plus a handful of stray
  // Poppins/Roboto/Inter/Space Grotesk one-offs. The result: bare
  // TextStyle() calls that DON'T go through GoogleFonts (~1,000+ sites,
  // e.g. main_customer.dart, main_admin.dart, dialog/snackbar text)
  // silently rendered in NotoSansTamil while everything else around
  // them rendered in Outfit -- the actual source of the "inconsistent"
  // look. Making 'Outfit' the real global font here means every one of
  // those un-migrated bare TextStyle() calls now automatically matches
  // the dominant Outfit look with zero per-file changes, and Tamil/
  // Hindi/Malayalam script glyphs (which Outfit doesn't cover) still
  // render correctly via the NotoSansTamil fallback below instead of
  // showing tofu boxes.
  static const String brandFontFamily = 'Outfit';
  static const List<String> brandFontFallback = ['NotoSansTamil'];

  // Public (not just used by light()/dark() below) so the admin/seller
  // apps -- which have their own standalone ThemeData rather than going
  // through ThemeService -- can apply the exact same Outfit +
  // NotoSansTamil-fallback text theme instead of drifting to a 3rd look.
  static TextTheme brandTextTheme(
    TextTheme base, {
    required Color bodyColor,
    required Color displayColor,
  }) {
    final outfit = GoogleFonts.outfitTextTheme(base);
    TextStyle? withFallback(TextStyle? style) =>
        style?.copyWith(fontFamilyFallback: brandFontFallback);
    return TextTheme(
      displayLarge: withFallback(outfit.displayLarge),
      displayMedium: withFallback(outfit.displayMedium),
      displaySmall: withFallback(outfit.displaySmall),
      headlineLarge: withFallback(outfit.headlineLarge),
      headlineMedium: withFallback(outfit.headlineMedium),
      headlineSmall: withFallback(outfit.headlineSmall),
      titleLarge: withFallback(outfit.titleLarge),
      titleMedium: withFallback(outfit.titleMedium),
      titleSmall: withFallback(outfit.titleSmall),
      bodyLarge: withFallback(outfit.bodyLarge),
      bodyMedium: withFallback(outfit.bodyMedium),
      bodySmall: withFallback(outfit.bodySmall),
      labelLarge: withFallback(outfit.labelLarge),
      labelMedium: withFallback(outfit.labelMedium),
      labelSmall: withFallback(outfit.labelSmall),
    ).apply(bodyColor: bodyColor, displayColor: displayColor);
  }

  static ThemeData light({
    required Color primary,
    required Color secondary,
    required Color tertiary,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
    ).copyWith(
      primary: primary,
      secondary: secondary,
      tertiary: tertiary,
      surface: surfaceWhite,
      surfaceContainerHighest: softWhite,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: deepText,
      outline: borderPink,
    );

    final gradients = AppBrandGradients(
      primary: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [primary, secondary, tertiary],
      ),
      hero: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomRight,
        colors: [secondary, primary, tertiary],
      ),
      surface: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [white, softWhite, Color(0xFFFFE3F2)],
      ),
    );

    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      fontFamily: brandFontFamily,
      fontFamilyFallback: brandFontFallback,
      primaryColor: primary,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: scheme,
      canvasColor: Colors.white,
      cardColor: surfaceWhite,
      shadowColor: primary.withValues(alpha: 0.18),
      dividerColor: borderPink,
      splashColor: primary.withValues(alpha: 0.08),
      highlightColor: secondary.withValues(alpha: 0.08),
      textTheme: brandTextTheme(
        ThemeData.light().textTheme,
        bodyColor: deepText,
        displayColor: deepText,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: primary,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: deepText,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: surfaceWhite,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: borderPink),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: borderPink),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: softWhite,
        hintStyle: const TextStyle(color: mutedText),
        prefixIconColor: primary,
        suffixIconColor: primary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: borderPink),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: borderPink),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: primary, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: borderPink),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
      iconTheme: IconThemeData(color: primary),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceWhite,
        indicatorColor: secondary.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? primary : mutedText,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected) ? primary : mutedText,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[gradients],
    );
  }

  // ── Dark variant (added for dark_purple / system_dark themes) ──
  static ThemeData dark({
    required Color primary,
    required Color secondary,
    required Color tertiary,
    Color background = const Color(0xFF0A0A1A),
    Color surface = const Color(0xFF16162A),
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: primary,
      secondary: secondary,
      tertiary: tertiary,
      surface: surface,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: const Color(0xFFEEEEF5),
      outline: primary.withValues(alpha: 0.25),
    );

    final gradients = AppBrandGradients(
      primary: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [primary, secondary, tertiary],
      ),
      hero: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomRight,
        colors: [secondary, primary, tertiary],
      ),
      surface: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [background, surface],
      ),
    );

    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: brandFontFamily,
      fontFamilyFallback: brandFontFallback,
      primaryColor: primary,
      scaffoldBackgroundColor: background,
      colorScheme: scheme,
      canvasColor: background,
      cardColor: surface,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      dividerColor: primary.withValues(alpha: 0.2),
      splashColor: primary.withValues(alpha: 0.12),
      highlightColor: secondary.withValues(alpha: 0.12),
      textTheme: brandTextTheme(
        ThemeData.dark().textTheme,
        bodyColor: const Color(0xFFEEEEF5),
        displayColor: const Color(0xFFEEEEF5),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: primary,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: const Color(0xFFEEEEF5),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: primary.withValues(alpha: 0.2)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: primary.withValues(alpha: 0.2)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: background,
        hintStyle: const TextStyle(color: Color(0xFF9999BB)),
        prefixIconColor: primary,
        suffixIconColor: primary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: primary.withValues(alpha: 0.25)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: primary.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: primary, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
      iconTheme: IconThemeData(color: primary),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: secondary.withValues(alpha: 0.25),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? primary : const Color(0xFF9999BB),
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected) ? primary : const Color(0xFF9999BB),
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[gradients],
    );
  }
}

// ── Theme #1: Pink & White (brand, always light) ──────────────
class NJPinkWhiteTheme {
  static ThemeData light() {
    return AppBrandTheme.light(
      primary: const Color(0xFFFF4FA3),
      secondary: const Color(0xFFFF6FBE),
      tertiary: const Color(0xFFB21FFF),
    );
  }
}

// ── Theme #2: Dark Purple (brand, always dark) ─────────────────
class DarkPurpleTheme {
  static ThemeData dark() {
    return AppBrandTheme.dark(
      primary: const Color(0xFF9C27FF),
      secondary: const Color(0xFFB21FFF),
      tertiary: const Color(0xFFFF4FA3),
    );
  }
}

// Kept for backwards-compat with any old call sites.
class PurpleTheme {
  static ThemeData light() => OriginalPurpleTheme.light();
}

class OriginalPurpleTheme {
  static ThemeData light() {
    return AppBrandTheme.light(
      primary: const Color(0xFF9C27FF),
      secondary: const Color(0xFFFF4FA3),
      tertiary: const Color(0xFFFF82D0),
    );
  }
}

// ── Theme #3: System Dark (neutral, no brand pink, always dark) ──
class SystemDarkTheme {
  static ThemeData dark() {
    return AppBrandTheme.dark(
      primary: const Color(0xFF6C8CFF),
      secondary: const Color(0xFF8FA6FF),
      tertiary: const Color(0xFF4FD1C5),
      background: const Color(0xFF121212),
      surface: const Color(0xFF1E1E1E),
    );
  }
}

// ── Theme #4: System Light (neutral, no brand pink, always light) ──
class SystemLightTheme {
  static ThemeData light() {
    return AppBrandTheme.light(
      primary: const Color(0xFF3B5BFF),
      secondary: const Color(0xFF5C7CFF),
      tertiary: const Color(0xFF00B8A9),
    );
  }
}

// ── Theme #5: Multicolor (vibrant multi-hue accents, light bg) ──
class MulticolorTheme {
  static ThemeData light() {
    final base = AppBrandTheme.light(
      primary: const Color(0xFFFF6B35),
      secondary: const Color(0xFF4FD1C5),
      tertiary: const Color(0xFF6C63FF),
    );
    // Extra rainbow-ish gradient used by screens that opt into the
    // multicolor look explicitly via Theme.of(context).extension.
    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[
        const AppBrandGradients(
          primary: LinearGradient(
            colors: [Color(0xFFFF6B35), Color(0xFFFFC900), Color(0xFF4FD1C5), Color(0xFF6C63FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          hero: LinearGradient(
            colors: [Color(0xFF6C63FF), Color(0xFF4FD1C5), Color(0xFFFFC900), Color(0xFFFF6B35)],
            begin: Alignment.topCenter,
            end: Alignment.bottomRight,
          ),
          surface: LinearGradient(
            colors: [Colors.white, Color(0xFFFFF3E0), Color(0xFFE0F7FA)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ],
    );
  }
}

class ThemeService extends ChangeNotifier {
  ThemeService() {
    unawaited(_loadTheme());
  }

  static const String _prefsKey = 'customer_theme_key';

  // FIX (Nizam's 5-theme request): expanded from the old 2-option
  // (purple/nj_tech) dropdown to 5 distinct themes. Old saved
  // 'purple'/'nj_tech' values are mapped forward in _loadTheme() so
  // existing installs don't reset to a random theme after this update.
  static const List<String> themeKeys = [
    'pink_white',
    'dark_purple',
    'system_dark',
    'system_light',
    'multicolor',
  ];

  // DEFAULT PER APP (Aug 19 2026, Nizam: sellers rejected the dark UI —
  // "business dull feel iruku dark la").
  //
  // The Seller app now starts on a LIGHT theme. Only the default
  // changes: the picker in seller_settings_screen still offers all five,
  // and a seller who has already chosen one keeps it, because
  // _loadTheme() overwrites this with their saved value on startup.
  //
  // Customer/Hero/Admin are untouched and still open on pink_white.
  String _themeKey =
      currentAppVariant == 'seller' ? 'system_light' : 'pink_white';

  String get themeKey => _themeKey;

  String get themeLabel {
    switch (_themeKey) {
      case 'dark_purple':
        return 'Dark Purple';
      case 'system_dark':
        return 'System Dark';
      case 'system_light':
        return 'System Light';
      case 'multicolor':
        return 'Multicolor';
      case 'pink_white':
      default:
        return 'Pink & White';
    }
  }

  bool get isDark => _themeKey == 'dark_purple' || _themeKey == 'system_dark';

  ThemeData get currentTheme {
    switch (_themeKey) {
      case 'dark_purple':
        return DarkPurpleTheme.dark();
      case 'system_dark':
        return SystemDarkTheme.dark();
      case 'system_light':
        return SystemLightTheme.light();
      case 'multicolor':
        return MulticolorTheme.light();
      case 'pink_white':
      default:
        return NJPinkWhiteTheme.light();
    }
  }

  Future<void> setTheme(String themeKey) async {
    if (themeKey == _themeKey) {
      return;
    }

    _themeKey = themeKey;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _themeKey);
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString(_prefsKey);
    if (savedTheme == null) {
      return;
    }

    // Map old 2-theme keys forward so existing installs keep a sensible
    // equivalent instead of silently resetting.
    final resolved = switch (savedTheme) {
      'nj_tech' => 'pink_white',
      'purple' => 'dark_purple',
      _ when themeKeys.contains(savedTheme) => savedTheme,
      _ => _themeKey,
    };

    if (resolved == _themeKey) {
      return;
    }

    _themeKey = resolved;
    notifyListeners();
  }
}
