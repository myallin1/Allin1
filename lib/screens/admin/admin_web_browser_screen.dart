// ================================================================
// admin_web_browser_screen.dart — a real browser, inside the app
// ================================================================
// NEW (Sep 5 2026 — Nizam: "admin valiya GitHub browser-la supera work
// aguthu but password maranthu reset panna varumbothu password-ku vera
// browser open panna solluthu ... GitHub-ku pakkathulaye browser-um
// onnu namma app-la").
//
// WHAT ACTUALLY WENT WRONG, BECAUSE IT IS NOT WHAT IT LOOKS LIKE
// The screenshot shows Gmail's app chooser, not our WebView. Two
// separate failures were stacked on top of each other:
//
//   1. Inside the app: GitHubEmbeddedScreen's navigation delegate sends
//      every non-github.com host to an EXTERNAL browser. That was the
//      right call when GitHub was the only thing in the app — an IdP
//      redirect or a file download genuinely belongs to a real browser.
//      But a password reset lands on a host outside the allowlist, so
//      the one flow that most needs to stay in the app was the one
//      guaranteed to leave it. It now lands HERE instead.
//
//   2. Outside the app: the reset link was tapped in Gmail, and Android
//      offered Chrome and the system browser because this app declares
//      no https intent-filter. Fixed in AndroidManifest — deliberately
//      scoped to github.com only. Registering for all https would put
//      this app in the chooser for every link on his phone, which is a
//      far worse outcome than the problem being solved.
//
// BATTERY AND HEAT — THE PART THAT NEEDED REAL WORK
// He asked for this explicitly, and a kept-alive WebView is genuinely
// one of the worst offenders in a mobile app. Two different costs, and
// they need two different fixes:
//
//   * COMPOSITING. A mounted WebViewWidget is a platform view the
//     engine composites EVERY FRAME, even when it is covered by another
//     tab. That is continuous GPU work for something nobody can see.
//     Fixed by unmounting the widget when the tab is not visible while
//     keeping the CONTROLLER alive — the page stays loaded, only the
//     surface goes away, so switching back is instant and costs
//     nothing while hidden.
//
//   * JAVASCRIPT AND TIMERS. Unmounting does NOT stop the page's own
//     setInterval/animation work; GitHub's live-update polling would
//     keep running and keep the radio and CPU awake behind a screen he
//     is not looking at. webview_flutter exposes no pause API at all,
//     so this goes through a tiny native channel to WebView.pauseTimers
//     (documented as process-global, not per-instance, which is exactly
//     what is wanted here). See AdminWebViewPower.
//
// The two together are the difference between "a tab you left open" and
// "a tab that is still working". Nothing here polls, and nothing runs
// on a timer of its own.
//
// CACHE, HONESTLY
// Nizam asked for Hive caching so the last state paints instantly. Hive
// is the wrong tool for this one and it would be dishonest to pretend
// otherwise: it stores Dart objects, and a rendered web page is not
// one. What actually delivers that behaviour is already there — the
// WebView's OWN disk cache serves the page body without a network round
// trip, and the controller staying alive means the tab is not even
// reloaded. What persists across a process kill is the URL, in
// SharedPreferences, which is the honest version of "same place": a
// scroll position and a half-typed comment cannot survive being killed,
// but landing back on the same page is most of the value for one
// string. Pull-to-refresh is wired for when he wants the network.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

const Color _bg = Color(0xFF0E0E1A);
const Color _surface = Color(0xFF1A1A2E);
const Color _text = Color(0xFFE8E8F0);
const Color _muted = Color(0xFF8A8AA3);

/// The in-app browser tab.
///
/// [visible] is what makes the battery story work: when false the
/// WebView surface is torn down and the page's timers are paused, while
/// the controller — and therefore the loaded page, its cookies and its
/// history — stays exactly where it was.
class AdminWebBrowserScreen extends StatefulWidget {
  const AdminWebBrowserScreen({
    super.key,
    this.initialUrl,
    this.visible = true,
    this.showAppBar = true,
  });

  /// Opens this immediately, beating the remembered page. Used when the
  /// GitHub tab hands a link over.
  final String? initialUrl;

  final bool visible;

  /// False when embedded as a segment of another screen that already
  /// has its own AppBar.
  final bool showAppBar;

  static const String homePage = 'https://github.com/myallin1/Allin1';

  /// Hands a URL to the browser tab from anywhere else in the app.
  ///
  /// Static because the caller (the GitHub tab's navigation delegate)
  /// has no handle on this State, and the controller outlives any
  /// single instance anyway.
  static Future<void> open(String url) async {
    // AUDIT FIX (Sep 5 2026): the first version added the url to a queue
    // AND loaded it immediately, then never removed it — so the next
    // rebuild drained the same entry and navigated a second time, on top
    // of wherever the admin had since browsed. One pending slot, cleared
    // by whoever consumes it, is the whole fix.
    _pendingUrl = url;
    final live = _AdminWebBrowserScreenState._live;
    if (live != null && live.mounted) await live._consumePending();
  }

