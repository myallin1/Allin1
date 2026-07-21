// ================================================================
// DEPRECATED — DO NOT USE
// This file is deprecated. Use lib/screens/bike_taxi/bike_booking_screen.dart instead.
// Kept for reference only. Do not modify.
//
// Original: BikeTaxiScreen v3.0 — Allin1 Super App
// FIXED for flutter_map ^8.2.2 + latlong2 ^0.9.1
// CTO Verified: All API changes applied ✅
// CTO Verified: All API changes applied
//
// Key fixes vs v2:
//   [1] isDotted → pattern: StrokePattern.dotted()
//   [2] AnimatedBuilder inside MarkerLayer → StatefulWidget marker
//   [3] Unnecessary type checks removed
//   [4] showModalBottomSheet explicit type arg added
//   [11] withValues addressed
//   [6] CameraFit.bounds padding syntax corrected
// ================================================================

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
// geocoding + geolocator were imported for the old _getCurrentLocation();
// LocationService/MapService handle both jobs now.
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/location_service.dart';
import '../services/map_service.dart';
import 'location_picker_screen.dart';
import 'payment_screen.dart';

// ── Theme (matches main.dart exactly) ───────────────────────────
const Color kBg = Color(0xFF0A0A1A);
const Color kSurface = Color(0xFF0D0D18);
const Color kCard = Color(0xFF141420);
const Color kCard2 = Color(0xFF1A1A28);
const Color kPurple = Color(0xFF7B6FE0);
const Color kPurple2 = Color(0xFF9B8FF0);
const Color kOrange = Color(0xFFE07C6F);
const Color kGreen = Color(0xFF3DBA6F);
const Color kGold = Color(0xFFF5C542);
const Color kText = Color(0xFFEEEEF5);
const Color kMuted = Color(0xFF7777A0);
const Color kBorder = Color(0x267B6FE0);

// ── Erode real coordinates ───────────────────────────────────────
const LatLng kErodeCenter = LatLng(11.3410, 77.7172);
const LatLng kPickupDefault = LatLng(11.3410, 77.7172);
const LatLng kDropDefault = LatLng(11.3520, 77.7280);

// ── Mock nearby rider positions ──────────────────────────────────
const List<LatLng> kNearbyRiders = [
  LatLng(11.3390, 77.7140),
  LatLng(11.3460, 77.7220),
  LatLng(11.3325, 77.7255),
];

// ── Ride type data model ─────────────────────────────────────────
class _RideType {
  final IconData icon;
  final String label;
  final String sublabel;
  final String eta;
  final int ratePerKm;
  final Color color;
  const _RideType({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.eta,
    required this.ratePerKm,
    required this.color,
  });
}

const List<_RideType> _rides = [
  _RideType(
    icon: Icons.directions_bike,
    label: 'Bike',
    sublabel: 'Fast · Solo',
    eta: '3 min',
    ratePerKm: 12,
    color: kGold,
  ),
  _RideType(
    icon: Icons.local_taxi,
    label: 'Auto',
    sublabel: 'Comfort · 3',
    eta: '5 min',
    ratePerKm: 14,
    color: kGreen,
  ),
  _RideType(
    icon: Icons.local_shipping,
    label: 'Parcel',
    sublabel: 'Quick Delivery',
    eta: '8 min',
    ratePerKm: 20,
    color: kPurple2,
  ),
];

// ── Recent places ────────────────────────────────────────────────
final List<_Place> _recentPlaces = [
  const _Place(
    Icons.home,
    'Home',
    '15, Gandhi Nagar, Erode',
    LatLng(11.3350, 77.7100),
  ),
  const _Place(
    Icons.work,
    'NJ TECH',
    'Periyar Nagar, Erode 638001',
    LatLng(11.3430, 77.7200),
  ),
  const _Place(
    Icons.store,
    'Erode Market',
    'Big Bazar Street, Erode',
    LatLng(11.3480, 77.7260),
  ),
  const _Place(
    Icons.local_hospital,
    'GKNM Hospital',
    'Nethaji Rd, Erode 638001',
    LatLng(11.3390, 77.7320),
  ),
];

class _Place {
  final IconData icon;
  final String label, address;
  final LatLng latlng;
  const _Place(this.icon, this.label, this.address, this.latlng);
}

// ================================================================
// BikeTaxiScreen
// ================================================================
class BikeTaxiScreen extends StatefulWidget {
  const BikeTaxiScreen({super.key});
  @override
  State<BikeTaxiScreen> createState() => _BikeTaxiScreenState();
}

