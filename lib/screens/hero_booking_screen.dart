// ================================================================
// hero_booking_screen.dart — Broadcast Order System: Hero Booking
// Structured task-creation form (category + location(s) + brief
// description + optional special instructions + preferred timing),
// with voice-to-text dictation on the text fields. Submitting creates
// a service_requests doc (requestType: hero_booking) and broadcasts
// to all online + available heroes, then hands off to the shared
// tracking screen.
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'dart:async';

import '../services/location_service.dart';
import '../services/map_service.dart';
import '../services/shared_location_inbox.dart';
import '../services/service_request_service.dart';
import '../utils/location_link_parser.dart';
import '../utils/service_request_labels.dart';
import 'hero_booking_tracking_screen.dart';
import 'location_picker_screen.dart';

const Color _kPink = Color(0xFFFF4FA3);
const Color _kPinkDark = Color(0xFFBE2A7A);
const Color _kPinkBg = Color(0xFFFFF0F7);
const Color _kBg = Color(0xFFFFFFFF);
const Color _kSurface = Color(0xFFF8F8FF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF9999BB);
const Color _kBorder = Color(0x33FF4FA3);

class HeroBookingScreen extends StatefulWidget {
  const HeroBookingScreen({super.key});
  @override
  State<HeroBookingScreen> createState() => _HeroBookingScreenState();
}

class _HeroBookingScreenState extends State<HeroBookingScreen> {
  String _selectedCategory = 'pickup_delivery';
  final _fromLocationCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _taskDescCtrl = TextEditingController();
  final _instructionsCtrl = TextEditingController();
  bool _showMoreDetails = false;
  String _timingMode = 'asap'; // 'asap' | 'scheduled'
  DateTime? _scheduledAt;
  bool _submitting = false;

  // ── Voice input (speech_to_text — already a pubspec dependency,
  // previously unused anywhere in the app) ─────────────────────────
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  TextEditingController? _listeningTarget;

  /// Whatever was in the field when the customer tapped the mic.
  /// Recognised words are written as base + spoken, so dictating never
  /// silently wipes text the customer already typed, and a session that
  /// restarts mid-way can't append onto its own earlier output.
  String _speechBaseText = '';

  /// Increments on every mic tap. A late callback from an older session
  /// carries a stale token and is discarded instead of writing into a
  /// field the customer has since moved on from.
  int _speechSession = 0;

  /// Resolved once and reused — the device may not have the locale we
  /// want, and asking for a missing one makes listen() fail outright.
  String? _resolvedSpeechLocaleId;
  bool _speechLocaleResolved = false;

  // ── Location autocomplete + "use current location" ───────────────
  // Reuses MapService().search() — already Erode-scoped via OSM
  // Nominatim as its primary source (see map_service.dart), so this is
  // NOT blocked by the separately-known Ola Maps API-key issue; Ola is
  // only a secondary fallback there if OSM returns nothing.
  final _mapService = MapService();
  Timer? _fromDebounce;
  Timer? _locationDebounce;
  List<Map<String, dynamic>> _fromSuggestions = [];
  List<Map<String, dynamic>> _locationSuggestions = [];
  bool _fromFetchingCurrent = false;
  bool _locationFetchingCurrent = false;
  // Coordinates for whichever suggestion (or current-location fetch)
  // was last picked — sent alongside the plain-text address so the
  // hero side has something to actually navigate by, not just free
  // text. Cleared back to null the moment the customer edits the text
  // manually (see the onChanged wiring below), since a hand-typed
  // address no longer corresponds to these specific coordinates.
  double? _fromLocationLat;
  double? _fromLocationLng;
  double? _locationLat;
  double? _locationLng;

  bool get _isPickupDelivery => _selectedCategory == 'pickup_delivery';

