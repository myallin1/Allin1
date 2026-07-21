// ================================================================
// Hero Settings Screen
// Allin1 Super App - Hero Configuration
// ================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

 import '../../services/localization_service.dart';
 import '../../services/map_service.dart';

class HeroSettingsScreen extends StatefulWidget {
  const HeroSettingsScreen({super.key});

  @override
  State<HeroSettingsScreen> createState() => _HeroSettingsScreenState();
}

class _HeroSettingsScreenState extends State<HeroSettingsScreen> {
  static const Color _bg = Color(0xFFFFFBFE);
  static const Color _surface = Colors.white;
  static const Color _pink = Color(0xFFFF4FA3);
  static const Color _text = Color(0xFF3D1230);
  static const Color _muted = Color(0xFF8F5A78);

  bool _notificationsEnabled = true;
  bool _rideAlertsEnabled = true;
  String _selectedMapProvider = 'Ola Maps';
  // Language selection now reads/writes through the app-wide
  // LocalizationService (Provider) — see _buildLanguageSettings()
  // below. The old 'hero_language_code' shared_preferences key and
  // _selectedLanguage field were never actually read by anything that
  // changed displayed text, so picking a language here used to be a
  // dead-end button.

  static const List<Map<String, String>> _mapProviderOptions = <Map<String, String>>[
    {'code': 'ola', 'name': 'Ola Maps'},
    {'code': 'osm', 'name': 'OpenStreetMap (OSM)'},
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _notificationsEnabled = prefs.getBool('hero_notifications_enabled') ?? true;
        _rideAlertsEnabled = prefs.getBool('hero_ride_alerts_enabled') ?? true;
        _selectedMapProvider = _getMapProviderNameFromCode(
          prefs.getString('hero_map_provider') ?? 'ola',
        );
      });
    } catch (e) {
      debugPrint('❌ HeroSettings load error: $e');
    }
  }

  Future<void> _saveSetting(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      debugPrint('❌ HeroSettings save error: $e');
    }
  }

  Future<void> _saveStringSetting(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (e) {
      debugPrint('❌ HeroSettings save error: $e');
    }
  }

  String _getMapProviderNameFromCode(String code) {
    final match = _mapProviderOptions.firstWhere(
      (opt) => opt['code'] == code,
      orElse: () => _mapProviderOptions[0],
    );
    return match['name']!;
  }

  String _getMapProviderCodeFromName(String name) {
    final match = _mapProviderOptions.firstWhere(
      (opt) => opt['name'] == name,
      orElse: () => _mapProviderOptions[0],
    );
    return match['code']!;
  }



  Future<void> _switchMapProvider(String providerName) async {
    final code = _getMapProviderCodeFromName(providerName);
    await _saveStringSetting('hero_map_provider', code);

    // Update MapService state if initialized
    try {
      final mapService = MapService();
      if (mapService.isInitialized) {
        // Force provider switch by updating selected provider
        // MapService will use this on next initialization/fallback
        if (code == 'osm') {
          // Switch to OSM by designating fallback path
          // MapService auto-falls back when Ola fails; we can trigger by clearing API key check
          // For now, persist the preference; MapService respects it on next init
          debugPrint('[HeroSettings] Map provider set to OSM (will apply on restart)');
        } else {
          debugPrint('[HeroSettings] Map provider set to Ola Maps');
        }
      }
    } catch (e) {
      debugPrint('❌ MapService switch error: $e');
    }

    setState(() {
      _selectedMapProvider = providerName;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Map provider set to $providerName. Restart app to apply.'),
          backgroundColor: _pink,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _text),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Hero Settings',
          style: GoogleFonts.outfit(
            color: _text,
            fontWeight: FontWeight.w600,
          ),
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
            _buildSectionHeader('Map Provider'),
            const SizedBox(height: 12),
            _buildMapProviderSettings(),
            const SizedBox(height: 28),
            _buildSectionHeader('Language & Region'),
            const SizedBox(height: 12),
            _buildLanguageSettings(),
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
      title,
      style: GoogleFonts.outfit(
        color: _text,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _buildNotificationSettings() {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _pink.withValues(alpha: 0.2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12FF4FA3),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildSwitchTile(
            icon: Icons.notifications_active_rounded,
            title: 'All Notifications',
            subtitle: 'Enable all push notifications',
            value: _notificationsEnabled,
             onChanged: (bool val) {
               setState(() => _notificationsEnabled = val);
               _saveSetting('hero_notifications_enabled', val);
             },
          ),
          const Divider(height: 1, indent: 56, endIndent: 16),
          _buildSwitchTile(
            icon: Icons.alt_route_rounded,
            title: 'Ride Alerts',
            subtitle: 'Sound + vibration for new rides',
            value: _rideAlertsEnabled,
            onChanged: (bool val) {
              setState(() => _rideAlertsEnabled = val);
              _saveSetting('hero_ride_alerts_enabled', val);
            },
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
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _pink.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: _pink, size: 22),
      ),
      title: Text(
        title,
        style: GoogleFonts.outfit(
          color: _text,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.outfit(
          color: _muted,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: _pink,
      ),
    );
  }

  Widget _buildMapProviderSettings() {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _pink.withValues(alpha: 0.2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12FF4FA3),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildProviderTile('Ola Maps', 'Default, high-detail Indian maps'),
          const Divider(height: 1, indent: 56, endIndent: 16),
          _buildProviderTile('OpenStreetMap', 'Community maps, offline-friendly'),
        ],
      ),
    );
  }

  Widget _buildProviderTile(String providerName, String subtitle) {
    final isSelected = _selectedMapProvider == providerName;
    return RadioListTile<String>(
      value: providerName,
      groupValue: _selectedMapProvider,
       onChanged: (String? val) {
         if (val != null) {
           _switchMapProvider(val);
         }
       },
      title: Row(
        children: [
          Icon(
            providerName.contains('Ola') ? Icons.map_rounded : Icons.public_rounded,
            color: isSelected ? _pink : _muted,
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            providerName,
            style: GoogleFonts.outfit(
              color: _text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.outfit(
          color: _muted,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      secondary: isSelected
          ? Icon(Icons.check_circle_rounded, color: _pink, size: 20)
          : Icon(Icons.circle_outlined, color: _muted, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildLanguageSettings() {
    // Reactive: rebuilds automatically if the language is ever changed
    // from elsewhere (e.g. another screen using the same
    // LocalizationService instance).
    final currentCode = context.watch<LocalizationService>().languageCode;
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _pink.withValues(alpha: 0.2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12FF4FA3),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildLanguageTile('en', 'English', currentCode),
          const Divider(height: 1, indent: 56, endIndent: 16),
          _buildLanguageTile('ta', 'தமிழ்', currentCode),
          const Divider(height: 1, indent: 56, endIndent: 16),
          _buildLanguageTile('tg', 'Tanglish (Tamil + English)', currentCode),
        ],
      ),
    );
  }

  Widget _buildLanguageTile(String code, String displayName, String currentCode) {
    final isSelected = currentCode == code;
    return RadioListTile<String>(
      value: code,
      groupValue: currentCode,
      onChanged: (String? val) {
        if (val != null) {
          unawaited(context.read<LocalizationService>().setLanguage(val));
        }
      },
      title: Text(
        displayName,
        style: GoogleFonts.outfit(
          color: _text,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      secondary: isSelected
          ? Icon(Icons.check_circle_rounded, color: _pink, size: 20)
          : Icon(Icons.circle_outlined, color: _muted, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildAboutSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _pink.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hero App',
            style: GoogleFonts.outfit(
              color: _text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Version 1.0.0\nBuilt for NJ TECH Erode Super App',
            style: GoogleFonts.outfit(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppVersion() {
    return Center(
      child: Text(
        'Allin1 Hero • v1.0.0',
        style: GoogleFonts.outfit(
          color: _muted,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
