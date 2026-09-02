// ================================================================
// hero_search_radar_screen.dart — generic "searching for a Hero"
// radar screen, modelled on bike_taxi/ride_search_screen.dart's
// sweeping-radar visual but built for the Broadcast Order System
// (service_requests collection) instead of the taxi-specific
// active_ride_requests/hero_pings RTDB flow.
//
// Every caller (hero_booking_screen.dart, grocery_order_screen.dart,
// custom_food_order_screen.dart, nj_tech_store_screen.dart,
// skilled_services_screen.dart) already creates its own
// service_requests doc and broadcasts it via ServiceRequestService.
// createServiceRequest() — this screen touches NONE of that backend
// logic. Its only job is to show the wait visually — the same
// experience Taxi gives — by watching the SAME doc's `status` field
// those flows already write, then hand off to whatever "matched"
// screen the caller wants via [matchedScreenBuilder], or show a
// timeout/retry state once kServiceRequestPingExpirySeconds elapses.
// ================================================================
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/service_request_service.dart';
import '../services/theme_context_extensions.dart';
import 'hero_booking_tracking_screen.dart';
import '../services/firestore_usage_tracking.dart';

class HeroSearchRadarScreen extends StatefulWidget {
  final String requestId;

  /// Customer-facing name for what's being searched for, e.g.
  /// 'Electrician', 'Grocery Seller', 'Repair Hero'. Plain display
  /// text — no lookup table, so any flow can pass its own label.
  final String serviceLabel;

  /// Builds the screen to hand off to once status leaves 'pending'/
  /// 'pinging'. Defaults to HeroBookingTrackingScreen for the
  /// existing Hero Booking family; other flows pass their own
  /// ServiceRequestTrackingScreen (or equivalent) here so this widget
  /// never needs to know about every flow's tracking screen.
  final Widget Function(String requestId)? matchedScreenBuilder;

  const HeroSearchRadarScreen({
    required this.requestId,
    required this.serviceLabel,
    this.matchedScreenBuilder,
    super.key,
  });

  @override
  State<HeroSearchRadarScreen> createState() => _HeroSearchRadarScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('requestId', requestId))
      ..add(StringProperty('serviceLabel', serviceLabel));
  }
}