  @override
  void initState() {
    super.initState();
    unawaited(_primeSearchBiasWithCustomerCity());
    // A location shared in from WhatsApp/Maps may already be waiting
    // (see shared_location_inbox.dart). Checked after the first frame
    // so there's a Navigator/ScaffoldMessenger to show the prompt on.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumeSharedLocationIfAny();
    });
  }

  // ── Incoming shared location ─────────────────────────────────────
  // The customer shared a location into the app from somewhere else. We
  // know the coordinates but not what they meant by it, so ask — that's
  // one tap, versus making them type an address they don't know.
  void _consumeSharedLocationIfAny() {
    final shared = SharedLocationInbox.instance.take();
    if (shared == null || !mounted) return;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Text(
          'Location received',
          style: GoogleFonts.outfit(
            color: _kText,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.place_rounded, color: _kPink, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    shared.label?.trim().isNotEmpty ?? false
                        ? shared.label!.trim()
                        : '${shared.lat.toStringAsFixed(5)}, '
                            '${shared.lng.toStringAsFixed(5)}',
                    style: const TextStyle(
                        color: _kText, fontSize: 13, height: 1.4,),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Where should this go?',
              style: TextStyle(color: _kMuted, fontSize: 12),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: _kPinkDark),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              unawaited(_applyPickedCoordinates(
                _fromLocationCtrl,
                isFrom: true,
                lat: shared.lat,
                lng: shared.lng,
                fallbackLabel: shared.label,
              ),);
            },
            child: const Text('Pickup'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPink,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              unawaited(_applyPickedCoordinates(
                _locationCtrl,
                isFrom: false,
                lat: shared.lat,
                lng: shared.lng,
                fallbackLabel: shared.label,
              ),);
            },
            child: const Text('Drop'),
          ),
        ],
      ),
    );
  }

  // Sets MapService's search bias to wherever this customer actually is,
  // instead of always searching around Erode — so pickup/drop suggestions
  // stay locally relevant as the app expands to other cities. Best-effort
  // and silent: tries the fast cached fix first, falls back to a fresh GPS
  // fix, and if both fail MapService/OSMProvider just keep using their
  // built-in Erode default, so nothing breaks for a customer who denies
  // location permission.
  Future<void> _primeSearchBiasWithCustomerCity() async {
    try {
      final cached = await LocationService().getLastKnownLocation();
      final position = cached ?? await LocationService().getCurrentLocation();
      if (position == null) return;
      _mapService.setSearchCenter(
        LatLng(position.latitude, position.longitude),
      );
    } catch (e) {
      debugPrint('[HeroBooking] search-bias location fetch failed: $e');
    }
  }

  @override
  void dispose() {
    _fromLocationCtrl.dispose();
    _locationCtrl.dispose();
    _taskDescCtrl.dispose();
    _instructionsCtrl.dispose();
    _fromDebounce?.cancel();
    _locationDebounce?.cancel();
    unawaited(_speech.stop());
    super.dispose();
  }

  // ── Speech locale: always Tamil, deliberately ────────────────────
  //
  // The recogniser has to be told a language BEFORE it starts listening
  // — it cannot work it out from the audio. So one has to be chosen.
  //
  // It is NOT the app's UI language. That's a display preference; a
  // customer can perfectly well run the app in English and speak Tamil,
  // and an earlier version of this tied the two together, which is why
  // speech came back as confident nonsense.
  //
  // It's not the phone's language either — leaving localeId null falls
  // back to that, with the same failure.
  //
  // Tamil is the right constant for this app. Google's ta_IN model is
  // trained on how Tamil speakers actually talk, which includes English
  // words mixed in, so it handles pure Tamil AND Tanglish — "Perundurai
  // road la oru shop irukku" transcribes correctly under ta_IN and gets
  // mangled under en_IN.
  //
  // The customers this feature exists for are the ones who can speak
  // Tamil but can't type English. Anyone comfortable enough in English
  // to need en_IN is comfortable enough to type, so there's no language
  // toggle here on purpose — one less control to explain.
  static const String _kSpeechLocale = 'ta_IN';

  /// Resolved against the device's real locale list, because asking for
  /// a locale the device doesn't have makes listen() fail outright —
  /// no recognition at all, rather than degraded recognition. If Tamil
  /// genuinely isn't installed, null hands the decision back to the
  /// system, which is worse but still functional.
  Future<String?> _resolveSpeechLocale() async {
    if (_speechLocaleResolved) return _resolvedSpeechLocaleId;
    _speechLocaleResolved = true;

    try {
      final locales = await _speech.locales();
      // Ids come back in varying shapes across platforms — 'ta_IN',
      // 'ta-IN', plain 'ta' — so normalise before comparing.
      const wanted = _kSpeechLocale;
      const wantedPrefix = 'ta';

      for (final locale in locales) {
        final id = locale.localeId.replaceAll('-', '_').toLowerCase();
        if (id == wanted.toLowerCase()) {
          _resolvedSpeechLocaleId = locale.localeId;
          return _resolvedSpeechLocaleId;
        }
      }
      // No exact ta_IN — take any Tamil variant.
      for (final locale in locales) {
        final id = locale.localeId.replaceAll('-', '_').toLowerCase();
        if (id.startsWith(wantedPrefix)) {
          _resolvedSpeechLocaleId = locale.localeId;
          debugPrint(
            '[HeroBooking][speech] using Tamil variant ${locale.localeId}',
          );
          return _resolvedSpeechLocaleId;
        }
      }
      debugPrint(
        '[HeroBooking][speech] Tamil unavailable on this device, '
        'falling back to system default',
      );
    } catch (e) {
      debugPrint('[HeroBooking][speech] locale resolve failed: $e');
    }
    return _resolvedSpeechLocaleId;
  }

  /// Collapses text that has been recognised twice back to back.
  ///
  /// Android's recogniser can restart itself mid-session and replay what
  /// it already reported, which lands in the field as "Erode bus stand
  /// Erode bus stand". Bounded sessions (pauseFor/listenFor below) make
  /// this rare, but the customer sees the result either way, so it's
  /// worth catching here too.
  static String _collapseImmediateRepeat(String input) {
    final text = input.trim();
    if (text.isEmpty) return text;
    final words = text.split(RegExp(r'\s+'));
    if (words.length < 2 || words.length.isOdd) return text;
    final half = words.length ~/ 2;
    final first = words.sublist(0, half).join(' ');
    final second = words.sublist(half).join(' ');
    return first.toLowerCase() == second.toLowerCase() ? first : text;
  }

  Future<void> _toggleListening(TextEditingController target) async {
    // Tapping the mic on the field that's already listening stops it.
    // Tapping a DIFFERENT field's mic used to just stop the first one
    // and do nothing else, so the customer had to tap twice for no
    // visible reason. Now it hands over.
    if (_isListening) {
      final sameField = identical(_listeningTarget, target);
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      if (sameField) return;
    }

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission is needed for voice input.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (!_speechAvailable) {
      _speechAvailable = await _speech.initialize(
        onError: (e) => debugPrint('[HeroBooking][speech] error: $e'),
        onStatus: (s) => debugPrint('[HeroBooking][speech] status: $s'),
      );
      if (!_speechAvailable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Voice input is not available on this device/browser.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    final localeId = await _resolveSpeechLocale();
    if (!mounted) return;

    _listeningTarget = target;
    _speechBaseText = target.text.trim();
    final session = ++_speechSession;
    setState(() => _isListening = true);

    try {
      await _speech.listen(
        onResult: (result) {
          // Discard anything from a session the customer has moved on
          // from — otherwise a trailing callback overwrites the field
          // they're now typing in.
          if (!mounted || session != _speechSession) return;

          final spoken = _collapseImmediateRepeat(result.recognizedWords);
          final combined = _speechBaseText.isEmpty
              ? spoken
              : (spoken.isEmpty ? _speechBaseText : '$_speechBaseText $spoken');

          setState(() {
            target.text = combined;
            target.selection = TextSelection.fromPosition(
              TextPosition(offset: target.text.length),
            );
          });

          // Dictating into a location field should refresh the search
          // suggestions, exactly as typing does. Programmatic writes to
          // a controller don't fire onChanged, so this never happened
          // before — the customer spoke an address and got no
          // suggestions at all.
          if (identical(target, _fromLocationCtrl)) {
            _onFromLocationChanged(combined);
          } else if (identical(target, _locationCtrl)) {
            _onLocationChanged(combined);
          }

          if (result.finalResult) {
            setState(() => _isListening = false);
          }
        },
        listenOptions: stt.SpeechListenOptions(
          // Was the default ListenMode.confirmation, which is tuned for
          // short yes/no style commands. An address or a task
          // description is a sentence — dictation mode is what that
          // needs, and using the wrong one is a large part of why
          // recognition was coming back wrong or truncated.
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          // Bounded session. With both of these left null the recogniser
          // runs open-ended and Android may silently restart it, which
          // is where the repeated text came from.
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
          cancelOnError: true,
          localeId: localeId,
        ),
      );
    } catch (e) {
      debugPrint('[HeroBooking][speech] listen failed: $e');
      if (mounted) {
        setState(() => _isListening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice input could not start. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickScheduledTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt ?? now),
    );
    if (time == null || !mounted) return;
    setState(() {
      _scheduledAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    if (_taskDescCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe your task first!'), backgroundColor: Colors.red),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      final requestId = await ServiceRequestService().createServiceRequest(
        requestType: 'hero_booking',
        customerId: user.uid,
        customerName: user.displayName ?? 'Customer',
        customerPhone: user.phoneNumber ?? '',
        details: {
          'category': _selectedCategory,
          'taskDescription': _taskDescCtrl.text.trim(),
          if (_isPickupDelivery && _fromLocationCtrl.text.trim().isNotEmpty)
            'fromLocation': _fromLocationCtrl.text.trim(),
          // Coordinates are only present when the customer picked a
          // suggestion or used "current location" — a hand-typed
          // address with no selection stays text-only, same as before
          // this round (no regression for free-text entry).
          if (_isPickupDelivery && _fromLocationLat != null && _fromLocationLng != null) ...{
            'fromLocationLat': _fromLocationLat,
            'fromLocationLng': _fromLocationLng,
          },
          if (_locationCtrl.text.trim().isNotEmpty)
            'location': _locationCtrl.text.trim(),
          if (_locationLat != null && _locationLng != null) ...{
            'locationLat': _locationLat,
            'locationLng': _locationLng,
          },
          if (_instructionsCtrl.text.trim().isNotEmpty)
            'specialInstructions': _instructionsCtrl.text.trim(),
          'preferredTiming': (_timingMode == 'scheduled' && _scheduledAt != null)
              ? _scheduledAt!.toIso8601String()
              : 'asap',
        },
      );

      // Fire-and-forget: if no hero accepts within the broadcast
      // window, route this request to the admin "New Orders" tab.
      // Detached from this screen's lifecycle since the customer
      // navigates away immediately after this call.
      unawaited(Future.delayed(
        const Duration(seconds: kServiceRequestPingExpirySeconds),
        () => ServiceRequestService().markTimeoutIfStillPending(requestId),
      ));

      if (!mounted) return;
      // Was ServiceRequestTrackingScreen (the older, generic 4-category
      // tracker with just a status stepper) — now routes to
      // HeroBookingTrackingScreen, the screen with the task-details
      // card, estimate-approval, payment, and rating features. It
      // resolves the customer's active hero_booking request live, so
      // no requestId/requestType args are needed here.
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const HeroBookingTrackingScreen(),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send request: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Hero Booking', style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 18)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kPink.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kPink.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Text('🦸', style: TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hire a Hero for anything', style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 14)),
                        const SizedBox(height: 2),
                        const Text('Errands, deliveries, help with tasks — describe it and we\'ll send the nearest available Hero.', style: TextStyle(color: _kMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── 1. Task category ─────────────────────────────────
            Text('What kind of task?', style: GoogleFonts.outfit(color: _kText, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kHeroBookingCategories.map(_categoryChip).toList(),
            ),
            const SizedBox(height: 20),

            // ── 2. Location(s) — progressive disclosure ──────────
            if (_isPickupDelivery) ...[
              Text('Pickup location', style: GoogleFonts.outfit(color: _kText, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _locationField(
                controller: _fromLocationCtrl,
                hint: 'e.g., Erode Collector Office',
                isFrom: true,
              ),
              const SizedBox(height: 16),
              Text('Drop location', style: GoogleFonts.outfit(color: _kText, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _locationField(
                controller: _locationCtrl,
                hint: 'e.g., My home, 12 Gandhi Street',
                isFrom: false,
              ),
            ] else ...[
              Text('Location', style: GoogleFonts.outfit(color: _kText, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _locationField(
                controller: _locationCtrl,
                hint: 'e.g., Erode Collector Office',
                isFrom: false,
              ),
            ],
            const SizedBox(height: 16),

            // ── 3. Brief task description ─────────────────────────
            Text('Brief description', style: GoogleFonts.outfit(color: _kText, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _voiceTextField(
              controller: _taskDescCtrl,
              hint: 'e.g., Collect my parcel and deliver it home',
              maxLines: 1,
            ),
            const SizedBox(height: 10),

            // ── 4. Special instructions — optional, expandable ────
            if (!_showMoreDetails)
              InkWell(
                onTap: () => setState(() => _showMoreDetails = true),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_circle_rounded, color: _kPink, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Add more details (optional)',
                        style: GoogleFonts.outfit(color: _kPinkDark, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Text('Special instructions', style: GoogleFonts.outfit(color: _kText, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _voiceTextField(
                controller: _instructionsCtrl,
                hint: 'Anything else the Hero should know?',
                maxLines: 3,
              ),
            ],
            const SizedBox(height: 20),

            // ── 5. Preferred timing — optional ────────────────────
            Text('When do you need this?', style: GoogleFonts.outfit(color: _kText, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(
              children: [
                _timingChip(label: 'ASAP', value: 'asap'),
                const SizedBox(width: 8),
                _timingChip(label: 'Schedule for later', value: 'scheduled'),
              ],
            ),
            if (_timingMode == 'scheduled') ...[
              const SizedBox(height: 10),
              InkWell(
                onTap: _pickScheduledTime,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _kSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule_rounded, color: _kPink, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        _scheduledAt != null
                            ? '${_scheduledAt!.day}/${_scheduledAt!.month}/${_scheduledAt!.year} at ${TimeOfDay.fromDateTime(_scheduledAt!).format(context)}'
                            : 'Pick a date & time',
                        style: GoogleFonts.outfit(color: _kText, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPink,
                  elevation: 4,
                  shadowColor: _kPink.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Find Me a Hero', style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const _ActiveHeroBookingCard(),
          ],
        ),
      ),
    );
  }

  // ── Category chip — pill style matching the app's premium pink
  // selected/unselected recipe (solid pink + white text + soft glow
  // when selected, matching bike_booking_screen.dart's chip language).
  Widget _categoryChip(Map<String, String> category) {
    final key = category['key']!;
    final label = category['label']!;
    final isSelected = _selectedCategory == key;
    return InkWell(
      onTap: () => setState(() => _selectedCategory = key),
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? _kPink : _kSurface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: isSelected ? _kPink : _kBorder),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _kPink.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: isSelected ? Colors.white : _kText,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _timingChip({required String label, required String value}) {
    final isSelected = _timingMode == value;
    return InkWell(
      onTap: () => setState(() => _timingMode = value),
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? _kPink : _kSurface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: isSelected ? _kPink : _kBorder),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _kPink.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: isSelected ? Colors.white : _kText,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ── Text field with an inline voice-dictation mic button. Styled
  // as a small pink gradient circle (Icons.mic_rounded) rather than a
  // bare default icon — kept as a real Material icon rather than a
  // guessed FluentEmojiFlat constant name, since I could not safely
  // confirm the exact microphone icon identifier in that package from
  // this sandbox (see deviation note in the implementation report).
  void _onFromLocationChanged(String query) {
    // Manual edit invalidates whatever coordinates a prior suggestion/
    // current-location fetch attached — the text no longer matches them.
    _fromLocationLat = null;
    _fromLocationLng = null;
    _fromDebounce?.cancel();
    final q = query.trim();
    if (q.length < 3) {
      if (mounted) setState(() => _fromSuggestions = []);
      return;
    }
    _fromDebounce = Timer(const Duration(milliseconds: 500), () async {
      final results = await _mapService.search(q);
      if (!mounted || _fromLocationCtrl.text.trim() != q) return;
      setState(() => _fromSuggestions = results);
    });
  }

  void _onLocationChanged(String query) {
    _locationLat = null;
    _locationLng = null;
    _locationDebounce?.cancel();
    final q = query.trim();
    if (q.length < 3) {
      if (mounted) setState(() => _locationSuggestions = []);
      return;
    }
    _locationDebounce = Timer(const Duration(milliseconds: 500), () async {
      final results = await _mapService.search(q);
      if (!mounted || _locationCtrl.text.trim() != q) return;
      setState(() => _locationSuggestions = results);
    });
  }

  void _selectFromSuggestion(Map<String, dynamic> loc) {
    setState(() {
      _fromLocationCtrl.text = loc['name'] as String? ?? '';
      _fromLocationLat = (loc['lat'] as num?)?.toDouble();
      _fromLocationLng = (loc['lng'] as num?)?.toDouble();
      _fromSuggestions = [];
    });
  }

  void _selectLocationSuggestion(Map<String, dynamic> loc) {
    setState(() {
      _locationCtrl.text = loc['name'] as String? ?? '';
      _locationLat = (loc['lat'] as num?)?.toDouble();
      _locationLng = (loc['lng'] as num?)?.toDouble();
      _locationSuggestions = [];
    });
  }

  Future<void> _useCurrentLocationFor(
    TextEditingController controller, {
    required bool isFrom,
  }) async {
    setState(() {
      if (isFrom) {
        _fromFetchingCurrent = true;
      } else {
        _locationFetchingCurrent = true;
      }
    });
    try {
      // Reuses LocationService().getCurrentLocation() — the app's one
      // canonical current-location fetch (location_service.dart:58-63),
      // already tuned with LocationAccuracy.high + a 15s time limit and
      // its own permission check. A bare Geolocator.getCurrentPosition()
      // call with no settings (what this used to do) can resolve to a
      // low-effort/cached/network-based fix instead of waiting for a
      // real GPS lock — on a laptop with no GPS chip, that's exactly
      // what produced two different, both-wrong locations for pickup
      // and drop fetched moments apart at the same physical spot.
      final position = await LocationService().getCurrentLocation();
      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Could not get your location. Please check location permission is allowed and try again.',),),
          );
        }
        return;
      }
      final result = await _mapService.reverseGeocode(
        LatLng(position.latitude, position.longitude),
      );
      final name = (result?['name'] as String?) ??
          (result?['full'] as String?) ??
          'Current Location';
      if (!mounted) return;
      setState(() {
        controller.text = name;
        if (isFrom) {
          _fromLocationLat = position.latitude;
          _fromLocationLng = position.longitude;
          _fromSuggestions = [];
        } else {
          _locationLat = position.latitude;
          _locationLng = position.longitude;
          _locationSuggestions = [];
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not fetch current location: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          if (isFrom) {
            _fromFetchingCurrent = false;
          } else {
            _locationFetchingCurrent = false;
          }
        });
      }
    }
  }

  // Opens the full-screen map picker and writes whatever the customer
  // pins back into this field — address text AND exact coordinates.
  // Seeded with the field's current coordinates when it already has
  // them, so re-opening resumes where they left off.
  Future<void> _selectOnMapFor(
    TextEditingController controller, {
    required bool isFrom,
  }) async {
    final existingLat = isFrom ? _fromLocationLat : _locationLat;
    final existingLng = isFrom ? _fromLocationLng : _locationLng;

    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute<PickedLocation>(
        builder: (_) => LocationPickerScreen(
          title: isFrom ? 'Pickup location' : 'Drop location',
          initialCenter: (existingLat != null && existingLng != null)
              ? LatLng(existingLat, existingLng)
              : null,
        ),
      ),
    );

    if (picked == null || !mounted) return;
    setState(() {
      controller.text = picked.name;
      if (isFrom) {
        _fromLocationLat = picked.lat;
        _fromLocationLng = picked.lng;
        _fromSuggestions = [];
      } else {
        _locationLat = picked.lat;
        _locationLng = picked.lng;
        _locationSuggestions = [];
      }
    });
  }

  // ── Paste a location link ────────────────────────────────────────
  // Reads the clipboard, pulls coordinates straight out of the text
  // (see location_link_parser.dart — a WhatsApp location link carries
  // them in plain sight, so no network call and no CORS problem), then
  // reverse-geocodes for a readable address.
  Future<void> _pasteLocationLinkFor(
    TextEditingController controller, {
    required bool isFrom,
  }) async {
    String pasted = '';
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      pasted = clip?.text?.trim() ?? '';
    } catch (e) {
      debugPrint('[HeroBooking] clipboard read failed: $e');
    }

    if (!mounted) return;

    if (pasted.isEmpty) {
      _showLocationLinkHelp(
        'Nothing copied yet',
        'Open WhatsApp, long-press the location message, tap Copy, then '
            'come back and try again.',
        controller,
        isFrom: isFrom,
      );
      return;
    }

    final result = LocationLinkParser.parse(pasted);

    if (result.isShortLink) {
      // maps.app.goo.gl and friends hide the coordinates behind a
      // redirect we can't follow from a browser. Don't dead-end the
      // customer — hand them straight to the map picker.
      _showLocationLinkHelp(
        'This link is shortened',
        "We can't read the exact spot from a shortened Google Maps link. "
            'Pick it on the map instead — it only takes a moment.',
        controller,
        isFrom: isFrom,
      );
      return;
    }

    if (!result.isResolved) {
      _showLocationLinkHelp(
        'No location in that link',
        "What you copied doesn't look like a location. Copy the location "
            'message itself from WhatsApp, or pick it on the map.',
        controller,
        isFrom: isFrom,
      );
      return;
    }

    await _applyPickedCoordinates(
      controller,
      isFrom: isFrom,
      lat: result.lat!,
      lng: result.lng!,
      fallbackLabel: result.label,
    );
  }

  /// Writes coordinates into a field, resolving a readable address for
  /// them first. Shared by the paste flow and the share-target flow.
  Future<void> _applyPickedCoordinates(
    TextEditingController controller, {
    required bool isFrom,
    required double lat,
    required double lng,
    String? fallbackLabel,
  }) async {
    String label = fallbackLabel?.trim() ?? '';
    try {
      final geo = await _mapService.reverseGeocode(LatLng(lat, lng));
      final resolved =
          (geo?['full'] as String?) ?? (geo?['name'] as String?) ?? '';
      if (resolved.trim().isNotEmpty) label = resolved.trim();
    } catch (e) {
      debugPrint('[HeroBooking] reverse geocode for pasted link failed: $e');
    }

    if (!mounted) return;
    setState(() {
      // Coordinates are exact even when the address lookup fails, so a
      // readable lat/lng is a better fallback than an empty field.
      controller.text = label.isNotEmpty
          ? label
          : '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
      if (isFrom) {
        _fromLocationLat = lat;
        _fromLocationLng = lng;
        _fromSuggestions = [];
      } else {
        _locationLat = lat;
        _locationLng = lng;
        _locationSuggestions = [];
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isFrom ? 'Pickup location set' : 'Drop location set',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Explains what went wrong and offers the map picker as the way out,
  /// so no failure path leaves the customer with nothing to tap.
  void _showLocationLinkHelp(
    String title,
    String message,
    TextEditingController controller, {
    required bool isFrom,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Text(
          title,
          style: GoogleFonts.outfit(
            color: _kText,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(color: _kMuted, fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close', style: TextStyle(color: _kMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPink,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              unawaited(_selectOnMapFor(controller, isFrom: isFrom));
            },
            child: const Text('Select on map'),
          ),
        ],
      ),
    );
  }

  // ── "More ways" sheet ────────────────────────────────────────────
  // Four location options side by side under a text field turned into
  // four cramped 11px links wrapping onto three lines — unreadable on a
  // phone. The two most-used stay inline; the rest live here, where each
  // one gets a proper icon, a full-size label and a line of explanation.
  Future<void> _showMoreLocationWays(
    TextEditingController controller, {
    required bool isFrom,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                isFrom ? 'Pickup location' : 'Drop location',
                style: GoogleFonts.outfit(
                  color: _kText,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _moreWayTile(
              sheetContext,
              icon: Icons.my_location_rounded,
              title: 'Use current location',
              subtitle: 'Where you are right now',
              onTap: () => _useCurrentLocationFor(controller, isFrom: isFrom),
            ),
            _moreWayTile(
              sheetContext,
              icon: Icons.map_rounded,
              title: 'Select on map',
              subtitle: 'Move the pin to the exact spot',
              onTap: () => _selectOnMapFor(controller, isFrom: isFrom),
            ),
            _moreWayTile(
              sheetContext,
              icon: Icons.content_paste_rounded,
              title: 'Paste location link',
              subtitle: 'A link someone sent you on WhatsApp',
              onTap: () => _pasteLocationLinkFor(controller, isFrom: isFrom),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _moreWayTile(
    BuildContext sheetContext, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Future<void> Function() onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: _kPink.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: _kPink, size: 19),
      ),
      title: Text(
        title,
        style: GoogleFonts.outfit(
          color: _kText,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: _kMuted, fontSize: 11),
      ),
      onTap: () {
        // Close the sheet first — the actions below push screens or
        // show dialogs of their own, and stacking them on top of a
        // sheet that is still open looks broken.
        Navigator.of(sheetContext).pop();
        unawaited(onTap());
      },
    );
  }

  // Small pink text action used for the row of location shortcuts under
  // each field. Factored out so the three entry points stay visually
  // identical and adding a fourth later is a one-liner.
  Widget _locationAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool busy = false,
  }) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            busy
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _kPink,),)
                : Icon(icon, color: _kPink, size: 14),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.outfit(
                    color: _kPinkDark,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,),),
          ],
        ),
      ),
    );
  }

  // Pickup/drop field: the existing voice TextField, plus a live search
  // dropdown and a row of location shortcuts — "Use current location"
  // and "Select on map". All optional; the customer can still just type
  // free text as before.
  Widget _locationField({
    required TextEditingController controller,
    required String hint,
    required bool isFrom,
  }) {
    final suggestions = isFrom ? _fromSuggestions : _locationSuggestions;
    final fetchingCurrent = isFrom ? _fromFetchingCurrent : _locationFetchingCurrent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _voiceTextField(
          controller: controller,
          hint: hint,
          maxLines: 1,
          onChanged: isFrom ? _onFromLocationChanged : _onLocationChanged,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 16,
          runSpacing: 2,
          children: [
            _locationAction(
              icon: Icons.my_location_rounded,
              label: 'Use current location',
              busy: fetchingCurrent,
              onTap: () => _useCurrentLocationFor(controller, isFrom: isFrom),
            ),
            _locationAction(
              icon: Icons.map_rounded,
              label: 'Select on map',
              onTap: () =>
                  unawaited(_selectOnMapFor(controller, isFrom: isFrom)),
            ),
            _locationAction(
              icon: Icons.more_horiz_rounded,
              label: 'More ways',
              onTap: () =>
                  unawaited(_showMoreLocationWays(controller, isFrom: isFrom)),
            ),
          ],
        ),
        if (suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorder),
            ),
            constraints: const BoxConstraints(maxHeight: 180),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: suggestions.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: _kBorder),
              itemBuilder: (context, i) {
                final s = suggestions[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_rounded,
                      color: _kPink, size: 18,),
                  title: Text(s['name'] as String? ?? '',
                      style: const TextStyle(fontSize: 13, color: _kText),),
                  onTap: () => isFrom
                      ? _selectFromSuggestion(s)
                      : _selectLocationSuggestion(s),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _voiceTextField({
    required TextEditingController controller,
    required String hint,
    required int maxLines,
    ValueChanged<String>? onChanged,
  }) {
    final isThisFieldListening = _isListening && _listeningTarget == controller;
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14, color: _kText),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _kMuted.withValues(alpha: 0.7), fontSize: 13),
        filled: true,
        fillColor: _kSurface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: () => _toggleListening(controller),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isThisFieldListening
                      ? [_kPink, _kPinkDark]
                      : [_kPink.withValues(alpha: 0.16), _kPink.withValues(alpha: 0.08)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: isThisFieldListening
                    ? [
                        BoxShadow(
                          color: _kPink.withValues(alpha: 0.4),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                isThisFieldListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: isThisFieldListening ? Colors.white : _kPinkDark,
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ================================================================
// ACTIVE HERO BOOKING STATUS — compact status widget, shown on this
// Hero Booking page itself (below the task-booking form), NOT on the
// main customer dashboard. Shows the customer's most recent,
// not-yet-completed hero_booking service_requests doc (current stage
// + an approximate ETA hint). Renders nothing when there's no active
// request. Tapping opens the full stage-tracker detail screen
// (hero_booking_tracking_screen.dart).
// ================================================================
class _ActiveHeroBookingCard extends StatelessWidget {
  const _ActiveHeroBookingCard();

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || userId.isEmpty) {
      return const SizedBox.shrink();
    }

    // Same 2-equality + orderBy(createdAt) shape already proven in
    // production by custom_food_order_screen.dart's _buildMyOrders()
    // — reuses that existing composite index on service_requests, no
    // new index required. Limit 5 + client-side filter for "not
    // completed" avoids needing a 3rd inequality-filter composite
    // index just for this widget.
    final stream = FirebaseFirestore.instance
        .collection('service_requests')
        .where('customerId', isEqualTo: userId)
        .where('requestType', isEqualTo: 'hero_booking')
        .orderBy('createdAt', descending: true)
        // Was 5. A customer can book several tasks in a row, and
        // anything past the cap never appeared at all.
        .limit(20)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final docs = snapshot.data!.docs;

        // Collect EVERY live booking, not just the newest.
        //
        // This loop used to assign the first not-finished doc to a
        // single `active` variable and `break`. So a customer who
        // booked ten tasks saw exactly one of them — the other nine
        // existed in Firestore, were being worked on by heroes, and
        // were completely invisible in the app. Now each one gets its
        // own card.
        final active = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        for (final doc in docs) {
          final docData = doc.data();
          final status = docData['status'] as String? ?? 'pending';
          final paymentStatus = docData['paymentStatus'] as String?;
          final customerRating = docData['customerRating'];
          // A completed-but-unpaid task must still surface here so the
          // customer notices a bill is waiting, and a paid-but-unrated
          // task must also still surface (cash-close path never routes
          // the customer through a payment screen, so this card — and
          // its tap-through to the tracking screen — is what leads them
          // to the rating prompt).
          final fullyDone = status == 'completed' &&
              paymentStatus == 'paid' &&
              customerRating != null;
          if (!fullyDone) {
            active.add(doc);
          }
        }
        if (active.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    active.length == 1
                        ? 'Your active booking'
                        : 'Your active bookings',
                    style: GoogleFonts.outfit(
                      color: _kText,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (active.length > 1) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2,),
                      decoration: BoxDecoration(
                        color: _kPink,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${active.length}',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              ...active.map(_buildBookingCard),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBookingCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return Builder(
      builder: (context) {
        final data = doc.data();
        final status = data['status'] as String? ?? 'pending';
        final statusLabel = serviceRequestStatusLabel('hero_booking', status);
        final etaLabel = heroBookingEtaLabel(status);
        final details = (data['details'] as Map<String, dynamic>?) ?? const {};
        final taskDescription =
            (details['taskDescription'] as String?)?.trim();

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                // Pass the specific id — without it the detail screen
                // resolves "most recent active" on its own and every
                // card in the list would open the same booking.
                builder: (_) => HeroBookingTrackingScreen(requestId: doc.id),
              ),
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kPinkBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _kPink.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _kPink.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text('🦸', style: TextStyle(fontSize: 22)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (taskDescription != null && taskDescription.isNotEmpty)
                              ? taskDescription
                              : 'Your Hero Booking',
                          style: GoogleFonts.outfit(
                              color: _kText,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          statusLabel,
                          style: GoogleFonts.outfit(
                              color: _kPinkDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,),
                        ),
                        if (etaLabel != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            etaLabel,
                            style: const TextStyle(color: _kMuted, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: _kMuted),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
