// ================================================================
// dmart_embedded_view_native.dart — ANDROID/iOS implementation
// ================================================================
// Selected by main_customer's conditional import pattern when
// dart.library.io IS available (native builds) -- see
// dmart_embedded_view_web.dart's counterpart for the web variant and
// dmart_screen.dart for the import switch.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class DmartEmbeddedView extends StatefulWidget {
  final String url;
  const DmartEmbeddedView({required this.url, super.key});

  @override
  State<DmartEmbeddedView> createState() => _DmartEmbeddedViewState();
}

class _DmartEmbeddedViewState extends State<DmartEmbeddedView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    final homeHost = Uri.parse(widget.url).host;
    // FIX (QA bug — "DMart WebView Login Loop"): the same-site check
    // below used to compare against the exact host from the initial
    // URL ('www.dmart.in') via `== homeHost` or `.endsWith('.$homeHost')`
    // (i.e. only accepts hosts literally ending in ".www.dmart.in").
    // DMart's OTP-verification step redirects through an auth/API
    // subdomain (e.g. accounts.dmart.in, api.dmart.in) that is NOT a
    // subdomain of "www.dmart.in" — so that navigation was classified
    // as "external", handed off to launchUrl() into the phone's real
    // browser (a different cookie jar), and the session cookie DMart
    // set there never made it back into this embedded WebView. Symptom
    // matched exactly: OTP sends fine (still on www.dmart.in), but
    // login "drops" and loops back to the start once OTP verification
    // redirects to that other subdomain. Fix: compare against the
    // registrable root domain ("dmart.in") instead of the literal
    // initial host, so every DMart subdomain — not just "www" — is
    // treated as same-site and stays inside this WebView.
    final homeHostParts = homeHost.split('.');
    final homeRootDomain = homeHostParts.length >= 2
        ? homeHostParts.sublist(homeHostParts.length - 2).join('.')
        : homeHost;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // FIX (Nizam's report: "feels like it opens the phone's own
      // internet/browser app"): with no NavigationDelegate at all,
      // Android's WebView falls back to its own default handling for
      // certain navigations inside the page (new-window requests, some
      // redirects) -- which can escalate to launching a full external
      // browser instead of staying inside this embedded view. Keeping
      // navigation within DMart's own domain (and its subdomains) here
      // instead is what makes it actually feel like it never left the
      // app. Anything OFF DMart's domain (a payment gateway, Google
      // Sign-In, etc.) still opens in a real external browser on
      // purpose -- a plain WebView is the wrong place to handle a
      // banking OTP screen.
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final requestHost = Uri.tryParse(request.url)?.host ?? '';
            final sameSite = requestHost.isEmpty ||
                requestHost == homeRootDomain ||
                requestHost.endsWith('.$homeRootDomain');
            if (sameSite) {
              return NavigationDecision.navigate;
            }
            unawaited(
              launchUrl(Uri.parse(request.url), mode: LaunchMode.externalApplication),
            );
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));

    // FIX (QA bug — "DMart Session Fix", CTO mandate item 1 & 2):
    //
    // (1) Third-party cookies: DMart's OTP-verification step sets its
    // session cookie via the cross-subdomain redirect the domain fix
    // above now keeps inside this WebView (accounts.dmart.in etc., a
    // different host than the www.dmart.in the page was first loaded
    // from) -- Android's WebView treats that as a third-party cookie
    // context and can silently refuse to persist it depending on the
    // device's WebView build. Explicitly allow it here. iOS's
    // WKWebView has no equivalent API/concept for this (it doesn't
    // block same-app WebView cookies the way Android historically
    // did), so this call is Android-only, guarded below.
    //
    // (2) DOM storage: CTO asked for an explicit
    // `AndroidWebViewController.setDomStorageEnabled(true)` call here.
    // That method does not exist on webview_flutter_android's
    // AndroidWebViewController (verified against the current 4.13.0
    // API docs) -- DOM storage (localStorage/sessionStorage) has no
    // on/off toggle in this plugin because it is unconditionally
    // enabled by default on both the Android and iOS platform
    // implementations. Confirmed not the cause of the login loop
    // (already true before this fix); no code change possible or
    // needed here.
    final platformController = _controller.platform;
    if (platformController is AndroidWebViewController) {
      unawaited(
        AndroidWebViewCookieManager(
          const PlatformWebViewCookieManagerCreationParams(),
        ).setAcceptThirdPartyCookies(platformController, true),
      );
    }
  }

  // FIX (Nizam's report: pressing back shows a blank page before
  // landing back on the dashboard): with no back-handling at all,
  // every single back press popped this whole screen immediately no
  // matter how deep the customer had navigated inside DMart's site
  // (e.g. into its location picker or a category page) -- Android's
  // WebView was torn down mid-render at that moment, and that half-torn
  // -down frame is the "blank page" flash seen right before the real
  // dashboard appears underneath. Fix: behave like a normal browser's
  // back button -- if DMart's own page has internal history to go back
  // through, go back WITHIN the page first, and only pop this whole
  // screen once there's nothing left to go back to inside DMart itself.
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
      child: WebViewWidget(controller: _controller),
    );
  }
}
