// ================================================================
// stranded_orders_banner.dart — the hero-side safety net.
// ================================================================
// NEW (Aug 28 2026 — Nizam: "admin mobile attend pannalainalum new
// orders... hero ku assign panni customer ku message anupuravaraikkum").
//
// See chitti_order_escalation_service.dart for why the HERO phones run
// this and not a server: on the Spark plan there is no server, and a
// timer on the admin's phone cannot run when that phone is off — which
// is the exact situation this exists for.
//
// WHY IT IS A BANNER AND NOT A SILENT BACKGROUND JOB
// A phone quietly releasing another person's order is the kind of
// behaviour nobody can explain later when it goes wrong. Showing the
// hero what is stranded, and why, makes the safety net legible: the
// hero taps, the order joins the normal ping queue, and the tap is a
// deliberate act rather than an invisible rule.
//
// It also happens to be the right incentive. A hero staring at an
// empty queue is the one person with both the motive and the live
// connection to notice a stranded order.
//
// RENDERS NOTHING ON THE NORMAL DAY
// If no order is stranded this collapses to a zero-height box, so it
// costs the hero home screen no space whatsoever when the admin is
// keeping up — which is most of the time.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/chitti/chitti_order_escalation_service.dart';

class StrandedOrdersBanner extends StatefulWidget {
  const StrandedOrdersBanner({super.key});

  @override
  State<StrandedOrdersBanner> createState() => _StrandedOrdersBannerState();
}

class _StrandedOrdersBannerState extends State<StrandedOrdersBanner> {
  static const Color _pink = Color(0xFFFF4FA3);
  static const Color _deep = Color(0xFF4A1236);
  static const Color _amber = Color(0xFFE07A00);

  /// Built once. Re-creating the stream inside build() would tear down
  /// and re-attach the Firestore listener on every rebuild, and a fresh
  /// attach re-bills the whole result set.
  late final Stream<List<StrandedOrder>> _stream;

  /// Ids this phone is mid-release on, so a double tap cannot fire two
  /// escalations. (The service is race-safe on its own; this is about
  /// the button not looking dead for a second.)
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _stream = ChittiOrderEscalationService.instance.watchStranded();
  }

  Future<void> _release(StrandedOrder o) async {
    setState(() => _busy.add(o.id));
    final outcome =
        await ChittiOrderEscalationService.instance.escalate(o.id);
    if (!mounted) return;
    setState(() => _busy.remove(o.id));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          switch (outcome) {
            EscalationOutcome.escalated =>
              'Sent to all heroes. Accept it from your ride alerts.',
            // Not phrased as a failure: another hero or the admin
            // getting there first is the system working, and a red
            // error would train heroes to stop tapping.
            EscalationOutcome.alreadyHandled =>
              'Someone already picked this one up.',
            EscalationOutcome.tooSoon =>
              'Not yet — giving the office a few more minutes.',
            EscalationOutcome.failed =>
              "Couldn't reach the server. Try again in a moment.",
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StrandedOrder>>(
      stream: _stream,
      builder: (context, snap) {
        final items = snap.data ?? const <StrandedOrder>[];
        // The normal day: nothing waiting, nothing shown.
        if (items.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _amber.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.hourglass_bottom_rounded,
                      color: _amber, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Customers still waiting',
                      style: GoogleFonts.outfit(
                        color: _deep,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'The office has not picked these up yet. Tap to send one to '
                'all heroes — then accept it from your ride alerts.',
                style: GoogleFonts.outfit(
                  color: const Color(0xFF8A4E72),
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              // Capped at three. A hero needs the oldest few, not an
              // inbox — and a long list on the home screen would push
              // the actual job controls off the fold.
              ...items.take(3).map((o) {
                final busy = _busy.contains(o.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              o.requestType.isEmpty ? 'Order' : o.requestType,
                              style: GoogleFonts.outfit(
                                color: _deep,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              o.waitedLabel(),
                              style: GoogleFonts.outfit(
                                color: _amber,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => _release(o),
                        style: TextButton.styleFrom(
                          backgroundColor: _pink,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          busy ? '…' : 'Send to heroes',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