class _BikeTaxiScreenState extends State<BikeTaxiScreen>
    with TickerProviderStateMixin {
  final MapController _mapCtrl = MapController();
  bool _mapReady = false;
  LatLng? _pendingMapCenter;
  double? _pendingMapZoom;

  int _rideIdx = 0;
  bool _showFare = false;
  bool _mapBig = false;
  bool _pickupSet = false;
  bool _dropSet = false;
  LatLng _pickupPos = kPickupDefault;
  LatLng _dropPos = kDropDefault;

  final TextEditingController _pickupCtrl = TextEditingController();
  final TextEditingController _dropCtrl = TextEditingController();
  final FocusNode _pickupFocus = FocusNode();
  final FocusNode _dropFocus = FocusNode();

  // ── Location search ──────────────────────────────────────────────
  // Same pipeline as hero_booking_screen: MapService.search() is
  // Ola-first (its autocomplete actually knows Erode shops and
  // streets), falling back to Nominatim only when Ola returns nothing.
  //
  // This screen previously had NO search at all. The only "suggestions"
  // were four hardcoded _recentPlaces entries with invented addresses
  // and coordinates, and anything the customer typed by hand never
  // produced a coordinate — see the _onChanged fix below for why that
  // mattered a great deal.
  final _mapService = MapService();
  Timer? _pickupDebounce;
  Timer? _dropDebounce;
  List<Map<String, dynamic>> _pickupSuggestions = [];
  List<Map<String, dynamic>> _dropSuggestions = [];
  bool _pickupFetching = false;
  bool _dropFetching = false;

  // Pulse anim for LIVE badge & promo
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // Slide anim for fare card
  late AnimationController _slideCtrl;
  late Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();

    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnim =
        CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic);

    _pickupCtrl.addListener(_onChanged);
    _dropCtrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _slideCtrl.dispose();
    _pickupCtrl.dispose();
    _dropCtrl.dispose();
    _pickupFocus.dispose();
    _dropFocus.dispose();
    _pickupDebounce?.cancel();
    _dropDebounce?.cancel();
    super.dispose();
  }

  // Coordinates behind the two fields. Null means "this field has text
  // but we do not know where it actually is".
  //
  // This distinction was the screen's most serious bug. _pickupSet and
  // _dropSet used to be set purely from "is the text box non-empty",
  // while _pickupPos/_dropPos only ever changed via the four hardcoded
  // _recentPlaces or the current-location button. So a customer who
  // TYPED an address got _pickupSet = true with _pickupPos still
  // sitting at kPickupDefault — and the fare, the distance, the map
  // route and the booking itself were all computed from a default
  // coordinate that had nothing to do with what they typed.
  //
  // Now a field only counts as "set" once we have a real coordinate for
  // it, which happens when they pick a suggestion, use their current
  // location, or drop a pin on the map.
  LatLng? _pickupResolved;
  LatLng? _dropResolved;

  void _onChanged() {
    final p = _pickupResolved != null && _pickupCtrl.text.trim().isNotEmpty;
    final d = _dropResolved != null && _dropCtrl.text.trim().isNotEmpty;
    if (p == _pickupSet && d == _dropSet) {
      return;
    }
    setState(() {
      _pickupSet = p;
      _dropSet = d;
      if (p) _pickupPos = _pickupResolved!;
      if (d) _dropPos = _dropResolved!;
    });
    if (p && d) {
      _slideCtrl.forward();
      setState(() => _showFare = true);
      Future<void>.delayed(const Duration(milliseconds: 300), _fitMap);
    } else {
      _slideCtrl.reverse();
      setState(() => _showFare = false);
    }
  }

  void _fitMap() {
    if (!_pickupSet || !_dropSet) {
      return;
    }
    if (!_mapReady) {
      _pendingMapCenter = LatLng(
        (_pickupPos.latitude + _dropPos.latitude) / 2,
        (_pickupPos.longitude + _dropPos.longitude) / 2,
      );
      _pendingMapZoom = 13.5;
      return;
    }
    final bounds = LatLngBounds.fromPoints([_pickupPos, _dropPos]);
    try {
      _mapCtrl.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(60),
        ),
      );
      _pendingMapCenter = null;
      _pendingMapZoom = null;
    } catch (e) {
      debugPrint('[BikeTaxiScreen] Map fit failed: $e');
    }
  }

  void _moveMap(LatLng center, double zoom) {
    _pendingMapCenter = center;
    _pendingMapZoom = zoom;
    if (!_mapReady) {
      debugPrint('[BikeTaxiScreen] Map move queued until ready');
      return;
    }
    try {
      _mapCtrl.move(center, zoom);
      _pendingMapCenter = null;
      _pendingMapZoom = null;
    } catch (e) {
      debugPrint('[BikeTaxiScreen] Map move failed: $e');
    }
  }

  void _handleMapReady() {
    _mapReady = true;
    final center = _pendingMapCenter;
    if (_pickupSet && _dropSet) {
      _fitMap();
    } else if (center != null) {
      _moveMap(center, _pendingMapZoom ?? 13.5);
    }
  }

  // Build bezier-curve route (3-point quadratic)
  List<LatLng> _buildRoute() {
    if (!_pickupSet || !_dropSet) {
      return [];
    }
    final mid = LatLng(
      (_pickupPos.latitude + _dropPos.latitude) / 2 + 0.004,
      (_pickupPos.longitude + _dropPos.longitude) / 2 + 0.003,
    );
    return List.generate(21, (i) {
      final t = i / 20.0;
      final t1 = 1 - t;
      return LatLng(
        t1 * t1 * _pickupPos.latitude +
            2 * t1 * t * mid.latitude +
            t * t * _dropPos.latitude,
        t1 * t1 * _pickupPos.longitude +
            2 * t1 * t * mid.longitude +
            t * t * _dropPos.longitude,
      );
    });
  }

  double _distKm() {
    const r = 6371.0;
    final dLat = (_dropPos.latitude - _pickupPos.latitude) * (pi / 180);
    final dLon = (_dropPos.longitude - _pickupPos.longitude) * (pi / 180);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_pickupPos.latitude * (pi / 180)) *
            cos(_dropPos.latitude * (pi / 180)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  void _fillPlace(_Place p) {
    if (!_pickupSet) {
      _pickupCtrl.text = p.address;
      _pickupResolved = p.latlng;
      _pickupSuggestions = [];
      _onChanged();
      FocusScope.of(context).requestFocus(_dropFocus);
    } else if (!_dropSet) {
      _dropCtrl.text = p.address;
      _dropResolved = p.latlng;
      _dropSuggestions = [];
      _onChanged();
      _dropFocus.unfocus();
    }
  }

  // ── Live search ──────────────────────────────────────────────────
  // Typing invalidates whatever coordinate was attached to the field:
  // the text no longer describes that point. The customer has to pick
  // a suggestion (or use the map / their location) to make it real
  // again, which is exactly what stops a hand-typed address from being
  // booked against a stale coordinate.
  void _onPickupTyped(String query) {
    _pickupResolved = null;
    _pickupDebounce?.cancel();
    _onChanged();
    final q = query.trim();
    if (q.length < 3) {
      if (mounted) setState(() => _pickupSuggestions = []);
      return;
    }
    setState(() => _pickupFetching = true);
    _pickupDebounce = Timer(const Duration(milliseconds: 450), () async {
      final results = await _mapService.search(q);
      if (!mounted || _pickupCtrl.text.trim() != q) return;
      setState(() {
        _pickupSuggestions = results;
        _pickupFetching = false;
      });
    });
  }

  void _onDropTyped(String query) {
    _dropResolved = null;
    _dropDebounce?.cancel();
    _onChanged();
    final q = query.trim();
    if (q.length < 3) {
      if (mounted) setState(() => _dropSuggestions = []);
      return;
    }
    setState(() => _dropFetching = true);
    _dropDebounce = Timer(const Duration(milliseconds: 450), () async {
      final results = await _mapService.search(q);
      if (!mounted || _dropCtrl.text.trim() != q) return;
      setState(() {
        _dropSuggestions = results;
        _dropFetching = false;
      });
    });
  }

  void _applySuggestion(Map<String, dynamic> s, {required bool isPickup}) {
    final lat = (s['lat'] as num?)?.toDouble();
    final lng = (s['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    final label = (s['name'] as String?)?.trim().isNotEmpty ?? false
        ? (s['name'] as String).trim()
        : (s['full'] as String? ?? '').trim();

    setState(() {
      if (isPickup) {
        _pickupCtrl.text = label;
        _pickupResolved = LatLng(lat, lng);
        _pickupSuggestions = [];
      } else {
        _dropCtrl.text = label;
        _dropResolved = LatLng(lat, lng);
        _dropSuggestions = [];
      }
    });
    _onChanged();
    if (isPickup) {
      FocusScope.of(context).requestFocus(_dropFocus);
    } else {
      _dropFocus.unfocus();
    }
  }

  /// Writes a resolved point into a field, looking up a readable
  /// address for it first. Shared by the current-location and
  /// map-picker paths.
  Future<void> _applyPoint(
    LatLng point, {
    required bool isPickup,
    String? fallbackLabel,
  }) async {
    String label = fallbackLabel?.trim() ?? '';
    try {
      final geo = await _mapService.reverseGeocode(point);
      final resolved =
          (geo?['full'] as String?) ?? (geo?['name'] as String?) ?? '';
      if (resolved.trim().isNotEmpty) label = resolved.trim();
    } catch (e) {
      debugPrint('[BikeTaxi] reverse geocode failed: $e');
    }
    if (!mounted) return;

    setState(() {
      final text = label.isNotEmpty
          ? label
          : '${point.latitude.toStringAsFixed(5)}, '
              '${point.longitude.toStringAsFixed(5)}';
      if (isPickup) {
        _pickupCtrl.text = text;
        _pickupResolved = point;
        _pickupSuggestions = [];
      } else {
        _dropCtrl.text = text;
        _dropResolved = point;
        _dropSuggestions = [];
      }
    });
    _onChanged();
    _moveMap(point, 15);
  }

  Future<void> _useCurrentLocationFor({required bool isPickup}) async {
    setState(() {
      if (isPickup) {
        _pickupFetching = true;
      } else {
        _dropFetching = true;
      }
    });
    try {
      // LocationService is the app's one tuned current-location fetch
      // (high accuracy, 15s limit, its own permission handling). This
      // screen used to call Geolocator.getCurrentPosition() bare, with
      // no accuracy settings, then geocode via the `geocoding` package
      // — a different stack from the rest of the app that happily
      // returns a low-effort cached fix. Same mistake, and same fix, as
      // hero_booking_screen.
      final position = await LocationService().getCurrentLocation();
      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not get your location. Check that location permission is allowed.',
              ),
            ),
          );
        }
        return;
      }
      await _applyPoint(
        LatLng(position.latitude, position.longitude),
        isPickup: isPickup,
      );
    } catch (e) {
      debugPrint('[BikeTaxi] current location failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          if (isPickup) {
            _pickupFetching = false;
          } else {
            _dropFetching = false;
          }
        });
      }
    }
  }

  // ── Suggestion dropdown ──────────────────────────────────────────
  Widget _buildSuggestions(
    List<Map<String, dynamic>> suggestions, {
    required bool isPickup,
  }) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 14, 0),
      constraints: const BoxConstraints(maxHeight: 190),
      decoration: BoxDecoration(
        color: kCard2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: kBorder),
        itemBuilder: (context, i) {
          final s = suggestions[i];
          final name = (s['name'] as String?) ?? '';
          final full = (s['full'] as String?) ?? '';
          return ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: const Icon(Icons.place_rounded, color: kPurple2, size: 18),
            title: Text(
              name.isEmpty ? full : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: kText),
            ),
            subtitle: (full.isNotEmpty && full != name)
                ? Text(
                    full,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: kMuted),
                  )
                : null,
            onTap: () => _applySuggestion(s, isPickup: isPickup),
          );
        },
      ),
    );
  }

  // ── Location shortcuts under each field ──────────────────────────
  Widget _buildLocationActions({required bool isPickup, required bool busy}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 2, 14, 0),
      child: Wrap(
        spacing: 16,
        runSpacing: 2,
        children: [
          _locationAction(
            icon: Icons.my_location_rounded,
            label: 'Use current location',
            busy: busy,
            onTap: () =>
                unawaited(_useCurrentLocationFor(isPickup: isPickup)),
          ),
          _locationAction(
            icon: Icons.map_rounded,
            label: 'Select on map',
            onTap: () => unawaited(_selectOnMapFor(isPickup: isPickup)),
          ),
        ],
      ),
    );
  }

  Widget _locationAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
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
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kPurple2,
                    ),
                  )
                : Icon(icon, color: kPurple2, size: 13),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: kPurple2,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectOnMapFor({required bool isPickup}) async {
    final existing = isPickup ? _pickupResolved : _dropResolved;
    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute<PickedLocation>(
        builder: (_) => LocationPickerScreen(
          title: isPickup ? 'Pickup location' : 'Drop location',
          initialCenter: existing,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _applyPoint(
      LatLng(picked.lat, picked.lng),
      isPickup: isPickup,
      fallbackLabel: picked.name,
    );
  }

  // _getCurrentLocation() used to live here: a bare
  // Geolocator.getCurrentPosition() with no accuracy settings, plus
  // address lookup through the `geocoding` package — a completely
  // separate stack from the LocationService + MapService the rest of
  // the app uses, and one that happily returns a low-effort cached fix.
  // Replaced by _useCurrentLocationFor(), which both fields now share.

  void _swap() {
    final tTxt = _pickupCtrl.text;
    final tPos = _pickupPos;
    // The resolved coordinates have to travel with the text. Swapping
    // only the display strings and _pickupPos/_dropPos left
    // _pickupResolved/_dropResolved pointing at the wrong field, so the
    // next _onChanged() would put the old coordinates straight back.
    final tResolved = _pickupResolved;
    setState(() {
      _pickupCtrl.text = _dropCtrl.text;
      _dropCtrl.text = tTxt;
      _pickupPos = _dropPos;
      _dropPos = tPos;
      _pickupResolved = _dropResolved;
      _dropResolved = tResolved;
      _pickupSuggestions = [];
      _dropSuggestions = [];
    });
    _onChanged();
  }

  void _book() {
    if (!_pickupSet || !_dropSet) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter pickup & drop locations 📍',
            style: GoogleFonts.outfit(color: kText),
          ),
          backgroundColor: kCard2,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }
    // FIX [4]: explicit type arg for showModalBottomSheet
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kCard2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _BookSheet(
        ride: _rides[_rideIdx],
        pickup: _pickupCtrl.text,
        drop: _dropCtrl.text,
        distKm: _pickupSet && _dropSet ? _distKm() : 4.5,
      ),
    );
  }

  // ================================================================
  // BUILD
  // ================================================================
  @override
  Widget build(BuildContext context) {
    final route = _buildRoute();
    final mapH = _mapBig
        ? MediaQuery.of(context).size.height * 0.55
        : MediaQuery.of(context).size.height * 0.38;

    return Scaffold(
      body: Stack(
        children: [
          // ── Layer 1: Real OSM Map ─────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            height: mapH,
            child: _buildMap(route),
          ),

          // ── Layer 2: Gradient overlay ─────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.65,
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0xEB0A0A1A),
                      Color(0xFF0A0A1A),
                    ],
                    stops: [0.0, 0.28, 0.55],
                  ),
                ),
              ),
            ),
          ),

          // ── Layer 3: Safe-area scrollable UI ──────────────────
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: _mapBig ? 250 : 165),
                        _buildLocCard(),
                        const SizedBox(height: 14),
                        _buildRideSelector(),
                        if (_showFare) ...[
                          const SizedBox(height: 14),
                          _buildFareCard(),
                        ],
                        const SizedBox(height: 22),
                        _buildRecent(),
                        const SizedBox(height: 20),
                        _buildPromo(),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Layer 4: Map controls ─────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 66, right: 14),
              child: Align(
                alignment: Alignment.topRight,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _mapBtn(
                      icon: _mapBig ? Icons.fullscreen_exit : Icons.fullscreen,
                      color: kPurple2,
                      onTap: () => setState(() => _mapBig = !_mapBig),
                    ),
                    const SizedBox(height: 8),
                    _mapBtn(
                      icon: Icons.my_location,
                      color: kGreen,
                      onTap: () => _moveMap(kErodeCenter, 14),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Layer 5: Book button ──────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBookBtn(),
          ),
        ],
      ),
    );
  }

  // ── MAP ───────────────────────────────────────────────────────
  Widget _buildMap(List<LatLng> route) {
    return FlutterMap(
      mapController: _mapCtrl,
      options: MapOptions(
        initialCenter: kErodeCenter,
        initialZoom: 13.5,
        minZoom: 10,
        maxZoom: 18,
        onMapReady: _handleMapReady,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
        ),
      ),
      children: [
        // CartoDB Dark Matter — Free, no API key
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.njtech.erode_super_app',
          maxZoom: 20,
        ),

        // Route polyline
        if (route.isNotEmpty)
          PolylineLayer(
            polylines: [
              // Main route
              Polyline(
                points: route,
                strokeWidth: 5,
                color: kPurple,
                borderColor: const Color(0x509B8FF0),
                borderStrokeWidth: 3,
              ),
              // FIX [1]: isDotted → pattern: StrokePattern.dotted()
              Polyline(
                points: route,
                strokeWidth: 2.5,
                color: const Color(0x40FFFFFF),
                pattern: const StrokePattern.dotted(),
              ),
            ],
          ),

        // Markers
        MarkerLayer(
          markers: [
            // Pickup
            if (_pickupSet)
              Marker(
                point: _pickupPos,
                width: 44,
                height: 54,
                child: const _PinMarker(color: kGreen, icon: Icons.location_on),
              ),

            // Drop
            if (_dropSet)
              Marker(
                point: _dropPos,
                width: 44,
                height: 54,
                child: const _PinMarker(color: kOrange, icon: Icons.flag),
              ),

            // FIX [2]: AnimatedBuilder removed from marker body.
            // Animated rider replaced with StatefulWidget marker.
            if (route.isNotEmpty)
              Marker(
                point: route[route.length ~/ 2],
                width: 46,
                height: 46,
                child: _AnimatedRiderMarker(color: _rides[_rideIdx].color),
              ),

            // Nearby riders (static)
            ...kNearbyRiders.map(
              (pt) => Marker(
                point: pt,
                width: 22,
                height: 22,
                child: _NearbyDot(color: _rides[_rideIdx].color),
              ),
            ),
          ],
        ),

        // OSM + CartoDB attribution (required by ToS)
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution(
              '© OpenStreetMap',
              onTap: () => launchUrl(
                Uri.parse('https://openstreetmap.org/copyright'),
              ),
            ),
            TextSourceAttribution(
              '© CartoDB',
              onTap: () =>
                  launchUrl(Uri.parse('https://carto.com/attributions')),
            ),
          ],
        ),
      ],
    );
  }

  // ── APP BAR ───────────────────────────────────────────────────
  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xF20D0D18),
        border: Border(bottom: BorderSide(color: kBorder)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: kBorder),
              ),
              child:
                  const Icon(Icons.arrow_back_ios_new, size: 14, color: kMuted),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient:
                  const LinearGradient(colors: [kGold, Color(0xFFD4961A)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: Text('🏍️', style: TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bike Taxi',
                  style: GoogleFonts.notoSansTamil(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: kText,
                  ),
                ),
                const Text(
                  'Erode · Fast & Affordable',
                  style: TextStyle(fontSize: 10, color: kMuted),
                ),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Transform.scale(
              scale: _pulseAnim.value,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0x1F3DBA6F),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x663DBA6F)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: kGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'LIVE',
                      style: TextStyle(
                        fontSize: 9,
                        color: kGreen,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── LOCATION CARD ─────────────────────────────────────────────
  Widget _buildLocCard() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF7141420),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x6608080F),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Pickup field
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
            child: Row(
              children: [
                Column(
                  children: [
                    Container(
                      width: 13,
                      height: 13,
                      decoration: const BoxDecoration(
                        color: kGreen,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x993DBA6F),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1.5,
                      height: 26,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: kBorder,
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _pickupCtrl,
                    focusNode: _pickupFocus,
                    onChanged: _onPickupTyped,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: kText,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Pickup — Where are you?',
                      hintStyle: TextStyle(fontSize: 13, color: kMuted),
                      border: InputBorder.none,
                      // Was isDense + zero padding, which squashed the
                      // text against the row and made a long address
                      // unreadable. A little breathing room here is the
                      // difference between "cramped" and "a field".
                      isDense: false,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) =>
                        FocusScope.of(context).requestFocus(_dropFocus),
                  ),
                ),
                if (_pickupCtrl.text.trim().isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _pickupCtrl.clear();
                      _pickupResolved = null;
                      setState(() => _pickupSuggestions = []);
                      _onChanged();
                    },
                    child: const Icon(Icons.close, size: 16, color: kMuted),
                  ),
              ],
            ),
          ),

          _buildSuggestions(_pickupSuggestions, isPickup: true),
          _buildLocationActions(isPickup: true, busy: _pickupFetching),

          // Swap divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const SizedBox(width: 28),
                const Expanded(child: Divider(color: kBorder)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _swap,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: kCard2,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: kBorder),
                    ),
                    child:
                        const Icon(Icons.swap_vert, size: 16, color: kPurple2),
                  ),
                ),
              ],
            ),
          ),

          // Drop field
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 14, 14),
            child: Row(
              children: [
                Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: kOrange,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x99E07C6F),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _dropCtrl,
                    focusNode: _dropFocus,
                    onChanged: _onDropTyped,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: kText,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Drop — Where to go?',
                      hintStyle: TextStyle(fontSize: 13, color: kMuted),
                      border: InputBorder.none,
                      isDense: false,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                    textInputAction: TextInputAction.done,
                  ),
                ),
                if (_dropCtrl.text.trim().isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _dropCtrl.clear();
                      _dropResolved = null;
                      setState(() => _dropSuggestions = []);
                      _onChanged();
                    },
                    child: const Icon(Icons.close, size: 16, color: kMuted),
                  ),
              ],
            ),
          ),

          _buildSuggestions(_dropSuggestions, isPickup: false),
          // The drop field previously had NO location actions at all —
          // pickup got a "my location" button and drop got nothing, so
          // the only way to set a destination was to type it (which,
          // before this round, produced no coordinate at all).
          _buildLocationActions(isPickup: false, busy: _dropFetching),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ── RIDE SELECTOR ─────────────────────────────────────────────
  Widget _buildRideSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.flash_on, size: 14, color: kGold),
            SizedBox(width: 6),
            Text(
              'CHOOSE RIDE TYPE',
              style: TextStyle(
                fontSize: 10,
                color: kMuted,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: List.generate(_rides.length, (i) {
            final r = _rides[i];
            final sel = _rideIdx == i;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _rideIdx = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                  decoration: BoxDecoration(
                    color: sel
                        ? Color.fromRGBO(
                            r.color.r.toInt(),
                            r.color.g.toInt(),
                            r.color.b.toInt(),
                            0.12,
                          )
                        : kCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: sel
                          ? Color.fromRGBO(
                              r.color.r.toInt(),
                              r.color.g.toInt(),
                              r.color.b.toInt(),
                              0.5,
                            )
                          : kBorder,
                      width: sel ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(r.icon, size: 28, color: sel ? r.color : kMuted),
                      const SizedBox(height: 5),
                      Text(
                        r.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: sel ? r.color : kText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        r.sublabel,
                        style: TextStyle(
                          fontSize: 9,
                          color: sel
                              ? Color.fromRGBO(
                                  r.color.r.toInt(),
                                  r.color.g.toInt(),
                                  r.color.b.toInt(),
                                  0.75,
                                )
                              : kMuted,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Color.fromRGBO(
                            r.color.r.toInt(),
                            r.color.g.toInt(),
                            r.color.b.toInt(),
                            0.12,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Color.fromRGBO(
                              r.color.r.toInt(),
                              r.color.g.toInt(),
                              r.color.b.toInt(),
                              0.35,
                            ),
                          ),
                        ),
                        child: Text(
                          r.eta,
                          style: TextStyle(
                            fontSize: 9,
                            color: r.color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  // ── FARE CARD ─────────────────────────────────────────────────
  Widget _buildFareCard() {
    final r = _rides[_rideIdx];
    final dist = _pickupSet && _dropSet ? _distKm() : 4.5;
    final fare = (dist * r.ratePerKm).round();

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
          .animate(_slideAnim),
      child: FadeTransition(
        opacity: _slideAnim,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                kCard,
                Color.fromRGBO(
                  r.color.r.toInt(),
                  r.color.g.toInt(),
                  r.color.b.toInt(),
                  0.06,
                ),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Color.fromRGBO(
                r.color.r.toInt(),
                r.color.g.toInt(),
                r.color.b.toInt(),
                0.3,
              ),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Color.fromRGBO(
                        r.color.r.toInt(),
                        r.color.g.toInt(),
                        r.color.b.toInt(),
                        0.12,
                      ),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: Color.fromRGBO(
                          r.color.r.toInt(),
                          r.color.g.toInt(),
                          r.color.b.toInt(),
                          0.3,
                        ),
                      ),
                    ),
                    child:
                        Center(child: Icon(r.icon, color: r.color, size: 24)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: r.color,
                          ),
                        ),
                        Text(
                          '${dist.toStringAsFixed(1)} km · ${r.eta}',
                          style: const TextStyle(fontSize: 11, color: kMuted),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹$fare',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: r.color,
                        ),
                      ),
                      const Text(
                        'Estimated',
                        style: TextStyle(fontSize: 9, color: kMuted),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: kBorder),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _chip(Icons.payment, 'Cash/UPI', kGreen),
                  _chip(Icons.timer, r.eta, kPurple2),
                  _chip(Icons.star, '4.8+ Riders', kGold),
                  _chip(Icons.map, 'OSM Tracked', kOrange),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData i, String t, Color c) => Column(
        children: [
          Icon(i, size: 18, color: c.withValues(alpha: 0.8)),
          const SizedBox(height: 3),
          Text(
            t,
            style:
                TextStyle(fontSize: 9, color: c, fontWeight: FontWeight.w600),
          ),
        ],
      );

  // ── RECENT PLACES ─────────────────────────────────────────────
  Widget _buildRecent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.history, size: 14, color: kMuted),
            SizedBox(width: 6),
            Text(
              'RECENT PLACES',
              style: TextStyle(
                fontSize: 10,
                color: kMuted,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._recentPlaces.map(
          (p) => GestureDetector(
            onTap: () => _fillPlace(p),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: kCard2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kBorder),
                    ),
                    child:
                        Center(child: Icon(p.icon, size: 20, color: kPurple2)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.label,
                          style: GoogleFonts.notoSansTamil(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: kText,
                          ),
                        ),
                        Text(
                          p.address,
                          style: const TextStyle(fontSize: 10, color: kMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.north_west, size: 14, color: kPurple2),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── CAPTAIN PROMO CARD ────────────────────────────────────────
  Widget _buildPromo() {
    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse(
          'https://wa.me/919597879191?text=${Uri.encodeComponent('I want to join as an Allin1 Hero! 🏍️')}',
        );
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1a1500), Color(0x14F5C542)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x59F5C542)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => Transform.scale(
                      scale: _pulseAnim.value,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x1AF5C542),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0x66F5C542)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: kGold,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'NOW HIRING — ERODE',
                              style: TextStyle(
                                fontSize: 9,
                                color: kGold,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Become an Allin1\nHero? 🏍️',
                    style: GoogleFonts.notoSansTamil(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: kText,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '₹500–₹1,000/day · Flexible timing\n'
                    'Your bike → your business!',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: kMuted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [kGold, Color(0xFFD4961A)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Join Now →',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1a1500),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            const Column(
              children: [
                Text('🏍️', style: TextStyle(fontSize: 52)),
                SizedBox(height: 4),
                Text(
                  'Erode',
                  style: TextStyle(
                    fontSize: 10,
                    color: kGold,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── BOOK BUTTON ───────────────────────────────────────────────
  Widget _buildBookBtn() {
    final r = _rides[_rideIdx];
    final ready = _pickupSet && _dropSet;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xFF08080F)],
          stops: [0.0, 0.5],
        ),
      ),
      child: GestureDetector(
        onTap: _book,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 56,
          decoration: BoxDecoration(
            gradient: ready
                ? LinearGradient(
                    colors: [
                      r.color,
                      Color.fromRGBO(
                        r.color.r.toInt(),
                        r.color.g.toInt(),
                        r.color.b.toInt(),
                        0.8,
                      ),
                    ],
                  )
                : null,
            color: ready ? null : kCard2,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: ready
                  ? Color.fromRGBO(
                      r.color.r.toInt(),
                      r.color.g.toInt(),
                      r.color.b.toInt(),
                      0.5,
                    )
                  : kBorder,
            ),
            boxShadow: ready
                ? [
                    BoxShadow(
                      color: Color.fromRGBO(
                        r.color.r.toInt(),
                        r.color.g.toInt(),
                        r.color.b.toInt(),
                        0.4,
                      ),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                r.icon,
                size: 24,
                color: ready ? const Color(0xFF1a1500) : kMuted,
              ),
              const SizedBox(width: 10),
              Text(
                ready
                    ? 'Book ${r.label} →'
                    : 'Enter your locations 📍',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: ready ? const Color(0xFF1a1500) : kMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── MAP CONTROL BUTTON ────────────────────────────────────────
  Widget _mapBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xF0141420),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kBorder),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

// ================================================================
// MARKER WIDGETS (extracted — fixes AnimatedBuilder issue)
// ================================================================

/// Static pin marker for pickup/drop
class _PinMarker extends StatelessWidget {
  final Color color;
  final IconData icon; // Changed from emoji to icon
  const _PinMarker({
    required this.color,
    required this.icon,
  }); // Changed from emoji to icon

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Color.fromRGBO(
              color.r.toInt(),
              color.g.toInt(),
              color.b.toInt(),
              0.2,
            ),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
            boxShadow: [
              BoxShadow(
                color: Color.fromRGBO(
                  color.r.toInt(),
                  color.g.toInt(),
                  color.b.toInt(),
                  0.55,
                ),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Icon(
              icon,
              size: 16,
              color: color,
            ),
          ), // Changed from Text(emoji) to Icon(icon)
        ),
        Container(
          width: 2,
          height: 10,
          color: Color.fromRGBO(
            color.r.toInt(),
            color.g.toInt(),
            color.b.toInt(),
            0.8,
          ),
        ),
      ],
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(ColorProperty('color', color))
      ..add(DiagnosticsProperty<IconData>('icon', icon));
  }
}

/// FIX [2]: Animated rider — StatefulWidget (no AnimatedBuilder in marker)
class _AnimatedRiderMarker extends StatefulWidget {
  final Color color;
  const _AnimatedRiderMarker({required this.color});
  @override
  State<_AnimatedRiderMarker> createState() => _AnimatedRiderMarkerState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(ColorProperty('color', color));
  }
}

class _AnimatedRiderMarkerState extends State<_AnimatedRiderMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
    _a = Tween<double>(begin: 0.6, end: 1)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (_, __) => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Color.fromRGBO(
            widget.color.r.toInt(),
            widget.color.g.toInt(),
            widget.color.b.toInt(),
            _a.value * 0.2,
          ),
          shape: BoxShape.circle,
          border: Border.all(color: widget.color, width: 2),
          boxShadow: [
            BoxShadow(
              color: Color.fromRGBO(
                widget.color.r.toInt(),
                widget.color.g.toInt(),
                widget.color.b.toInt(),
                _a.value * 0.65,
              ),
              blurRadius: 14,
              spreadRadius: 3,
            ),
          ],
        ),
        child: const Center(child: Text('🏍️', style: TextStyle(fontSize: 20))),
      ),
    );
  }
}

/// Nearby rider dot
class _NearbyDot extends StatelessWidget {
  final Color color;
  const _NearbyDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.fromRGBO(
          color.r.toInt(),
          color.g.toInt(),
          color.b.toInt(),
          0.9,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(
              color.r.toInt(),
              color.g.toInt(),
              color.b.toInt(),
              0.6,
            ),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      child: const Center(child: Text('🏍', style: TextStyle(fontSize: 11))),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(ColorProperty('color', color));
  }
}

// ================================================================
// BOOKING BOTTOM SHEET
// ================================================================
class _BookSheet extends StatefulWidget {
  final _RideType ride;
  final String pickup;
  final String drop;
  final double distKm;

  const _BookSheet({
    required this.ride,
    required this.pickup,
    required this.drop,
    required this.distKm,
  });

  @override
  State<_BookSheet> createState() => _BookSheetState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<_RideType>('ride', ride))
      ..add(StringProperty('pickup', pickup))
      ..add(StringProperty('drop', drop))
      ..add(DoubleProperty('distKm', distKm));
  }
}

