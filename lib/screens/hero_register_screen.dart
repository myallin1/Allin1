// ================================================================
// Hero Register Screen
// Allin1 Super App - Hero Onboarding
// ================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/city_config.dart';
import '../services/affiliate_service.dart';
import '../services/cloudinary_upload_service.dart';
import '../services/hero_onboarding_cache.dart';
import '../services/hero_payment_qr_service.dart';
import '../services/localization_service.dart';
import '../services/location_service.dart';
import '../widgets/hero_qr_pick_crop.dart';
// ROUTING FIX (merge duplicate registration/status flows): this screen is
// now reached DIRECTLY, before any sign-in step, so a fresh hero may have
// no Firebase Auth session at all when they hit Submit — Google Sign-In is
// now triggered inline from _submitRegistration() below when needed. Post-
// submit routing now goes to HeroPendingScreen (the same live-listening
// tracker used everywhere else), not the old one-shot, non-live
// HeroVerificationPendingScreen — see hero_pending_screen.dart.
import 'hero_pending_screen.dart';
import 'selfie_capture_screen.dart';

// THEME FIX (merge duplicate registration forms): this screen used to be
// a dark theme, separate from the light pink/white ProfileSetupScreen
// that Google-login heroes saw first. Nizam asked for a single merged
// form using the light theme he liked — repainted the palette below,
// widget structure/logic unchanged.
const Color _bg    = Color(0xFFFFF6FA);
const Color _card  = Color(0xFFFFEAF3);
const Color _green = Color(0xFF00A84A);
const Color _gold  = Color(0xFFB8860B);
const Color _njPink = Color(0xFFFF4FA3); // NJ TECH brand pink
const Color _text  = Color(0xFF201A22);
const Color _muted = Color(0xFF8C7A88);
const Color _red   = Color(0xFFE0245E);

/// Result of the concurrent document-upload pass — carries both the
/// successful URLs and a human-readable list of anything that failed,
/// so the caller can abort the commit instead of silently registering a
/// hero with missing proof documents.
class _DocUploadResult {
  const _DocUploadResult({required this.urls, required this.failures});
  final Map<String, String> urls;
  final List<String> failures;
}

class _HeroCategory {
  const _HeroCategory({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.dbLabel,
  });

  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final String dbLabel;
}

const List<_HeroCategory> _heroCategories = <_HeroCategory>[
  _HeroCategory(
    key: 'bike',
    title: 'Bike Taxi',
    subtitle: 'Fast two-wheeler rides',
    icon: Icons.two_wheeler_rounded,
    dbLabel: 'Bike Taxi',
  ),
  _HeroCategory(
    key: 'auto',
    title: 'Auto Rickshaw',
    subtitle: 'City auto service',
    icon: Icons.electric_rickshaw_rounded,
    dbLabel: 'Auto Rickshaw',
  ),
  _HeroCategory(
    key: 'car',
    title: 'Cab / Mini',
    subtitle: 'Cab and mini vehicle',
    icon: Icons.local_taxi_rounded,
    dbLabel: 'Cab / Mini',
  ),
  _HeroCategory(
    key: 'parcel',
    title: 'Parcel Delivery',
    subtitle: 'Goods and package delivery',
    icon: Icons.local_shipping_rounded,
    dbLabel: 'Parcel Delivery',
  ),
  // FIX: the customer-facing Taxi page (ride_search_screen.dart's
  // _normalizeCategoryKey / kFoodSidebarCategoryKeys-style canonical
  // list) supports 6 real vehicle types — bike, auto, cab, parcel,
  // mini_truck, lorry — but this registration form only ever offered
  // 4 of them (+ the non-vehicle emergency_manpower option). A hero
  // who actually drives a mini-truck or lorry had no correct category
  // to pick. Added both.
  _HeroCategory(
    key: 'mini_truck',
    title: 'Mini Truck',
    subtitle: 'Small goods carrier',
    icon: Icons.airport_shuttle_rounded,
    dbLabel: 'Mini Truck',
  ),
  _HeroCategory(
    key: 'lorry',
    title: 'Lorry',
    subtitle: 'Heavy goods carrier',
    icon: Icons.fire_truck_rounded,
    dbLabel: 'Lorry',
  ),
  _HeroCategory(
    key: 'emergency_manpower',
    title: 'Only Emergency Manpower',
    subtitle: 'SOS responder only',
    icon: Icons.health_and_safety_rounded,
    dbLabel: 'Only Emergency Manpower',
  ),
];

class HeroRegisterScreen extends StatefulWidget {
  const HeroRegisterScreen({super.key});

  @override
  State<HeroRegisterScreen> createState() => _HeroRegisterScreenState();
}

