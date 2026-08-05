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
//
// NEW (CTO mandate — Dual-Mode Grocery Cart, Mode 3 "I Need This"):
// this file was converted from StatelessWidget to StatefulWidget to
// hold the "processing" flag for the new FAB below — everything above
// (AppBar, back button, "Open in browser", the embedded view itself)
// is byte-identical in behavior to before, just moved into a State
// class. Read the FAB's own comment for why this is a photo-attach
// flow rather than a literal invisible screen-capture — the embedded
// view above is a genuine cross-origin <iframe> on web, and browsers
// flatly refuse to let any page read another origin's pixels/DOM
// (same-origin policy) — this is not a shortcut, it's a hard security
// wall no client-side code can get around, on any site's app, ever.
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/ai_activation_service.dart';
import '../services/grocery_ai_notes_service.dart';
import '../services/guru_api_service.dart';
import '../widgets/dmart_embedded_view_web.dart'
    if (dart.library.io) '../widgets/dmart_embedded_view_native.dart';
import 'grocery_order_screen.dart';

// DMart's public online-order landing page. Update here if the specific
// Erode store's storefront URL differs from the general DMart Ready URL.
const String kDmartUrl = 'https://www.dmart.in/';

const Color _kBg = Color(0xFFFFFFFF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF9999BB);
const Color _kPink = Color(0xFFFF4FA3);

class DmartScreen extends StatefulWidget {
  const DmartScreen({super.key});

  @override
  State<DmartScreen> createState() => _DmartScreenState();
}

class _DmartScreenState extends State<DmartScreen> {
  bool _processing = false;

  Future<void> _openInBrowser(BuildContext context) async {
    final uri = Uri.parse(kDmartUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open DMart. Check your connection.')),
      );
    }
  }

  // NEW (CTO mandate — Dual-Mode Grocery Cart, Mode 3): the honest,
  // buildable version of "capture the current screen context". A
  // cross-origin iframe's pixels are not readable from this app on
  // web (browser security, not our limitation — see file header), so
  // instead of pretending to auto-capture, this asks the customer for
  // their OWN device screenshot (which the OS captures fine, since
  // that's outside the browser's same-origin sandbox) and reads it
  // with the same vision pipeline guru_chat_screen.dart already uses
  // for screenshot troubleshooting. Reuses file_picker (already a
  // dependency, already used for exactly this "pick a screenshot" job
  // in grocery_order_screen.dart) rather than adding a second image
  // package.
  Future<void> _captureAndAddItem() async {
    if (_processing) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Take a screenshot of what you want (your device\'s screenshot '
            'shortcut), then pick it in the next step.'),
        duration: Duration(seconds: 4),
      ),
    );

    setState(() => _processing = true);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      final bytes = result?.files.single.bytes;
      if (bytes == null) return; // cancelled

      final compressed = _compress(bytes) ?? bytes;
      final apiKey = mounted ? context.read<AiActivationService>().apiKey : '';
      if (apiKey.trim().isEmpty) {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text("Guru AI isn't available on your account yet.")),
        );
        return;
      }

      final extracted = await GuruApiService().extractGroceryItemFromImage(
        imageBytes: compressed,
        apiKeyOverride: apiKey,
      );
      if (extracted == null) {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't read a product from that photo — please type it "
              'into the grocery list instead.')),
        );
        return;
      }

      final item = extracted['item'] ?? '';
      final quantity = extracted['quantity'];
      GroceryAiNotesService.instance.addItem(item, quantity: (quantity?.isEmpty ?? true) ? null : quantity);

      if (!mounted) return;
      final label = (quantity != null && quantity.isNotEmpty) ? '$quantity $item' : item;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Added "$label" to your grocery list.'),
          action: SnackBarAction(
            label: 'REVIEW',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const GroceryOrderScreen()),
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Something went wrong: $e')));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  // Same decode/resize/re-encode approach as guru_chat_screen.dart's
  // _compressForVision (duplicated rather than shared — that method is
  // private to that State class; this keeps the two screens
  // independently simple rather than introducing a shared-utility
  // refactor of already-working code).
  Uint8List? _compress(Uint8List rawBytes) {
    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) return null;
      final resized = decoded.width > 800 || decoded.height > 800
          ? img.copyResize(
              decoded,
              width: decoded.width >= decoded.height ? 800 : null,
              height: decoded.height > decoded.width ? 800 : null,
            )
          : decoded;
      return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
    } catch (e) {
      debugPrint('[DmartScreen] compression failed: $e');
      return null;
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
      // NEW (CTO mandate — Dual-Mode Grocery Cart, Mode 3): purely
      // additive — the body/AppBar above are unchanged, this just adds
      // a new FAB on top.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _processing ? null : _captureAndAddItem,
        backgroundColor: _kPink,
        icon: _processing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.camera_alt_rounded, color: Colors.white),
        label: Text(
          _processing ? 'Reading...' : 'I Need This',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
