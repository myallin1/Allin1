// ================================================================
// github_embedded_screen.dart — GitHub, embedded inside the admin
// app, instead of handing off to the phone's browser every time.
// ================================================================
// NEW (Sep 2 2026 — Nizam: "ovvoru time um namma admin app kullaye
// namma GitHub open aganum but ovvoru time um login kekama oru setup
// pannita apdiye work aaganum, athuku antha app vitu veliya poitu
// vanthalum ullapona namma dev and GitHub page um same position la
// stage la irukanum, itha nama app la many places la implement
// pannirukom so atha analyze panni build pannu").
//
// The "many places" pattern he means is DmartEmbeddedView
// (lib/widgets/dmart_embedded_view_native.dart) — a WebView kept
// scoped to one site's own domain family, with Android's third-party
// cookie acceptance turned on so a cross-subdomain login redirect
// (DMart's OTP flow crosses to accounts.dmart.in) still lands its
// session cookie inside this same WebView instead of silently
// dropping it. This screen is that same shape, re-tuned for GitHub's
// domain family instead of DMart's:
//   - github.com itself (the site, and the OAuth/device-flow pages)
//   - *.githubusercontent.com (avatars, raw file content, gists)
//   - *.githubassets.com (GitHub's own static assets/scripts)
// A DMart-style single-root check would have exiled every avatar and
// static asset to the phone's real browser — GitHub's UI genuinely
// spans three separate registrable domains, unlike DMart's one.
//
// "Login kekama" is WebView's own cookie jar doing its normal job:
// Android persists it across app restarts by itself once a real
// browser session cookie lands in it, the same way DmartEmbeddedView
// already relies on for DMart. "Same stage" is just this screen not
// reloading its start URL on re-entry — see _url below, set once in
// initState from the constructor and never re-applied while this
// screen instance is alive.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _text = Color(0xFFEEEEF5);

class GitHubEmbeddedScreen extends StatefulWidget {
  const GitHubEmbeddedScreen({
    super.key,
    this.url = 'https://github.com/myallin1/Allin1/pulls',
    this.title = 'GitHub',
  });

  final String url;
  final String title;

  /// Steps the shared WebView back one page if it has history.
  ///
  /// NEW (Sep 4 2026): needed once this screen became a bottom-nav TAB.
  /// SuperAdminHomeScreen wraps everything in PopScope(canPop: false)
  /// and sends any back press to "return to the Overview tab" -- which
  /// is right for every other tab, and wrong here: while browsing an
  /// issue thread, back should walk GitHub's own history first, exactly
  /// as it does when this screen is pushed. Static because the parent
  /// has no handle on this State, and the controller it acts on already
  /// outlives any single instance anyway.
  static Future<bool> goBackIfPossible() async {
    final c = _GitHubEmbeddedScreenState._sharedController;
    if (c == null) return false;
    try {
      if (await c.canGoBack()) {
        await c.goBack();
        return true;
      }
    } catch (_) {
      // A dead/disposed platform view should fall through to the
      // parent's tab handling, not throw during a back press.
    }
    return false;
  }

  @override
  State<GitHubEmbeddedScreen> createState() => _GitHubEmbeddedScreenState();
}

class _GitHubEmbeddedScreenState extends State<GitHubEmbeddedScreen> {
  static const List<String> _allowedRootDomains = [
    'github.com',
    'githubusercontent.com',
    'githubassets.com',
    'githubcopilot.com',
  ];

  // NEW (Sep 3 2026 — Nizam: "namma app la issue create panni anupitrum
  // bothu namma admin app veliya vanthavo ila vera screen ku potu
  // vanthavo nama vitta stage laye admin app la irukanum").
  //
  // The controller used to be created per-State in initState, which
  // covered two of the three cases he asked about but not the third:
  //
  //   leaving the APP and coming back  -> already fine (the screen
  //       stays on the navigator stack, WebView keeps its page)
  //   logging in once                  -> already fine (cookie jar)
  //   leaving this SCREEN inside the   -> BROKEN: popping disposed the
  //       app and reopening GitHub        controller, so reopening
  //                                       reloaded widget.url from
  //                                       scratch and a half-typed
  //                                       issue was gone.
  //
  // Hoisting the controller to a static makes the WebView outlive any
  // single screen instance, so re-entering re-attaches to the exact
  // page, scroll position and unsubmitted form the admin left behind.
  // WebViewController is platform-backed and independent of the widget
  // tree, so the same instance can legally be handed to a new
  // WebViewWidget — this is the supported way to do it in
  // webview_flutter 4.x.
  //
  // Deliberately never disposed: one WebView for the app's lifetime is
  // the entire point, and Android reclaims it with the process. Only
  // the FIRST screen instance loads a URL (see _isFresh below); later
  // ones inherit whatever page is already open.
  static WebViewController? _sharedController;

