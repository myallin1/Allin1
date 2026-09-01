// ================================================================
// dmart_embedded_view_web.dart — WEB implementation
// ================================================================
// Default variant, selected by main_customer's conditional import
// pattern (this file when dart.library.io is NOT available, i.e. web/
// PWA builds) -- see dmart_screen.dart for the import switch.
//
// webview_flutter (the plugin used on Android/iOS, see
// dmart_embedded_view_native.dart) has no web implementation at all, so
// on web this renders the target URL in a real <iframe> instead, via
// Flutter web's platform-view mechanism. Our own Scaffold (AppBar +
// bottom bar) wraps this, so the app's chrome stays visible around the
// iframe -- exactly the "must not feel like the user left the app"
// requirement.
//
// CAVEAT (flagged, not hidden): many sites -- and DMart's own site is a
// real candidate -- send `X-Frame-Options`/`Content-Security-Policy:
// frame-ancestors` headers that BLOCK being iframed by any other origin,
// as a security measure against clickjacking. If that's the case here,
// the iframe will show a blank area or the browser's own "refused to
// connect" message, and there is no client-side workaround for that --
// it's enforced by the browser honoring headers DMart's server sends,
// not something this app can override. If that happens, the fallback is
// the "Open DMart in browser" button in dmart_screen.dart's app bar.
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class DmartEmbeddedView extends StatefulWidget {
  final String url;
  const DmartEmbeddedView({required this.url, super.key});

  @override
  State<DmartEmbeddedView> createState() => _DmartEmbeddedViewState();
}

class _DmartEmbeddedViewState extends State<DmartEmbeddedView> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType =
        'dmart-iframe-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = web.HTMLIFrameElement()
        ..src = widget.url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
