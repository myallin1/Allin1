// ================================================================
// invite_friends_screen.dart — customer referral (share + QR)
// ================================================================
// NEW (Aug 13 2026 — Nizam: "customer avaroda tray kulla share app via
// whatsapp button... automatic ah oru qr generate aganum... antha qr ah
// avanga friend ku kaamichu refer panni scan panna vaikalam").
//
// One screen, two ways to invite, both backed by the SAME personal
// code:
//   1. Share via WhatsApp — opens WhatsApp with a ready message.
//   2. Show my QR — the friend scans straight off this phone's screen.
//      No typing, no details to hand over, nothing to install first.
//
// The code is created once (AffiliateService.ensureMyReferralCode) and
// then cached on users/{uid}.referralCode, so re-opening this screen
// costs a single field read rather than generating anything new.
//
// PRIVACY NOTE (deliberate design): the customer's NAME never appears
// in the link. It is stored as the campaign label so Admin sees
// "Ravi Kumar — 6 installs", while the link that gets forwarded around
// WhatsApp groups is just an anonymous short code.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/affiliate_service.dart';

const Color _bg = Color(0xFFFFF6FA);
const Color _surface = Color(0xFFFFFFFF);
const Color _card = Color(0xFFFFEAF3);
const Color _pink = Color(0xFFFF4FA3);
const Color _pink2 = Color(0xFFBE2A7A);
const Color _text = Color(0xFF201A22);
const Color _muted = Color(0xFF8C7A88);
const Color _whatsapp = Color(0xFF25D366);

/// Who is doing the inviting (Aug 17 2026 — Nizam: "heros avanga innoru
/// heros ah refer panna antha particular hero app la irunthu hero
/// referral qr and link generation").
///
/// One screen, two modes, rather than a copied hero_invite_screen.dart.
/// The layout, QR rendering, WhatsApp share, copy-link and invite count
/// are identical work; only the referral TYPE, the DESTINATION and the
/// wording differ. A second copy would have drifted the first time one
/// of them was fixed.
enum InviteMode {
  /// Customer inviting other customers -> lands on the customer app.
  customer,

  /// Hero inviting other heroes -> MUST land on the hero app. Sending a
  /// would-be hero to the customer app is a dead end: there is no hero
  /// registration there, so the referral is silently wasted.
  hero,
}

class InviteFriendsScreen extends StatefulWidget {
  const InviteFriendsScreen({
    this.displayName,
    this.mode = InviteMode.customer,
    super.key,
  });
  final String? displayName;
  final InviteMode mode;

  @override
  State<InviteFriendsScreen> createState() => _InviteFriendsScreenState();
}

