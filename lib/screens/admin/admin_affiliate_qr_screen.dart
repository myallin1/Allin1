// ================================================================
// admin_affiliate_qr_screen.dart — Affiliate QR Generator
// ================================================================
// NEW (Aug 12 2026 — Nizam: "oru super affiliate marketing qr generater
// system ah namma app la build pannu... qr monkey ke tough kudukuramari
// irukanum nammaloda qr generator and qr affilate generator"): the
// general-purpose sibling of AdminQrGeneratorScreen (which only ever
// makes ONE hardcoded poster QR). This screen:
//   1. Generates any number of trackable affiliate/referral QR codes —
//      one per hero-recruitment agent, customer growth campaign, or
//      seller-onboarding field agent (the 3 affiliate types Nizam
//      confirmed) — each with its own short code and live scan/signup
//      counters (see AffiliateService).
//   2. Gives full visual customization matching the reference site
//      (app.qr-code-generator.com): foreground/background hex colors,
//      module dot shape, and corner "eye" shape — all via qr_flutter's
//      own vector rendering, so this stays as fast/cheap as the
//      existing poster QR screen (zero extra network calls).
//   3. Shows a live dashboard of every code ever generated with its
//      scans and signups, so Nizam can see which agent/campaign is
//      actually converting — the part QR Monkey and most free QR sites
//      don't offer at all without a paid plan.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/affiliate_service.dart';
import 'admin_campaign_detail_screen.dart';
import '../../services/qr_image_saver_stub.dart'
    if (dart.library.html) '../../services/qr_image_saver_web.dart';

const Color _bg = Color(0xFF0A0A12);
const Color _card = Color(0xFF141420);
const Color _border = Color(0xFF262636);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _pink = Color(0xFFFF4FA3);
const Color _green = Color(0xFF00C853);
// Inline validation feedback on the custom-slug field (Aug 17 2026).
const Color _red = Color(0xFFFF5252);

// NEW (Aug 13 2026 — dynamic QR): the printed code now encodes the
// /q/?c=CODE short link (see web/q/index.html) instead of the campaign
// destination itself. That indirection is what makes the QR editable
// after printing — see AffiliateService.updateDestination().
//
// The base URL constant that used to live here was removed with that
// change: AffiliateService.kAppBaseUrl is now the single source of
// truth, so the app URL can never drift between the generator and the
// redirect page.

const List<Color> _kColorPresets = [
  Colors.black,
  _pink,
  Color(0xFF6C3CE9),
  Color(0xFF0A2540),
  _green,
  Color(0xFFFF8A00),
];

/// What sits in the middle of the QR. See _logoMode in the state class
/// for why 'brand' is drawn programmatically rather than from an asset.
enum _LogoMode { none, brand, custom }

enum _AffiliateType { hero, customer, seller }

extension on _AffiliateType {
  String get value => switch (this) {
        _AffiliateType.hero => 'hero',
        _AffiliateType.customer => 'customer',
        _AffiliateType.seller => 'seller',
      };
  String get label => switch (this) {
        _AffiliateType.hero => 'Hero Recruitment',
        _AffiliateType.customer => 'Customer Referral',
        _AffiliateType.seller => 'Seller Onboarding',
      };
  IconData get icon => switch (this) {
        _AffiliateType.hero => Icons.emoji_people_rounded,
        _AffiliateType.customer => Icons.campaign_rounded,
        _AffiliateType.seller => Icons.storefront_rounded,
      };
}

class AdminAffiliateQrScreen extends StatefulWidget {
  const AdminAffiliateQrScreen({super.key});

  @override
  State<AdminAffiliateQrScreen> createState() => _AdminAffiliateQrScreenState();
}

class _AdminAffiliateQrScreenState extends State<AdminAffiliateQrScreen> {
  final GlobalKey _qrBoundaryKey = GlobalKey();
  final TextEditingController _labelController = TextEditingController();

  /// Optional readable slug for the printed link (Aug 17 2026). Blank =
  /// the original random 6-char code, so this is purely additive.
  final TextEditingController _slugController = TextEditingController();
  final TextEditingController _shareMessageController = TextEditingController(
    text: 'Welcome to Allin1 Super App! Here is your onboarding link:',
  );

