// ================================================================
// Hero Register Screen
// Allin1 Super App - Hero Onboarding
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/city_config.dart';
import '../services/cloudinary_upload_service.dart';
import '../services/location_service.dart';
// ROUTING FIX (merge duplicate registration/status flows): this screen is
// now reached DIRECTLY, before any sign-in step, so a fresh hero may have
// no Firebase Auth session at all when they hit Submit — Google Sign-In is
// now triggered inline from _submitRegistration() below when needed. Post-
// submit routing now goes to HeroPendingScreen (the same live-listening
// tracker used everywhere else), not the old one-shot, non-live
// HeroVerificationPendingScreen — see hero_pending_screen.dart.
import 'hero_pending_screen.dart';

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

  Future<void> _detectCity() async {
    setState(() => _detectingCity = true);
    try {
      final position = await LocationService().getCurrentLocation();
      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not get your location. Please enable GPS and try again.'), backgroundColor: _red),
          );
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
      }
    } finally {
      if (mounted) setState(() => _detectingCity = false);
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
  // FIX: was only true during the doc-upload step, with a silent gap
  // during Google sign-in and the duplicate-phone Firestore check right
  // before it — the button looked idle/clickable again during that gap,
  // which Nizam reported as the app looking "hung" after tapping Submit.
  // Now covers the ENTIRE submit flow (sign-in through final Firestore
  // writes) via a single try/finally in _submitRegistration(), and drives
  // a full-screen overlay (see build()) in addition to the button spinner.
  bool _isSubmitting = false;

  // T2: CEO WhatsApp placeholder — replace 91XXXXXXXXXX with real number
  static const String _adminWhatsApp = '91XXXXXXXXXX';
  static const String _adminPhone    = '+91XXXXXXXXXX';

  @override
  void dispose() {
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

    final googleSignIn = GoogleSignIn(
      clientId: kIsWeb ? _googleWebClientId : null,
      serverClientId: kIsWeb ? null : _googleWebClientId,
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

  /// Uploads the 3 mandatory doc photos (all 3 are guaranteed non-null
  /// by the time this runs — _submitRegistration validates that before
  /// calling this), returning a map of the ones that uploaded
  /// successfully. If a single upload fails (network blip etc.) it's
  /// logged and skipped rather than blocking the whole registration —
  /// the hero can still fall back to WhatsApp/Call for that one doc.
  Future<Map<String, String>> _uploadPickedDocPhotos(String uid) async {
    final urls = <String, String>{};
    final jobs = <String, PlatformFile?>{
      'licenseDocUrl': _licensePhoto,
      'aadhaarDocUrl': _aadhaarPhoto,
      'panDocUrl': _panPhoto,
    };
    for (final entry in jobs.entries) {
      final file = entry.value;
      if (file == null || file.bytes == null) continue;
      try {
        final url = await CloudinaryUploadService().uploadImageBytes(
          file.bytes!,
          fileName: '${entry.key}_${file.name}',
          folder: 'hero_documents/$uid',
          // Higher than the 100KB default — these are ID/license
          // documents admin must actually read to verify a hero, so a
          // bit more room keeps printed text legible.
          targetBytes: 200 * 1024,
        );
        urls[entry.key] = url;
      } catch (e) {
        debugPrint('[HeroRegister] ${entry.key} upload failed: $e');
      }
    }
    return urls;
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
        const SnackBar(content: Text('Please tap "Use my current location" first.'), backgroundColor: _red),
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

    if (mounted) setState(() => _isSubmitting = true);
    try {
      final user = await _ensureSignedIn();
      if (user == null) {
        // Google picker was cancelled — not a real error, just stop here
        // silently so the hero can retry without a scary red banner.
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
      final enteredPhone =
          (user.phoneNumber ?? _phoneController.text.trim()).trim();
      if (enteredPhone.isNotEmpty) {
        final existing = await FirebaseFirestore.instance
            .collection('heroes')
            .where('phone', isEqualTo: enteredPhone)
            .limit(1)
            .get();
        final duplicate = existing.docs
            .any((doc) => doc.id != user.uid);
        if (duplicate) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'This phone number is already registered as a Hero. '
                  'Please log in with your existing account instead.',
                ),
                backgroundColor: _red,
              ),
            );
          }
          return;
        }
      }

       // Upload the 3 mandatory doc photos (already validated present above).
       final docUrls = await _uploadPickedDocPhotos(user.uid);

       // Save to heroes collection
       await FirebaseFirestore.instance.collection('heroes').doc(user.uid).set({
         'heroId': user.uid,
         'uid': user.uid,
         'name': _nameController.text.trim(),
         'phone': user.phoneNumber ?? _phoneController.text.trim(),
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
         'approvalStatus': 'pending',
         'status': 'offline',
         'onboardingMethod': docUrls.isEmpty ? 'manual_whatsapp' : 'in_app_upload',
         'createdAt': FieldValue.serverTimestamp(),
       });

       // FIX: main_hero.dart's _HeroSetupGate decides whether to show this
       // registration form again by reading users/{uid}.isSetupComplete —
       // this write was missing, so a hero who submitted here would be
       // sent right back to an empty registration form on their next app
       // open (before admin even had a chance to approve them), instead
       // of the pending-status tracker. Mirrors what
       // AuthService.completeProfileSetup does for the customer/Google
       // path.
       await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
         {
           'phone': user.phoneNumber ?? _phoneController.text.trim(),
           'phoneNumber': user.phoneNumber ?? _phoneController.text.trim(),
           'role': 'hero',
           'isSetupComplete': true,
           'setupCompletedAt': FieldValue.serverTimestamp(),
         },
         SetOptions(merge: true),
       );

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Auth error (${e.code}): ${e.message ?? e.toString()}',
            ),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on FirebaseException catch (e) {
      // Task 4: Typed Firestore / Database error — prints plugin + code
      debugPrint(
        '[HeroRegister] FirebaseException [${e.plugin}]: ${e.code} — ${e.message}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Database error (${e.code}): ${e.message ?? e.toString()}',
            ),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, st) {
      // Task 4: Unexpected error — full stack trace to console for debugging
      debugPrint('[HeroRegister] Unexpected error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registration failed: ${e.toString()}'),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      // FIX: single point that turns the loading overlay off, covering
      // every exit path (success navigation, cancelled sign-in, and all
      // 3 error branches above) — no more window where the screen looks
      // idle/hung while a network call is actually still in flight.
      if (mounted) setState(() => _isSubmitting = false);
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
    return Stack(
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
                        Text(
                          'Setting up your Hero account…',
                          style: GoogleFonts.outfit(
                            color: _text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Signing in, uploading documents — please wait',
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
              const SizedBox(height: 12),
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

