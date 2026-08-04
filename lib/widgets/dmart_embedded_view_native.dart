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
                requestHost == homeHost ||
                requestHost.endsWith('.$homeHost');
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