  _AffiliateType _type = _AffiliateType.hero;
  bool _busy = false;
  bool _roundedShape = false;
  bool _roundedEyes = false;
  Color _fgColor = Colors.black;
  Color _bgColor = Colors.white;
  String? _statusMessage;

  // ── Centre logo (Aug 13 2026 — Nizam: "qr generate pannurathulayum qr
  // center la logo image vachu build pannikuramari system venum") ─────
  //
  // Two distinct rendering paths, deliberately:
  //   _LogoMode.brand  -> the programmatic MyAllin1 mark drawn in the
  //                       Stack below. Needs no asset file (there is no
  //                       brand PNG in assets/), so it can never break.
  //   _LogoMode.custom -> a real uploaded image handed to qr_flutter's
  //                       embeddedImage, which paints it INTO the QR
  //                       (correctly centred, and captured by the same
  //                       RepaintBoundary used for PNG export/share).
  _LogoMode _logoMode = _LogoMode.brand;
  Uint8List? _logoBytes;
  String? _logoName;

  /// Logo width as a fraction of QR width. SCANNABILITY MATH: error
  /// correction level H recovers ~30% of the code's AREA. A centred
  /// square logo of width f covers f² of the area — so 0.20 -> 4%,
  /// 0.25 -> 6.25%, 0.30 -> 9%. All are comfortably inside the budget,
  /// which is why the slider is capped at 0.30 rather than left open:
  /// past that the quiet-zone and finder patterns start to suffer for
  /// reasons error correction cannot fix.
  double _logoScale = 0.22;

  /// Thickness of the white ring around a custom logo, as a fraction of
  /// the LOGO's width (0.10 = a 5% ring on each side).
  ///
  /// Ratio-of-logo, not ratio-of-QR (Aug 17 2026 — Nizam: "logo outer la
  /// oru white box overa vanthturuthu... logo suththi oralavuku white
  /// border vantha pothum"). The old code sized the patch off the QR
  /// width, so shrinking the logo did not shrink its white surround —
  /// at small logo sizes the box dwarfed the logo inside it.
  ///
  /// Do not set this to 0. The ring is functional: it gives scanners a
  /// clean boundary where a transparent or non-square PNG would
  /// otherwise leave half-covered dark modules showing.
  static const double _kLogoBorderRatio = 0.10;

  double get _logoAreaPct => _logoScale * _logoScale * 100;

