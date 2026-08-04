// ================================================================
// dmart_screen.dart — DMart e-menu, embedded in-app
// ================================================================
// Per Nizam/CTO's approved feature batch: tapping "Order from DMart"
// (see grocery_order_screen.dart's banner) loads DMart's e-menu without
// the customer feeling like they left the app -- this screen keeps our
// own AppBar (with back button + an explicit "Open in browser" escape
// hatch) around the embedded page, exactly like every other screen in
// the app, rather than handing off to an external browser tab.
//
// Platform split (see the two widgets this imports): webview_flutter
// has no web implementation, so native (Android/iOS) uses it directly
// while web/PWA renders a real <iframe> instead. Both are wrapped by
// this same Scaffold either way.
//
// CAVEAT (please read before assuming this "just works" on every
// device): DMart's own website may send security headers
// (X-Frame-Options / CSP frame-ancestors) that block being embedded by
// any other site -- a common anti-clickjacking measure completely
// outside this app's control. If DMart's page shows blank inside this
// screen, that's what's happening, and the "Open in browser" button in
// the app bar is the fallback for that case.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/dmart_embedded_view_web.dart'
    if (dart.library.io) '../widgets/dmart_embedded_view_native.dart';

// DMart's public online-order landing page. Update here if the specific
// Erode store's storefront URL differs from the general DMart Ready URL.
const String kDmartUrl = 'https://www.dmart.in/';

const Color _kBg = Color(0xFFFFFFFF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF9999BB);

class DmartScreen extends StatelessWidget {
  const DmartScreen({super.key});

  Future<void> _openInBrowser(BuildContext context) async {
    final uri = Uri.parse(kDmartUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open DMart. Check your connection.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'DMart',
          style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, color: _kMuted, size: 20),
            tooltip: 'Open in browser',
            onPressed: () => _openInBrowser(context),
          ),
        ],
      ),
      body: const DmartEmbeddedView(url: kDmartUrl),
    );
  }
}