class _InviteFriendsScreenState extends State<InviteFriendsScreen> {
  String? _code;
  int _invited = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final isHero = widget.mode == InviteMode.hero;
    final code = await AffiliateService.instance.ensureMyReferralCode(
      displayName: widget.displayName,
      referralType: isHero
          ? AffiliateService.kHeroReferralType
          : AffiliateService.kCustomerReferralType,
      // Pinned as a pair with the type by firestore.rules — see the
      // affiliate_codes create rule.
      destination: isHero ? '${AffiliateService.kHeroAppBaseUrl}/' : null,
      // Heroes live in heroes/{uid}, customers in users/{uid}. This is
      // where the generated code is cached, which is what makes the
      // whole thing idempotent instead of minting a new code per open.
      profileCollection: isHero ? 'heroes' : 'users',
    );
    if (!mounted) return;
    if (code == null) {
      // FIX (Aug 18 2026): ensureMyReferralCode() returns null both when
      // no real user is signed in AND when the Firestore write itself
      // was rejected (e.g. a rules mismatch) — those are very different
      // problems for the person reading this screen. A hero who is
      // fully logged in and online was seeing "Please sign in" for a
      // rules bug that had nothing to do with their auth state. Checking
      // the actual auth state here means the message only claims
      // "sign in" when that is really the cause.
      final user = FirebaseAuth.instance.currentUser;
      final signedIn = user != null && !user.isAnonymous;
      setState(() {
        _loading = false;
        _error = signedIn
            ? 'Could not get your invite link right now. Please try again in a moment.'
            : 'Please sign in to get your invite link.';
      });
      return;
    }
    final count = await AffiliateService.instance.myReferralSignups(code);
    if (!mounted) return;
    setState(() {
      _code = code;
      _invited = count;
      _loading = false;
    });
  }

  String get _link =>
      _code == null ? '' : AffiliateService.shortUrlFor(_code!);

  /// Hero wording is a RECRUITMENT pitch, not a "try this app" pitch —
  /// the person receiving it is being asked to earn, not to order.
  String get _message => widget.mode == InviteMode.hero
      ? 'Naan MyAllin1-la Hero-va work panren — bike taxi, food and parcel '
          'delivery, Erode-la. 100% delivery income Hero-kku thaan, 0% '
          'commission. Neengalum join pannunga:\n$_link'
      : 'Hey! I use MyAllin1 for bike taxi, food, parcel and local services '
          'in Erode — try it, it works right in your browser:\n$_link';

  Future<void> _shareWhatsApp() async {
    final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(_message)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text('Invite Friends',
            style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _pink))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(color: _muted, fontSize: 13)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _heroCard(),
                    const SizedBox(height: 18),
                    _qrCard(),
                    const SizedBox(height: 18),
                    _linkCard(),
                    const SizedBox(height: 18),
                    _howItWorks(),
                    const SizedBox(height: 28),
                  ],
                ),
    );
  }

  Widget _heroCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_pink, _pink2]),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 34),
            const SizedBox(height: 10),
            Text('Share MyAllin1 with friends',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              _invited == 0
                  ? 'Send your link and help your friends get around Erode.'
                  : 'You have invited $_invited ${_invited == 1 ? 'friend' : 'friends'} so far. Thank you!',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.92), fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _shareWhatsApp,
                icon: const Icon(Icons.chat_rounded, size: 18),
                label: Text('Share via WhatsApp',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _whatsapp,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _qrCard() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _card, width: 1.5),
        ),
        child: Column(
          children: [
            Text('Or let them scan this',
                style: GoogleFonts.outfit(
                    color: _text, fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Your friend just points their camera at it — nothing to type.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(color: _muted, fontSize: 11.5)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _pink.withValues(alpha: 0.14),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: QrImageView(
                data: _link,
                version: QrVersions.auto,
                size: 208,
                backgroundColor: Colors.white,
                // H so the code stays readable off a phone screen at an
                // angle, in poor light, with a finger partly over it.
                errorCorrectionLevel: QrErrorCorrectLevel.H,
                eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.circle, color: _pink2),
                dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.circle, color: _text),
              ),
            ),
            const SizedBox(height: 12),
            Text('Code: ${_code ?? ''}',
                style: GoogleFonts.robotoMono(
                    color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _linkCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(_link,
                  style: GoogleFonts.outfit(color: _text, fontSize: 12.5)),
            ),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _link));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invite link copied')),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 15, color: _pink2),
              label: Text('Copy',
                  style: GoogleFonts.outfit(
                      color: _pink2, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

  Widget _howItWorks() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How it works',
              style: GoogleFonts.outfit(
                  color: _text, fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          _step(1, 'Send your link or show your QR to a friend.'),
          _step(2, 'They open it — MyAllin1 loads straight in their browser.'),
          _step(3, 'Once they sign up, they are counted as your invite.'),
        ],
      );

  Widget _step(int n, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: _pink, shape: BoxShape.circle),
              child: Text('$n',
                  style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(text,
                    style: GoogleFonts.outfit(
                        color: _muted, fontSize: 12, height: 1.45)),
              ),
            ),
          ],
        ),
      );
}
