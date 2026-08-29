// ================================================================
// skilled_services_screen.dart — customer-facing trade booking
// (electrician, plumber, laptop & PC, TV, fridge & AC)
// ================================================================
// NEW (Aug 29 2026 — Nizam: "register pannuna heros ku namma customer
// app la irunthu search pannumbothu nearby 5 kms la iruka heros
// availability kaatanum, apo request kudukumbothu customer request
// entha hero accept pandraro avarukku followup aganum").
//
// NO NEW PIPELINE. Every booking made here is an ordinary
// `electronics_service` request carrying `details.category` set to the
// trade — the same move mobile_service_sheet.dart already makes with
// category 'mobile'. Because of that, the parts Nizam asked for last
// are the parts that needed no code at all:
//   * "followup aganum" — the accepted hero is followed in
//     ServiceRequestTrackingScreen, which already handles this
//     requestType; the atomic accept in
//     ServiceRequestService.acceptServiceRequest already guarantees
//     exactly one hero wins.
//   * Admin visibility, my_orders history, status advance, the hero's
//     own ping card — all already wired for electronics_service.
//
// What IS new here is the availability count. See [_NearbyCounts].
// ================================================================

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart' as rtdb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/hero_skill_catalog.dart';
import '../services/auth_prompt_service.dart';
import '../services/location_service.dart';
import '../services/service_request_service.dart';
import '../widgets/location_capture_field.dart';
import 'service_request_tracking_screen.dart';

const Color _bg = Color(0xFF0E0B12);
const Color _card = Color(0xFF1A1420);
const Color _border = Color(0xFF2C2233);
const Color _text = Color(0xFFF4EEF7);
const Color _muted = Color(0xFF9C90A8);
const Color _pink = Color(0xFFFF4FA3);

/// How many heroes of each trade are online within
/// [kSkillDispatchRadiusKm], keyed by skill key.
///
/// Computed CLIENT-SIDE from a single read of the `online_heroes`
/// presence node — the same node dispatch itself iterates. That is
/// deliberate: any other source (a counter doc, a query on `heroes`)
/// would be a second opinion about who is available, and the moment it
/// disagreed with dispatch the customer would be told "3 electricians
/// nearby" and then watch their request find nobody. One read, one
/// truth, and it costs nothing on the Firebase Spark plan.
typedef _NearbyCounts = Map<String, int>;

class SkilledServicesScreen extends StatefulWidget {
  const SkilledServicesScreen({super.key});

  @override
  State<SkilledServicesScreen> createState() => _SkilledServicesScreenState();
}

class _SkilledServicesScreenState extends State<SkilledServicesScreen> {
  _NearbyCounts _counts = const <String, int>{};
  bool _loadingCounts = true;

