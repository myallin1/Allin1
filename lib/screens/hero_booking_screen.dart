// ================================================================
// hero_booking_screen.dart — Broadcast Order System: Hero Booking
// Structured task-creation form (category + location(s) + brief
// description + optional special instructions + preferred timing),
// with voice-to-text dictation on the text fields. Submitting creates
// a service_requests doc (requestType: hero_booking) and broadcasts
// to all online + available heroes, then hands off to the shared
// tracking screen.
// ================================================================
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../services/location_service.dart';
import '../services/map_service.dart';
import '../services/service_request_service.dart';
import '../services/shared_location_inbox.dart';
import '../utils/location_link_parser.dart';
import '../utils/service_request_labels.dart';
import '../widgets/server_busy_dialog.dart';
import 'hero_booking_status_screen.dart';
import 'hero_booking_tracking_screen.dart';
import 'location_picker_screen.dart';
import '../services/theme_context_extensions.dart';

// Batch 1 retrofit: former hardcoded hex constants (_kPink, _kPinkDark,
// _kPinkBg, _kBg, _kSurface, _kText, _kMuted, _kBorder) removed in favor
// of context.colors.* (theme_context_extensions.dart) so this screen is
// reactive to all 5 app themes instead of frozen on the old pink/white
// palette. Mapping: _kPink->accent, _kPinkDark->accentSecondary,
// _kPinkBg->subtleFill, _kBg->background, _kSurface->surface,
// _kText->text, _kMuted->mutedText, _kBorder->border.

class HeroBookingScreen extends StatefulWidget {
  const HeroBookingScreen({super.key, this.initialCategory = 'pickup_delivery'});

  /// Which kHeroBookingCategories key the form opens on. Defaults to
  /// 'pickup_delivery' for the dashboard's own Hero Booking mega card;
  /// the dashboard's "Call for Customise Order" entry point passes
  /// 'other' so it lands where that promise ("describe anything, a
  /// Hero will handle it") actually lives now.
  final String initialCategory;

  @override
  State<HeroBookingScreen> createState() => _HeroBookingScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('initialCategory', initialCategory));
  }
}

