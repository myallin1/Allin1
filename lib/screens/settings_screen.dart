// ================================================================
// Settings Screen - App Settings & Preferences
// Allin1 Super App
// ================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

import '../services/ai_activation_service.dart';
import '../services/map_service.dart';
import '../services/theme_service.dart';
import 'ai_settings_screen.dart';

const Color kSurface = Color(0xFF0D0D18);
const Color kCard = Color(0xFF141420);
const Color kCard2 = Color(0xFF1A1A28);
const Color kPurple = Color(0xFF7B6FE0);
const Color kPurple2 = Color(0xFF7B6FE0);
const Color kOrange = Color(0xFFE07C6F);
const Color kGreen = Color(0xFF3DBA6F);
const Color kGold = Color(0xFFF5C542);
const Color kRed = Color(0xFFE05555);
const Color kText = Color(0xFFEEEEF5);
const Color kMuted = Color(0xFF7777A0);
const Color kBorder = Color(0x267B6FE0);

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
  Future<void> _initServices() async {
    try {
      _settingsBox = Hive.isBoxOpen('settings')
          ? Hive.box('settings')
          : await Hive.openBox('settings');
      _mapService = MapService();
      if (!_mapService.isInitialized) {
        await _mapService.initialize();
      }
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
  }

  @override
  void dispose() {
    super.dispose();
  }

  // FIX #3: Load settings with mounted check
  Future<void> _loadSettings() async {
    try {
      final box = _settingsBox;
      final langCode =
          box.get('language_code', defaultValue: 'english') as String;
      final currency = box.get('currency', defaultValue: 'INR (₹)') as String;
      final notifications =
          box.get('notifications', defaultValue: true) as bool;
      final rideAlerts = box.get('rideAlerts', defaultValue: true) as bool;
      final promotions = box.get('promotions', defaultValue: false) as bool;
      final location = box.get('location', defaultValue: true) as bool;
      final biometric = box.get('biometric', defaultValue: false) as bool;

      if (!mounted) return;
      setState(() {
        _selectedLanguage = _getLanguageNameFromCode(langCode);
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
      {'code': 'english', 'name': 'English'},
      {'code': 'tamil', 'name': 'Tamil'},
      {'code': 'thanglish', 'name': 'Thanglish'},
      {'code': 'tamil_tech', 'name': 'Tamil + Tech'},
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
    final themeService = context.watch<ThemeService>();
    final aiActivation = context.watch<AiActivationService>();

    if (_isLoading) {
      return const Scaffold(
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
          icon: const Icon(Icons.arrow_back_ios_new, color: kText),
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
            _buildSectionHeader('Guru AI'),
            const SizedBox(height: 12),
            _buildAiConfigurationSection(aiActivation),
            const SizedBox(height: 28),
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

  Widget _buildPreferenceSettings(ThemeService themeService) {
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
          _buildDivider(),
          _buildThemeTile(themeService),
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
            child: const Icon(Icons.palette_outlined, color: kPurple, size: 20),
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
                  'Choose Purple or NJ Tech instantly',
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
                  value: 'purple',
                  child: Text('Purple'),
                ),
                DropdownMenuItem(
                  value: 'nj_tech',
                  child: Text('NJ Tech'),
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

  Widget _buildAiConfigurationSection(AiActivationService aiActivation) {
    final activated = aiActivation.isAiActivated;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: kCard2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: activated ? kGreen.withValues(alpha: 0.28) : kBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: activated
                    ? kGreen.withValues(alpha: 0.12)
                    : kPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                activated
                    ? Icons.auto_awesome_rounded
                    : Icons.key_rounded,
                color: activated ? kGreen : kPurple,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Configuration',
                    style: GoogleFonts.outfit(
                      color: kText,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    activated
                        ? 'Guru AI is ready on this device.'
                        : 'Add your Groq API key for advanced BYOK access.',
                    style: GoogleFonts.outfit(
                      color: kMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: activated
                    ? kGreen.withValues(alpha: 0.14)
                    : kOrange.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                activated ? 'Ready' : 'Setup',
                style: GoogleFonts.outfit(
                  color: activated ? kGreen : kOrange,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const AiSettingsScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.chevron_right_rounded, color: kMuted),
            ),
          ],
        ),
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
            onTap: () {},
          ),
          _buildDivider(),
          _buildTapTile(
            icon: Icons.description_outlined,
            title: 'Terms of Service',
            subtitle: 'View terms and conditions',
            onTap: () {},
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
            onTap: () {},
          ),
          _buildDivider(),
          _buildTapTile(
            icon: Icons.share_outlined,
            title: 'Share App',
            subtitle: 'Invite friends to join',
            onTap: () {},
          ),
          _buildDivider(),
          _buildTapTile(
            icon: Icons.help_outline,
            title: 'Help & Support',
            subtitle: 'Get help with issues',
            onTap: () {},
          ),
        ],
      ),
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
              const Icon(Icons.chevron_right, color: kMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(
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

  static const List<Map<String, String>> _languages = [
    {
      'code': 'english',
      'name': 'English',
      'emoji': 'EN',
      'desc': 'All text in English',
    },
    {
      'code': 'tamil',
      'name': 'Tamil',
      'emoji': 'TM',
      'desc': 'Muzukka Tamilil',
    },
    {
      'code': 'thanglish',
      'name': 'Thanglish',
      'emoji': 'TG',
      'desc': 'Tamil words in English letters',
    },
    {
      'code': 'tamil_tech',
      'name': 'Tamil + Tech',
      'emoji': 'TT',
      'desc': 'Mainly Tamil, technical = English',
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
                const Icon(Icons.language_rounded, color: kGold, size: 22),
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
                  _saveSetting('language_code', lang['code'] ?? 'english');
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
          isSelected ? const Icon(Icons.check_circle, color: kGold) : null,
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