class _HeroSearchRadarScreenState extends State<HeroSearchRadarScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _radarCtrl;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  int _elapsedSeconds = 0;
  Timer? _tick;
  bool _handled = false;
  bool _timedOut = false;
  String? _matchedHeroName;
  String? _matchedHeroPhone;

  @override
  void initState() {
    super.initState();
    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
      if (_elapsedSeconds >= kServiceRequestPingExpirySeconds &&
          !_handled &&
          !_timedOut) {
        setState(() => _timedOut = true);
        _radarCtrl.stop();
      }
    });
    _sub = FirebaseFirestore.instance
        .collection('service_requests')
        .doc(widget.requestId)
        .trackedSnapshots()
        .listen((doc) {
      if (!mounted || _handled) return;
      final status = doc.data()?['status'] as String? ?? '';
      // 'pending' / 'pinging' are the only "still searching" states
      // across every flow that uses this screen — anything else means
      // a hero/seller has taken the request (or it ended), so hand
      // off immediately.
      const stillSearching = {'pending', 'pinging'};
      const terminalNoMatch = {'cancelled', 'timeout'};
      if (status.isNotEmpty &&
          !stillSearching.contains(status) &&
          !terminalNoMatch.contains(status)) {
        _handled = true;
        _radarCtrl.stop();
        _tick?.cancel();
        final data = doc.data() ?? {};
        // Written by ServiceRequestService.acceptServiceRequest() at
        // the moment of match — reading it here is just a display
        // read, no write of our own. Falls back to hero_assigned* for
        // callers whose accept path uses that field name instead.
        setState(() {
          _matchedHeroName = (data['assignedHeroName'] as String?) ??
              (data['heroAssignedName'] as String?);
          _matchedHeroPhone = (data['assignedHeroPhone'] as String?) ??
              (data['heroAssignedPhone'] as String?);
        });
        // Brief "Hero found!" confirmation stays on THIS screen before
        // handing off — so the customer actually sees the moment a
        // hero picked up their request, instead of an instant jump.
        Timer(const Duration(milliseconds: 1800), () {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => _matchedScreen()),
          );
        });
      }
    });
  }

  Widget _matchedScreen() =>
      widget.matchedScreenBuilder?.call(widget.requestId) ??
      HeroBookingTrackingScreen(requestId: widget.requestId);

  @override
  void dispose() {
    _radarCtrl.dispose();
    _tick?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  void _tryAgain() {
    // createServiceRequest() already broadcast to every eligible hero
    // once; there is no separate re-broadcast entry point for a plain
    // hero_booking request (unlike the deferred food-order path). A
    // timed-out request is still visible to Admin's "New Orders" tab
    // (see markTimeoutIfStillPending), so re-arming the wait here just
    // gives the customer another look while admin picks it up.
    setState(() {
      _timedOut = false;
      _elapsedSeconds = 0;
    });
    _radarCtrl.repeat();
  }

  // Leaving this screen never cancels the underlying service_requests
  // doc — the broadcast that createServiceRequest() already sent stays
  // live, and heroes can still accept it. So "back" just steps away
  // from the visual; the customer can always resume via "Booking
  // Status" (HeroBookingStatusScreen routes a still-pending request
  // straight back to this same screen).
  void _leaveSearch() {
    if (!_handled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Still searching in the background — check "Booking Status" '
            'anytime to come back to this.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
    }
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final categoryLabel = widget.serviceLabel;
    return PopScope(
      // Never let a system back-gesture fall through and close the
      // app while a search is live — always resolve it into an
      // in-app navigation (same background-search message as the
      // app-bar back arrow) instead.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leaveSearch();
      },
      child: Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        color: context.colors.text, size: 20,),
                    onPressed: _leaveSearch,
                  ),
                  Expanded(
                    child: Text(
                      'Finding a $categoryLabel Hero',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: context.colors.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: _handled
                    ? _foundView(categoryLabel)
                    : _timedOut
                        ? _timeoutView()
                        : _radarView(categoryLabel),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _radarView(String categoryLabel) {
    final remaining =
        (kServiceRequestPingExpirySeconds - _elapsedSeconds).clamp(0, kServiceRequestPingExpirySeconds);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 260,
          height: 260,
          child: AnimatedBuilder(
            animation: _radarCtrl,
            builder: (context, _) => CustomPaint(
              painter: _RadarPainter(
                progress: _radarCtrl.value,
                color: context.colors.accent,
              ),
              child: Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.colors.accent,
                    boxShadow: [
                      BoxShadow(
                        color: context.colors.accent.withValues(alpha: 0.5),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.bolt_rounded,
                      color: Colors.white, size: 28,),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Searching nearby $categoryLabel heroes…',
          style: GoogleFonts.outfit(
            color: context.colors.text,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${remaining}s remaining',
          style: TextStyle(color: context.colors.mutedText, fontSize: 12),
        ),
        const SizedBox(height: 32),
        // FIX (Sep 2 2026 — service-booking flow audit): this button was
        // labeled "Cancel" but _leaveSearch() below has never cancelled
        // anything — it just pops the screen while the request keeps
        // broadcasting in the background, and its own snackbar SAYS so
        // ("Still searching in the background — check Booking Status
        // anytime"). A customer tapping "Cancel" believing they withdrew
        // their request would be surprised when a hero later calls to
        // accept it. This screen is shared by every non-ride request
        // type (custom orders, food, grocery, NJ Tech/mobile service,
        // every skill trade including Acting Driver — see file header),
        // and genuine cancellation is nowhere in this pipeline at all
        // (checked ServiceRequestTrackingScreen and every caller — none
        // wire cancelServiceRequest()), so the safe, correct fix here is
        // the label: say what the button actually does.
        OutlinedButton(
          onPressed: _leaveSearch,
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: context.colors.accent, width: 1.4),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Text('Search in Background',
              style: TextStyle(color: context.colors.accent, fontWeight: FontWeight.w700),),
        ),
      ],
    );
  }

  Widget _foundView(String categoryLabel) {
    final heroName = _matchedHeroName?.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.colors.accent,
            boxShadow: [
              BoxShadow(
                color: context.colors.accent.withValues(alpha: 0.4),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 44),
        ),
        const SizedBox(height: 20),
        Text(
          '$categoryLabel Hero found!',
          style: GoogleFonts.outfit(
            color: context.colors.text,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        if (heroName != null && heroName.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            [heroName, _matchedHeroPhone?.trim()]
                .where((s) => s != null && s.isNotEmpty)
                .join(' · '),
            style: TextStyle(color: context.colors.mutedText, fontSize: 13),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: context.colors.accent,
          ),
        ),
      ],
    );
  }

  Widget _timeoutView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.search_off_rounded, color: context.colors.mutedText, size: 64),
        const SizedBox(height: 16),
        Text(
          'No hero picked this up yet',
          style: GoogleFonts.outfit(
            color: context.colors.text,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Our team has been notified and will arrange one shortly, or you can try broadcasting again.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.colors.mutedText, fontSize: 12),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _tryAgain,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.colors.accent,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text('Try Again',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => _matchedScreen()),
          ),
          child: Text('View Booking Status',
              style: TextStyle(color: context.colors.mutedText),),
        ),
      ],
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  final Color color;
  _RadarPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.width / 2;

    for (int i = 0; i < 3; i++) {
      final ringProgress = (progress + i / 3) % 1.0;
      final radius = maxRadius * ringProgress;
      final opacity = (1 - ringProgress).clamp(0.0, 1.0);
      final ringPaint = Paint()
        ..color = color.withValues(alpha: opacity * 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius, ringPaint);
    }

    final bgPaint = Paint()..color = color.withValues(alpha: 0.06);
    canvas.drawCircle(center, maxRadius, bgPaint);

    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [color.withValues(alpha: 0.0), color.withValues(alpha: 0.35)],
        startAngle: 0,
        endAngle: pi / 2,
        transform: GradientRotation(progress * 2 * pi),
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius));
    canvas.drawCircle(center, maxRadius, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
