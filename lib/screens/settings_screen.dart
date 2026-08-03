// ================================================================
// Settings Screen - App Settings & Preferences
// Allin1 Super App
// ================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/localization_service.dart';
import '../services/map_service.dart';
import '../services/theme_service.dart';
import '../widgets/server_busy_dialog.dart' show kCallCenterNumberIntl;

// Rate App / Share App links — customer app's actual Play Store
// package name (see android/app/build.gradle.kts customer flavor) and
// its live PWA link.
const String kPlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.njtech.myallin1';
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
    ts = Provider.of<ThemeService>(context, listen: true);
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
  bool _notificationsEnabled = true;
  bool _rideAlertsEnabled = true;
  bool _promotionalAlerts = false;
  final bool _darkModeEnabled = true; // App is already dark
  bool _locationEnabled = true;
  bool _biometricEnabled = false;
  String _selectedLanguage = 'English';
  String _selectedCurrency = 'INR (₹)';

  @override
  void initState() {
    super.initState();
    _initServices();
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
    super.dispose();
  }

  // FIX #3: Load settings with mounted check
  Future<void> _loadSettings() async {
    try {
      final box = _settingsBox;
      final currency = box.get('currency', defaultValue: 'INR (₹)') as String;
      final notifications =
          box.get('notifications', defaultValue: true) as bool;
      final rideAlerts = box.get('rideAlerts', defaultValue: true) as bool;
      final promotions = box.get('promotions', defaultValue: false) as bool;
      final location = box.get('location', defaultValue: true) as bool;
      final biometric = box.get('biometric', defaultValue: false) as bool;

      if (!mounted) return;
      // Language now reads from the real, app-wide LocalizationService
      // (via Provider) instead of this screen's own local Hive key —
      // that old 'language_code' key was never read by anything else,
      // so picking a language here never actually changed any text.
      // See localization_service.dart.
      final languageCode = context.read<LocalizationService>().languageCode;
      setState(() {
        _selectedLanguage = _getLanguageNameFromCode(languageCode);
        _selectedCurrency = currency;
        _notificationsEnabled = notifications;
        _rideAlertsEnabled = rideAlerts;
        _promotionalAlerts = promotions;
        _locationEnabled = location;
        _biometricEnabled = biometric;
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
        body: Center(child: CircularProgressIndicator(color: kGold)),
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
          'Settings',
          style: GoogleFonts.outfit(color: kText, fontWeight: FontWeight.w600),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Notifications'),
            const SizedBox(height: 12),
            _buildNotificationSettings(),
            const SizedBox(height: 28),
            _buildSectionHeader('Preferences'),
            const SizedBox(height: 12),
            _buildPreferenceSettings(themeService),
            const SizedBox(height: 28),
            // FIX (per Nizam's explicit request): removed the "Guru AI"
            // settings section here — it let customers paste their OWN
            // Groq API key directly (a raw key-input TextField in
            // AiSettingsScreen), which both bypassed and exposed the
            // intended activation flow (customer WhatsApps a claim ->
            // we manually add their key server-side, see
            // rewards_screen.dart's _AiQuizDialog). Nothing about that
            // manual admin step should ever be visible to customers, and
            // letting them self-serve their own key defeated the entire
            // point of it being an admin-controlled reward.
            _buildSectionHeader('🗺️ Map Provider'),
            const SizedBox(height: 12),
            _buildMapProviderSettings(),
            const SizedBox(height: 28),
            _buildSectionHeader('Language & Region'),
            const SizedBox(height: 12),
            _buildLanguageSettings(),
            const SizedBox(height: 28),
            _buildSectionHeader('Privacy & Security'),
            const SizedBox(height: 12),
            _buildPrivacySettings(),
            const SizedBox(height: 28),
            _buildSectionHeader('About'),
            const SizedBox(height: 12),
            _buildAboutSection(),
            const SizedBox(height: 40),
            _buildAppVersion(),
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

  Widget _buildNotificationSettings() {
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
            title: 'Push Notifications',
            subtitle: 'Receive push notifications',
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
            title: 'Ride Alerts',
            subtitle: 'Get updates about your rides',
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
            title: 'Promotional Alerts',
            subtitle: 'Offers and deals',
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

  Widget _buildPreferenceSettings(ThemeService? themeService) {
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
            title: 'Location Services',
            subtitle: 'Allow app to access location',
            value: _locationEnabled,
            onChanged: (v) {
              if (!mounted) return;
              setState(() => _locationEnabled = v);
              _saveSetting('location', v);
            },
          ),
          _buildDivider(),
          _buildSwitchTile(
            icon: Icons.fingerprint,
            title: 'Biometric Login',
            subtitle: 'Use fingerprint for quick login',
            value: _biometricEnabled,
            onChanged: (v) {
              if (!mounted) return;
              setState(() => _biometricEnabled = v);
              _saveSetting('biometric', v);
            },
          ),
          _buildDivider(),
          _buildSwitchTile(
            icon: Icons.dark_mode_outlined,
            title: 'Dark Mode',
            subtitle: 'Dark theme is currently active',
            value: _darkModeEnabled,
            onChanged: null,
          ),
          if (themeService != null) ...[
            _buildDivider(),
            _buildThemeTile(themeService),
          ],
        ],
      ),
    );
  }

  Widget _buildThemeTile(ThemeService themeService) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.palette_outlined, color: kPurple, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Theme',
                  style: GoogleFonts.outfit(
                    color: kText,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Pick your favourite look',
                  style: GoogleFonts.outfit(
                    color: kMuted,
                    fontSize: 12,
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
  Widget _buildMapProviderSettings() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kCard2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          _buildMapProviderInfoTile(),
        ],
      ),
    );
  }

  Widget _buildMapProviderInfoTile() {
    return ListenableBuilder(
      listenable: _mapService,
      builder: (context, _) {
        final provider = _mapService.selectedProvider;
        final isFallback = _mapService.isUsingFallback;
        final isOla = provider == MapProviderType.ola;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Map Provider (Auto-Managed)',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isFallback
                          ? 'Using OpenStreetMap (Ola Maps unavailable)'
                          : 'Using Ola Maps (Primary)',
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



  Widget _buildLanguageSettings() {
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
            title: 'Language',
            subtitle: _selectedLanguage,
            onTap: _showLanguagePicker,
          ),
          _buildDivider(),
          _buildTapTile(
            icon: Icons.currency_exchange,
            title: 'Currency',
            subtitle: _selectedCurrency,
            onTap: _showCurrencyPicker,
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

  Widget _buildPrivacySettings() {
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
            title: 'Privacy Policy',
            subtitle: 'View our privacy policy',
            onTap: () => _openLegalPage('privacy.html'),
          ),
          _buildDivider(),
          _buildTapTile(
            icon: Icons.description_outlined,
            title: 'Terms of Service',
            subtitle: 'View terms and conditions',
            onTap: () => _openLegalPage('terms.html'),
          ),
          _buildDivider(),
          _buildTapTile(
            icon: Icons.delete_outline,
            title: 'Delete Account',
            subtitle: 'Permanently delete your account',
            titleColor: kRed,
            onTap: _showDeleteAccountDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection() {
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
            title: 'Rate App',
            subtitle: 'Rate us on Play Store',
            onTap: _rateApp,
          ),
          _buildDivider(),
          _buildTapTile(
            icon: Icons.share_outlined,
            title: 'Share App',
            subtitle: 'Invite friends to join',
            onTap: _shareApp,
          ),
          _buildDivider(),
          _buildTapTile(
            icon: Icons.help_outline,
            title: 'Help & Support',
            subtitle: 'Get help with issues',
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
        'Try myallin1 — Erode\'s own super app for bike taxi, food, grocery & more, all in one place!\n$kCustomerAppShareUrl';
    await Clipboard.setData(const ClipboardData(text: message));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied! Share it with your friends.')),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open link: $url')),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: kPurple, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    color: kText,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    color: kMuted,
                    fontSize: 12,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kPurple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: kPurple, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        color: titleColor ?? kText,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.outfit(
                        color: kMuted,
                        fontSize: 12,
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

  Widget _buildAppVersion() {
    return Center(
      child: Column(
        children: [
          Text(
            'Allin1 Super App',
            style: GoogleFonts.outfit(
              color: kText,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Version 1.0.0 (Build 1)',
            style: GoogleFonts.outfit(
              color: kMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Made with ❤️ in Erode',
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
  // (en/ta/tg/hi) — see localization_service.dart.
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
  ];

  void _showLanguagePicker() {
    const List<Map<String, String>> langs = _languages;
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
                Icon(Icons.language_rounded, color: kGold, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Language / Mozhi',
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
              'App text style select pannunga',
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
                        Icon(
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

  void _showCurrencyPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kCard2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Currency',
              style: GoogleFonts.outfit(
                color: kText,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _buildCurrencyOption(ctx, 'INR (₹)', 'Indian Rupee'),
            _buildCurrencyOption(ctx, r'USD ($)', 'US Dollar'),
            _buildCurrencyOption(ctx, 'EUR (€)', 'Euro'),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrencyOption(BuildContext ctx, String currency, String name) {
    final isSelected = _selectedCurrency == currency;
    return ListTile(
      onTap: () {
        if (!mounted) return;
        setState(() => _selectedCurrency = currency);
        _saveSetting('currency', currency);
        Navigator.of(ctx).pop();
      },
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isSelected ? kGold.withValues(alpha: 0.1) : kCard,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            currency.split(' ')[0],
            style: GoogleFonts.outfit(
              color: isSelected ? kGold : kMuted,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      title: Text(name, style: GoogleFonts.outfit(color: kText)),
      trailing:
          isSelected ? Icon(Icons.check_circle, color: kGold) : null,
    );
  }

  void _showDeleteAccountDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Account?',
          style: GoogleFonts.outfit(color: kText, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'This action cannot be undone. All your data including ride history, saved addresses, and payment methods will be permanently deleted.',
          style: GoogleFonts.outfit(color: kMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: kMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Account deletion requested. Contact support for assistance.',
                    style: GoogleFonts.notoSansTamil(color: Colors.white),
                  ),
                  backgroundColor: kOrange,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Text(
              'Delete',
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
