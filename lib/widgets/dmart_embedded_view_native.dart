// ================================================================
// dmart_embedded_view_native.dart — ANDROID/iOS implementation
// ================================================================
// Selected by main_customer's conditional import pattern when
// dart.library.io IS available (native builds) -- see
// dmart_embedded_view_web.dart's counterpart for the web variant and
// dmart_screen.dart for the import switch.
import 'package:flutter/material.dart';
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
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