  /// The one link waiting to be shown, if any.
  ///
  /// Survives the browser not existing yet: a github.com link tapped in
  /// Gmail on a COLD START arrives long before this widget is built, and
  /// dropping it would look exactly like the app ignoring the tap.
  static String? _pendingUrl;

  /// True once a link has been handed over or the segment tapped.
  ///
  /// AUDIT FIX: openInAdminBrowser used to switch to the browser segment
  /// without this, and the segment only builds its child after a tap —
  /// so a cold-start link landed on a blank screen.
  static bool wanted = false;

  /// Steps the browser back if it has history — same contract as
  /// GitHubEmbeddedScreen.goBackIfPossible, for the parent's PopScope.
  static Future<bool> goBackIfPossible() async {
    final c = _AdminWebBrowserScreenState._sharedController;
    if (c == null) return false;
    try {
      if (await c.canGoBack()) {
        await c.goBack();
        return true;
      }
    } catch (_) {
      // Fall through to the parent's tab handling rather than throwing
      // during a back press.
    }
    return false;
  }

  @override
  State<AdminWebBrowserScreen> createState() => _AdminWebBrowserScreenState();
}

class _AdminWebBrowserScreenState extends State<AdminWebBrowserScreen> {
  /// Survives this screen being popped or its tab being hidden. Dies
  /// with the process, which is what [_kLastUrl] is for.
  static WebViewController? _sharedController;

  /// The mounted State, so a link handed over while the browser is
  /// already on screen loads immediately instead of waiting for a
  /// rebuild that may never come.
  static _AdminWebBrowserScreenState? _live;

  static const String _kLastUrl = 'admin_browser_last_url';

  late final WebViewController _controller;
  final TextEditingController _urlField = TextEditingController();

  /// AUDIT FIX (Sep 5 2026): _editingUrl was set on tap and cleared only
  /// by submitting. Tap the address bar, change your mind, tap the page
  /// — the flag stayed true and the bar never showed another URL again
  /// for the life of the app. Focus is the signal, not the tap.
  final FocusNode _urlFocus = FocusNode();

  bool _loading = true;
  bool _editingUrl = false;
  bool _refreshing = false;

  /// Where a drag started, and whether the page was scrolled to the top
  /// when it did. Only an over-scroll from the very top means "refresh";
  /// anywhere else it is ordinary page scrolling and must be left alone.
  double? _pullStartY;
  bool _pullFromTop = false;
  int _progress = 0;
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();

    _urlFocus.addListener(() {
      if (_urlFocus.hasFocus) {
        setState(() => _editingUrl = true);
      } else {
        setState(() {
          _editingUrl = false;
          _urlField.text = _pretty(_currentUrl);
        });
      }
    });

    final existing = _sharedController;
    final isFresh = existing == null;
    _controller = existing ?? WebViewController();

