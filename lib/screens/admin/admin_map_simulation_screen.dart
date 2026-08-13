// ================================================================
// admin_map_simulation_screen.dart — Internal Map Load-Test Harness
// ================================================================
// NEW (Aug 12 2026 — per Nizam's explicit instruction after
// map_simulation_service.dart was found wired into the LIVE
// customer/hero map via a remote Firestore toggle): this screen is now
// the ONLY place in the entire app that may ever start
// MapSimulationService. It is reachable ONLY from the Admin app's
// drawer — never linked from the customer or hero apps, never driven
// by a remote flag, and always carries the permanent watermark banner
// below so a screenshot or recording of this screen can never be
// mistaken for the real, live map.
//
// Purpose: let Nizam/CTO verify Allin1MapWidget's rendering
// performance (frame rate, marker-layer rebuild cost) under a
// realistic load — 30 ambient vehicles + 10 "hero" avatars — before
// that many real heroes exist, WITHOUT that load ever touching a real
// customer's screen.
import 'package:flutter/material.dart';

import '../../services/map_simulation_service.dart';
import '../../widgets/allin1_map_widget.dart';

const Color _bg = Color(0xFF0A0A12);
const Color _card = Color(0xFF141420);
const Color _border = Color(0xFF262636);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _pink = Color(0xFFFF4FA3);
const Color _red = Color(0xFFFF3B30);

class AdminMapSimulationScreen extends StatefulWidget {
  const AdminMapSimulationScreen({super.key});

  @override
  State<AdminMapSimulationScreen> createState() => _AdminMapSimulationScreenState();
}

class _AdminMapSimulationScreenState extends State<AdminMapSimulationScreen> {
  final MapSimulationService _sim = MapSimulationService.instance;

  @override
  void dispose() {
    // Leaving this screen always stops the simulation — it should never
    // keep running in the background once nobody is watching it here.
    _sim.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text(
          'Map Load-Test (Internal)',
          style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        iconTheme: const IconThemeData(color: _text),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Permanent watermark banner — cannot be hidden/toggled ──
            Container(
              width: double.infinity,
              color: _red,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'SIMULATION — INTERNAL LOAD TEST — NOT REAL DATA',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: _card, border: Border(bottom: BorderSide(color: _border))),
              child: const Text(
                'This map is 100% fake, generated on-device with zero network calls. It exists only to stress-test '
                'rendering performance with 40 moving markers. It is never shown to customers, heroes, or investors — '
                'this screen is Admin-only and not linked from any other app.',
                style: TextStyle(color: _muted, fontSize: 11.5, height: 1.5),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: _sim,
                builder: (context, _) {
                  return Stack(
                    children: [
                      Allin1MapWidget(
                        markers: _sim.simulatedMarkers,
                        interactive: true,
                      ),
                      // Second, always-on-top watermark so it survives
                      // even if someone screenshots just the map area.
                      Positioned(
                        top: 10,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'SIMULATION',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: _card, border: Border(top: BorderSide(color: _border))),
              child: ListenableBuilder(
                listenable: _sim,
                builder: (context, _) {
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          _sim.isActive
                              ? '${_sim.simulatedMarkers.length} markers rendering'
                              : 'Simulation stopped',
                          style: const TextStyle(color: _text, fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => setState(() => _sim.isActive ? _sim.stop() : _sim.start()),
                        icon: Icon(_sim.isActive ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
                        label: Text(_sim.isActive ? 'Stop' : 'Start Load Test'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _sim.isActive ? _red : _pink,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
