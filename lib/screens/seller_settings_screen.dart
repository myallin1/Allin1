// ================================================================
// Seller Settings Screen
// Allin1 Super App — Seller/Partner Configuration
//
// FIX (Nizam's request: same theme-switcher pattern as customer app,
// applied to hero AND seller): the seller app had no Settings screen at
// all before this, so there was nowhere to change the theme even after
// ThemeService was wired into main_seller.dart. Modeled directly on
// hero_settings_screen.dart's proven layout (notifications + language +
// theme + about), trimmed to what's actually relevant for a seller
// (no map-provider picker — sellers don't navigate maps).
// ================================================================
import 'dart:async';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'ai_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/cloudinary_upload_service.dart';
import '../services/custom_hotel_service.dart';
import '../services/food_seller_service.dart';
import '../services/localization_service.dart';
import '../services/theme_service.dart';
import '../widgets/cached_cloud_image.dart';
import '../widgets/hero_qr_pick_crop.dart';

class SellerSettingsScreen extends StatefulWidget {
  const SellerSettingsScreen({super.key});

  @override
  State<SellerSettingsScreen> createState() => _SellerSettingsScreenState();
}

class _SellerSettingsScreenState extends State<SellerSettingsScreen> {
  static const Color _bg = Color(0xFFF7FAF8);
  static const Color _surface = Colors.white;
  static const Color _pink = Color(0xFFE0418F);
  static const Color _text = Color(0xFF1A1A1A);
  static const Color _muted = Color(0xFF6B7280);

  bool _orderNotificationsEnabled = true;
  bool _newOrderSoundEnabled = true;

  bool _isCustomHotel = false;
  String _hotelLogoUrl = '';
  bool _isUploadingLogo = false;

  // ── Direct-to-seller UPI payment collection (Sep 2026) ─────────────
  // See SellerModel.sellerUpiVpa/sellerPaymentQrBase64's own comments
  // for why this is a Firestore field rather than the hero QR's
  // local-only pattern — a food order's checkout happens on the
  // CUSTOMER's phone, remotely, so the seller's payment details must
  // actually reach Firestore to be visible there at all.
  final _upiVpaCtrl = TextEditingController();
  Uint8List? _paymentQrBytes; // decoded from Firestore for preview
  bool _isSavingPayment = false;
  bool _loadedPaymentSettings = false;

