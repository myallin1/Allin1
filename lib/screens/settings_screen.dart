// ================================================================
// Settings Screen - App Settings & Preferences
// Allin1 Super App
// ================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, HapticFeedback;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/ai_activation_service.dart';
import '../services/localization_service.dart';
import '../services/map_service.dart';
import '../services/theme_service.dart';
import '../widgets/server_busy_dialog.dart' show kCallCenterNumberIntl;
import 'ai_settings_screen.dart';

// Rate App / Share App links — customer app's actual Play Store
// package name (see android/app/build.gradle.kts customer flavor) and
// its live PWA link.
// NEW (CTO mandate — Naming Standardization): updated to match the
// customer flavor's new applicationId (com.njtech.allin1.customer,
// was com.njtech.myallin1) — kept in sync since neither app is live
// on the Play Store yet, so there's no existing listing this could
// break.
const String kPlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.njtech.allin1.customer';
const String kCustomerAppShareUrl = 'https://my-allin1.web.app';

// NOTE (Nizam's full Option 2 rollout): the theme dropdown further down
// this screen already reads/writes ThemeService correctly -- but the
// screen's own background/card/text colors below were still these old
// hardcoded constants, so picking a theme never visibly changed the
// Settings page itself. kPurple/kPurple2 here are this screen's
// PRIMARY/SECONDARY brand color (not a decorative accent), so they get
// their own local sync rather than the shared app_palette.dart.
Color kSurface = const Color(0xFF0D0D18);
Color kCard    = const Color(0xFF141420);
Color kCard2   = const Color(0xFF1A1A28);
Color kPurple  = const Color(0xFF7B6FE0);
Color kPurple2 = const Color(0xFF7B6FE0);
Color kText    = const Color(0xFFEEEEF5);
Color kMuted   = const Color(0xFF7777A0);
Color kBorder  = const Color(0x267B6FE0);
const Color kOrange = Color(0xFFE07C6F);
const Color kGreen  = Color(0xFF3DBA6F);
const Color kGold   = Color(0xFFF5C542);
const Color kRed    = Color(0xFFE05555);