  /// The customer's position, resolved once and then reused for both the
  /// availability count and the dispatch radius on any booking made from
  /// this screen — so what the customer was shown and who actually gets
  /// pinged are measured from the same point.
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    unawaited(_loadNearby());
  }

  Future<void> _loadNearby() async {
    try {
      final position = await LocationService().getCurrentLocation();
      if (!mounted) return;
      _lat = position?.latitude;
      _lng = position?.longitude;

      final snap =
          await rtdb.FirebaseDatabase.instance.ref('online_heroes').get();
      final counts = <String, int>{};
      if (snap.exists && snap.value is Map) {
        final heroes = Map<dynamic, dynamic>.from(snap.value! as Map);
        heroes.forEach((_, raw) {
          if (raw is! Map) return;
          final heroData = Map<String, dynamic>.from(raw);

          // Same presence semantics as dispatch: only an EXPLICIT false
          // means unavailable. A node missing the key is a hero the
          // broadcaster would still ping, so counting them differently
          // here would misreport availability.
          if ((heroData['isAvailable'] as bool?) == false) return;

          final skills = heroSkillsOf(heroData);
          if (skills.isEmpty) return;

          if (_lat != null && _lng != null) {
            final heroLat = (heroData['lat'] as num?)?.toDouble() ??
                (heroData['latitude'] as num?)?.toDouble();
            final heroLng = (heroData['lng'] as num?)?.toDouble() ??
                (heroData['longitude'] as num?)?.toDouble();
            if (heroLat == null || heroLng == null) return;
            final km = Geolocator.distanceBetween(
                  _lat!, _lng!, heroLat, heroLng,
                ) /
                1000.0;
            if (km > kSkillDispatchRadiusKm) return;
          }

          for (final skill in skills) {
            counts[skill] = (counts[skill] ?? 0) + 1;
          }
        });
      }
      if (!mounted) return;
      setState(() {
        _counts = counts;
        _loadingCounts = false;
      });
    } catch (e) {
      // A failed count is cosmetic — the trades stay bookable, and the
      // card simply shows no availability line. Blocking the screen on
      // it would turn a location-permission refusal into "you cannot
      // book an electrician."
      debugPrint('[SkilledServices] nearby count failed: $e');
      if (mounted) setState(() => _loadingCounts = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: Text(
          'Home Services',
          style: GoogleFonts.outfit(
            color: _text,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: _pink,
        onRefresh: _loadNearby,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Text(
              'Verified local professionals',
              style: GoogleFonts.outfit(
                color: _text,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Every Hero here is admin-approved and KYC verified. '
              'We ping the ones within ${kSkillDispatchRadiusKm.toStringAsFixed(0)} km '
              'of you — the first to accept is yours, and you can follow '
              'them until the job is done.',
              style: GoogleFonts.outfit(
                color: _muted,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            ...kHeroSkills.map(
              (skill) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SkillCard(
                  skill: skill,
                  nearbyCount: _counts[skill.key] ?? 0,
                  loading: _loadingCounts,
                  onTap: () => showSkillBookingSheet(
                    context,
                    skill: skill,
                    customerLat: _lat,
                    customerLng: _lng,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkillCard extends StatelessWidget {
  const _SkillCard({
    required this.skill,
    required this.nearbyCount,
    required this.loading,
    required this.onTap,
  });

  final HeroSkill skill;
  final int nearbyCount;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final available = nearbyCount > 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: skill.color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(skill.icon, color: skill.color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    skill.title,
                    style: GoogleFonts.outfit(
                      color: _text,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    skill.tamilTitle,
                    style: GoogleFonts.outfit(
                      color: skill.color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    skill.subtitle,
                    style: GoogleFonts.outfit(color: _muted, fontSize: 11.5),
                  ),
                  const SizedBox(height: 7),
                  // AVAILABILITY. Three distinct states, and the third
                  // one matters most: "none nearby right now" is said
                  // plainly rather than hidden, because a customer who
                  // books into an empty radius and waits out a 90-second
                  // ping expiry learns the same fact far more slowly and
                  // much more annoyed. The card stays TAPPABLE anyway —
                  // a hero may come online in the next minute, and this
                  // is a count, not a gate.
                  if (loading)
                    Text(
                      'Checking who is nearby…',
                      style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                    )
                  else
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: available
                                ? const Color(0xFF27AE60)
                                : _muted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          available
                              ? '$nearbyCount available within '
                                  '${kSkillDispatchRadiusKm.toStringAsFixed(0)} km'
                              : 'None nearby right now — you can still book',
                          style: GoogleFonts.outfit(
                            color: available
                                ? const Color(0xFF27AE60)
                                : _muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _muted),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// BOOKING SHEET
// ================================================================

Future<void> showSkillBookingSheet(
  BuildContext context, {
  required HeroSkill skill,
  double? customerLat,
  double? customerLng,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _SkillBookingSheet(
      skill: skill,
      initialLat: customerLat,
      initialLng: customerLng,
    ),
  );
}

class _SkillBookingSheet extends StatefulWidget {
  const _SkillBookingSheet({
    required this.skill,
    this.initialLat,
    this.initialLng,
  });

  final HeroSkill skill;
  final double? initialLat;
  final double? initialLng;

  @override
  State<_SkillBookingSheet> createState() => _SkillBookingSheetState();
}

class _SkillBookingSheetState extends State<_SkillBookingSheet> {
  final _issueCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  double? _lat;
  double? _lng;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Seeded from the screen's own fix so a customer who never touches
    // the location field still dispatches against a real position —
    // without it, every booking made straight from the grid would fall
    // back to the city-wide fan-out the radius is meant to replace.
    _lat = widget.initialLat;
    _lng = widget.initialLng;
  }

  @override
  void dispose() {
    _issueCtrl.dispose();
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: _pink),
    );
  }

  Future<void> _submit() async {
    if (_issueCtrl.text.trim().isEmpty) {
      _toast('Please describe the problem');
      return;
    }
    if (_contactCtrl.text.trim().length < 10) {
      _toast('Please enter a valid contact number');
      return;
    }
    // Nizam's ask was specifically "nearby 5 km la iruka heros
    // kaatanum" — that promise is enforced entirely by [_lat]/[_lng]
    // reaching createServiceRequest. Unlike mobile_service_sheet.dart
    // (electronics_service with no radius, where a missing location is
    // harmless because the fan-out is city-wide anyway), a skill
    // booking with no location silently WIDENS to the whole city the
    // moment GPS is unavailable — see _broadcastToEligibleHeroes's
    // applyRadius guard. Blocking here, rather than falling back
    // quietly, is what keeps that promise instead of breaking it the
    // first time a customer's GPS permission is off.
    if (_lat == null || _lng == null) {
      _toast('Please set your location so nearby ${widget.skill.title}s can be found');
      return;
    }
    if (!await requireRealAuth(
      context,
      reason: 'Sign in to book a ${widget.skill.title}',
    )) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;

    setState(() => _sending = true);
    try {
      final requestId = await ServiceRequestService().createServiceRequest(
        // Same requestType the NJ Tech and Mobile Hub flows use — this
        // is what buys the whole lifecycle for free. See the file header.
        requestType: 'electronics_service',
        customerId: user.uid,
        customerName: _nameCtrl.text.trim().isNotEmpty
            ? _nameCtrl.text.trim()
            : (user.displayName ?? 'Customer'),
        customerPhone: _contactCtrl.text.trim(),
        details: <String, dynamic>{
          kSkillRequestCategoryKey: widget.skill.key,
          'categoryLabel': widget.skill.title,
          'intent': 'skill_service',
          'issue': _issueCtrl.text.trim(),
          if (_addressCtrl.text.trim().isNotEmpty)
            'address': _addressCtrl.text.trim(),
          if (_lat != null) 'locationLat': _lat,
          if (_lng != null) 'locationLng': _lng,
        },
        // The only genuinely new arguments in this flow. Both null-safe
        // on the service side: without them the broadcast behaves
        // exactly as it does for every pre-existing caller.
        requiredSkill: widget.skill.key,
        customerLat: _lat,
        customerLng: _lng,
      );

      if (!mounted) return;
      Navigator.pop(context);
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ServiceRequestTrackingScreen(
            requestId: requestId,
            requestType: 'electronics_service',
          ),
        ),
      );
    } catch (e) {
      if (mounted) _toast('Could not book: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    TextInputType? keyboard,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(
              color: _text,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: keyboard,
            maxLines: maxLines,
            style: GoogleFonts.outfit(color: _text, fontSize: 13.5),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.outfit(color: _muted, fontSize: 12.5),
              filled: true,
              fillColor: _card,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: widget.skill.color),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skill = widget.skill;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return DecoratedBox(
            decoration: const BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: skill.color.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(skill.icon,
                                color: skill.color, size: 22,),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Book ${skill.title}',
                                  style: GoogleFonts.outfit(
                                    color: _text,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  skill.tamilTitle,
                                  style: GoogleFonts.outfit(
                                    color: skill.color,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _field(
                        _issueCtrl,
                        'What is the problem? *',
                        'e.g. Bedroom fan not working, makes noise',
                        maxLines: 3,
                      ),
                      _field(_nameCtrl, 'Your name', 'Optional'),
                      _field(
                        _contactCtrl,
                        'Contact number *',
                        '9XXXXXXXXX',
                        keyboard: TextInputType.phone,
                      ),
                      Text(
                        'Where is the work?',
                        style: GoogleFonts.outfit(
                          color: _text,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      LocationCaptureField(
                        addressController: _addressCtrl,
                        pickerTitle: 'Select service location',
                        accentColor: skill.color,
                        onLocationPicked: (lat, lng) {
                          // Overrides the seeded position — the address
                          // the customer picked is where the work is,
                          // which is not always where their phone is.
                          _lat = lat;
                          _lng = lng;
                        },
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Nearby ${skill.title}s within '
                        '${kSkillDispatchRadiusKm.toStringAsFixed(0)} km get '
                        'your request. The first one to accept is assigned to '
                        'you, and you can track them from there.',
                        style: GoogleFonts.outfit(
                          color: _muted,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: skill.color,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _sending ? null : _submit,
                          child: _sending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Send request',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
