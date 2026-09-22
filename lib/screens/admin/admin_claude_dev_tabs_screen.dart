// ================================================================
// admin_claude_dev_tabs_screen.dart — Claude and the dev-activity
// monitor, side by side (same split pattern as admin_web_tabs_screen
// .dart's GitHub/Browser segments)
// ================================================================
// NEW (Sep 22 2026 — Nizam: "claude ku poganum new va claude create
// pannu 7th optiona but athula claude external browser or normal
// browser look la open agama browser embedded view la open aganum...
// intha development flow activity pakkurathuku claude section 2 ah
// split panni oru pakkam claude oru pakkam development activity
// monitor nu github mariye pirichuruvom").
//
// WHY A SEGMENT AND NOT TWO SEPARATE BOTTOM-NAV ITEMS
// Same reasoning as admin_web_tabs_screen.dart's own header: a 7th AND
// 8th bottom tab would crowd the bar past readability. Two segments
// inside one "Claude" tab keeps the nav honest while still giving both
// views their own one-tap slot, exactly like GitHub/Browser already do.
//
// WHY THE CLAUDE SEGMENT REUSES AdminTabbedBrowserScreen DIRECTLY
// That screen already IS the "embedded view, not an external browser"
// requirement — the Dev tab's "Claude Desktop" tile opens the exact
// same screen. Both entry points share the SAME static tab list, so
// opening Claude from either place shows the SAME persisted state —
// which is also exactly what "app close pannitu reopen pannunalum
// same stage la irukanum" asked for, and that persistence (Hive-
// adjacent SharedPreferences, url+title+active index) already exists
// there unchanged.
//
// A fresh install landing on this tab BEFORE ever tapping the Dev
// tab's tile still needs Claude open by default, not the generic
// GitHub fallback every other AdminTabbedBrowserScreen caller wants —
// see the defaultUrl/defaultTitle params passed below.
//
// KNOWN SIMPLIFICATION: AdminTabbedBrowserScreen manages its own
// WebView pause/resume purely off the app's foreground/background
// state (see its own _syncPower()) — it has no "is my segment
// currently the visible one" signal the way GitHubEmbeddedScreen/
// AdminWebBrowserScreen do via their `visible` param. So while the Dev
// Monitor segment is showing, the hidden Claude WebView keeps running
// rather than pausing. This is a real but minor cost (no crash, no
// data issue) — wiring true segment-visibility awareness into
// AdminTabbedBrowserScreen would mean touching its per-tab controller
// setup, which is a bigger change than this feature needs on day one.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'admin_tabbed_browser_screen.dart';
import 'chitti_dev_monitor_screen.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF16162A);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF8A8AA3);
const Color _accent = Color(0xFFB21FFF);

class AdminClaudeDevTabsScreen extends StatefulWidget {
  const AdminClaudeDevTabsScreen({super.key});

  /// Which segment is showing — static so re-visiting this bottom tab
  /// remembers the last segment, same contract AdminWebTabsScreen uses
  /// for its own _segment field.
  static int _segment = 0;

  @override
  State<AdminClaudeDevTabsScreen> createState() =>
      _AdminClaudeDevTabsScreenState();
}

class _AdminClaudeDevTabsScreenState extends State<AdminClaudeDevTabsScreen> {
  int get _segment => AdminClaudeDevTabsScreen._segment;

  void _select(int index) {
    if (_segment == index) return;
    setState(() => AdminClaudeDevTabsScreen._segment = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _segmentBar(),
            Expanded(
              child: Stack(
                children: [
                  Offstage(
                    offstage: _segment != 0,
                    child: const AdminTabbedBrowserScreen(
                      key: ValueKey('claude_embedded_tab'),
                      defaultUrl: 'https://claude.ai/code',
                      defaultTitle: 'Claude Code',
                    ),
                  ),
                  Offstage(
                    offstage: _segment != 1,
                    child: const ChittiDevMonitorScreen(
                      key: ValueKey('claude_dev_monitor_tab'),
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

  Widget _segmentBar() => Container(
        color: _bg,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Row(
          children: [
            _segmentButton(0, Icons.smart_toy_outlined, 'Claude'),
            const SizedBox(width: 8),
            _segmentButton(1, Icons.monitor_heart_outlined, 'Dev Activity'),
          ],
        ),
      );

  Widget _segmentButton(int index, IconData icon, String label) {
    final selected = _segment == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _select(index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? _accent.withValues(alpha: 0.16) : _surface,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? _accent : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: selected ? _accent : _muted),
              const SizedBox(width: 7),
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: selected ? _text : _muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