void _syncSettingsPalette(BuildContext context) {
  ThemeService ts;
  try {
    ts = Provider.of<ThemeService>(context);
  } catch (_) {
    return;
  }
  final theme = ts.currentTheme;
  final cs = theme.colorScheme;
  kPurple = cs.primary;
  kPurple2 = cs.secondary;
  kSurface = cs.surface;
  kCard = cs.surface;
  kCard2 = Color.alphaBlend(cs.primary.withValues(alpha: 0.06), cs.surface);
  kText = cs.onSurface;
  kMuted = cs.onSurface.withValues(alpha: 0.55);
  kBorder = theme.dividerColor;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // FIX #1: Hive box instance
  late Box<dynamic> _settingsBox;
  late final MapService _mapService;
  // FIX #2: Loading state
  bool _isLoading = true;

  // Settings state
  //
  // FIX (Nizam's request: remove unwanted/dead buttons from Settings):
  // three tiles removed from this screen entirely --
  //   - Biometric Login: local_auth is not a dependency anywhere in
  //     pubspec.yaml, so this switch saved a Hive flag nothing else ever
  //     read. There is no biometric login anywhere in the app.
  //   - Dark Mode: was `onChanged: null` (permanently on, un-tappable) --
  //     dead weight now that the real Theme picker right below it
  //     already gives 5 actual switchable themes. A toggle a customer
  //     can see but can never change just reads as broken.
  //   - Currency: INR/USD/EUR picker whose value (`_selectedCurrency`)
  //     was never read anywhere else in the codebase -- every price in
  //     every screen is hardcoded to INR (this is an Erode-only app).
  //     Picking "USD" here changed nothing.
  bool _notificationsEnabled = true;
  bool _rideAlertsEnabled = true;
  bool _promotionalAlerts = false;
  bool _locationEnabled = true;
  String _selectedLanguage = 'English';

  @override
  void initState() {
    super.initState();
    _initServices();
    unawaited(_loadAiUnlockState());
  }

  // FIX #1: Hive optimization + MapService init safety
  //
  // FIX (Nizam's lag report): this used to `await _mapService.initialize()`
  // — which makes a live network call to check Ola Maps availability,
  // with up to a 5-second timeout (see map_service.dart) — BEFORE
  // flipping _isLoading to false. Every single open of Settings was
  // gated behind that network round-trip even though nothing else on
  // this screen needs it (the map-provider tile below is reactive via
  // ListenableBuilder and updates itself once MapService finishes).
  // Now Hive settings load first (fast, local-only) and the spinner
  // clears immediately; MapService initializes in the background and
  // the map-provider tile just updates in place a moment later.
  Future<void> _initServices() async {
    _mapService = MapService();
    try {
      _settingsBox = Hive.isBoxOpen('settings')
          ? Hive.box('settings')
          : await Hive.openBox('settings');
      await _loadSettings();
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('❌ Init services error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }

    if (!_mapService.isInitialized) {
      unawaited(_mapService.initialize());
    }
  }

  @override
  void dispose() {
    // Leaving this running would fire _openAiSettings() on a disposed
    // State if the customer navigated away mid-hold.
    _holdTimer?.cancel();
    super.dispose();
  }

  // FIX #3: Load settings with mounted check
  Future<void> _loadSettings() async {
    try {
      final box = _settingsBox;
      final notifications =
          box.get('notifications', defaultValue: true) as bool;
      final rideAlerts = box.get('rideAlerts', defaultValue: true) as bool;
      final promotions = box.get('promotions', defaultValue: false) as bool;
      final location = box.get('location', defaultValue: true) as bool;

      if (!mounted) return;
      // Language now reads from the real, app-wide LocalizationService
      // (via Provider) instead of this screen's own local Hive key —
      // that old 'language_code' key was never read by anything else,
      // so picking a language here never actually changed any text.
      // See localization_service.dart.
      final languageCode = context.read<LocalizationService>().languageCode;
      setState(() {
        _selectedLanguage = _getLanguageNameFromCode(languageCode);
        _notificationsEnabled = notifications;
        _rideAlertsEnabled = rideAlerts;
        _promotionalAlerts = promotions;
        _locationEnabled = location;
      });
    } catch (e) {
      debugPrint('❌ Load settings error: $e');
    }
  }

  String _getLanguageNameFromCode(String code) {
    const languages = [
      {'code': 'en', 'name': 'English'},
      {'code': 'ta', 'name': 'Tamil'},
      {'code': 'tg', 'name': 'Thanglish'},
      {'code': 'hi', 'name': 'Hindi'},
      {'code': 'ml', 'name': 'Malayalam'},
    ];
    for (final lang in languages) {
      if (lang['code'] == code) return lang['name']!;
    }
    return 'English';
  }

  Future<void> _saveSetting(String key, value) async {
    try {
      await _settingsBox.put(key, value);
    } catch (e) {
      debugPrint('❌ Save setting error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncSettingsPalette(context);
    // i18n (Nizam's phase 1 request): `watch` so the whole Settings page
    // repaints instantly the moment the customer picks a new language
    // in the picker below -- no restart needed, same live-update
    // mechanism the theme switcher already uses.
    final t = context.watch<LocalizationService>().t;
    // FIX: this screen is shared -- Admin app also navigates here (see
    // admin_dashboard_screen.dart / super_admin_home_screen.dart) but
    // never provides ThemeService, so the previous unconditional
    // `context.watch<ThemeService>()` here would throw and crash the
    // whole Settings page for admins. Made defensive/nullable; the
    // Theme picker tile below (_buildThemeTile) only renders when this
    // is non-null.
    ThemeService? themeService;
    try {
      themeService = context.watch<ThemeService>();
    } catch (_) {
      themeService = null;
    }

    if (_isLoading) {
      return Scaffold(
        backgroundColor: kSurface,
        body: const Center(child: CircularProgressIndicator(color: kGold)),
      );
    }

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: kText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          t('settings_title'),
          style: GoogleFonts.outfit(color: kText, fontWeight: FontWeight.w600),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(t('notifications_section')),
            const SizedBox(height: 12),
            _buildNotificationSettings(t),
            const SizedBox(height: 28),
            _buildSectionHeader(t('preferences_section')),
            const SizedBox(height: 12),
            _buildPreferenceSettings(themeService, t),
            const SizedBox(height: 28),
            // FIX (per Nizam/CTO's "bring your own key" pivot — reverses
            // the earlier removal noted below): customers now activate
            // their OWN "AI superhero" by pasting a free Groq API key
            // here, decentralizing AI cost off Allin1's own admin-
            // provisioned keys. The old WhatsApp-claim flow in
            // rewards_screen.dart's _AiQuizDialog still exists for
            // customers who'd rather not self-serve a key; this is an
            // additional path, not a replacement.
            //
            // (Historical note, kept for context: this section was
            // previously removed because letting customers self-serve a
            // key bypassed an admin-controlled reward flow. That's no
            // longer the product direction — see AiSettingsScreen /
            // AiActivationService.)
            _buildSectionHeader('🦸 AI Assistant'),
            const SizedBox(height: 12),
            _buildAiAssistantSettings(),
            const SizedBox(height: 28),
            _buildSectionHeader('🗺️ ${t('map_provider_section')}'),
            const SizedBox(height: 12),
            _buildMapProviderSettings(t),
            const SizedBox(height: 28),
            _buildSectionHeader(t('language_region_section')),
            const SizedBox(height: 12),
            _buildLanguageSettings(t),
            const SizedBox(height: 28),
            _buildSectionHeader(t('privacy_security_section')),
            const SizedBox(height: 12),
            _buildPrivacySettings(t),
            const SizedBox(height: 28),
            _buildSectionHeader(t('about_section')),
            const SizedBox(height: 12),
            _buildAboutSection(t),
            const SizedBox(height: 40),
            _buildAppVersion(t),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: GoogleFonts.outfit(
        color: kMuted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildNotificationSettings(String Function(String) t) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kCard2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          _buildSwitchTile(
            icon: Icons.notifications_outlined,
            title: t('push_notifications_title'),
            subtitle: t('push_notifications_subtitle'),
            value: _notificationsEnabled,
            onChanged: (v) {
              if (!mounted) return;
              setState(() => _notificationsEnabled = v);
              _saveSetting('notifications', v);
            },
          ),
          _buildDivider(),
          _buildSwitchTile(
            icon: Icons.directions_car_outlined,
            title: t('ride_alerts_title'),
            subtitle: t('ride_alerts_subtitle'),
            value: _rideAlertsEnabled,
            onChanged: (v) {
              if (!mounted) return;
              setState(() => _rideAlertsEnabled = v);
              _saveSetting('rideAlerts', v);
            },
          ),
          _buildDivider(),
          _buildSwitchTile(
            icon: Icons.campaign_outlined,
            title: t('promotional_alerts_title'),
            subtitle: t('promotional_alerts_subtitle'),
            value: _promotionalAlerts,
            onChanged: (v) {
              if (!mounted) return;
              setState(() => _promotionalAlerts = v);
              _saveSetting('promotions', v);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPreferenceSettings(ThemeService? themeService, String Function(String) t) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kCard2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          _buildSwitchTile(
            icon: Icons.location_on_outlined,
            title: t('location_services_title'),
            subtitle: t('location_services_subtitle'),
            value: _locationEnabled,
            onChanged: (v) {
              if (!mounted) return;
              setState(() => _locationEnabled = v);
              _saveSetting('location', v);
            },
          ),
          if (themeService != null) ...[
            _buildDivider(),
            _buildThemeTile(themeService, t),
          ],
        ],
      ),
    );
  }

  Widget _buildThemeTile(ThemeService themeService, String Function(String) t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.palette_outlined, color: kPurple, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('theme_title'),
                  style: GoogleFonts.outfit(
                    color: kText,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  t('theme_subtitle'),
                  style: GoogleFonts.outfit(
                    color: kMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: themeService.themeKey,
              dropdownColor: kCard,
              style: GoogleFonts.outfit(color: kText, fontSize: 13),
              items: const [
                DropdownMenuItem(
                  value: 'pink_white',
                  child: Text('Pink & White'),
                ),
                DropdownMenuItem(
                  value: 'dark_purple',
                  child: Text('Dark Purple'),
                ),
                DropdownMenuItem(
                  value: 'system_dark',
                  child: Text('System Dark'),
                ),
                DropdownMenuItem(
                  value: 'system_light',
                  child: Text('System Light'),
                ),
                DropdownMenuItem(
                  value: 'multicolor',
                  child: Text('Multicolor'),
                ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                themeService.setTheme(value);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Map Provider Settings ──
  // NEW (per Nizam/CTO's "bring your own key" pivot): premium entry
  // point into AiSettingsScreen, styled to stand out from the plain
  // _buildTapTile rows elsewhere on this page (gradient badge icon,
  // live activation-status subtitle) since this is meant to read as an
  // exciting feature, not routine account settings.
  // ── HIDDEN UNLOCK (Aug 19 2026, Nizam) ─────────────────────────
  // The AI configuration screen asks the customer to paste a Groq API
  // key. That is a power-user action: someone who wanders into it by
  // accident just sees a form they cannot fill in, and a settings page
  // full of things you cannot use reads as broken.
  //
  // So it is gated the way Android gates Developer Options — repeated
  // taps on a visible row. Two stages, per Nizam:
  //   FIRST TIME : 13 taps to unlock it, permanently.
  //   AFTER THAT : a 5-second long-press opens it again.
  //
  // The unlock is PERSISTED, so it survives reopening the app. If it
  // were not, an unlocked user would have to tap 13 times every single
  // session — which is a chore, not a secret.
  //
  // NOTE ON DISCOVERABILITY: 13 taps is deliberately un-findable. That
  // means the ONLY way a customer learns this exists is if you tell
  // them. That's the intent, but it does mean support has to hand out
  // the gesture — worth remembering when someone asks how to activate
  // their key.
  static const int _kAiUnlockTaps = 13;
  static const String _kAiUnlockedPrefsKey = 'ai_config_unlocked';

  int _aiTapCount = 0;
  bool _aiUnlocked = false;
  DateTime? _lastAiTapAt;

  Future<void> _loadAiUnlockState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final unlocked = prefs.getBool(_kAiUnlockedPrefsKey) ?? false;
      if (mounted && unlocked) setState(() => _aiUnlocked = true);
    } catch (_) {
      // Non-fatal: worst case the customer taps 13 times again.
    }
  }

  void _openAiSettings() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const AiSettingsScreen()),
    );
  }

  void _onAiTap() {
    // Already unlocked: taps do nothing. Opening is long-press only
    // from here on, exactly as specified — otherwise the row would be
    // a one-tap shortcut and the long-press would be pointless.
    if (_aiUnlocked) {
      _snack('Press and hold for 5 seconds to open AI settings');
      return;
    }

    // Reset the run if the taps are too far apart, so 13 accidental
    // taps spread over a long session don't add up to an unlock.
    final now = DateTime.now();
    if (_lastAiTapAt != null &&
        now.difference(_lastAiTapAt!) > const Duration(seconds: 2)) {
      _aiTapCount = 0;
    }
    _lastAiTapAt = now;
    _aiTapCount++;

    if (_aiTapCount >= _kAiUnlockTaps) {
      _aiTapCount = 0;
      setState(() => _aiUnlocked = true);
      unawaited(
        SharedPreferences.getInstance()
            .then((p) => p.setBool(_kAiUnlockedPrefsKey, true))
            .catchError((Object _) => false),
      );
      HapticFeedback.heavyImpact();
      _snack('🦸 Chitti unlocked! Press and hold to open.');
      _openAiSettings();
      return;
    }

    // Silent for the first several taps — announcing the countdown from
    // tap one would give the secret away to anyone who brushed the row.
    final left = _kAiUnlockTaps - _aiTapCount;
    if (left <= 5) {
      HapticFeedback.selectionClick();
      _snack('$left more…');
    }
  }

  Timer? _holdTimer;

  /// Starts the 5-second hold. Only meaningful once unlocked — holding
  /// a still-locked row must not become a shortcut past the 13 taps.
  void _startHold() {
    if (!_aiUnlocked) return;
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      _openAiSettings();
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  void _snack(String msg) {
    final messenger = ScaffoldMessenger.of(context)..removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.outfit(fontSize: 12.5)),
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildAiAssistantSettings() {
    final aiActivation = context.watch<AiActivationService>();
    final activated = aiActivation.isAiActivated;

    return Material(
      color: Colors.transparent,
      // GestureDetector, not InkWell.onLongPress: Flutter's built-in
      // long-press fires at ~500ms and is not configurable, and Nizam
      // asked for a FIVE second hold. So the hold is timed manually
      // from the raw press-down/press-up events.
      child: GestureDetector(
        onTap: _onAiTap,
        onTapDown: (_) => _startHold(),
        onTapUp: (_) => _cancelHold(),
        onTapCancel: _cancelHold,
        // A drag off the row is a cancel too — otherwise a scroll that
        // began on this tile would keep the timer running and pop the
        // screen open five seconds into an unrelated gesture.
        onVerticalDragStart: (_) => _cancelHold(),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: activated
                  ? const Color(0x4D00C853)
                  : const Color(0x4DFF4FA3),
            ),
            gradient: LinearGradient(
              colors: activated
                  ? [const Color(0x1A00C853), const Color(0x0D00C853)]
                  : [const Color(0x1AFF4FA3), const Color(0x0DB21FFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF4FA3), Color(0xFFB21FFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  activated ? Icons.auto_awesome_rounded : Icons.bolt_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Single line now, per Nizam — the old two-line
                    // title + subtitle said the same thing twice and
                    // was the tallest row on the page.
                    Text(
                      'Activate ur Own Ai superhero Chitti',
                      style: GoogleFonts.outfit(
                        color: activated ? const Color(0xFF00C853) : kText,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: kMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapProviderSettings(String Function(String) t) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kCard2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          _buildMapProviderInfoTile(t),
        ],
      ),
    );
  }

  Widget _buildMapProviderInfoTile(String Function(String) t) {
    return ListenableBuilder(
      listenable: _mapService,
      builder: (context, _) {
        final provider = _mapService.selectedProvider;
        final isFallback = _mapService.isUsingFallback;
        final isOla = provider == MapProviderType.ola;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isOla
                      ? const Color(0xFFFF6B35).withValues(alpha: 0.1)
                      : const Color(0xFF3DBA6F).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isOla ? Icons.star_rounded : Icons.public_rounded,
                  color: isOla
                      ? const Color(0xFFFF6B35)
                      : const Color(0xFF3DBA6F),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('map_provider_info_title'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isFallback
                          ? t('map_provider_fallback')
                          : t('map_provider_primary'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.info_outline_rounded,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.4),
              ),
            ],
          ),
        );
      },
    );
  }



  Widget _buildLanguageSettings(String Function(String) t) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kCard2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          _buildTapTile(
            icon: Icons.language,
            title: t('language_label'),
            subtitle: _selectedLanguage,
            onTap: _showLanguagePicker,
          ),
        ],
      ),
    );
  }

  // FIX (Play Store pre-submission blocker): these tiles used to be
  // no-op onTap: () {} — Play Console requires a working, reachable
  // privacy policy (and reviewers check Terms too). Both pages are
  // static HTML served alongside every web build (web/privacy.html,
  // web/terms.html — flutter build web copies everything under web/
  // into build/web/ automatically, so they're live at
  // https://my-allin1.web.app/privacy.html the moment the next deploy
  // runs) and reachable from native builds via url_launcher.
  Future<void> _openLegalPage(String fileName) async {
    final url = Uri.parse('https://my-allin1.web.app/$fileName');
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the page. Check your connection.')),
      );
    }
  }

  Widget _buildPrivacySettings(String Function(String) t) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kCard2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          _buildTapTile(
            icon: Icons.privacy_tip_outlined,
            title: t('privacy_policy_title'),
            subtitle: t('privacy_policy_subtitle'),
            onTap: () => _openLegalPage('privacy.html'),
          ),
          _buildDivider(),
          _buildTapTile(
            icon: Icons.description_outlined,
            title: t('terms_title'),
            subtitle: t('terms_subtitle'),
            onTap: () => _openLegalPage('terms.html'),
          ),
          _buildDivider(),
          _buildTapTile(
            icon: Icons.delete_outline,
            title: t('delete_account_title'),
            subtitle: t('delete_account_subtitle'),
            titleColor: kRed,
            onTap: _showDeleteAccountDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection(String Function(String) t) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kCard2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          _buildTapTile(
            icon: Icons.star_outline,
            title: t('rate_app_title'),
            subtitle: t('rate_app_subtitle'),
            onTap: _rateApp,
          ),
          _buildDivider(),
          _buildTapTile(
            icon: Icons.share_outlined,
            title: t('share_app_title'),
            subtitle: t('share_app_subtitle'),
            onTap: _shareApp,
          ),
          _buildDivider(),
          _buildTapTile(
            icon: Icons.help_outline,
            title: t('help_support_title'),
            subtitle: t('help_support_subtitle'),
            onTap: _openHelpAndSupport,
          ),
        ],
      ),
    );
  }

  // FIX (Nizam's audit): Rate App / Share App / Help & Support were
  // dead onTap: () {} no-ops — tapping them visibly did nothing.
  Future<void> _rateApp() async {
    final uri = Uri.parse(kPlayStoreUrl);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _showLinkFailedSnack(kPlayStoreUrl);
    } catch (_) {
      _showLinkFailedSnack(kPlayStoreUrl);
    }
  }

  Future<void> _shareApp() async {
    const message =
        "Try myallin1 — Erode's own super app for bike taxi, food, grocery & more, all in one place!\n$kCustomerAppShareUrl";
    await Clipboard.setData(const ClipboardData(text: message));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.read<LocalizationService>().t('share_link_copied_snack'))),
    );
  }

  Future<void> _openHelpAndSupport() async {
    final message = Uri.encodeComponent('Hi, I need help with the Allin1 app.');
    final uri = Uri.parse('https://wa.me/$kCallCenterNumberIntl?text=$message');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _showLinkFailedSnack('https://wa.me/$kCallCenterNumberIntl');
    } catch (_) {
      _showLinkFailedSnack('https://wa.me/$kCallCenterNumberIntl');
    }
  }

  void _showLinkFailedSnack(String url) {
    if (!mounted) return;
    final t = context.read<LocalizationService>().t;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${t('could_not_open_link_snack')}: $url')),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required void Function(bool)? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: kPurple, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    color: kText,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    color: kMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: kGold,
            activeTrackColor: kGold.withValues(alpha: 0.3),
            inactiveThumbColor: kMuted,
            inactiveTrackColor: kBorder,
          ),
        ],
      ),
    );
  }

  Widget _buildTapTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? titleColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kPurple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: kPurple, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        color: titleColor ?? kText,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.outfit(
                        color: kMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: kMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      color: kBorder,
      height: 1,
      indent: 60,
    );
  }

  Widget _buildAppVersion(String Function(String) t) {
    return Center(
      child: Column(
        children: [
          Text(
            t('app_version_name'),
            style: GoogleFonts.outfit(
              color: kText,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t('app_version_number'),
            style: GoogleFonts.outfit(
              color: kMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t('app_made_with_love'),
            style: GoogleFonts.outfit(
              color: kMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // Codes match LocalizationService's translation-map keys directly
  // (en/ta/tg/hi/ml) — see localization_service.dart.
  static const List<Map<String, String>> _languages = [
    {
      'code': 'en',
      'name': 'English',
      'emoji': 'EN',
      'desc': 'All text in English',
    },
    {
      'code': 'ta',
      'name': 'Tamil',
      'emoji': 'TM',
      'desc': 'Muzukka Tamilil',
    },
    {
      'code': 'tg',
      'name': 'Thanglish',
      'emoji': 'TG',
      'desc': 'Tamil words in English letters',
    },
    {
      'code': 'hi',
      'name': 'Hindi',
      'emoji': 'HI',
      'desc': 'हिन्दी में सब कुछ',
    },
    {
      'code': 'ml',
      'name': 'Malayalam',
      'emoji': 'ML',
      'desc': 'എല്ലാം മലയാളത്തിൽ',
    },
  ];

  void _showLanguagePicker() {
    const List<Map<String, String>> langs = _languages;
    final t = context.read<LocalizationService>().t;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kCard2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: kMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.language_rounded, color: kGold, size: 22),
                const SizedBox(width: 8),
                Text(
                  t('language_picker_title'),
                  style: GoogleFonts.outfit(
                    color: kText,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              t('language_picker_subtitle'),
              style: GoogleFonts.outfit(color: kMuted, fontSize: 11),
            ),
            const SizedBox(height: 20),
            ...langs.map((lang) {
              final isSel = _selectedLanguage == lang['name'];
              return GestureDetector(
                onTap: () {
                  if (!mounted) return;
                  setState(() => _selectedLanguage = lang['name']!);
                  // Real switch — writes through the app-wide
                  // LocalizationService (Provider), which is what
                  // actually changes displayed text, instead of the
                  // old Hive 'language_code' key nothing ever read.
                  unawaited(
                    context
                        .read<LocalizationService>()
                        .setLanguage(lang['code'] ?? 'en'),
                  );
                  Future.delayed(const Duration(milliseconds: 250), () {
                    if (mounted) Navigator.of(ctx).pop();
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSel ? kGold.withValues(alpha: 0.08) : kCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSel
                          ? kGold.withValues(alpha: 0.5)
                          : const Color(0x1AFFFFFF),
                      width: isSel ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isSel
                              ? kGold.withValues(alpha: 0.12)
                              : const Color(0x0FFFFFFF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            lang['emoji']!,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lang['name']!,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: isSel ? kGold : kText,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              lang['desc']!,
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: kMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSel)
                        const Icon(
                          Icons.check_circle_rounded,
                          color: kGold,
                          size: 22,
                        )
                      else
                        const Icon(
                          Icons.radio_button_unchecked,
                          color: Color(0x33FFFFFF),
                          size: 22,
                        ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0x0F7B6FE0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x1A7B6FE0)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 13,
                    color: Color(0xFF9B8FF0),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Language change next restart-la apply agum.',
                      style: GoogleFonts.outfit(fontSize: 10, color: kMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog() {
    final t = context.read<LocalizationService>().t;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          t('delete_account_dialog_title'),
          style: GoogleFonts.outfit(color: kText, fontWeight: FontWeight.w600),
        ),
        content: Text(
          t('delete_account_dialog_body'),
          style: GoogleFonts.outfit(color: kMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('cancel_label'), style: GoogleFonts.outfit(color: kMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    t('delete_account_requested_snack'),
                    style: GoogleFonts.notoSansTamil(color: Colors.white),
                  ),
                  backgroundColor: kOrange,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Text(
              t('delete_label'),
              style: GoogleFonts.outfit(
                color: kRed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