  // A cropped QR PNG is normally tens of KB; this is a generous ceiling
  // (before base64, which adds ~33%) that still keeps the whole
  // sellers/{id} doc comfortably under Firestore's 1MB document limit
  // even with everything else already on that doc.
  static const int _kMaxQrBytes = 700 * 1024;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkCustomHotelStatus();
    _loadPaymentSettings();
  }

  Future<void> _loadPaymentSettings() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final seller = await FoodSellerService().getSeller(uid);
      if (!mounted || seller == null) return;
      setState(() {
        _upiVpaCtrl.text = seller.sellerUpiVpa ?? '';
        final qrB64 = seller.sellerPaymentQrBase64;
        _paymentQrBytes =
            (qrB64 != null && qrB64.isNotEmpty) ? base64Decode(qrB64) : null;
        _loadedPaymentSettings = true;
      });
    } catch (e) {
      debugPrint('[SellerSettings] Payment settings load error: $e');
      if (mounted) setState(() => _loadedPaymentSettings = true);
    }
  }

  Future<void> _saveUpiVpa() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final vpa = _upiVpaCtrl.text.trim();
    setState(() => _isSavingPayment = true);
    try {
      await FoodSellerService().updateSellerProfile(uid, {
        // Empty string clears it — food_checkout_screen.dart treats an
        // empty/null VPA as "not configured" either way.
        'sellerUpiVpa': vpa.isEmpty ? null : vpa,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              vpa.isEmpty ? 'UPI ID removed' : 'UPI ID saved — customers will see this at checkout',
              style: GoogleFonts.outfit(),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('[SellerSettings] UPI VPA save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save UPI ID', style: GoogleFonts.outfit()),
              backgroundColor: Colors.red,),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingPayment = false);
    }
  }

  Future<void> _pickAndSavePaymentQr() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      // Reuses the exact same pick+crop flow hero_register_screen.dart /
      // hero_payment_qr_screen.dart already use for a hero's own payment
      // QR — same 1:1 crop, same "never silently no-op" fallback.
      final bytes = await pickAndCropPaymentQr(context);
      if (bytes == null) return; // cancelled
      if (bytes.length > _kMaxQrBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'That QR image is too large (${(bytes.length / 1024).round()} KB). '
                'Please pick a smaller/cleaner screenshot.',
                style: GoogleFonts.outfit(),
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      setState(() => _isSavingPayment = true);
      final b64 = base64Encode(bytes);
      await FoodSellerService().updateSellerProfile(uid, {
        'sellerPaymentQrBase64': b64,
      });
      if (mounted) {
        setState(() {
          _paymentQrBytes = bytes;
          _isSavingPayment = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment QR saved — customers will see this at checkout',
                style: GoogleFonts.outfit(),),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('[SellerSettings] Payment QR save error: $e');
      if (mounted) {
        setState(() => _isSavingPayment = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save QR', style: GoogleFonts.outfit()),
              backgroundColor: Colors.red,),
        );
      }
    }
  }

  Future<void> _removePaymentQr() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _isSavingPayment = true);
    try {
      await FoodSellerService().updateSellerProfile(uid, {
        'sellerPaymentQrBase64': null,
      });
      if (mounted) {
        setState(() {
          _paymentQrBytes = null;
          _isSavingPayment = false;
        });
      }
    } catch (e) {
      debugPrint('[SellerSettings] Payment QR remove error: $e');
      if (mounted) setState(() => _isSavingPayment = false);
    }
  }

  @override
  void dispose() {
    _upiVpaCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkCustomHotelStatus() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final doc = await CustomHotelService().hotelStream(uid).first;
      if (doc.exists && doc.data() != null) {
        setState(() {
          _isCustomHotel = true;
          _hotelLogoUrl = doc.data()!['logoUrl'] as String? ?? '';
        });
      }
    } catch (e) {
      debugPrint('❌ SellerSettings custom hotel check error: $e');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _orderNotificationsEnabled =
            prefs.getBool('seller_order_notifications_enabled') ?? true;
        _newOrderSoundEnabled =
            prefs.getBool('seller_new_order_sound_enabled') ?? true;
      });
    } catch (e) {
      debugPrint('❌ SellerSettings load error: $e');
    }
  }

  Future<void> _saveSetting(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      debugPrint('❌ SellerSettings save error: $e');
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
          'Seller Settings',
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
            if (_isCustomHotel) ...[
              _buildSectionHeader('Hotel Profile'),
              const SizedBox(height: 12),
              _buildHotelProfileSection(),
              const SizedBox(height: 28),
            ],
            // NEW (Sep 2026 — merchant-account-free UPI collection):
            // lets this seller receive food payment straight into their
            // OWN UPI account, no gateway, same-day settlement. See
            // food_checkout_screen.dart for where the customer sees this.
            _buildSectionHeader('Payment Collection'),
            const SizedBox(height: 12),
            _buildPaymentCollectionSection(),
            const SizedBox(height: 28),
            _buildSectionHeader('Notifications'),
            const SizedBox(height: 12),
            _buildNotificationSettings(),
            const SizedBox(height: 28),
            // NEW (Aug 28 2026 - Nizam: "mobile la chitti innum girl
            // voice la than pesuran"). The voice picker existed but was
            // only reachable from the customer app's routes - a Seller
            // had no way to audition their phone's actual voice list
            // and pin the right one.
            _buildSectionHeader("Chitti's Voice"),
            const SizedBox(height: 12),
            _buildChittiVoiceSettings(),
            const SizedBox(height: 28),
            _buildSectionHeader('Language & Region'),
            const SizedBox(height: 12),
            _buildLanguageSettings(),
            const SizedBox(height: 28),
            _buildSectionHeader('Theme'),
            const SizedBox(height: 12),
            _buildThemeSettings(),
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

  Widget _buildChittiVoiceSettings() {
    return DecoratedBox(
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
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _pink.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.record_voice_over_rounded,
              color: _pink, size: 22),
        ),
        title: Text(
          'Voice & Tone',
          style: GoogleFonts.outfit(
            color: _text,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          "Pick which of your phone's installed voices Chitti uses",
          style: GoogleFonts.outfit(
            color: _muted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: _muted),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const AiSettingsScreen()),
        ),
      ),
    );
  }

  Widget _buildNotificationSettings() {
    return DecoratedBox(
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
            title: 'Order Notifications',
            subtitle: 'Get notified about new and updated orders',
            value: _orderNotificationsEnabled,
            onChanged: (val) {
              setState(() => _orderNotificationsEnabled = val);
              _saveSetting('seller_order_notifications_enabled', val);
            },
          ),
          const Divider(height: 1, indent: 56, endIndent: 16),
          _buildSwitchTile(
            icon: Icons.volume_up_rounded,
            title: 'New Order Sound',
            subtitle: 'Play a sound when a new order comes in',
            value: _newOrderSoundEnabled,
            onChanged: (val) {
              setState(() => _newOrderSoundEnabled = val);
              _saveSetting('seller_new_order_sound_enabled', val);
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
        activeThumbColor: _pink,
      ),
    );
  }

  Widget _buildHotelProfileSection() {
    return DecoratedBox(
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _pink.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: _pink.withValues(alpha: 0.3), width: 2),
              ),
              child: ClipOval(
                child: _isUploadingLogo
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(color: _pink, strokeWidth: 2),
                      )
                    : _hotelLogoUrl.isNotEmpty
                        ? CachedCloudImage(
                            _hotelLogoUrl,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                          )
                        : const Icon(Icons.storefront, color: _pink, size: 32),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Profile Logo',
                    style: GoogleFonts.outfit(
                      color: _text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Upload a square logo to display on your storefront',
                    style: GoogleFonts.outfit(
                      color: _muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _isUploadingLogo ? null : _pickAndUploadLogo,
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: const Text('Change Logo'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _pink,
                      side: const BorderSide(color: _pink),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

  Future<void> _pickAndUploadLogo() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) return;

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 85, // Same as menu items — clarity with compression
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1), // Square logo
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Logo',
            toolbarColor: _bg,
            toolbarWidgetColor: _pink,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
          ),
          IOSUiSettings(
            title: 'Crop Logo',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
          ),
        ],
      );
      if (croppedFile == null) return;

      setState(() => _isUploadingLogo = true);

      final bytes = await File(croppedFile.path).readAsBytes();
      final url = await CloudinaryUploadService().uploadImageBytes(
        bytes,
        fileName: 'logo_$uid.jpg',
      );
      
      await CustomHotelService().updateHotelLogo(uid, url);

      setState(() {
        _hotelLogoUrl = url;
        _isUploadingLogo = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logo updated successfully', style: GoogleFonts.outfit()),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Hotel Logo Upload Error: $e');
      if (mounted) {
        setState(() => _isUploadingLogo = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update logo', style: GoogleFonts.outfit()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildPaymentCollectionSection() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _pink.withValues(alpha: 0.2)),
        boxShadow: const [
          BoxShadow(color: Color(0x12FF4FA3), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Get paid directly — no company account, no delay',
              style: GoogleFonts.outfit(color: _text, fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Set either (or both) below. Customers will see whichever '
              "you've set at checkout and pay you directly.",
              style: GoogleFonts.outfit(color: _muted, fontSize: 11.5),
            ),
            const SizedBox(height: 16),
            Text('Your UPI ID', style: GoogleFonts.outfit(color: _text, fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _upiVpaCtrl,
                    enabled: !_isSavingPayment,
                    style: GoogleFonts.outfit(fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'e.g. hotelname@ybl',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isSavingPayment ? null : _saveUpiVpa,
                  style: ElevatedButton.styleFrom(backgroundColor: _pink),
                  child: _isSavingPayment
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),)
                      : const Text('Save', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Your Payment QR', style: GoogleFonts.outfit(color: _text, fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _pink.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _pink.withValues(alpha: 0.2)),
                  ),
                  child: !_loadedPaymentSettings
                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: _pink))
                      : _paymentQrBytes != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(_paymentQrBytes!, fit: BoxFit.cover),
                            )
                          : const Icon(Icons.qr_code_2_rounded, color: _muted, size: 32),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _isSavingPayment ? null : _pickAndSavePaymentQr,
                        icon: const Icon(Icons.upload_rounded, size: 16),
                        label: Text(_paymentQrBytes != null ? 'Change QR' : 'Upload QR'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _pink,
                          side: const BorderSide(color: _pink),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        ),
                      ),
                      if (_paymentQrBytes != null) ...[
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: _isSavingPayment ? null : _removePaymentQr,
                          style: TextButton.styleFrom(foregroundColor: Colors.red, padding: EdgeInsets.zero),
                          child: const Text('Remove', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageSettings() {
    // Reactive: rebuilds automatically if the language is ever changed
    // from elsewhere (e.g. another screen using the same
    // LocalizationService instance).
    final currentCode = context.watch<LocalizationService>().languageCode;
    return DecoratedBox(
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
          const Divider(height: 1, indent: 56, endIndent: 16),
          _buildLanguageTile('hi', 'हिन्दी (Hindi)', currentCode),
        ],
      ),
    );
  }

  Widget _buildLanguageTile(String code, String displayName, String currentCode) {
    final isSelected = currentCode == code;
    return RadioListTile<String>(
      value: code,
      groupValue: currentCode,
      onChanged: (val) {
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
          ? const Icon(Icons.check_circle_rounded, color: _pink, size: 20)
          : const Icon(Icons.circle_outlined, color: _muted, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  static const List<Map<String, String>> _themeOptions = <Map<String, String>>[
    {'key': 'pink_white', 'label': 'Pink & White'},
    {'key': 'dark_purple', 'label': 'Dark Purple'},
    {'key': 'system_dark', 'label': 'System Dark'},
    {'key': 'system_light', 'label': 'System Light'},
    {'key': 'multicolor', 'label': 'Multicolor'},
  ];

  Widget _buildThemeSettings() {
    // Reactive: rebuilds automatically when the theme changes.
    final currentKey = context.watch<ThemeService>().themeKey;
    return DecoratedBox(
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
          for (var i = 0; i < _themeOptions.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56, endIndent: 16),
            _buildThemeTile(_themeOptions[i]['key']!, _themeOptions[i]['label']!, currentKey),
          ],
        ],
      ),
    );
  }

  Widget _buildThemeTile(String key, String label, String currentKey) {
    final isSelected = currentKey == key;
    return RadioListTile<String>(
      value: key,
      groupValue: currentKey,
      onChanged: (val) {
        if (val != null) {
          unawaited(context.read<ThemeService>().setTheme(val));
        }
      },
      title: Text(
        label,
        style: GoogleFonts.outfit(
          color: _text,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      secondary: isSelected
          ? const Icon(Icons.check_circle_rounded, color: _pink, size: 20)
          : const Icon(Icons.circle_outlined, color: _muted, size: 20),
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
            'Seller App',
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
        'Allin1 Seller • v1.0.0',
        style: GoogleFonts.outfit(
          color: _muted,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
