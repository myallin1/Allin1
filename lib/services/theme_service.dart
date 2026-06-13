import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      fontFamily: 'NotoSansTamil',
      primaryColor: primary,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: scheme,
      canvasColor: Colors.white,
      cardColor: surfaceWhite,
      shadowColor: primary.withValues(alpha: 0.18),
      dividerColor: borderPink,
      splashColor: primary.withValues(alpha: 0.08),
      highlightColor: secondary.withValues(alpha: 0.08),
      textTheme: GoogleFonts.notoSansTamilTextTheme(
        ThemeData.light().textTheme,
      ).apply(
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
}

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

class NJPinkWhiteTheme {
  static ThemeData light() {
    return AppBrandTheme.light(
      primary: const Color(0xFFFF4FA3),
      secondary: const Color(0xFFFF6FBE),
      tertiary: const Color(0xFFB21FFF),
    );
  }
}

class ThemeService extends ChangeNotifier {
  ThemeService() {
    unawaited(_loadTheme());
  }

  static const String _prefsKey = 'customer_theme_key';
  String _themeKey = 'purple';

  String get themeKey => _themeKey;

  String get themeLabel => _themeKey == 'nj_tech' ? 'NJ Tech' : 'Purple';

  ThemeData get currentTheme =>
      _themeKey == 'nj_tech' ? NJPinkWhiteTheme.light() : PurpleTheme.light();

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
    if (savedTheme == null || savedTheme == _themeKey) {
      return;
    }

    _themeKey = savedTheme;
    notifyListeners();
  }
}