  /// The page the admin was last on, remembered across app RESTARTS.
  ///
  /// NEW (Sep 4 2026 — Nizam: "app close pannitu vanthalum" same screen).
  /// _sharedController already survives leaving this screen, but it dies
  /// with the process — Android kills the app and the WebView goes with
  /// it. Persisting just the URL is the honest version of "same place":
  /// scroll position and a half-typed comment genuinely cannot survive a
  /// process death, but landing back on the same issue instead of the PR
  /// list is most of the value and costs one string.
  static const String _kLastUrl = 'github_embedded_last_url';

  late final WebViewController _controller;
  bool _loading = true;

  static bool _isAllowedHost(String host) {
    if (host.isEmpty) return true;
    return _allowedRootDomains.any(
      (root) => host == root || host.endsWith('.$root'),
    );
  }

  @override
  void initState() {
    super.initState();

    final existing = _sharedController;
    final isFresh = existing == null;
    _controller = existing ?? WebViewController();

    // The navigation delegate closes over THIS State's setState, so it
    // is re-installed every time the screen is rebuilt — otherwise the
    // second instance's spinner would be driven by the first (disposed)
    // State and would never turn off.
    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (url) {
            if (mounted) setState(() => _loading = false);
            // Written on every page settle, not on dispose: Android can
            // kill the process without ever calling dispose(), which is
            // exactly the case this is for.
            unawaited(_rememberUrl(url));
          },
          onNavigationRequest: (request) {
            final host = Uri.tryParse(request.url)?.host ?? '';
            if (_isAllowedHost(host)) return NavigationDecision.navigate;
            // A github.com login can hand off to a real IdP (Google/
            // SSO) or a file download link — those are correctly a
            // real browser/download manager's job, not this WebView's.
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
      // widget.url is the fallback, not the default: on a cold start we
      // would rather land the admin back where he was than on the PR
      // list he has already seen. An explicitly-passed url (a deep link
      // to one issue) still wins -- see _restoreOrLoad.
      unawaited(_restoreOrLoad());

      // Same reasoning as DmartEmbeddedView: GitHub's login can redirect
      // across its own subdomains (github.com -> githubusercontent.com
      // for an avatar right after auth) which Android's WebView can
      // treat as a third-party cookie context. Only needs doing once,
      // on the controller that actually gets created.
      final platformController = _controller.platform;
      if (platformController is AndroidWebViewController) {
        unawaited(
          AndroidWebViewCookieManager(
            const PlatformWebViewCookieManagerCreationParams(),
          ).setAcceptThirdPartyCookies(platformController, true),
        );
      }
    } else {
      // Re-entering an already-loaded WebView: nothing is loading, so
      // don't leave the spinner up waiting for an onPageFinished that
      // will never fire.
      _loading = false;
    }
  }

  /// Loads the page the admin was last on, falling back to
  /// [GitHubEmbeddedScreen.url].
  ///
  /// A caller that passes a non-default url means "open THIS", which is
  /// a deliberate deep link and beats the remembered page.
  Future<void> _restoreOrLoad() async {
    var target = widget.url;
    const fallback = 'https://github.com/myallin1/Allin1/pulls';
    if (widget.url == fallback) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString(_kLastUrl);
        if (saved != null && saved.trim().isNotEmpty) target = saved;
      } catch (_) {
        // A prefs failure just means "start at the default" -- never a
        // reason to leave the screen blank.
      }
    }
    await _controller.loadRequest(Uri.parse(target));
  }

  Future<void> _rememberUrl(String url) async {
    if (!_isAllowedHost(Uri.tryParse(url)?.host ?? '')) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastUrl, url);
    } catch (_) {
      // Losing the bookmark is not worth surfacing to the admin.
    }
  }

  Future<bool> _handleBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _handleBack();
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          elevation: 0,
          iconTheme: const IconThemeData(color: _text),
          title: Text(
            widget.title,
            style: GoogleFonts.outfit(
                color: _text, fontWeight: FontWeight.w700, fontSize: 16),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: _text),
              onPressed: () => _controller.reload(),
            ),
            IconButton(
              icon: const Icon(Icons.open_in_browser_rounded, color: _text),
              tooltip: 'Open in browser instead',
              onPressed: () async {
                final current = await _controller.currentUrl();
                if (current == null) return;
                await launchUrl(Uri.parse(current),
                    mode: LaunchMode.externalApplication);
              },
            ),
          ],
          bottom: _loading
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(2),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              : null,
        ),
        body: WebViewWidget(controller: _controller),
      ),
    );
  }
}