    // Re-installed on every build of this State, not just the first:
    // the delegate closes over THIS State's setState, and a second
    // instance driven by the first (disposed) State would sit on a
    // spinner that never turns off.
    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _currentUrl = url;
              if (!_editingUrl) _urlField.text = _pretty(url);
            });
          },
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _refreshing = false;
              _currentUrl = url;
              if (!_editingUrl) _urlField.text = _pretty(url);
            });
            // Written on every page settle rather than in dispose():
            // Android can kill the process without ever calling
            // dispose(), which is precisely the case this is for.
            unawaited(_rememberUrl(url));
          },
          onNavigationRequest: (request) {
            final scheme = Uri.tryParse(request.url)?.scheme ?? '';
            // A real browser handles http(s). Anything else — tel:,
            // mailto:, upi:, intent: — belongs to the app that owns it,
            // and a WebView cannot render it anyway.
            if (scheme == 'http' || scheme == 'https') {
              return NavigationDecision.navigate;
            }
            unawaited(
              launchUrl(Uri.parse(request.url),
                  mode: LaunchMode.externalApplication),
            );
            return NavigationDecision.prevent;
          },
        ),
      );

    if (isFresh) {
      _sharedController = _controller;
      unawaited(_restoreOrLoad());

      // Same reasoning as the GitHub tab: a login can redirect across
      // sibling domains (github.com -> githubusercontent.com right
      // after auth) which Android's WebView treats as a third-party
      // cookie context. Only needs doing on the controller that is
      // actually created.
      final platform = _controller.platform;
      if (platform is AndroidWebViewController) {
        unawaited(
          AndroidWebViewCookieManager(
            const PlatformWebViewCookieManagerCreationParams(),
          ).setAcceptThirdPartyCookies(platform, true),
        );
      }
    } else {
      // Re-entering an already-loaded page: nothing is in flight, so
      // don't leave a spinner waiting for an onPageFinished that will
      // never fire.
      _loading = false;
      unawaited(_syncUrlFromController());
    }

    _live = this;
    unawaited(_consumePending());
  }

  @override
  void didUpdateWidget(AdminWebBrowserScreen old) {
    super.didUpdateWidget(old);
    if (widget.visible) unawaited(_consumePending());
  }

  /// Loads the waiting link, if there is one, and clears it so it can
  /// never be replayed by a later rebuild.
  Future<void> _consumePending() async {
    final url = AdminWebBrowserScreen._pendingUrl;
    if (url == null) return;
    AdminWebBrowserScreen._pendingUrl = null;
    try {
      await _controller.loadRequest(Uri.parse(url));
    } catch (e) {
      debugPrint('[AdminBrowser] could not open handed-off link: $e');
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    _pullStartY = e.position.dy;
    _pullFromTop = false;
    // Asked once per gesture rather than on every move: getScrollPosition
    // is a platform-channel round trip, and one per frame during a drag
    // is exactly the kind of cost this screen is supposed to avoid.
    unawaited(() async {
      try {
        final pos = await _controller.getScrollPosition();
        if (mounted) _pullFromTop = pos.dy <= 1;
      } catch (_) {
        _pullFromTop = false;
      }
    }());
  }

  void _onPointerMove(PointerMoveEvent e) {
    final start = _pullStartY;
    if (start == null || !_pullFromTop || _refreshing) return;
    if (e.position.dy - start < 110) return;
    _pullStartY = null;
    setState(() => _refreshing = true);
    unawaited(
      _controller.reload().whenComplete(() {
        // onPageFinished clears the bar; this is the belt for a load
        // that errors out and never finishes.
        Future<void>.delayed(const Duration(seconds: 3), () {
          if (mounted && _refreshing) setState(() => _refreshing = false);
        });
      }),
    );
  }

  Future<void> _syncUrlFromController() async {
    try {
      final url = await _controller.currentUrl();
      if (url != null && mounted) {
        setState(() {
          _currentUrl = url;
          if (!_editingUrl) _urlField.text = _pretty(url);
        });
      }
    } catch (_) {
      // A missing URL just means an empty address bar.
    }
  }

  Future<void> _restoreOrLoad() async {
    // AUDIT FIX: this reads prefs, so it finishes AFTER a synchronous
    // handoff load and used to overwrite it with the remembered page —
    // the handed-off link flashed up and then vanished.
    if (AdminWebBrowserScreen._pendingUrl != null) return;
    var target = widget.initialUrl;
    if (target == null || target.trim().isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString(_kLastUrl);
        target = (saved != null && saved.trim().isNotEmpty)
            ? saved
            : AdminWebBrowserScreen.homePage;
      } catch (_) {
        target = AdminWebBrowserScreen.homePage;
      }
    }
    await _controller.loadRequest(Uri.parse(target));
  }

  Future<void> _rememberUrl(String url) async {
    // about:blank and data: URLs are transient states, not places —
    // remembering one would restore a blank screen on next launch.
    if (!url.startsWith('http')) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastUrl, url);
    } catch (_) {
      // Losing the bookmark is not worth surfacing to the admin.
    }
  }

  /// Strips the scheme for display. The full URL is still what gets
  /// loaded and what the padlock check should be made against — this is
  /// only to stop "https://" eating a third of a phone-width field.
  static String _pretty(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return url;
    final shown = url.replaceFirst(RegExp('^https?://'), '');
    return shown.isEmpty ? url : shown;
  }

  /// Turns whatever was typed into something loadable. A bare domain
  /// becomes https; anything with a space becomes a search, because a
  /// browser that errors on "flutter webview pause" is not a browser.
  static Uri _resolveInput(String raw) {
    final input = raw.trim();
    if (input.isEmpty) return Uri.parse(AdminWebBrowserScreen.homePage);
    if (input.startsWith('http://') || input.startsWith('https://')) {
      return Uri.parse(input);
    }
    final looksLikeHost =
        !input.contains(' ') && RegExp(r'^[\w.-]+\.\w{2,}(/.*)?$').hasMatch(input);
    if (looksLikeHost) return Uri.parse('https://$input');
    return Uri.parse(
        'https://www.google.com/search?q=${Uri.encodeQueryComponent(input)}');
  }

  Future<void> _go(String raw) async {
    _urlFocus.unfocus();
    await _controller.loadRequest(_resolveInput(raw));
  }

  Future<bool> handleBack() async {
    try {
      if (await _controller.canGoBack()) {
        await _controller.goBack();
        return false;
      }
    } catch (_) {
      // Treat a dead view as "nothing to go back to".
    }
    return true;
  }

  @override
  void dispose() {
    if (_live == this) _live = null;
    _urlFocus.dispose();
    _urlField.dispose();
    // Deliberately NOT clearing _sharedController: the whole point is
    // that the page survives leaving the tab.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        _addressBar(),
        if (_loading)
          LinearProgressIndicator(
            minHeight: 2,
            value: _progress > 0 && _progress < 100 ? _progress / 100 : null,
          ),
        Expanded(
          // THE BATTERY FIX, and it is this one line as much as the
          // native channel: a hidden platform view is still composited
          // every frame. Keeping the controller but dropping the widget
          // means the page is still loaded and still logged in, and
          // costs nothing at all while another tab is on screen.
          child: widget.visible
              ? Stack(
                  children: [
                    // AUDIT FIX (Sep 5 2026): pull-to-refresh was wired
                    // as a RefreshIndicator over a throwaway ListView
                    // sitting BEHIND the WebView. A widget behind a
                    // platform view never receives a single pointer, so
                    // the gesture was dead on arrival and the feature
                    // silently did nothing.
                    //
                    // A Listener is the right tool precisely because it
                    // does NOT enter the gesture arena — it observes raw
                    // pointers without competing, so the page still
                    // scrolls, zooms and taps exactly as before while
                    // this watches for an over-scroll at the top.
                    Listener(
                      onPointerDown: _onPointerDown,
                      onPointerMove: _onPointerMove,
                      onPointerUp: (_) => _pullStartY = null,
                      onPointerCancel: (_) => _pullStartY = null,
                      child: WebViewWidget(controller: _controller),
                    ),
                    if (_refreshing)
                      const Positioned(
                        top: 10,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          ),
                        ),
                      ),
                  ],
                )
              : const ColoredBox(color: _bg),
        ),
      ],
    );

    if (!widget.showAppBar) return body;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await handleBack();
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          elevation: 0,
          iconTheme: const IconThemeData(color: _text),
          title: Text(
            'Browser',
            style: GoogleFonts.outfit(
                color: _text, fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
        body: body,
      ),
    );
  }

  Widget _addressBar() {
    return Container(
      color: _bg,
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: _muted, size: 20),
            tooltip: 'Back',
            onPressed: () async {
              if (await _controller.canGoBack()) await _controller.goBack();
            },
          ),
          Expanded(
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(19),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    _currentUrl.startsWith('https://')
                        ? Icons.lock_rounded
                        : Icons.lock_open_rounded,
                    size: 13,
                    // Not decoration: this is the one signal that says
                    // whether a password typed on this page is going
                    // somewhere encrypted.
                    color: _currentUrl.startsWith('https://')
                        ? const Color(0xFF00C853)
                        : const Color(0xFFFF6B35),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _urlField,
                      focusNode: _urlFocus,
                      onSubmitted: _go,
                      textInputAction: TextInputAction.go,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      style: GoogleFonts.outfit(color: _text, fontSize: 12.5),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Search or type a link',
                        hintStyle:
                            GoogleFonts.outfit(color: _muted, fontSize: 12.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // AUDIT FIX: this offered a "Stop" that called reload() on
          // both branches — pressing stop RESTARTED the load. There is
          // no stopLoading anywhere in webview_flutter 4.x, so the
          // honest fix is to not pretend: one reload button, always.
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _muted, size: 20),
            tooltip: 'Reload',
            onPressed: () => unawaited(_controller.reload()),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: _muted, size: 20),
            color: _surface,
            onSelected: (v) async {
              switch (v) {
                case 'forward':
                  if (await _controller.canGoForward()) {
                    await _controller.goForward();
                  }
                case 'home':
                  await _controller
                      .loadRequest(Uri.parse(AdminWebBrowserScreen.homePage));
                case 'external':
                  if (_currentUrl.isNotEmpty) {
                    await launchUrl(Uri.parse(_currentUrl),
                        mode: LaunchMode.externalApplication);
                  }
              }
            },
            itemBuilder: (_) => [
              _menuItem('forward', Icons.arrow_forward_rounded, 'Forward'),
              _menuItem('home', Icons.home_rounded, 'Home'),
              _menuItem('external', Icons.open_in_new_rounded, 'Open in Chrome'),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) =>
      PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 16, color: _muted),
            const SizedBox(width: 10),
            Text(label, style: GoogleFonts.outfit(color: _text, fontSize: 13)),
          ],
        ),
      );
}