  Widget _logoModeChip(String label, _LogoMode mode) {
    final on = _logoMode == mode;
    return GestureDetector(
      onTap: () {
        // Selecting Custom with nothing uploaded opens the picker
        // straight away rather than silently doing nothing.
        if (mode == _LogoMode.custom && _logoBytes == null) {
          _pickLogo();
          return;
        }
        setState(() => _logoMode = mode);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on ? _pink : _card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? _pink : _border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: on ? Colors.white : _muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<void> _pickLogo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.first;
      if (f.bytes == null) return;
      if (!mounted) return;
      setState(() {
        _logoBytes = f.bytes;
        _logoName = f.name;
        _logoMode = _LogoMode.custom;
        _statusMessage = 'Logo added — check the preview still scans.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Could not load that image: $e');
    }
  }

  // The most recently generated code — shown large in the preview card.
  String? _activeCode;
  _AffiliateType? _activeType;
  String? _activeLabel;

  @override
  void dispose() {
    _labelController.dispose();
    _slugController.dispose();
    _shareMessageController.dispose();
    super.dispose();
  }

  // UPDATED (Aug 13 2026): encodes the DYNAMIC short link, not the
  // destination. Previously this baked ?ref=CODE&rtype=... straight into
  // the printed QR, which meant the destination was frozen the moment
  // the poster went to the printer. Now it points at /q/?c=CODE, which
  // looks the code up at scan time — so a campaign can be repointed,
  // paused or resumed forever without reprinting anything.
  String get _activeUrl =>
      _activeCode == null ? '' : AffiliateService.shortUrlFor(_activeCode!);

  Future<void> _generateCode() async {
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      setState(() => _statusMessage = 'Enter a name/label for this affiliate first.');
      return;
    }

    // CUSTOM SLUG (Aug 17 2026 — Nizam: "antha link customer panic
    // aackuramari text back la varuthu... decentana extension words
    // naane customize pandramari link venum").
    //
    // Optional. Left blank, the random 6-char generator runs exactly as
    // before, so nothing about the existing flow changes.
    String? customCode;
    final rawCustom = _slugController.text.trim();
    if (rawCustom.isNotEmpty) {
      customCode = AffiliateService.normalizeCustomCode(rawCustom);
      if (customCode == null) {
        setState(() => _statusMessage =
            'Custom link must be 3–32 characters, letters/numbers/hyphens, '
            'and include at least one letter. Words like "verify", "otp" or '
            '"payment" are blocked — they make a link look like a scam.');
        return;
      }
    }

    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final adminUid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown_admin';

      // Checked here, not inside the service, so the admin gets a clear
      // "already taken" instead of silently overwriting a live campaign
      // (which would repoint its QR and merge its scan counts).
      if (customCode != null &&
          !await AffiliateService.instance.isCodeAvailable(customCode)) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _statusMessage =
              '"$customCode" is already in use by another campaign. '
              'Try a different word.';
        });
        return;
      }

      String destination = 'https://erode-super-app.web.app/';
      if (_type == _AffiliateType.hero) {
        destination = 'https://hero-allin1.web.app/';
      } else if (_type == _AffiliateType.seller) {
        destination = 'https://grow-allin1.web.app/';
      }

      final code = await AffiliateService.instance.createAffiliateCode(
        type: _type.value,
        label: label,
        createdBy: adminUid,
        destination: destination,
        customCode: customCode,
      );
      if (!mounted) return;
      setState(() {
        _activeCode = code;
        _activeType = _type;
        _activeLabel = label;
        _labelController.clear();
        _slugController.clear();
        _statusMessage = 'Generated code $code — customize below, then save/share.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Could not generate code: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ================================================================
  // DELETE / RETIRE A CAMPAIGN  (Aug 17 2026)
  // ================================================================
  // Two different needs, deliberately offered as two different actions,
  // because they have very different consequences and an admin under
  // time pressure will otherwise reach for whichever one is closest.
  //
  //   PAUSE  — the campaign was real. Keeps every scan/signup number for
  //            reporting; the printed QR stops sending people to the
  //            campaign destination and lands them on the app root
  //            instead. Reversible. This is the right choice ~90% of
  //            the time, so it is the SAFE (non-red) button.
  //   DELETE — the campaign was a mistake and was never printed. The row
  //            and the public redirect both go. Irreversible.
  //
  // A campaign with scans has been SEEN BY REAL PEOPLE, which usually
  // means a QR is out in the world. Deleting that does not un-print the
  // poster — it just makes those future scans attributable to nobody.
  // So when scans > 0 the delete requires typing the code by hand: not
  // theatre, it is the difference between "I meant this one" and "I
  // long-pressed the wrong row".
  Future<void> _confirmDeleteCampaign({
    required String code,
    required String label,
    required int scans,
    required int signups,
    required bool isActive,
  }) async {
    final hasTraffic = scans > 0 || signups > 0;
    final typedCtrl = TextEditingController();

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final typedOk = !hasTraffic ||
              typedCtrl.text.trim().toLowerCase() == code.toLowerCase();
          return AlertDialog(
            backgroundColor: _card,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              hasTraffic ? 'Retire or delete?' : 'Delete this campaign?',
              style: const TextStyle(color: _text, fontWeight: FontWeight.w800),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: _text, fontWeight: FontWeight.w700)),
                  Text(code,
                      style: const TextStyle(color: _muted, fontSize: 12)),
                  const SizedBox(height: 12),
                  if (hasTraffic) ...[
                    Text(
                      'This campaign has $scans scan(s) and $signups signup(s). '
                      'Real people have used it, so a printed QR is probably '
                      'out there.',
                      style: const TextStyle(
                          color: _muted, fontSize: 12.5, height: 1.45),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Deleting will NOT un-print those posters — future '
                      'scans will just land on the app home page and count '
                      'for nobody. Pausing keeps all the numbers and can be '
                      'undone.',
                      style: TextStyle(
                          color: _muted, fontSize: 12.5, height: 1.45),
                    ),
                    const SizedBox(height: 14),
                    Text('Type $code to confirm deletion:',
                        style: const TextStyle(color: _red, fontSize: 12)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: typedCtrl,
                      autocorrect: false,
                      style: const TextStyle(color: _text),
                      onChanged: (_) => setLocal(() {}),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: _bg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _border),
                        ),
                      ),
                    ),
                  ] else
                    const Text(
                      'No scans and no signups yet — nothing is lost. If this '
                      'QR was already printed, pause it instead.',
                      style: TextStyle(
                          color: _muted, fontSize: 12.5, height: 1.45),
                    ),
                ],
              ),
            ),
            actionsOverflowDirection: VerticalDirection.down,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: _muted)),
              ),
              if (isActive)
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'pause'),
                  child: const Text('Pause instead',
                      style: TextStyle(
                          color: _green, fontWeight: FontWeight.w700)),
                ),
              TextButton(
                onPressed: typedOk ? () => Navigator.pop(ctx, 'delete') : null,
                child: Text(
                  'Delete',
                  style: TextStyle(
                    color: typedOk ? _red : _muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    typedCtrl.dispose();
    if (action == null || !mounted) return;

    try {
      if (action == 'pause') {
        await AffiliateService.instance.setActive(code, false);
        if (!mounted) return;
        setState(() => _statusMessage =
            'Campaign $code paused — its numbers are kept and it can be '
            'resumed any time.');
        return;
      }

      await AffiliateService.instance.deleteAffiliateCode(code);
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Campaign $code deleted.';
        // Clear the preview if the deleted code is the one on screen,
        // otherwise the QR panel keeps offering Save/Share for a link
        // that no longer resolves.
        if (_activeCode == code) {
          _activeCode = null;
          _activeLabel = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Could not $action campaign: $e');
    }
  }

  Future<Uint8List> _capturePngBytes() async {
    final boundary =
        _qrBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('QR widget not ready yet.');
    final image = await boundary.toImage(pixelRatio: 6);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw StateError('Could not encode QR image.');
    return byteData.buffer.asUint8List();
  }

  Future<void> _saveQrImage() async {
    if (_busy || _activeCode == null) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final pngBytes = await _capturePngBytes();
      final savedPath = await QrImageSaver().saveAndOpen(
        pngBytes,
        'allin1_affiliate_${_activeCode}_qr.png',
      );
      if (!mounted) return;
      setState(() => _statusMessage = 'Saved: $savedPath');
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Could not save the QR image: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareQrImage() async {
    if (_busy || _activeCode == null) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final pngBytes = await _capturePngBytes();
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              pngBytes,
              mimeType: 'image/png',
              name: 'allin1_affiliate_${_activeCode}_qr.png',
            ),
          ],
          text: '${_shareMessageController.text.trim()} $_activeUrl',
        ),
      );
      if (!mounted) return;
      setState(() {
        _statusMessage = result.status == ShareResultStatus.success ? 'Shared.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Could not open the share sheet: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildColorSwatch(Color color, bool isBg) {
    final current = isBg ? _bgColor : _fgColor;
    final selected = current.toARGB32() == color.toARGB32();
    return GestureDetector(
      onTap: () => setState(() {
        if (isBg) {
          _bgColor = color;
        } else {
          _fgColor = color;
        }
      }),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : _border,
            width: selected ? 2.5 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)]
              : null,
        ),
      ),
    );
  }

  Widget _buildTypeChip(_AffiliateType t) {
    final selected = _type == t;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _type = t),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? _pink.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? _pink : _border),
          ),
          child: Column(
            children: [
              Icon(t.icon, color: selected ? _pink : _muted, size: 20),
              const SizedBox(height: 4),
              Text(
                t.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? _text : _muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final qrEyeShape = _roundedEyes ? QrEyeShape.circle : QrEyeShape.square;
    final qrModuleShape = _roundedShape ? QrDataModuleShape.circle : QrDataModuleShape.square;
    const double qrSize = 220;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text(
          'Affiliate QR Generator',
          style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        iconTheme: const IconThemeData(color: _text),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 1. Create new code ──────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'NEW AFFILIATE CODE',
                      style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildTypeChip(_AffiliateType.hero),
                        _buildTypeChip(_AffiliateType.customer),
                        _buildTypeChip(_AffiliateType.seller),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _labelController,
                      style: const TextStyle(color: _text),
                      decoration: InputDecoration(
                        hintText: 'Agent/campaign name (e.g. "Ramesh - Erode")',
                        hintStyle: const TextStyle(color: _muted, fontSize: 13),
                        filled: true,
                        fillColor: _bg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _border),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // ── Custom readable link (Aug 17 2026) ──────────
                    // Optional. A random code like K7M2XQ on a printed
                    // poster reads like a phishing token to the person
                    // being asked to scan it; "erode-hotels" reads like
                    // a local business. Blank keeps the old random code.
                    TextField(
                      controller: _slugController,
                      style: const TextStyle(color: _text),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixText: 'my-allin1.web.app/q/?c=',
                        prefixStyle: const TextStyle(
                            color: _muted, fontSize: 12.5),
                        hintText: 'erode-hotels',
                        hintStyle: const TextStyle(color: _muted, fontSize: 13),
                        helperText: _slugController.text.trim().isEmpty
                            ? 'Optional — leave blank for an auto code'
                            : (AffiliateService.normalizeCustomCode(
                                        _slugController.text) ==
                                    null
                                ? 'Not usable — 3–32 chars, letters/numbers/'
                                    'hyphens, must contain a letter'
                                : 'Link will be: my-allin1.web.app/q/?c='
                                    '${AffiliateService.normalizeCustomCode(_slugController.text)}'),
                        helperStyle: TextStyle(
                          fontSize: 11,
                          color: _slugController.text.trim().isNotEmpty &&
                                  AffiliateService.normalizeCustomCode(
                                          _slugController.text) ==
                                      null
                              ? _red
                              : _muted,
                        ),
                        helperMaxLines: 2,
                        filled: true,
                        fillColor: _bg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _border),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _generateCode,
                        icon: const Icon(Icons.add_link_rounded, size: 18),
                        label: const Text('Generate Affiliate Code'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _pink,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_activeCode != null) ...[
                const SizedBox(height: 20),
                // ── 2. Preview + customize ─────────────────────────
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _border),
                  ),
                  child: Column(
                    children: [
                      RepaintBoundary(
                        key: _qrBoundaryKey,
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          color: _bgColor,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              QrImageView(
                                data: _activeUrl,
                                version: QrVersions.auto,
                                size: qrSize,
                                backgroundColor: _bgColor,
                                // Level H (~30% recoverable) is what makes
                                // a centre logo safe at all — never lower
                                // this while the logo feature exists.
                                errorCorrectionLevel: QrErrorCorrectLevel.H,
                                eyeStyle: QrEyeStyle(eyeShape: qrEyeShape, color: _fgColor),
                                dataModuleStyle:
                                    QrDataModuleStyle(dataModuleShape: qrModuleShape, color: _fgColor),
                                // FIX (Aug 17 2026 — Nizam: "qr ku namma
                                // upload pandra logo outer la oru white
                                // box overa vanthturuthu").
                                //
                                // ROOT CAUSE: the logo was being drawn
                                // TWICE. qr_flutter's `embeddedImage`
                                // painted it into the code here, and the
                                // Stack overlay below then painted the
                                // SAME image again on top — inside a
                                // white container 6% wider than the logo
                                // PLUS 2.5%-of-QR padding on every side.
                                // Those two paddings compounded into the
                                // oversized white box, and the doubled
                                // draw made the logo look soft where the
                                // two copies were a fraction out of
                                // alignment.
                                //
                                // embeddedImage is dropped and the
                                // overlay kept, because the overlay is
                                // the only one of the two that can also
                                // provide the "quiet patch" a
                                // transparent/non-square PNG needs (see
                                // below). One draw, one padding.
                                embeddedImage: null,
                              ),
                              // The logo, on a white patch just big
                              // enough to be a border.
                              //
                              // The patch is not decoration — without a
                              // solid backdrop, half-covered dark
                              // modules peek out around a transparent or
                              // non-square PNG and scanners read noise
                              // where they expect clean data.
                              //
                              // Sized as a RATIO OF THE LOGO, not of the
                              // whole QR, which is what went wrong
                              // before: _kLogoBorderRatio 0.10 means the
                              // white ring is always 5% of the logo's
                              // width on each side, whether the logo is
                              // set to 14% or 30% of the code. Ratio of
                              // QR made the border grow independently of
                              // the logo and swamp it at small sizes.
                              if (_logoMode == _LogoMode.custom && _logoBytes != null)
                                IgnorePointer(
                                  child: Builder(
                                    builder: (_) {
                                      final logoBox = qrSize * _logoScale;
                                      final patch =
                                          logoBox * (1 + _kLogoBorderRatio);
                                      return Container(
                                        width: patch,
                                        height: patch,
                                        decoration: BoxDecoration(
                                          color: _bgColor,
                                          borderRadius: BorderRadius.circular(
                                              patch * 0.14),
                                        ),
                                        child: Padding(
                                          padding: EdgeInsets.all(
                                              logoBox * _kLogoBorderRatio / 2),
                                          child: Image.memory(
                                            _logoBytes!,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              if (_logoMode == _LogoMode.brand)
                                Container(
                                  width: qrSize * 0.16,
                                  height: qrSize * 0.16,
                                  decoration: BoxDecoration(
                                    color: _bgColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: _fgColor, width: 2),
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: qrSize * 0.12,
                                      height: qrSize * 0.12,
                                      decoration: BoxDecoration(color: _fgColor, shape: BoxShape.circle),
                                      child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 16),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '${_activeLabel ?? ''} · ${_activeType?.label ?? ''} · code $_activeCode',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _text, fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        _activeUrl,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _muted, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CUSTOMIZE',
                        style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1),
                      ),
                      const SizedBox(height: 12),
                      Text('QR color', style: TextStyle(color: _text.withValues(alpha: 0.8), fontSize: 12.5)),
                      const SizedBox(height: 8),
                      Row(children: _kColorPresets.map((c) => Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: _buildColorSwatch(c, false),
                          ),).toList(),),
                      const SizedBox(height: 16),
                      Text('Background color', style: TextStyle(color: _text.withValues(alpha: 0.8), fontSize: 12.5)),
                      const SizedBox(height: 8),
                      Row(children: [Colors.white, const Color(0xFFF5F5FA), const Color(0xFFFFF3E0)]
                          .map((c) => Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: _buildColorSwatch(c, true),
                              ),).toList(),),
                      const SizedBox(height: 18),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _roundedShape,
                        onChanged: (v) => setState(() => _roundedShape = v),
                        activeThumbColor: _pink,
                        title: const Text('Rounded dots', style: TextStyle(color: _text, fontSize: 13.5)),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _roundedEyes,
                        onChanged: (v) => setState(() => _roundedEyes = v),
                        activeThumbColor: _pink,
                        title: const Text('Rounded corners (eyes)', style: TextStyle(color: _text, fontSize: 13.5)),
                      ),
                      const SizedBox(height: 8),
                      Text('Centre logo',
                          style: TextStyle(color: _text.withValues(alpha: 0.8), fontSize: 12.5)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _logoModeChip('None', _LogoMode.none),
                          const SizedBox(width: 8),
                          _logoModeChip('MyAllin1 mark', _LogoMode.brand),
                          const SizedBox(width: 8),
                          _logoModeChip('Custom', _LogoMode.custom),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _pickLogo,
                            icon: const Icon(Icons.upload_rounded, size: 16, color: _pink),
                            label: Text(
                              _logoBytes == null ? 'Upload image' : 'Replace image',
                              style: const TextStyle(color: _pink, fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: _pink),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (_logoBytes != null)
                            Expanded(
                              child: Text(
                                _logoName ?? 'logo',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: _muted, fontSize: 11),
                              ),
                            ),
                          if (_logoBytes != null)
                            IconButton(
                              tooltip: 'Remove image',
                              icon: const Icon(Icons.close_rounded, color: _muted, size: 16),
                              onPressed: () => setState(() {
                                _logoBytes = null;
                                _logoName = null;
                                if (_logoMode == _LogoMode.custom) {
                                  _logoMode = _LogoMode.brand;
                                }
                              }),
                            ),
                        ],
                      ),
                      if (_logoMode == _LogoMode.custom && _logoBytes != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Text('Logo size',
                                style: TextStyle(color: _muted, fontSize: 11.5)),
                            Expanded(
                              child: Slider(
                                value: _logoScale,
                                min: 0.14,
                                max: 0.30,
                                activeColor: _pink,
                                onChanged: (v) => setState(() => _logoScale = v),
                              ),
                            ),
                            Text('${(_logoScale * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(color: _text, fontSize: 11.5)),
                          ],
                        ),
                        // Live scannability read-out. Level H recovers
                        // ~30% of the code AREA, and a square logo of
                        // width f covers f² — so this is the number that
                        // actually matters, not the width percentage.
                        Row(
                          children: [
                            Icon(
                              _logoAreaPct <= 9
                                  ? Icons.verified_rounded
                                  : Icons.warning_amber_rounded,
                              size: 14,
                              color: _logoAreaPct <= 9 ? _green : Colors.orange,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Covers ${_logoAreaPct.toStringAsFixed(1)}% of the code — '
                                'error correction H handles up to ~30%.',
                                style: const TextStyle(color: _muted, fontSize: 10.5),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Always test-scan the printed proof before a big print run.',
                          style: TextStyle(color: _muted, fontSize: 10),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SHARE MESSAGE',
                        style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _shareMessageController,
                        style: const TextStyle(color: _text, fontSize: 13.5),
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Message to send with link...',
                          hintStyle: TextStyle(color: _muted.withValues(alpha: 0.5)),
                          filled: true,
                          fillColor: const Color(0xFFF5F5FA),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _shareQrImage,
                        icon: const Icon(Icons.share_rounded, color: _text, size: 18),
                        label: const Text('Share', style: TextStyle(color: _text)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: _border),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _saveQrImage,
                        icon: _busy
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.download_rounded, size: 18),
                        label: Text(_busy ? 'Working…' : 'Save HD'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _pink,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              if (_statusMessage != null) ...[
                const SizedBox(height: 14),
                Text(_statusMessage!, textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 12)),
              ],

              const SizedBox(height: 28),
              // ── 3. Live performance dashboard ────────────────────
              const Text(
                'ALL AFFILIATE CODES',
                style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1),
              ),
              const SizedBox(height: 4),
              // Discoverability for the two row gestures. A long-press
              // action nobody is told about may as well not exist —
              // that is how the delete capability stayed "missing" even
              // though firestore.rules has allowed it all along.
              const Text(
                'Tap a row for insights · long-press to pause or delete',
                style: TextStyle(color: _muted, fontSize: 10.5),
              ),
              const SizedBox(height: 12),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: AffiliateService.instance.watchAffiliateCodes(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator(color: _pink)),
                    );
                  }
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text('No affiliate codes yet.', style: TextStyle(color: _muted, fontSize: 12.5)),
                      ),
                    );
                  }
                  return Column(
                    children: docs.map((doc) {
                      final data = doc.data();
                      final scans = (data['scans'] as num?)?.toInt() ?? 0;
                      final signups = (data['signups'] as num?)?.toInt() ?? 0;
                      final rate = scans == 0 ? 0.0 : (signups / scans * 100);
                      final type = (data['type'] as String?) ?? 'customer';
                      final typeEnum = _AffiliateType.values.firstWhere(
                        (t) => t.value == type,
                        orElse: () => _AffiliateType.customer,
                      );
                      // NEW (Aug 13 2026): the whole row is now a tap
                      // target into the per-campaign insights screen
                      // (scans over time, unique vs total, OS split,
                      // live destination editing) — the QRCG-style
                      // detail view Nizam asked for.
                      final isActive = (data['active'] as bool?) ?? true;
                      return InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                AdminCampaignDetailScreen(code: doc.id),
                          ),
                        ),
                        // NEW (Aug 17 2026 — Nizam: "wrong affilate qr ah
                        // namma admin nala delete pannamudila").
                        // Long-press rather than a visible trash icon on
                        // every row: tapping a row is the common action
                        // (open insights) and a delete button sitting
                        // next to it, on a list of live campaigns, is a
                        // misfire waiting to happen.
                        onLongPress: () => _confirmDeleteCampaign(
                          code: doc.id,
                          label: (data['label'] as String?) ?? doc.id,
                          scans: scans,
                          signups: signups,
                          isActive: isActive,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: _pink.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(typeEnum.icon, color: _pink, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (data['label'] as String?) ?? doc.id,
                                    style: const TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${typeEnum.label} · ${doc.id}',
                                    style: const TextStyle(color: _muted, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('$scans scans', style: const TextStyle(color: _muted, fontSize: 11)),
                                Text(
                                  '$signups signups',
                                  style: const TextStyle(color: _green, fontSize: 12.5, fontWeight: FontWeight.w800),
                                ),
                                if (scans > 0)
                                  Text(
                                    '${rate.toStringAsFixed(0)}% convert',
                                    style: const TextStyle(color: _muted, fontSize: 10),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.chevron_right_rounded,
                                color: _muted, size: 18),
                          ],
                        ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