class _HeroBookingScreenState extends State<HeroBookingScreen> {
  late String _selectedCategory;
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
    _selectedCategory = widget.initialCategory;
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
            color: context.colors.text,
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
                Icon(Icons.place_rounded, color: context.colors.accent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    shared.label?.trim().isNotEmpty ?? false
                        ? shared.label!.trim()
                        : '${shared.lat.toStringAsFixed(5)}, '
                            '${shared.lng.toStringAsFixed(5)}',
                    style: const TextStyle(
                        color: context.colors.text, fontSize: 13, height: 1.4,),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Where should this go?',
              style: TextStyle(color: context.colors.mutedText, fontSize: 12),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: context.colors.accentSecondary),
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
              backgroundColor: context.colors.accent,
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
      ),);

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
        showServerBusyDialog(context);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.colors.text, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Hero Booking', style: GoogleFonts.outfit(color: context.colors.text, fontWeight: FontWeight.w800, fontSize: 18)),
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
                color: context.colors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.colors.accent.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Text('🦸', style: TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hire a Hero for anything', style: GoogleFonts.outfit(color: context.colors.text, fontWeight: FontWeight.w800, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text("Errands, deliveries, help with tasks — describe it and we'll send the nearest available Hero.", style: TextStyle(color: context.colors.mutedText, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── What a Hero can do -- tappable idea slider ────────
            // Concrete examples, not just the dry category labels
            // below: this is what actually helps a customer realise
            // the range of tasks a Hero covers. Tapping a card jumps
            // straight to its matching category.
            Text('What can a Hero do for you?', style: GoogleFonts.outfit(color: context.colors.text, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            _HeroTaskIdeasMarquee(
              onSelect: (key) => setState(() => _selectedCategory = key),
            ),
            const SizedBox(height: 24),

            // ── 1. Task category ─────────────────────────────────
            Text('What kind of task?', style: GoogleFonts.outfit(color: context.colors.text, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kHeroBookingCategories.map(_categoryChip).toList(),
            ),
            const SizedBox(height: 20),

            // ── 2. Location(s) — progressive disclosure ──────────
            if (_isPickupDelivery) ...[
              Text('Pickup location', style: GoogleFonts.outfit(color: context.colors.text, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _locationField(
                controller: _fromLocationCtrl,
                hint: 'e.g., Erode Collector Office',
                isFrom: true,
              ),
              const SizedBox(height: 16),
              Text('Drop location', style: GoogleFonts.outfit(color: context.colors.text, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _locationField(
                controller: _locationCtrl,
                hint: 'e.g., My home, 12 Gandhi Street',
                isFrom: false,
              ),
            ] else ...[
              Text('Location', style: GoogleFonts.outfit(color: context.colors.text, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _locationField(
                controller: _locationCtrl,
                hint: 'e.g., Erode Collector Office',
                isFrom: false,
              ),
            ],
            const SizedBox(height: 16),

            // ── 3. Brief task description ─────────────────────────
            Text('Brief description', style: GoogleFonts.outfit(color: context.colors.text, fontSize: 14, fontWeight: FontWeight.w700)),
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
                      Icon(Icons.add_circle_rounded, color: context.colors.accent, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Add more details (optional)',
                        style: GoogleFonts.outfit(color: context.colors.accentSecondary, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Text('Special instructions', style: GoogleFonts.outfit(color: context.colors.text, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _voiceTextField(
                controller: _instructionsCtrl,
                hint: 'Anything else the Hero should know?',
                maxLines: 3,
              ),
            ],
            const SizedBox(height: 20),

            // ── 5. Preferred timing — optional ────────────────────
            Text('When do you need this?', style: GoogleFonts.outfit(color: context.colors.text, fontSize: 14, fontWeight: FontWeight.w700)),
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
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.colors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.schedule_rounded, color: context.colors.accent, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        _scheduledAt != null
                            ? '${_scheduledAt!.day}/${_scheduledAt!.month}/${_scheduledAt!.year} at ${TimeOfDay.fromDateTime(_scheduledAt!).format(context)}'
                            : 'Pick a date & time',
                        style: GoogleFonts.outfit(color: context.colors.text, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),

          ],
        ),
      ),
      // FIX (per Nizam's correction): every service request type must
      // share the SAME bottom page-split UI already proven for Food
      // Genie and NJ Tech — a Book button + a "Booking Status" button
      // that opens a full list of past+current tasks, instead of an
      // inline active-booking card buried at the bottom of the form or
      // (the earlier, rejected attempt) auto-jumping the tile tap
      // straight into tracking.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.accent,
                      elevation: 4,
                      shadowColor: context.colors.accent.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.bolt_rounded, color: Colors.white, size: 18),
                    label: Text('Find Me a Hero', style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: context.colors.accent, width: 1.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HeroBookingStatusScreen()),
                    ),
                    icon: Icon(Icons.receipt_long_rounded, color: context.colors.accent, size: 18),
                    label: Text('Booking Status', style: GoogleFonts.outfit(color: context.colors.accent, fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
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
          color: isSelected ? context.colors.accent : context.colors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: isSelected ? context.colors.accent : context.colors.border),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: context.colors.accent.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: isSelected ? Colors.white : context.colors.text,
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
          color: isSelected ? context.colors.accent : context.colors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: isSelected ? context.colors.accent : context.colors.border),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: context.colors.accent.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: isSelected ? Colors.white : context.colors.text,
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
            color: context.colors.text,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(color: context.colors.mutedText, fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Close', style: TextStyle(color: context.colors.mutedText)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.accent,
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
                  color: context.colors.text,
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
          color: context.colors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: context.colors.accent, size: 19),
      ),
      title: Text(
        title,
        style: GoogleFonts.outfit(
          color: context.colors.text,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: context.colors.mutedText, fontSize: 11),
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
            if (busy) const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: context.colors.accent,),) else Icon(icon, color: context.colors.accent, size: 14),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.outfit(
                    color: context.colors.accentSecondary,
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
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.border),
            ),
            constraints: const BoxConstraints(maxHeight: 180),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: suggestions.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: context.colors.border),
              itemBuilder: (context, i) {
                final s = suggestions[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_rounded,
                      color: context.colors.accent, size: 18,),
                  title: Text(s['name'] as String? ?? '',
                      style: TextStyle(fontSize: 13, color: context.colors.text),),
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
      style: TextStyle(fontSize: 14, color: context.colors.text),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: context.colors.mutedText.withValues(alpha: 0.7), fontSize: 13),
        filled: true,
        fillColor: context.colors.surface,
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
                      ? [context.colors.accent, context.colors.accentSecondary]
                      : [context.colors.accent.withValues(alpha: 0.16), context.colors.accent.withValues(alpha: 0.08)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: isThisFieldListening
                    ? [
                        BoxShadow(
                          color: context.colors.accent.withValues(alpha: 0.4),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                isThisFieldListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: isThisFieldListening ? Colors.white : context.colors.accentSecondary,
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
// HERO TASK IDEAS -- tappable auto-scrolling slider
// ================================================================
// Concrete examples of what a Hero can be booked for, shown as an
// auto-scrolling strip above the category chips. Each card maps to one
// of kHeroBookingCategories (service_request_labels.dart) so tapping a
// card both shows the customer a real example AND pre-selects the
// right category for them.
const List<Map<String, String>> _kHeroTaskIdeas = [
  {'icon': '\u{1F4E6}', 'label': 'Parcel Pickup & Delivery', 'category': 'pickup_delivery'},
  {'icon': '\u{1F6D2}', 'label': 'Grocery Run & Medicine Pickup', 'category': 'errand'},
  {'icon': '\u{1F4C4}', 'label': 'Bill Payment & Document Drop', 'category': 'paperwork'},
  {'icon': '\u{1F475}', 'label': 'Help for Elders', 'category': 'other'},
  {'icon': '\u{1F382}', 'label': 'Midnight Cake Delivery', 'category': 'custom_order'},
  {'icon': '\u{1F4AA}', 'label': 'Hero as Bouncer', 'category': 'other'},
];

class _HeroTaskIdeasMarquee extends StatefulWidget {
  final void Function(String categoryKey) onSelect;
  const _HeroTaskIdeasMarquee({required this.onSelect});

  @override
  State<_HeroTaskIdeasMarquee> createState() => _HeroTaskIdeasMarqueeState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(ObjectFlagProperty<void Function(String categoryKey)>.has('onSelect', onSelect));
  }
}

class _HeroTaskIdeasMarqueeState extends State<_HeroTaskIdeasMarquee> {
  late final ScrollController _sc;
  Timer? _timer;
  static const double _cardW = 132;

  @override
  void initState() {
    super.initState();
    _sc = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startMarquee());
  }

  // Same continuous-loop technique as dashboard_screen.dart's
  // _NJServiceMarquee: the item list is doubled below so jumping back
  // to 0 at the halfway point is invisible, and 32ms (~30fps) keeps the
  // background CPU cost low for a strip that doesn't need 60fps.
  void _startMarquee() {
    _timer = Timer.periodic(const Duration(milliseconds: 32), (_) {
      if (!mounted || !_sc.hasClients) return;
      final max = _sc.position.maxScrollExtent;
      if (max <= 0) return;
      final next = _sc.offset + 1.2;
      if (next >= max) {
        _sc.jumpTo(0);
      } else {
        _sc.jumpTo(next);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doubled = [..._kHeroTaskIdeas, ..._kHeroTaskIdeas];
    return SizedBox(
      height: 92,
      child: ListView.builder(
        controller: _sc,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: doubled.length,
        itemBuilder: (context, i) {
          final idea = doubled[i % _kHeroTaskIdeas.length];
          return GestureDetector(
            onTap: () => widget.onSelect(idea['category']!),
            child: Container(
              width: _cardW,
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(
                color: context.colors.subtleFill,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.colors.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(idea['icon']!, style: const TextStyle(fontSize: 26)),
                  const SizedBox(height: 6),
                  Text(
                    idea['label']!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                        color: context.colors.text, fontSize: 11, fontWeight: FontWeight.w700,),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
