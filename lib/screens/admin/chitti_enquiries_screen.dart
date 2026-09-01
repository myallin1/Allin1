// ================================================================
// ChittiEnquiriesScreen — the leads Chitti could not price itself.
// ================================================================
// NEW (Aug 28 2026 — Nizam: "rate and models daily maarum, so namma
// kita than final rate and final offer kekkanum. Angirunthu namaku oru
// enquiry varramari set pannirlam, atha namma seller and admin phone
// la monitor pannalam").
//
// ChittiEnquiryService has been writing these since the market-answer
// work landed. Nothing read them. A lead nobody opens is worse than no
// lead at all: the customer was told "NJ Tech will confirm the exact
// rate shortly", which was a promise the app could not keep. This
// screen is the second half of that promise.
//
// SHOWN IN TWO APPS, SO THE PALETTE ADAPTS
// Admin is dark navy; Seller is light teal. One hardcoded palette
// would look broken in whichever app it was not designed for, and this
// screen belongs to both by Nizam's rule. `_Palette.of()` is the whole
// of that accommodation — the layout is identical.
//
// WHY THERE IS NO SELLER FILTER
// An enquiry is a question about a price, asked before any shop is
// chosen — there is no sellerId to filter on, and inventing one would
// mean guessing which shop the customer meant. Every seller sees every
// open enquiry, which is what "monitor on seller and admin phone"
// asks for.
//
// PERISHABILITY IS THE POINT
// A rate question answered tomorrow has already been answered by
// somebody else's shop. Hence the age badge, newest first, and the
// call button being the largest thing on the card.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_variant.dart';
import '../../services/chitti/chitti_enquiry_service.dart';

/// The two looks this screen has to live in.
@immutable
class _Palette {
  const _Palette({
    required this.bg,
    required this.surface,
    required this.card,
    required this.text,
    required this.muted,
    required this.border,
    required this.accent,
  });

  factory _Palette.of(String variant) => variant == 'seller'
      ? const _Palette(
          bg: Color(0xFFF7FAF8),
          surface: Color(0xFFFFFFFF),
          card: Color(0xFFFFFFFF),
          text: Color(0xFF1A1A1A),
          muted: Color(0xFF6B7280),
          border: Color(0x14000000),
          accent: Color(0xFF11998E),
        )
      : const _Palette(
          bg: Color(0xFF0A0A1A),
          surface: Color(0xFF12121E),
          card: Color(0xFF1A1A2E),
          text: Color(0xFFEEEEF5),
          muted: Color(0xFF7777A0),
          border: Color(0x1AFFFFFF),
          accent: Color(0xFF11998E),
        );

  final Color bg;
  final Color surface;
  final Color card;
  final Color text;
  final Color muted;
  final Color border;
  final Color accent;
}

class ChittiEnquiriesScreen extends StatefulWidget {
  const ChittiEnquiriesScreen({super.key});

  @override
  State<ChittiEnquiriesScreen> createState() => _ChittiEnquiriesScreenState();
}

class _ChittiEnquiriesScreenState extends State<ChittiEnquiriesScreen> {
  /// Built once, not per build().
  ///
  /// Stateless would rebuild this stream on every rotation, theme
  /// change or inherited-widget update, and each re-attach re-bills the
  /// whole result set against a 50,000 reads/day budget.
  late final Stream<List<ChittiEnquiry>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = ChittiEnquiryService.watchOpen();
  }

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(currentAppVariant);

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: p.text),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: p.text, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const Text('💬', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              'Customer Enquiries',
              style: GoogleFonts.outfit(
                color: p.text,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: p.border),
        ),
      ),
      body: StreamBuilder<List<ChittiEnquiry>>(
        stream: _stream,
        builder: (context, snap) {
          // Errors first. A missing index or a rules rejection otherwise
          // renders as an empty list, which reads as "no leads" — the
          // most damaging possible lie on this particular screen.
          if (snap.hasError) {
            return _Message(
              palette: p,
              emoji: '⚠️',
              title: "Couldn't load enquiries",
              body: 'If this persists, check that the firestore.rules '
                  'change for chitti_enquiries has been deployed.',
            );
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: p.accent),
            );
          }

          final items = snap.data ?? const <ChittiEnquiry>[];
          if (items.isEmpty) {
            return _Message(
              palette: p,
              emoji: '✅',
              title: 'Nothing waiting',
              body: 'When Chitti cannot price something itself, the '
                  'customer’s question lands here with their number.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
            itemCount: items.length,
            itemBuilder: (_, i) => _EnquiryCard(
              enquiry: items[i],
              palette: p,
            ),
          );
        },
      ),
    );
  }
}

class _EnquiryCard extends StatelessWidget {
  const _EnquiryCard({required this.enquiry, required this.palette});

  final ChittiEnquiry enquiry;
  final _Palette palette;

