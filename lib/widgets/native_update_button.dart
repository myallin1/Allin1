// ================================================================
// NativeUpdateButton — one update affordance, four apps
// Allin1 (Aug 19 2026)
// ================================================================
// The Customer and Hero apps each grew their own copy of "check GitHub
// for a newer release, then show a button that downloads and installs
// the APK". Seller and Admin never got one at all — so a seller could
// sit on a months-old build with no way to know, which at final-build
// stage is the version most likely to be running in a real shop.
//
// This is that behaviour as ONE widget. Dropping a third and fourth
// copy of it into the Seller and Admin dashboards would have been
// faster today and would have guaranteed the four drift apart, exactly
// as the first two already had.
//
// ── WHAT THIS CAN AND CANNOT DO ────────────────────────────────
// It cannot silently update the app. Android does not permit a
// sideloaded APK to install itself without the user confirming at the
// system installer dialog, and there is no flag, permission or trick
// that changes that — REQUEST_INSTALL_PACKAGES (already in the
// manifest) buys the right to SHOW that dialog, not to skip it.
//
// So the honest best case is: one tap here, one tap on the system
// "Install", one tap on "Open". Genuinely automatic updates require
// Play Store distribution and its In-App Update API.
//
// Everything below is therefore built to make those three taps as
// obvious and as hard to get wrong as possible.
//
// ── FAIL-SILENT BY DESIGN ──────────────────────────────────────
// If the version check fails for ANY reason — offline, GitHub down,
// rate-limited, malformed tag — the widget renders nothing at all.
// A broken update checker must never become a broken-looking app bar,
// and a false "update available" badge is worse than no badge: it
// trains people to ignore the real one.
// ================================================================

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/app_update_checker.dart';

class NativeUpdateButton extends StatefulWidget {
  /// 'customer' | 'hero' | 'seller' | 'admin'. Selects which APK is
  /// fetched — see UpdateService.fallbackApkUrl.
  final String appVariant;

  /// Tint for the badge. Defaults to the app-bar-safe amber that reads
  /// as "attention" without looking like an error.
  final Color color;

  const NativeUpdateButton({
    super.key,
    required this.appVariant,
    this.color = const Color(0xFFFFBB00),
  });

  @override
  State<NativeUpdateButton> createState() => _NativeUpdateButtonState();
}

class _NativeUpdateButtonState extends State<NativeUpdateButton> {
  bool _available = false;
  bool _busy = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    // Web/PWA has its own service-worker update path (see
    // WebVersionChecker); an APK button there would download an
    // Android package into a browser. isUpdateAvailable() already
    // returns false on web, but returning early here also skips the
    // network call entirely.
    if (kIsWeb) return;
    try {
      final has = await AppUpdateChecker().isUpdateAvailable();
      if (mounted && has) setState(() => _available = true);
    } catch (_) {
      // Fail silent — see the header.
    }
  }

  Future<void> _install() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = 0;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final downloaded = await AppUpdateChecker().downloadAndInstall(
        appVariant: widget.appVariant,
        onProgress: (p) {
          // Progress is shown because these APKs are tens of megabytes
          // over an Erode mobile connection. Without it, a 40-second
          // download looks like a button that did nothing, and people
          // tap it again — which the checker's _isDownloading guard
          // absorbs, but which still reads as broken.
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      if (downloaded) {
        // The APK is on the phone and Android's installer has been
        // handed the file. The install itself is now the user's to
        // confirm, so we stop claiming ownership of it.
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Tap Install on the next screen to finish updating'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        // AUDIT FIX (Sep 5 2026 — Play Store eligibility): a
        // Play-installed user was just sent to the Play Store listing
        // instead of getting a raw APK. "Tap Install on the next
        // screen" would be flatly wrong here — there is no next screen
        // in THIS app, they are looking at a different app entirely.
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Opening Play Store — tap Update there'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('[NativeUpdateButton] ${widget.appVariant} update failed: $e');
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Update download failed. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to say — take up no space at all rather than rendering a
    // disabled or "up to date" control. An always-present update button
    // that usually does nothing is what made the old customer-app
    // version meaningless.
    if (!_available) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: _busy ? null : _install,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: widget.color.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    // Indeterminate until the server reports a total
                    // length; a bar stuck at 0% looks more broken than
                    // a spinner.
                    value: _progress > 0 ? _progress : null,
                    valueColor: AlwaysStoppedAnimation<Color>(widget.color),
                  ),
                )
              else
                Icon(Icons.system_update_rounded,
                    size: 15, color: widget.color),
              const SizedBox(width: 5),
              Text(
                _busy
                    ? (_progress > 0
                        ? '${(_progress * 100).toInt()}%'
                        : 'Downloading')
                    : 'Update',
                style: TextStyle(
                  color: widget.color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