class _BookSheetState extends State<_BookSheet> {
  bool _confirming = false;
  bool _waitingRider = false;
  bool _accepted = false;
  bool _completed = false;
  String _rideDocId = '';
  String _captainName = '';
  String _captainPhone = '';
  String _eta = '';
  double? _captLat;
  double? _captLng;
  int _rating = 0;

  int get _fare => (widget.distKm * widget.ride.ratePerKm).round();

  Future<void> _confirmRide() async {
    setState(() => _confirming = true);
    try {
      final doc = await FirebaseFirestore.instance.collection('rides').add({
        'pickup': widget.pickup,
        'drop': widget.drop,
        'distKm': widget.distKm,
        'fare': _fare,
        'rideType': widget.ride.label,
        'status': 'pending',
        'customerPhone': FirebaseAuth.instance.currentUser?.phoneNumber ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'acceptedAt': null,
        'captainId': null,
        'captainName': null,
      });

      // Task 3: Trigger push notification via Firestore collection
      await FirebaseFirestore.instance.collection('notifications').add({
        'type': 'new_ride',
        'rideId': doc.id,
        'pickup': widget.pickup,
        'drop': widget.drop,
        'fare': _fare,
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
      });
      setState(() {
        _rideDocId = doc.id;
        _confirming = false;
        _waitingRider = true;
      });
      // Listen for real-time status changes
      FirebaseFirestore.instance
          .collection('rides')
          .doc(doc.id)
          .snapshots()
          .listen((snap) {
        if (!mounted || !snap.exists) {
          return;
        }
        final data = snap.data();
        if (data == null) {
          return;
        }

        final status = data['status'] as String? ?? 'pending';
        if (status == 'accepted' && !_accepted) {
          setState(() {
            _accepted = true;
            _waitingRider = false;
            _captainName = data['captainName'] as String? ?? 'NJ TECH Rider';
            _captainPhone = data['captainPhone'] as String? ?? '';
            _eta = data['eta'] as String? ?? '5 min';
          });
        }
        if (_accepted) {
          setState(() {
            _captLat = data['captainLat'] as double?;
            _captLng = data['captainLng'] as double?;
          });
        }
        if (status == 'completed' && !_completed) {
          setState(() {
            _completed = true;
            _accepted = false;
          });
        }
      });
    } catch (e) {
      setState(() => _confirming = false);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFE05555),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _cancelRide() async {
    if (_rideDocId.isEmpty) {
      return;
    }
    await FirebaseFirestore.instance
        .collection('rides')
        .doc(_rideDocId)
        .update({'status': 'cancelled'});
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _payUPI() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PaymentScreen(
          amount: _fare.toDouble(),
          note: 'Bike Taxi Ride',
          rideDocId: _rideDocId.isNotEmpty ? _rideDocId : null,
        ),
      ),
    );
  }

  Future<void> _callCaptain() async {
    if (_captainPhone.isEmpty) {
      return;
    }
    final uri = Uri.parse('tel:$_captainPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        decoration: const BoxDecoration(
          color: kCard2,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: kBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _summaryRow(),
            const SizedBox(height: 14),
            const Divider(color: kBorder),
            const SizedBox(height: 10),
            _locRow('🟢', 'Pickup', widget.pickup),
            const SizedBox(height: 8),
            _locRow('🟠', 'Drop', widget.drop),
            const SizedBox(height: 18),
            if (_completed)
              _completedView()
            else if (_accepted)
              _acceptedView()
            else if (_waitingRider)
              _waitingView()
            else
              _confirmView(),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow() {
    final r = widget.ride;
    return Row(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Color.fromRGBO(
              r.color.r.toInt(),
              r.color.g.toInt(),
              r.color.b.toInt(),
              0.12,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Color.fromRGBO(
                r.color.r.toInt(),
                r.color.g.toInt(),
                r.color.b.toInt(),
                0.3,
              ),
            ),
          ),
          child: Center(child: Icon(r.icon, size: 24, color: r.color)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: r.color,
                ),
              ),
              Text(
                '${widget.distKm.toStringAsFixed(1)} km · ${r.eta}',
                style: const TextStyle(fontSize: 11, color: kMuted),
              ),
            ],
          ),
        ),
        Text(
          '₹$_fare',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: r.color,
          ),
        ),
      ],
    );
  }

  Widget _confirmView() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Route ready on Map · Confirm to find your Hero!',
            style: TextStyle(fontSize: 12, color: kMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _confirming ? null : _confirmRide,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.ride.color,
                foregroundColor: const Color(0xFF1a1500),
                disabledBackgroundColor: const Color(0x99F5C542),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: _confirming
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Color(0xFF1a1500),
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Confirm & find a Captain 🏍️',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      );

  Widget _waitingView() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0x1A7B6FE0),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x407B6FE0)),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Color(0xFF9B8FF0),
                    strokeWidth: 2,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Finding your Hero...',
                        style: GoogleFonts.notoSansTamil(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: kText,
                        ),
                      ),
                      Text(
                        'Ride ID: ${_rideDocId.length > 8 ? _rideDocId.substring(0, 8) : _rideDocId}...',
                        style: const TextStyle(fontSize: 9, color: kMuted),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0x1A3DBA6F),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0x663DBA6F)),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      fontSize: 8,
                      color: kGreen,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _cancelRide,
            child: const Text(
              'Cancel Ride',
              style: TextStyle(color: Color(0xFFE05555), fontSize: 12),
            ),
          ),
        ],
      );

  Widget _acceptedView() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0x0F3DBA6F),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x4D3DBA6F)),
            ),
            child: Row(
              children: [
                const Text('🏍️', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _captainName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: kText,
                        ),
                      ),
                      Text(
                        'ETA: $_eta · OSM Tracked',
                        style: const TextStyle(fontSize: 10, color: kGreen),
                      ),
                    ],
                  ),
                ),
                if (_captainPhone.isNotEmpty)
                  GestureDetector(
                    onTap: _callCaptain,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0x1A3DBA6F),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x4D3DBA6F)),
                      ),
                      child: const Icon(Icons.phone, size: 18, color: kGreen),
                    ),
                  ),
              ],
            ),
          ),
          if (_captLat != null && _captLng != null) ...[
            const SizedBox(height: 14),
            Container(
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(_captLat!, _captLng!),
                    initialZoom: 14,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: [
                            LatLng(_captLat!, _captLng!),
                            const LatLng(11.3520, 77.7280),
                          ], // Drop
                          color: kPurple,
                          strokeWidth: 3,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        const Marker(
                          point: LatLng(11.3520, 77.7280),
                          child: Text('🏁', style: TextStyle(fontSize: 20)),
                        ),
                        Marker(
                          point: LatLng(_captLat!, _captLng!),
                          width: 40,
                          height: 40,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              color: kGold,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '🏍️',
                                style: TextStyle(fontSize: 18),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            'Wait for your Hero to arrive!',
            style: TextStyle(fontSize: 11, color: kMuted),
          ),
        ],
      );

  Widget _completedView() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0x1A3DBA6F), Color(0x1AF5C542)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x4D3DBA6F)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🎉', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ride Complete!',
                        style: GoogleFonts.notoSansTamil(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: kGreen,
                        ),
                      ),
                      const Text(
                        'Pay now!',
                        style: TextStyle(fontSize: 11, color: kMuted),
                      ),
                    ],
                  ),
                ),
                Text(
                  '₹$_fare',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: kGold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // UPI Payment Button — Zero gateway fees!
          GestureDetector(
            onTap: _payUPI,
            child: Container(
              width: double.infinity,
              height: 58,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A73E8), Color(0xFF1557B0)],
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x661A73E8),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Text(
                        '₹',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1A73E8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pay ₹$_fare via UPI',
                        style: GoogleFonts.notoSansTamil(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const Text(
                        'GPay · PhonePe · Paytm · BHIM',
                        style: TextStyle(fontSize: 9, color: Color(0xCCFFFFFF)),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Zero gateway fees · Opens your UPI app directly',
            style: TextStyle(fontSize: 9, color: kMuted),
            textAlign: TextAlign.center,
          ),
          _ratingWidget(),
        ],
      );

  Widget _ratingWidget() {
    return Column(
      children: [
        const SizedBox(height: 14),
        const Text(
          'How was your ride?',
          style: TextStyle(
            fontSize: 14,
            color: kText,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            5,
            (i) => GestureDetector(
              onTap: () async {
                setState(() => _rating = i + 1);
                if (_rideDocId.isNotEmpty) {
                  await FirebaseFirestore.instance
                      .collection('rides')
                      .doc(_rideDocId)
                      .update({'customerRating': i + 1});
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  i < _rating ? '⭐' : '☆',
                  style: const TextStyle(fontSize: 32),
                ),
              ),
            ),
          ),
        ),
        if (_rating > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Thank you for rating $_rating stars! 🙏',
              style: const TextStyle(fontSize: 12, color: kGreen),
            ),
          ),
      ],
    );
  }

  Widget _locRow(String dot, String lbl, String txt) => Row(
        children: [
          Text(dot, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lbl,
                style: const TextStyle(
                  fontSize: 9,
                  color: kMuted,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                txt,
                style: const TextStyle(
                  fontSize: 13,
                  color: kText,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      );
}
