// ================================================================
// admin_web_tabs_screen.dart — GitHub and the browser, side by side
// ================================================================
// NEW (Sep 5 2026 — Nizam: "GitHub-ku pakkathulaye browser-um onnu
// namma app-la Chrome browser features-la onnu build pannurulam").
//
// WHY A SEGMENT AND NOT A SIXTH BOTTOM-NAV ITEM
// The admin shell already carries five bottom tabs. A sixth would push
// the labels to the point of unreadability on a phone, and the browser
// is not a peer of Overview or Orders — it is the same activity as the
// GitHub tab, one step wider. Two segments inside the one web tab keeps
// the nav honest and puts the browser exactly where he asked for it:
// next to GitHub.
//
// ONLY ONE WEBVIEW IS EVER MOUNTED
// This is the whole reason this wrapper exists rather than a Stack of
// both. Each child gets `visible`, and a child that is not visible
// renders a plain coloured box instead of its WebViewWidget while
// keeping its controller — so the hidden tab is still logged in, still
// on the same page, still has its history, and costs nothing to keep.
// Mounting both would double the platform-view compositing cost for a
// surface only one of which can be seen, which is exactly the heating
// Nizam asked to avoid.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/admin_webview_power.dart';
import 'admin_web_browser_screen.dart';
import 'github_embedded_screen.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF16162A);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF8A8AA3);
const Color _accent = Color(0xFF6C63FF);

class AdminWebTabsScreen extends StatefulWidget {
  const AdminWebTabsScreen({super.key, this.visible = true});

  /// False while another BOTTOM tab is on screen. The shell keeps this
  /// mounted in its IndexedStack so returning is instant, which is
  /// right — but a mounted web tab nobody can see must not keep working.
  final bool visible;

  /// Which segment is showing. Static so the shell's back handler can
  /// route a back press to the right WebView without holding a
  /// reference to this State — the same contract the two child screens
  /// already use for their controllers.
  static int _segment = 0;

  /// Walks the ACTIVE segment's own history first, exactly as the
  /// GitHub tab did before the browser existed.
  static Future<bool> goBackIfPossible() => _segment == 0
      ? GitHubEmbeddedScreen.goBackIfPossible()
      : AdminWebBrowserScreen.goBackIfPossible();

  @override
  State<AdminWebTabsScreen> createState() => _AdminWebTabsScreenState();
}

class _AdminWebTabsScreenState extends State<AdminWebTabsScreen>
    with WidgetsBindingObserver {
  int get _segment => AdminWebTabsScreen._segment;

  /// The browser is not built until something needs it — a handed-off
  /// link, or him tapping the segment. Building it on first paint would
  /// create a second WebView (and its whole native process attachment)
  /// for a tab he may never open in this session.
  bool _browserEverShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncPower();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Leaving the web tab entirely means no WebView needs to be running.
    unawaited(AdminWebViewPower.setActive(active: false));
    super.dispose();
  }

  /// THE SINGLE ARBITER OF THE GLOBAL PAUSE, and it has to be single.
  ///
  /// WebView.pauseTimers() is process-wide, not per-instance (that is
  /// exactly why it is reachable at all — see AdminWebViewPower). So if
  /// each child called it for its own visibility, hiding the browser
  /// segment would pause the GitHub page that is still on screen. Only
  /// this widget knows both answers, so only this widget calls it.
  ///
  /// Running when: the app is in the foreground AND this bottom tab is
  /// the one showing. Leaving the app entirely -- pressing home,
  /// switching to WhatsApp -- is the case most likely to warm the
  /// phone, because it is the case where nobody is watching.
  ///
  /// Every call is edge-triggered by the OS or by a tap. Nothing polls.
  bool _foreground = true;

  void _syncPower() {
    unawaited(
      AdminWebViewPower.setActive(active: _foreground && widget.visible),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _foreground = state == AppLifecycleState.resumed;
    _syncPower();
  }

  @override
  void didUpdateWidget(AdminWebTabsScreen old) {
    super.didUpdateWidget(old);
    if (old.visible != widget.visible) _syncPower();
  }

  void _select(int index) {
    if (_segment == index) return;
    setState(() {
      AdminWebTabsScreen._segment = index;
      if (index == 1) _browserEverShown = true;
    });
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
                    child: GitHubEmbeddedScreen(
                      key: const ValueKey('github_tab'),
                      visible: widget.visible && _segment == 0,
                      // A link that leaves GitHub is loaded by the
                      // browser; without this it would load correctly
                      // on a segment he cannot see and look like a
                      // dead tap.
                      onHandOffToBrowser: () => _select(1),
                    ),
                  ),
                  if (_browserEverShown)
                    Offstage(
                      offstage: _segment != 1,
                      child: AdminWebBrowserScreen(
                        key: const ValueKey('browser_tab'),
                        visible: widget.visible && _segment == 1,
                        showAppBar: false,
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
            _segmentButton(0, Icons.hub_rounded, 'GitHub'),
            const SizedBox(width: 8),
            _segmentButton(1, Icons.public_rounded, 'Browser'),
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

/// Opens a URL in the admin's own browser segment from anywhere.
///
/// Used by the incoming-link handler in main_admin: a github.com link
/// tapped in Gmail now offers this app, and it should land on the web
/// tab rather than wherever the admin happened to be.
Future<void> openInAdminBrowser(String url) async {
  AdminWebTabsScreen._segment = 1;
  await AdminWebBrowserScreen.open(url);
}