class _HeroRegisterScreenState extends State<HeroRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController        = TextEditingController();
  final _phoneController       = TextEditingController();
  final _dobController         = TextEditingController(); // T1: D.O.B
  final _addressController     = TextEditingController(); // T1: Address
  final _licenseNumberController = TextEditingController();
  final _aadhaarController     = TextEditingController(); // T1: Aadhaar No
  final _panController         = TextEditingController(); // T1: PAN No
  // FIX: Nizam wants heroes to state which Erode-area locality they want
  // to work in, using free-text keywords (e.g. "Perundurai, Bhavani Road")
  // so admin can see where hero coverage clusters vs. where customer
  // demand actually is (see location_search_logs / admin location-demand
  // screen). Stored as preferredWorkLocation on the heroes doc, shown in
  // HeroApprovalsScreen's detail dialog.
  final _preferredLocationController = TextEditingController();
  // Multi-city (Nizam's plan, item 3): GPS-detected (not manually
  // picked) via "Use my current location" -- mandatory, null until
  // _detectCity() resolves it. admin sees + verifies it in
  // hero_approvals_screen.dart during approval.
  String? _selectedCity;
  bool _detectingCity = false;

  // FIX (CTO critical-bug mandate — Hero onboarding pipeline): before
  // this, a GPS/location-permission failure left _selectedCity null
  // FOREVER with only a "please enable GPS and try again" snackbar as
  // the way out — and _submitRegistration() hard-blocks on
  // _selectedCity == null, so a hero who denied location permission
  // (or is on a device/browser where GPS is flaky, e.g. web/PWA) could
  // never submit at all. Now offers a manual city picker as an
  // explicit fallback whenever auto-detect fails, so the form can
  // always be completed.
  Future<void> _detectCity() async {
    setState(() => _detectingCity = true);
    try {
      final position = await LocationService().getCurrentLocation();
      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not get your location. Pick your city manually instead.'), backgroundColor: _red),
          );
          await _pickCityManually();
        }
        return;
      }
      final cityName = await LocationService().getCityFromCoordinates(
        LatLng(position.latitude, position.longitude),
      );
      final matched = cityName == null
          ? null
          : (() {
              final normalized = cityName.trim().toLowerCase();
              for (final c in kSupportedCities) {
                if (normalized.contains(c.slug) || c.slug.contains(normalized)) return c.slug;
              }
              return null;
            })();
      if (mounted) {
        setState(() => _selectedCity = matched ?? kDefaultCity);
        _scheduleDraftSave();
      }
    } finally {
      if (mounted) setState(() => _detectingCity = false);
    }
  }

  /// Manual fallback for city selection — reachable automatically when
  /// GPS detection fails, and also directly via a "Choose manually"
  /// link next to the city tile, so a hero is never stuck waiting on
  /// GPS to complete registration.
  Future<void> _pickCityManually() async {
    if (!mounted) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text(
                'Select your city',
                style: GoogleFonts.outfit(color: _text, fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...kSupportedCities.map(
                (c) => ListTile(
                  title: Text(c.label, style: GoogleFonts.outfit(color: _text)),
                  trailing: _selectedCity == c.slug ? const Icon(Icons.check_circle_rounded, color: _njPink) : null,
                  onTap: () => Navigator.pop(sheetContext, c.slug),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (chosen != null && mounted) {
      setState(() => _selectedCity = chosen);
      _scheduleDraftSave();
    }
  }
  String? _selectedVehicleType;
  bool _agreedEmergencyResponder = false;

  // FIX: form used to collect only the license/aadhaar/pan NUMBERS,
  // with a comment saying docs come via WhatsApp only — admin had no
  // photo to actually verify a number against. Each field now has its
  // own document photo uploaded right here (via Cloudinary — see
  // cloudinary_upload_service.dart), shown to admin in
  // HeroApprovalsScreen. Per Nizam's explicit instruction, these are now
  // MANDATORY — _submitRegistration() blocks submission until all 3 are
  // picked. WhatsApp/Call remain available as a manual backup verification
  // channel (Step 2 card below) if a hero has trouble uploading here, but
  // the form itself can no longer be submitted without photos.
  PlatformFile? _licensePhoto;
  PlatformFile? _aadhaarPhoto;
  PlatformFile? _panPhoto;
  // NEW (CTO mandate — Advanced KYC & Facial Verification): a live
  // camera selfie, captured via image_picker's ImageSource.camera (not
  // file_picker above, which only opens the gallery/file browser) so
  // the Admin AI Co-Pilot's facial-comparison check
  // (admin_kyc_vision_service.dart) has something genuine to compare
  // the ID document photo against. Stored as raw bytes immediately on
  // capture — same "hold bytes in memory, upload once at Submit" shape
  // the 3 doc photos above already use.
  Uint8List? _selfieBytes;
  String? _selfieFileName;
  // NEW (Aug 12 2026 — Nizam: payment QR upload point on the
  // registration form): OPTIONAL, unlike the 3 doc photos + selfie
  // above — a hero can add this later from Settings → Payment QR if
  // they don't have it handy right now. Saved LOCALLY on this device
  // the moment it's cropped (see _pickPaymentQr below), never uploaded
  // to Cloudinary or Firestore — see hero_payment_qr_service.dart's
  // header for why.
  Uint8List? _paymentQrBytes;
  // FIX: was only true during the doc-upload step, with a silent gap
  // during Google sign-in and the duplicate-phone Firestore check right
  // before it — the button looked idle/clickable again during that gap,
  // which Nizam reported as the app looking "hung" after tapping Submit.
  // Now covers the ENTIRE submit flow (sign-in through final Firestore
  // writes) via a single try/finally in _submitRegistration(), and drives
  // a full-screen overlay (see build()) in addition to the button spinner.
  bool _isSubmitting = false;
  // NEW (Aug 12 2026 — UI/UX re-audit, Nizam: "processing and uploading
  // your documents... please wait", user must NEVER think the app is
  // frozen): the overlay used to show one static line for the entire
  // multi-second flow. Now updated at each real stage transition below
  // so the hero sees concrete, honest progress (signing in -> uploading
  // documents -> uploading selfie -> saving your registration) instead
  // of one generic message the whole time.
  String _submissionStatus = 'Getting ready…';

  // NEW (Aug 12 2026 — Nizam: "particulara yenga problemo antha section
  // la error kaatitu athe section la red error kaatanum and screen
  // layum yenna error nu print aganum"): snackbars vanish after a few
  // seconds and say nothing about WHERE the problem is. These drive a
  // persistent red banner pinned above the Submit button
  // (_buildErrorBanner) that names the failing section and the exact
  // error text, and stays on screen until the next submit attempt.
  String? _submitError;
  String? _submitErrorSection;

  void _setSubmitError(String section, String message) {
    if (!mounted) return;
    setState(() {
      _submitErrorSection = section;
      _submitError = message;
    });
  }

  void _clearSubmitError() {
    if (!mounted) return;
    setState(() {
      _submitErrorSection = null;
      _submitError = null;
    });
  }

  // T2: CEO WhatsApp placeholder — replace 91XXXXXXXXXX with real number
  static const String _adminWhatsApp = '91XXXXXXXXXX';
  static const String _adminPhone    = '+91XXXXXXXXXX';

  // NEW (Aug 12 2026 — Nizam: "form submit agalaina data yellame close
  // agi again hero va front page ku kutitu varuthu, ithu too worst"):
  // ROOT CAUSE of the total data loss. On WEB/PWA, _ensureSignedIn()
  // below calls GoogleSignIn().signIn(); when the browser blocks the
  // popup (very common on mobile Chrome), the plugin falls back to a
  // full-page REDIRECT. A redirect tears down the entire Flutter app,
  // so every controller, every picked photo and every selection on this
  // screen is destroyed — and when the app reloads, _HeroSetupGate sees
  // an unfinished hero and drops them on a blank registration form.
  // Nothing was "closed" by our code; the page itself was replaced.
  //
  // Fix: continuously mirror the typed fields into SharedPreferences and
  // restore them in initState(), so even a full page reload (redirect
  // sign-in, accidental refresh, browser tab restore, app kill) brings
  // the hero back to their filled-in form instead of an empty one.
  // NOTE: only TEXT fields are drafted. Picked photo bytes are
  // deliberately NOT persisted — they can be multi-MB each and would
  // blow past SharedPreferences' practical size limits; the hero
  // re-attaches photos only, which is a far smaller ask than retyping
  // every field.
  static const String _kDraftKey = 'hero_register_draft_v1';
  Timer? _draftDebounce;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreDraft());
    unawaited(_restoreSavedQr());
    for (final c in <TextEditingController>[
      _nameController,
      _phoneController,
      _dobController,
      _addressController,
      _licenseNumberController,
      _aadhaarController,
      _panController,
      _preferredLocationController,
    ]) {
      c.addListener(_scheduleDraftSave);
    }
  }

  // FIX (Aug 12 2026 — same "QR shows as not uploaded" report): even
  // once saving works, this screen never LOADED an already-saved QR, so
  // a hero who added their QR, then reloaded/came back, saw the empty
  // "Add your payment QR (optional)" state again despite it being
  // saved on the device. Reads it back on mount.
  Future<void> _restoreSavedQr() async {
    final saved = await HeroPaymentQrService.instance.loadQr();
    if (saved == null || !mounted) return;
    setState(() => _paymentQrBytes = saved);
  }

  void _scheduleDraftSave() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 600), _saveDraft);
  }

  Future<void> _saveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kDraftKey,
        jsonEncode(<String, dynamic>{
          'name': _nameController.text,
          'phone': _phoneController.text,
          'dob': _dobController.text,
          'address': _addressController.text,
          'license': _licenseNumberController.text,
          'aadhaar': _aadhaarController.text,
          'pan': _panController.text,
          'preferredLocation': _preferredLocationController.text,
          'city': _selectedCity,
          'vehicleType': _selectedVehicleType,
          'agreed': _agreedEmergencyResponder,
        }),
      );
    } catch (e) {
      debugPrint('[HeroRegister] draft save failed (non-fatal): $e');
    }
  }

  Future<void> _restoreDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kDraftKey);
      if (raw == null || raw.isEmpty || !mounted) return;
      final d = jsonDecode(raw) as Map<String, dynamic>;
      _nameController.text = (d['name'] as String?) ?? '';
      _phoneController.text = (d['phone'] as String?) ?? '';
      _dobController.text = (d['dob'] as String?) ?? '';
      _addressController.text = (d['address'] as String?) ?? '';
      _licenseNumberController.text = (d['license'] as String?) ?? '';
      _aadhaarController.text = (d['aadhaar'] as String?) ?? '';
      _panController.text = (d['pan'] as String?) ?? '';
      _preferredLocationController.text = (d['preferredLocation'] as String?) ?? '';
      if (!mounted) return;
      setState(() {
        _selectedCity = d['city'] as String?;
        _selectedVehicleType = d['vehicleType'] as String?;
        _agreedEmergencyResponder = (d['agreed'] as bool?) ?? false;
      });
    } catch (e) {
      debugPrint('[HeroRegister] draft restore failed (non-fatal): $e');
    }
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kDraftKey);
    } catch (_) {}
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _addressController.dispose();
    _licenseNumberController.dispose();
    _aadhaarController.dispose();
    _panController.dispose();
    _preferredLocationController.dispose();
    super.dispose();
  }

  // FIX: this used to substring-match ('truck' -> 'car', anything else
  // unmatched -> 'bike'), which silently mis-categorized 'parcel' and
  // 'lorry' selections as 'bike', and would have mapped the new
  // 'mini_truck' category to 'car' too. [selectedVehicleType] is
  // already one of _heroCategories' own keys (that's what the category
  // picker sets it to), so just pass it through if it's a real key —
  // no substring guessing needed.
  String _normalizeVehicleType(String value) {
    final key = value.trim().toLowerCase();
    final isKnownKey = _heroCategories.any((c) => c.key == key);
    return isKnownKey ? key : 'bike';
  }

  String _vehicleCategoryLabel(String key) {
    return _heroCategories
        .firstWhere(
          (category) => category.key == key,
          orElse: () => _heroCategories.first,
        )
        .dbLabel;
  }

  Future<void> _launchWhatsApp() async {
    // T2: CEO-specified message — number is a placeholder, replace before release
    final message = Uri.encodeComponent(
      'Hi NJ TECH, I have submitted my Hero Registration. Here are my documents.',
    );
    final url = Uri.parse('https://wa.me/$_adminWhatsApp?text=$message');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open WhatsApp')),
      );
    }
  }

  Future<void> _launchCall() async {
    final url = Uri.parse('tel:$_adminPhone');

    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open phone dialer'),
        ),
      );
    }
  }

  // FIX (merge duplicate registration/status flows): this screen is now
  // reachable directly (no forced sign-in step first), so a brand-new
  // hero may have no Firebase Auth session yet when they tap Submit.
  // Nizam's instruction: run Google Sign-In "in the background" of the
  // same Submit button rather than sending them to a separate sign-in
  // screen first. If a session already exists (e.g. they arrived here
  // via the phone-OTP hero login flow), this is a no-op and that
  // existing user is used as-is.
  static const String _googleWebClientId =
      '357526153693-02b0behmsf3k720jujg3e8j82frj04q7.apps.googleusercontent.com';

  Future<User?> _ensureSignedIn() async {
    final existing = FirebaseAuth.instance.currentUser;
    if (existing != null) return existing;

    // FIX (Aug 12 2026 — ROOT CAUSE of "form submit aagala, error kaatuchu
    // but athukulla jump agi sign up page ku vanthuruchu"): on WEB this
    // used google_sign_in's signIn(), which the console itself flags as
    // deprecated ("The google_sign_in plugin `signIn` method is
    // deprecated on the web"). That path opens a popup and then polls
    // `window.closed` to detect completion — and the four
    // "Cross-Origin-Opener-Policy policy would block the window.closed
    // call" errors in the same console show the browser BLOCKING exactly
    // that check. When the popup handshake can't complete, the plugin
    // falls back to a full-page REDIRECT. A redirect reloads the entire
    // Flutter app: the registration screen, the filled form, and the red
    // error banner I added are all destroyed mid-submit, and the app
    // re-boots into _HeroSetupGate which — with no completed setup —
    // lands the hero on the login/sign-up page. That is precisely the
    // "jump" Nizam described, and it also explains why the
    // mobile-number error only flashed for an instant before vanishing:
    // it WAS rendering correctly, the page just got torn down underneath
    // it. It also explains the [cloud_firestore/permission-denied] in
    // the console — post-reload code touching Firestore before an auth
    // session exists.
    //
    // FirebaseAuth's own signInWithPopup() is the supported web path: it
    // never redirects, so this screen stays mounted, the form keeps its
    // data, and any error surfaces in the banner exactly as designed.
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile');
      final cred = await FirebaseAuth.instance.signInWithPopup(provider);
      return cred.user;
    }

    final googleSignIn = GoogleSignIn(
      serverClientId: _googleWebClientId,
      scopes: const ['email', 'profile'],
    );
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) return null; // user cancelled the picker
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final userCredential =
        await FirebaseAuth.instance.signInWithCredential(credential);
    return userCredential.user;
  }

  Future<void> _pickDocPhoto(String docType) async {
    try {
      final result = await FilePicker.platform
          .pickFiles(type: FileType.image, withData: true);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (!mounted) return;
      setState(() {
        switch (docType) {
          case 'license':
            _licensePhoto = file;
            break;
          case 'aadhaar':
            _aadhaarPhoto = file;
            break;
          case 'pan':
            _panPhoto = file;
            break;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not pick photo: $e'), backgroundColor: _red),
      );
    }
  }

  // NEW (CTO mandate — Advanced KYC & Facial Verification): forces the
  // device's actual camera (ImageSource.camera), unlike _pickDocPhoto
  // above which opens the gallery/file browser — a gallery pick could
  // be an old photo of anyone, which would defeat the whole point of a
  // "live" selfie for facial comparison. imageQuality: 70 does a
  // reasonable on-device JPEG compression before the bytes even reach
  // us; CloudinaryUploadService's targetBytes below compresses further
  // to a small, storage-friendly size, matching the CTO's "compressed"
  // requirement.
  // FIX (CTO critical-bug mandate — Hero onboarding pipeline): the old
  // version only ever tried ImageSource.camera and, on ANY failure
  // (permission denied on native, getUserMedia blocked on web/PWA —
  // e.g. no HTTPS, or the page loaded inside an iframe without
  // Permissions-Policy: camera), showed a raw exception string and left
  // _selfieBytes null forever. Since _submitRegistration() hard-blocks
  // submission until _selfieBytes is set, a camera failure silently
  // made the ENTIRE form unsubmittable — this is bug #1 and #2 from the
  // same root cause. Now: try the camera first (still the default, so a
  // genuine live selfie is preferred for facial-comparison KYC), and if
  // that throws for ANY reason, automatically fall back to the gallery/
  // file picker so the hero can still supply a photo and finish
  // registering, with a clear snackbar explaining what happened instead
  // of a raw error string.
  // FIX (per Nizam's request — round-box live selfie): the old flow
  // used image_picker's ImageSource.camera, which opens the OS's
  // native camera app — Flutter can't draw a face-guide overlay on
  // top of that. Now pushes SelfieCaptureScreen, an in-app live
  // `camera` package preview with a dark scrim + oval "round box"
  // cutout painted over it, so the hero has to line their face up
  // inside the oval before capturing. That screen has its own
  // internal camera-unavailable fallback (permission denied, no
  // camera hardware, blocked getUserMedia on web); there's no plain
  // "Gallery" bypass sitting next to a working camera anymore.
  Future<void> _captureSelfie() async {
    final result = await Navigator.push<SelfieCaptureResult>(
      context,
      MaterialPageRoute(builder: (_) => const SelfieCaptureScreen()),
    );
    if (result == null || !mounted) return; // hero cancelled
    setState(() {
      _selfieBytes = result.bytes;
      _selfieFileName = result.fileName;
    });
  }

  /// Uploads the live selfie (if captured) to the same Cloudinary
  /// folder convention as the doc photos, returning {'selfieUrl': ...}
  /// or an empty map if there's nothing to upload — mirrors
  /// _uploadPickedDocPhotos' shape exactly so both merge into the
  /// Firestore write with `...` the same way.
  Future<Map<String, String>> _uploadSelfiePhoto(String uid) async {
    final bytes = _selfieBytes;
    if (bytes == null) return const {};
    try {
      final url = await CloudinaryUploadService().uploadImageBytes(
        bytes,
        fileName: 'selfie_${_selfieFileName ?? 'capture.jpg'}',
        folder: 'hero_documents/$uid',
        targetBytes: CloudinaryUploadService.kDocumentTargetBytes,
      );
      return {'selfieUrl': url};
    } catch (e) {
      debugPrint('[HeroRegister] selfie upload failed: $e');
      return const {};
    }
  }

  /// Uploads the 3 mandatory doc photos (all 3 are guaranteed non-null
  /// by the time this runs — _submitRegistration validates that before
  /// calling this), returning a map of the ones that uploaded
  /// successfully. If a single upload fails (network blip etc.) it's
  /// logged and skipped rather than blocking the whole registration —
  /// the hero can still fall back to WhatsApp/Call for that one doc.
  /// Human-readable names for the error banner, keyed by the Firestore
  /// field each upload targets.
  static const Map<String, String> _docLabels = <String, String>{
    'licenseDocUrl': 'License photo',
    'aadhaarDocUrl': 'Aadhaar photo',
    'panDocUrl': 'PAN photo',
  };

  /// FIX (Aug 12 2026 — pre-build audit, two real defects in one method):
  ///
  /// 1. SILENT PARTIAL SUBMISSION. Every per-document failure used to be
  ///    swallowed with a debugPrint and skipped, so a hero whose uploads
  ///    failed still sailed through to a successful Firestore commit —
  ///    landing in Admin's approval queue with NO photos to verify
  ///    against, and no indication to anyone that anything went wrong.
  ///    That is very likely part of what Nizam saw as "form admin ku
  ///    varala / half-a-varuthu". Failures are now collected and
  ///    returned to the caller, which aborts the commit and names the
  ///    exact failing document in the red banner.
  ///
  /// 2. SEQUENTIAL UPLOADS. The 3 documents uploaded one after another,
  ///    each with its own compress + network round trip, so total submit
  ///    time was the SUM of all of them (and the selfie after that).
  ///    They're independent, so they now run concurrently via
  ///    Future.wait — roughly 3-4x faster on the critical path, which is
  ///    the single biggest UX win available in this pipeline.
  Future<_DocUploadResult> _uploadPickedDocPhotos(String uid) async {
    final jobs = <String, PlatformFile?>{
      'licenseDocUrl': _licensePhoto,
      'aadhaarDocUrl': _aadhaarPhoto,
      'panDocUrl': _panPhoto,
    };

    final urls = <String, String>{};
    final failures = <String>[];

    await Future.wait(jobs.entries.map((entry) async {
      final file = entry.value;
      if (file == null || file.bytes == null) {
        failures.add(_docLabels[entry.key] ?? entry.key);
        return;
      }
      try {
        final url = await CloudinaryUploadService().uploadImageBytes(
          file.bytes!,
          fileName: '${entry.key}_${file.name}',
          folder: 'hero_documents/$uid',
          // Higher than the 100KB default — these are ID/license
          // documents admin must actually read to verify a hero, so a
          // bit more room keeps printed text legible.
          targetBytes: CloudinaryUploadService.kDocumentTargetBytes,
        );
        urls[entry.key] = url;
      } catch (e) {
        debugPrint('[HeroRegister] ${entry.key} upload failed: $e');
        failures.add('${_docLabels[entry.key] ?? entry.key} ($e)');
      }
    }));

    return _DocUploadResult(urls: urls, failures: failures);
  }

  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final selectedVehicleType = _selectedVehicleType;
    if (selectedVehicleType == null || selectedVehicleType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your Hero category'),
          backgroundColor: _red,
        ),
      );
      return;
    }
    if (!_agreedEmergencyResponder) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please accept the SOS Network first responder agreement',
          ),
          backgroundColor: _red,
        ),
      );
      return;
    }
    if (_selectedCity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set your city first — tap the location button or "Choose city manually".'), backgroundColor: _red),
      );
      return;
    }

    // FIX: doc photos are now mandatory — block submission if any of the
    // 3 are missing instead of silently allowing an all-numbers-no-proof
    // registration through (which left admin nothing to visually verify).
    final missingDocs = <String>[
      if (_licensePhoto == null) 'License photo',
      if (_aadhaarPhoto == null) 'Aadhaar photo',
      if (_panPhoto == null) 'PAN photo',
      // NEW (CTO mandate — Advanced KYC & Facial Verification): a
      // selfie is now mandatory alongside the 3 doc photos, same
      // reasoning as the FIX comment above — without it, the Admin AI's
      // facial-comparison step has nothing to compare against and
      // every report falls back to "no selfie on file, manual
      // verification required" indefinitely.
      if (_selfieBytes == null) 'Live selfie',
    ];
    if (missingDocs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please upload: ${missingDocs.join(', ')}'),
          backgroundColor: _red,
        ),
      );
      return;
    }

    _clearSubmitError();
    if (mounted) {
      setState(() {
        _isSubmitting = true;
        _submissionStatus = 'Signing you in…';
      });
    }
    try {
      final user = await _ensureSignedIn();
      if (user == null) {
        _setSubmitError(
          'Sign-in',
          'Sign-in was cancelled or blocked. Your details are saved — '
          'just tap Submit again to retry.',
        );
        return;
      }
      final vehicleType = _normalizeVehicleType(selectedVehicleType);
      final vehicleCategoryLabel = _vehicleCategoryLabel(vehicleType);

      // FIX (duplicate-hero prevention, P4): heroes/{uid} is keyed by
      // Firebase Auth uid, so the same person signing in via 2 different
      // methods (e.g. phone OTP once, Google once) — or just entering a
      // different phone number the second time — gets 2 separate hero
      // docs with no link between them. Block registration if this exact
      // phone number is already registered under a DIFFERENT uid, rather
      // than silently creating a duplicate. Existing duplicates from
      // before this fix are not touched here — that needs Nizam's
      // decision on cleanup, tracked separately.
      if (mounted) setState(() => _submissionStatus = 'Checking your details…');

      final enteredPhone =
          (user.phoneNumber ?? _phoneController.text.trim()).trim();
      // FIX (Aug 12 2026 — the "mobile number problem" flash Nizam saw):
      // this duplicate check is a QUERY across the whole heroes
      // collection. It is a nice-to-have guard, NOT a precondition for
      // registering — but any failure here (permission-denied on a
      // collection listing, an offline blip, a missing index) used to
      // propagate out to the generic catch blocks and abort the entire
      // submission, blaming the hero's phone number for what is really
      // an infrastructure problem. It is now best-effort: a genuine
      // duplicate still blocks (that's the point), but if the CHECK
      // itself cannot run, we log it and let registration proceed —
      // heroes/{uid} is keyed by uid anyway, so the worst case is a
      // duplicate row for admin to merge, which is far better than a
      // real hero being unable to sign up at all.
      if (enteredPhone.isNotEmpty) {
        try {
        final existing = await FirebaseFirestore.instance
            .collection('heroes')
            .where('phone', isEqualTo: enteredPhone)
            .limit(1)
            .get();
        final duplicate = existing.docs
            .any((doc) => doc.id != user.uid);
        if (duplicate) {
          _setSubmitError(
            'Contact Number',
            'This phone number is already registered as a Hero. '
            'Please log in with your existing account instead, or use a '
            'different number.',
          );
          return;
        }
        } catch (e) {
          // Check could not run — proceed rather than blocking a real
          // hero. See the comment above this block for the reasoning.
          debugPrint('[HeroRegister] duplicate-phone check skipped: $e');
        }
      }

       // Upload the 3 mandatory doc photos + the live selfie.
       // UPDATED (Aug 12 2026 — pre-build audit): documents and selfie
       // now upload CONCURRENTLY (they were strictly sequential, so the
       // hero waited for the sum of 4 compress+upload round trips). All
       // 4 are independent, so Future.wait cuts the critical path
       // dramatically.
       if (mounted) {
         setState(() => _submissionStatus = 'Processing and uploading your documents…');
       }
       final uploads = await Future.wait(<Future<Object>>[
         _uploadPickedDocPhotos(user.uid),
         _uploadSelfiePhoto(user.uid),
       ]);
       final docResult = uploads[0] as _DocUploadResult;
       final docUrls = docResult.urls;
       final selfieUrl = uploads[1] as Map<String, String>;

       // FIX (Aug 12 2026 — pre-build audit): previously ANY failed
       // document upload was silently skipped and the registration
       // committed anyway, putting a hero into Admin's approval queue
       // with missing/absent proof photos and nobody aware of it. Since
       // all 3 documents + the selfie are MANDATORY by policy (enforced
       // in the validation block above), a failure here must abort the
       // submission and say exactly which file failed — not quietly
       // produce a half-registered hero.
       final allFailures = <String>[
         ...docResult.failures,
         if (selfieUrl.isEmpty) 'Live selfie',
       ];
       if (allFailures.isNotEmpty) {
         _setSubmitError(
           'Document upload',
           'These could not be uploaded: ${allFailures.join(', ')}. '
           'Nothing has been submitted yet — check your connection and '
           'tap Submit again, or re-attach the affected photo.',
         );
         return;
       }

       // Save to heroes collection AND mark users/{uid}.isSetupComplete —
       // FIX (Aug 8 2026 — root cause of "already-registered pending hero
       // sent back to the registration form"): these used to be two
       // independent await FirebaseFirestore....set() calls. If the app
       // was killed, lost connection, or the second call simply failed
       // right after the first one succeeded, heroes/{uid} would already
       // have a real 'pending' application while users/{uid}.isSetupComplete
       // stayed false/missing forever — and _HeroSetupGate in
       // main_hero.dart reads isSetupComplete FIRST, so that hero got
       // routed straight back to a blank registration form on every
       // reopen, even though admin could already see and approve them.
       // A WriteBatch makes both writes succeed or fail together, so that
       // particular desync can no longer happen for a brand-new
       // submission (main_hero.dart also got an independent self-heal
       // fallback for any hero who already hit this before today).
       //
       // FIX (Aug 8 2026): added SetOptions(merge:true) on the heroes
       // write — this used to be a full overwrite, which would silently
       // wipe out any fields hero_login_screen.dart's earlier identity-
       // sync had already set on this same doc (created at first sign-in,
       // before this form is ever reached). merge:true makes this a true
       // "fill in the rest" write instead of a blind replace. Paired with
       // the firestore.rules fix on the heroes/{heroId} update rule,
       // which was rejecting this exact write with permission-denied
       // because the pre-created stub doc has no approvalStatus field yet.
       if (mounted) setState(() => _submissionStatus = 'Saving your registration…');
       final registrationBatch = FirebaseFirestore.instance.batch();
       final heroDocRef =
           FirebaseFirestore.instance.collection('heroes').doc(user.uid);
       registrationBatch.set(heroDocRef, {
         'heroId': user.uid,
         'uid': user.uid,
         'name': _nameController.text.trim(),
         // FIX (audit: customer/hero number wiring — heroes/{uid} was only
         // ever getting 'phone' written here, never 'phoneNumber', even
         // though hero_profile_tab.dart and other screens read
         // heroData['phoneNumber'] from this same collection. Matches the
         // dual-field convention (both kept in sync) already used on
         // users/{uid} a few lines below and in hero_login_screen.dart's
         // _syncHeroIdentityFields.
         'phone': user.phoneNumber ?? _phoneController.text.trim(),
         'phoneNumber': user.phoneNumber ?? _phoneController.text.trim(),
         'email': user.email ?? '',
         // T1: New fields per CEO directive
         'dob': _dobController.text.trim(),
         'address': _addressController.text.trim(),
         'aadhaarNumber': _aadhaarController.text.trim(),
         'panNumber': _panController.text.trim(),
         'preferredWorkLocation': _preferredLocationController.text.trim(),
         // Multi-city: hero's GPS-detected operating city — feeds
         // dispatch matching so this hero only receives pings for
         // rides/orders in their own city. Admin can also reassign a
         // hero's city later from the admin app if needed.
         'city': _selectedCity ?? kDefaultCity,
         'vehicleType': vehicleType,
         'heroCategory': vehicleType,
         'vehicleCategoryLabel': vehicleCategoryLabel,
         'isEmergencyHelper': true,
         'sosNetworkAcceptedAt': FieldValue.serverTimestamp(),
         'licenseNumber': _licenseNumberController.text.trim(),
         // FIX: doc photo URLs, uploaded above — was previously always
         // absent ("no document URLs — hero sends physical docs via
         // WhatsApp"). WhatsApp is still available as a fallback (see
         // the Step 2 WhatsApp card below), but now admin can also see
         // an actual photo here to cross-check against the typed
         // numbers before approving.
         ...docUrls,
         ...selfieUrl,
         'approvalStatus': 'pending',
         'status': 'offline',
         'onboardingMethod': docUrls.isEmpty ? 'manual_whatsapp' : 'in_app_upload',
         'createdAt': FieldValue.serverTimestamp(),
       }, SetOptions(merge: true));

       // FIX: main_hero.dart's _HeroSetupGate decides whether to show this
       // registration form again by reading users/{uid}.isSetupComplete —
       // this write was missing, so a hero who submitted here would be
       // sent right back to an empty registration form on their next app
       // open (before admin even had a chance to approve them), instead
       // of the pending-status tracker. Mirrors what
       // AuthService.completeProfileSetup does for the customer/Google
       // path. Now part of the same batch as the heroes/{uid} write above
       // — see the batch comment for why.
       final usersDocRef =
           FirebaseFirestore.instance.collection('users').doc(user.uid);
       registrationBatch.set(
         usersDocRef,
         {
           'phone': user.phoneNumber ?? _phoneController.text.trim(),
           'phoneNumber': user.phoneNumber ?? _phoneController.text.trim(),
           'role': 'hero',
           'isSetupComplete': true,
           'setupCompletedAt': FieldValue.serverTimestamp(),
         },
         SetOptions(merge: true),
       );

       // FIX (Aug 12 2026 — same "stuck forever" audit as the Cloudinary
       // timeout above): Firestore's WriteBatch.commit() Future only
       // resolves after the server acknowledges the write, so a long
       // connectivity drop right here could hang just as badly as the
       // upload did. This timeout guarantees the try/finally below
       // always completes within a bounded time, so _isSubmitting is
       // guaranteed to reset and the Submit button always becomes
       // pressable again — no more permanent lockout on a bad network.
       await registrationBatch.commit().timeout(
         const Duration(seconds: 20),
         onTimeout: () => throw Exception(
           'Could not reach the server — check your connection and try again.',
         ),
       );

       // NEW (Aug 12 2026 — Affiliate QR Generator): increments the
       // referring code's signup counter if this hero came in from an
       // affiliate link; a no-op otherwise. Fire-and-forget — never
       // blocks or fails registration.
       unawaited(AffiliateService.instance.completeConversion(
         uid: user.uid,
         name: _nameController.text.trim(),
         phone: user.phoneNumber ?? _phoneController.text.trim(),
         email: user.email ?? '',
         city: _selectedCity ?? kDefaultCity,
         role: 'hero',
       ));

       // NEW (Aug 12 2026 — Local Cache Strategy): the moment the batch
       // above actually lands, cache 'pending' locally so the NEXT app
       // boot (this device, this browser/PWA) can route straight to
       // HeroPendingScreen with zero Firestore read — see
       // hero_onboarding_cache.dart and main_hero.dart's _HeroSetupGate.
       unawaited(HeroOnboardingCache.setPending());

       // Submission fully landed — the draft has served its purpose and
       // must not resurface on any future visit to this form.
       unawaited(_clearDraft());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Registration submitted! Awaiting admin approval.',
            ),
            backgroundColor: _gold,
          ),
        );

        // ROUTING FIX: Do NOT sign the user out.
        // Navigate to the live-updating pending tracker — same screen
        // used everywhere else in the app for pending heroes — so the
        // hero sees the 3-step status immediately and is auto-redirected
        // into the dashboard the moment admin approves, no re-open needed.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const HeroPendingScreen(),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      // Task 4: Typed Firebase Auth error — prints exact code to console
      debugPrint('[HeroRegister] FirebaseAuthException: ${e.code} — ${e.message}');
      _setSubmitError(
        'Sign-in',
        'Auth error (${e.code}): ${e.message ?? e.toString()}',
      );
    } on FirebaseException catch (e) {
      // Task 4: Typed Firestore / Database error — prints plugin + code
      debugPrint(
        '[HeroRegister] FirebaseException [${e.plugin}]: ${e.code} — ${e.message}',
      );
      _setSubmitError(
        'Saving your registration',
        'Database error (${e.code}): ${e.message ?? e.toString()}',
      );
    } catch (e, st) {
      // Task 4: Unexpected error — full stack trace to console for debugging
      debugPrint('[HeroRegister] Unexpected error: $e\n$st');
      // _submissionStatus still holds whichever stage was running when
      // this threw, so the banner can name the exact failing section.
      _setSubmitError(
        _submissionStatus.replaceAll('…', ''),
        e.toString(),
      );
    } finally {
      // FIX: single point that turns the loading overlay off, covering
      // every exit path (success navigation, cancelled sign-in, and all
      // 3 error branches above) — no more window where the screen looks
      // idle/hung while a network call is actually still in flight.
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submissionStatus = 'Getting ready…';
        });
      }
    }
  }

  Widget _docPhotoTile({
    required String label,
    required PlatformFile? photo,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: photo != null ? _green.withValues(alpha: 0.5) : _muted.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            if (photo != null && photo.bytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(photo.bytes!, width: 36, height: 36, fit: BoxFit.cover),
              )
            else
              const Icon(Icons.add_a_photo_outlined, color: _muted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                photo?.name ?? label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: photo != null ? _text : _muted,
                  fontSize: 12,
                ),
              ),
            ),
            if (photo != null)
              IconButton(
                icon: const Icon(Icons.close, size: 16, color: _muted),
                onPressed: onClear,
              ),
          ],
        ),
      ),
    );
  }

  // NEW (CTO mandate — Advanced KYC & Facial Verification): mirrors
  // _docPhotoTile's look, adapted for raw bytes (image_picker's XFile
  // doesn't produce a PlatformFile) instead of a picked file.
  Widget _selfieTile() {
    return InkWell(
      onTap: _captureSelfie,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _selfieBytes != null ? _green.withValues(alpha: 0.5) : _muted.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            if (_selfieBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(_selfieBytes!, width: 36, height: 36, fit: BoxFit.cover),
              )
            else
              const Icon(Icons.camera_alt_outlined, color: _muted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _selfieBytes != null ? (_selfieFileName ?? 'Selfie captured') : 'Take a live selfie (required)',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: _selfieBytes != null ? _text : _muted,
                  fontSize: 12,
                ),
              ),
            ),
            if (_selfieBytes != null)
              IconButton(
                icon: const Icon(Icons.close, size: 16, color: _muted),
                onPressed: () => setState(() {
                  _selfieBytes = null;
                  _selfieFileName = null;
                }),
              ),
            // No "Gallery" bypass here anymore — SelfieCaptureScreen
            // (pushed by _captureSelfie above) owns its own
            // camera-unavailable fallback internally, so there's no
            // standing shortcut next to a working live camera.
          ],
        ),
      ),
    );
  }

  // NEW (Aug 12 2026 — payment QR upload point): pick from gallery,
  // crop to a tight square (see hero_qr_pick_crop.dart), save straight
  // to this device via HeroPaymentQrService — never Cloudinary, never
  // Firestore. Saved immediately on crop, not deferred to Submit, so a
  // hero who fills the form over multiple sittings doesn't lose it.
  Future<void> _pickPaymentQr() async {
    final cropped = await pickAndCropPaymentQr(context);
    if (cropped == null || !mounted) return;
    // FIX (Aug 12 2026 — "QR upload button not wired?" report): saveQr()
    // was awaited with no try/catch here, so any failure (Hive not
    // ready on web, disk write denied on native, etc.) threw an
    // unhandled Future rejection — the crop dialog would close but
    // nothing ever visibly happened (setState never ran), which looks
    // exactly like a dead/unwired button from the hero's side. Now
    // fails loudly with a snackbar instead of silently, and the
    // in-memory _paymentQrBytes is only set after the save actually
    // succeeds.
    try {
      await HeroPaymentQrService.instance.saveQr(cropped);
      if (!mounted) return;
      setState(() => _paymentQrBytes = cropped);
    } catch (e) {
      debugPrint('[HeroRegister] payment QR save failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save QR: $e'), backgroundColor: _red),
      );
    }
  }

  Widget _paymentQrTile() {
    return InkWell(
      onTap: _pickPaymentQr,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _paymentQrBytes != null
                ? _green.withValues(alpha: 0.5)
                : _muted.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            if (_paymentQrBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 36,
                  height: 36,
                  color: Colors.white,
                  child: Image.memory(_paymentQrBytes!, fit: BoxFit.contain),
                ),
              )
            else
              const Icon(Icons.qr_code_2_rounded, color: _muted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _paymentQrBytes != null
                    ? 'Payment QR saved on this device'
                    : 'Add your payment QR (optional)',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: _paymentQrBytes != null ? _text : _muted,
                  fontSize: 12,
                ),
              ),
            ),
            if (_paymentQrBytes != null)
              IconButton(
                icon: const Icon(Icons.close, size: 16, color: _muted),
                onPressed: () async {
                  await HeroPaymentQrService.instance.deleteQr();
                  if (!mounted) return;
                  setState(() => _paymentQrBytes = null);
                },
              ),
          ],
        ),
      ),
    );
  }

  // ── "How to register (3 steps)" native guide ──────────────────────
  // NEW (Aug 12 2026 — Nizam's call after the video-vs-native-UI
  // discussion): replaces the planned tutorial video entirely. Chosen
  // over a YouTube iframe / MP4 because (a) a video costs ~1-2MB before
  // the first frame on mobile data, against ~0KB here, (b) a confused
  // hero can SCAN a native guide to the exact step they're stuck on
  // instead of scrubbing a timeline — which is what actually reduces
  // drop-off, and (c) it updates in the same commit as the form,
  // works offline, is readable with sound off, and is localizable
  // through the existing LocalizationService (all 5 languages, keys
  // hero_guide_*). Collapsed by default so it never pushes the form
  // itself below the fold.
  bool _guideExpanded = false;

  Widget _buildHowToRegisterGuide(BuildContext context) {
    final t = context.watch<LocalizationService>().t;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _njPink.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _guideExpanded = !_guideExpanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _njPink.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.menu_book_rounded, color: _njPink, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('hero_guide_title'),
                          style: GoogleFonts.outfit(
                            color: _text,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t('hero_guide_hint'),
                          style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _guideExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.keyboard_arrow_down_rounded, color: _njPink),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState:
                _guideExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _guideStep(1, t('hero_guide_s1_title'), t('hero_guide_s1_body'), Icons.person_rounded),
                  _guideStep(2, t('hero_guide_s2_title'), t('hero_guide_s2_body'), Icons.badge_rounded),
                  _guideStep(3, t('hero_guide_s3_title'), t('hero_guide_s3_body'), Icons.verified_rounded, isLast: true),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _gold.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lightbulb_outline_rounded, color: _gold, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t('hero_guide_tip'),
                            style: GoogleFonts.outfit(
                              color: _text,
                              fontSize: 11,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _guideStep(
    int number,
    String title,
    String body,
    IconData icon, {
    bool isLast = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(color: _njPink, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(
                  '$number',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: _njPink.withValues(alpha: 0.25),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 8 : 16, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 14, color: _njPink),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.outfit(
                            color: _text,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: GoogleFonts.outfit(
                      color: _muted,
                      fontSize: 11.5,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCategorySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hero Category',
          style: GoogleFonts.outfit(
            color: _text,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 430;
            final cardWidth = isCompact
                ? constraints.maxWidth
                : (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 10,
              children: _heroCategories.map((category) {
                final selected = _selectedVehicleType == category.key;
                return SizedBox(
                  width: cardWidth,
                  child: _HeroCategoryCard(
                    category: category,
                    selected: selected,
                    onTap: () {
                      setState(() {
                        _selectedVehicleType = category.key;
                      });
                      _scheduleDraftSave();
                    },
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // FIX: Submit used to only show a spinner INSIDE the button — during
    // the parts of the flow that aren't instant (Google sign-in round
    // trip, duplicate-phone check, 3 photo uploads, 2 Firestore writes),
    // the rest of the screen looked completely idle, and Nizam reported
    // it looking "hung." Stack a full-screen dimmed overlay with its own
    // spinner + status text on top whenever _isSubmitting is true — it's
    // now unmistakable that something is happening, not stuck.
    // NEW (Aug 12 2026 — Nizam: "form filling complete aguravarayum
    // antha loading page laye irukanum"): blocks the Android back
    // gesture/button while a submission is in flight, so the hero can't
    // back out mid-upload into a half-submitted state. No effect once
    // _isSubmitting is false — the form behaves exactly as before.
    return PopScope(
      canPop: !_isSubmitting,
      child: Stack(
      children: [
        _buildForm(context),
        if (_isSubmitting)
          Positioned.fill(
            child: AbsorbPointer(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.45),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 24,),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          strokeWidth: 3,
                          color: _njPink,
                        ),
                        const SizedBox(height: 16),
                        // UPDATED (Aug 12 2026 — UI/UX re-audit): now
                        // reflects the real current stage
                        // (_submissionStatus, set at each step of
                        // _submitRegistration) instead of one static
                        // line for the whole flow — the hero can see
                        // concrete progress, never just a frozen spinner.
                        Text(
                          _submissionStatus,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            color: _text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Please wait — do not close or go back',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            color: _muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Hero Registration',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              // FIX: the "How to be an Allin1 Hero?" guidance now lives on
              // its own screen BEFORE this form (see hero_intro_screen.dart)
              // instead of inline here — Nizam wants it as a proper
              // graphical intro page a hero sees first, not squeezed above
              // the form fields.
              Text(
                'Fill in all details accurately and upload clear document photos. '
                'Admin will call you to verify before approving.',
                style: GoogleFonts.outfit(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              _buildHowToRegisterGuide(context),
              const SizedBox(height: 20),

              // ── Personal Information ──────────────────────────
              _sectionLabel('👤  Personal Information'),
              const SizedBox(height: 12),
              _field(
                controller: _nameController,
                label: 'Full Name',
                icon: Icons.person_rounded,
                validator: (v) => v!.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              _field(
                controller: _phoneController,
                label: 'Contact Number',
                icon: Icons.phone_rounded,
                keyboardType: TextInputType.phone,
                validator: (v) =>
                    v!.trim().length < 10 ? 'Enter a valid 10-digit number' : null,
              ),
              const SizedBox(height: 12),
              // T1: Date of Birth — text entry (dd/mm/yyyy)
              _field(
                controller: _dobController,
                label: 'Date of Birth (dd/mm/yyyy)',
                icon: Icons.cake_rounded,
                keyboardType: TextInputType.datetime,
                validator: (v) =>
                    v!.trim().isEmpty ? 'Date of birth is required' : null,
              ),
              const SizedBox(height: 12),
              _field(
                controller: _addressController,
                label: 'Full Address',
                icon: Icons.home_rounded,
                maxLines: 2,
                validator: (v) =>
                    v!.trim().isEmpty ? 'Address is required' : null,
              ),
              const SizedBox(height: 12),
              // Multi-city: which CITY this hero operates in (structured,
              // filterable — feeds dispatch matching so this hero only
              // gets pinged for rides/orders in their own city). GPS-
              // detected via "Use my current location" (mandatory, per
              // Nizam's request), not manually picked — same pattern as
              // seller_onboarding_screen.dart. Distinct from the
              // free-text "Preferred Work Area" field below, which is a
              // finer-grained area-within-the-city hint.
              InkWell(
                onTap: _detectingCity ? null : _detectCity,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _selectedCity != null ? _njPink.withValues(alpha: 0.12) : _card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _selectedCity != null ? _njPink : _muted.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      if (_detectingCity) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _njPink)) else Icon(_selectedCity != null ? Icons.check_circle_rounded : Icons.my_location_rounded, color: _njPink, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _selectedCity != null
                              ? 'City: ${cityLabelFor(_selectedCity!)}'
                              : 'Use my current location (required)',
                          style: GoogleFonts.outfit(color: _text, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // FIX (CTO critical-bug mandate): manual fallback, always
              // visible — a hero doesn't have to wait for GPS to fail
              // first if they already know location access won't work
              // (denied earlier, no GPS on this device, restricted PWA
              // context, etc.).
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _pickCityManually,
                  child: Text(
                    'Choose city manually',
                    style: GoogleFonts.outfit(color: _njPink, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // FIX: work-area interest field, per Nizam's request — lets
              // a hero say where in Erode they want to work (keywords,
              // e.g. "Perundurai, Bhavani Road, Erode Town"), shown to
              // admin alongside customer search-demand data so coverage
              // gaps are visible. Free text, not mandatory (a hero may
              // genuinely be open to all areas).
              _field(
                controller: _preferredLocationController,
                label: 'Preferred Work Area (e.g. Perundurai, Bhavani Road)',
                icon: Icons.location_on_rounded,
                validator: (_) => null,
              ),
              const SizedBox(height: 4),
              Text(
                'Optional — helps admin match you to nearby work first.',
                style: GoogleFonts.outfit(color: _muted, fontSize: 11),
              ),
              const SizedBox(height: 20),

              // ── Document Numbers ──────────────────────────────
              _sectionLabel('📄  Document Numbers'),
              const SizedBox(height: 12),
              _field(
                controller: _licenseNumberController,
                label: 'Driving License Number',
                icon: Icons.drive_eta_rounded,
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    v!.trim().isEmpty ? 'License number is required' : null,
              ),
              const SizedBox(height: 8),
              _docPhotoTile(
                label: 'License photo (required)',
                photo: _licensePhoto,
                onTap: () => _pickDocPhoto('license'),
                onClear: () => setState(() => _licensePhoto = null),
              ),
              const SizedBox(height: 12),
              _field(
                controller: _aadhaarController,
                label: 'Aadhaar Number',
                icon: Icons.fingerprint_rounded,
                keyboardType: TextInputType.number,
                validator: (v) =>
                    v!.trim().length != 12 ? 'Enter valid 12-digit Aadhaar' : null,
              ),
              const SizedBox(height: 8),
              _docPhotoTile(
                label: 'Aadhaar photo (required)',
                photo: _aadhaarPhoto,
                onTap: () => _pickDocPhoto('aadhaar'),
                onClear: () => setState(() => _aadhaarPhoto = null),
              ),
              const SizedBox(height: 12),
              _field(
                controller: _panController,
                label: 'PAN Number',
                icon: Icons.credit_card_rounded,
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    v!.trim().length < 10 ? 'Enter valid PAN number' : null,
              ),
              const SizedBox(height: 8),
              _docPhotoTile(
                label: 'PAN photo (required)',
                photo: _panPhoto,
                onTap: () => _pickDocPhoto('pan'),
                onClear: () => setState(() => _panPhoto = null),
              ),
              const SizedBox(height: 4),
              Text(
                'All 3 photos are required so admin can verify you and '
                'call to confirm before approving. Having trouble? Use '
                'WhatsApp / Call below as a backup.',
                style: GoogleFonts.outfit(color: _muted, fontSize: 11),
              ),
              const SizedBox(height: 16),

              // NEW (CTO mandate — Advanced KYC & Facial Verification):
              // live selfie, required alongside the 3 doc photos above.
              _sectionLabel('🤳  Live Selfie'),
              const SizedBox(height: 12),
              _selfieTile(),
              const SizedBox(height: 4),
              Text(
                'Required — used to confirm your face matches your ID documents. '
                'Please use your front camera in good lighting, no filters.',
                style: GoogleFonts.outfit(color: _muted, fontSize: 11),
              ),
              const SizedBox(height: 20),

              // NEW (Aug 12 2026 — Nizam's payment QR upload point):
              // optional, saved locally only. Same "Show your QR to
              // the customer" popup (see hero_payment_qr_popup.dart)
              // reads whatever is saved here — a hero who skips this
              // now can still add it later from Settings.
              _sectionLabel('💳  Payment QR (optional)'),
              const SizedBox(height: 12),
              _paymentQrTile(),
              const SizedBox(height: 4),
              Text(
                'Your UPI/payment QR — shown to customers who pay you '
                'directly after a ride/task. Cropped to just the QR and '
                'saved on this device only, never uploaded anywhere. You '
                'can add or change this later from Settings.',
                style: GoogleFonts.outfit(color: _muted, fontSize: 11),
              ),
              const SizedBox(height: 20),

              // ── Vehicle Category ──────────────────────────────
              _sectionLabel('🚗  Vehicle Category'),
              const SizedBox(height: 12),
              _buildHeroCategorySelector(),
              const SizedBox(height: 16),
              _buildEmergencyResponderAgreement(),
              const SizedBox(height: 24),

              // ── T2: Step 2 WhatsApp Card ──────────────────────
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1B2E1B), Color(0xFF122012)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFF25D366).withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF25D366).withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF25D366)
                                .withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            '💬',
                            style: TextStyle(fontSize: 20),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Trouble uploading? Contact Admin',
                            style: GoogleFonts.outfit(
                              color: const Color(0xFF25D366),
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Send photos of your Driving License, PAN Card, and Aadhaar Card to our official WhatsApp for profile activation.',
                      style: GoogleFonts.outfit(
                        // NOTE: this card keeps a dark green WhatsApp-brand
                        // background regardless of the surrounding light
                        // theme, so its text stays an explicit light color
                        // (not the theme's _text, which is now dark) for
                        // contrast.
                        color: const Color(0xFFEFEFEF),
                        fontSize: 13,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _launchWhatsApp,
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: Text(
                          'Send Documents via WhatsApp',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _launchCall,
                        icon: const Icon(Icons.call_rounded, size: 16),
                        label: Text(
                          'Call Admin for Quick Verification',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          // T3: was Colors.blue — now NJ Pink
                          foregroundColor: _njPink,
                          side: BorderSide(
                            color: _njPink.withValues(alpha: 0.5),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // NEW (Aug 12 2026 — Nizam: "yenga problemo antha section
              // la error kaatitu red error kaatanum"): persistent,
              // section-named failure banner. Unlike the old snackbars
              // it does not disappear on its own, so the hero can read
              // it, fix the named field, and retry — with everything
              // they typed still on screen.
              if (_submitError != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _red, width: 1.4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: _red, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Problem in: ${_submitErrorSection ?? 'Submission'}',
                              style: GoogleFonts.outfit(
                                color: _red,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _submitError!,
                        style: GoogleFonts.outfit(color: _text, fontSize: 12, height: 1.45),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Nothing you typed was lost — fix the item above and tap Submit again.',
                        style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // ── Submit ────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitRegistration,
                  style: ElevatedButton.styleFrom(
                    // T3: was _green — now NJ Pink per brand fix
                    backgroundColor: _njPink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 6,
                    shadowColor: _njPink.withValues(alpha: 0.4),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white,),
                        )
                      : Text(
                          'Submit Registration →',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Your form will be reviewed. Approval typically takes 2–4 hours.',
                  style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  // ── Reusable helpers ─────────────────────────────────────────
  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(
          text,
          style: GoogleFonts.outfit(
            color: _text,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.words,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      maxLines: maxLines,
      style: GoogleFonts.outfit(color: _text, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.outfit(color: _muted, fontSize: 13),
        prefixIcon: Icon(icon, color: _muted, size: 20),
        filled: true,
        fillColor: _card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _njPink, width: 1.5),
        ),
        errorStyle: const TextStyle(color: _red, fontSize: 11),
      ),
      validator: validator,
    );
  }

   Widget _buildEmergencyResponderAgreement() {
    return InkWell(
      onTap: () {
        setState(() {
          _agreedEmergencyResponder = !_agreedEmergencyResponder;
        });
        _scheduleDraftSave();
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _agreedEmergencyResponder
              ? _green.withValues(alpha: 0.16)
              : _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _agreedEmergencyResponder
                ? _green
                : Colors.white.withValues(alpha: 0.1),
            width: _agreedEmergencyResponder ? 1.6 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _agreedEmergencyResponder,
              activeColor: _green,
              checkColor: Colors.white,
              side: const BorderSide(color: _muted),
              onChanged: (value) {
                setState(() {
                  _agreedEmergencyResponder = value ?? false;
                });
                _scheduleDraftSave();
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'I agree to act as an Emergency First Responder (SOS Network) in my area.',
                style: GoogleFonts.outfit(
                  color: _text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroCategoryCard extends StatelessWidget {
  const _HeroCategoryCard({
    required _HeroCategory category,
    required bool selected,
    required VoidCallback onTap,
  })  : _category = category,
        _selected = selected,
        _onTap = onTap;

  final _HeroCategory _category;
  final bool _selected;
  final VoidCallback _onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          // THEME FIX: unselected cards used to be dark-navy — repainted
          // white/soft-pink so the whole picker matches the light theme.
          gradient: LinearGradient(
            colors: _selected
                ? const [Color(0xFFFF4FA3), Color(0xFFBE2A7A)]
                : const [Colors.white, Color(0xFFFFF0F7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: _selected ? _njPink : _njPink.withValues(alpha: 0.18),
            width: _selected ? 1.6 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: (_selected ? _njPink : Colors.black)
                  .withValues(alpha: _selected ? 0.28 : 0.06),
              blurRadius: _selected ? 22 : 12,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _selected
                    ? Colors.white.withValues(alpha: 0.22)
                    : _njPink.withValues(alpha: 0.1),
              ),
              child: Icon(
                _category.icon,
                color: _selected ? Colors.white : _njPink,
                size: 26,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _category.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: _selected ? Colors.white : _text,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _category.subtitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: _selected
                    ? Colors.white.withValues(alpha: 0.78)
                    : _muted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