  /// "12m ago" — how cold this lead is, at a glance.
  String get _age {
    final at = enquiry.createdAt;
    if (at == null) return '';
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  /// Older than a few hours and the customer has almost certainly asked
  /// someone else — worth showing, worth flagging.
  bool get _isStale {
    final at = enquiry.createdAt;
    return at != null && DateTime.now().difference(at).inHours >= 4;
  }

  String get _kindLabel => switch (enquiry.kind) {
        'displayRepair' => 'Display repair',
        'mobilePurchase' => 'Mobile purchase',
        _ => 'General',
      };

  Future<void> _call(BuildContext context) async {
    final phone = enquiry.customerPhone.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number on this enquiry.')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the dialler for $phone.')),
      );
    }
  }

  // NEW (Sep 2 2026 — Nizam: "chitti udane athuku enaku venungra records
  // ilana whatsapp la pricing send pannunu sonan antha product ku yenna
  // quality yevlo rate podanumnu enkita kettu udane customer ku
  // anupum"). Admin types the actual quote here — never Chitti's
  // scraped marketReference verbatim, matching this whole screen's
  // rule that NJ Tech's own number is the one thing customer-facing.
  // Opens WhatsApp with the message pre-filled; NJ Tech still taps
  // Send themselves, so a wrong number or a typo is caught before
  // anything goes out.
  Future<void> _quoteViaWhatsApp(BuildContext context) async {
    final phone = enquiry.customerPhone.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number on this enquiry.')),
      );
      return;
    }
    final rateCtrl = TextEditingController();
    final rate = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Quote for ${enquiry.customerName.trim().isEmpty ? "this customer" : enquiry.customerName.trim()}',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(enquiry.question, style: GoogleFonts.outfit(fontSize: 12.5, color: palette.muted)),
            if (enquiry.marketReference.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Chitti showed: ${enquiry.marketReference}',
                  style: GoogleFonts.outfit(fontSize: 11, fontStyle: FontStyle.italic, color: palette.muted)),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: rateCtrl,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'e.g. Original display, ₹1200, fitted same day',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(rateCtrl.text.trim()),
            child: const Text('Open WhatsApp'),
          ),
        ],
      ),
    );
    if (rate == null || rate.isEmpty) return;

    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) digits = '91$digits';
    final message = 'Hi${enquiry.customerName.trim().isEmpty ? '' : ' ${enquiry.customerName.trim()}'}, '
        'this is NJ Tech, Erode. Regarding your enquiry — "${enquiry.question}":\n\n$rate\n\n'
        'Let us know if you would like to go ahead.';
    final uri = Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(message)}');
    if (!context.mounted) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp.')),
      );
      return;
    }
    // The quote is now in NJ Tech's own hands to actually send inside
    // WhatsApp, but the lead itself is answered from this screen's
    // point of view — leaving it open would mean someone else re-quotes
    // the same customer later.
    await ChittiEnquiryService.markAnswered(enquiry.id);
  }

  Future<void> _markAnswered(BuildContext context) async {
    // Confirmed, because this is the only way a lead leaves the list
    // and there is no undo — a mis-tap would silently drop a customer
    // who is still waiting for a call.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Mark as answered?',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'It will leave this list. Do this once you have actually '
          'given the customer a price.',
          style: GoogleFonts.outfit(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Mark answered'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ChittiEnquiryService.markAnswered(enquiry.id);
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final name = enquiry.customerName.trim();
    final phone = enquiry.customerPhone.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isStale ? const Color(0xFFE07A00) : p.border,
          width: _isStale ? 1.2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _kindLabel,
                  style: GoogleFonts.outfit(
                    color: p.accent,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              if (_age.isNotEmpty)
                Text(
                  _age,
                  style: GoogleFonts.outfit(
                    color: _isStale ? const Color(0xFFE07A00) : p.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            enquiry.question,
            style: GoogleFonts.outfit(
              color: p.text,
              fontSize: 14.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (enquiry.model.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Model: ${enquiry.model}',
              style: GoogleFonts.outfit(color: p.muted, fontSize: 12),
            ),
          ],
          if (enquiry.marketReference.isNotEmpty) ...[
            const SizedBox(height: 6),
            // What Chitti already showed them. Quoting below this needs
            // to be a deliberate choice, not a surprise at the counter.
            Text(
              'Chitti showed: ${enquiry.marketReference}',
              style: GoogleFonts.outfit(
                color: p.muted,
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.person_outline, size: 15, color: p.muted),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  [
                    if (name.isNotEmpty) name,
                    if (phone.isNotEmpty) phone,
                  ].join(' · '),
                  style: GoogleFonts.outfit(color: p.muted, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _quoteViaWhatsApp(context),
              icon: const Icon(Icons.chat_rounded, size: 17),
              label: Text('Quote via WhatsApp', style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _call(context),
                  icon: Icon(Icons.call, size: 16, color: p.accent),
                  label: Text(
                    'Call',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: p.accent),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    side: BorderSide(color: p.accent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _markAnswered(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    side: BorderSide(color: p.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Done',
                    style: GoogleFonts.outfit(
                      color: p.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.palette,
    required this.emoji,
    required this.title,
    required this.body,
  });

  final _Palette palette;
  final String emoji;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.outfit(
                color: palette.text,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: palette.muted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
