// ================================================================
// admin_call_services_screen.dart — what customers asked Chitti for
// during in-app calls
// ================================================================
// NEW (Sep 2026 — Nizam: "customer oru intent or avanga requirement ah
// chitti kitta sonnangana apo chitti antha call ah namma customer app
// pesi mudichathum namma admin app ku varanum services option kulla
// call services nu athukla customeroda intenta chitti namaku
// sollum...admin atha follow pannuvaru").
//
// SILENT QUEUE, ON PURPOSE — per Nizam's explicit choice when this was
// scoped: no push notification, no sound. This is a list to check when
// convenient, the same shape every other admin queue in this app
// already is (New Orders, Service Requests) — a badge count on the
// Services tile is the only signal, matching _AdminReviewBadgeWrapper's
// existing pattern elsewhere on super_admin_home_screen.dart.
//
// EVERY TOOL CALL IS SHOWN, NOT A FILTERED SUBSET — also an explicit
// choice: chitti_call_service_log.dart's header explains why hand-
// picking which intents "count" would have been a second, hidden
// classification decision.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _card = Color(0xFF1A1A2E);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _amber = Color(0xFFFFB300);
const Color _green = Color(0xFF00C853);
const Color _border = Color(0xFF2A2A40);

class AdminCallServicesScreen extends StatelessWidget {
  const AdminCallServicesScreen({super.key});

  static const String collection = 'call_service_requests';

  /// The stream super_admin_home_screen.dart's badge tile watches —
  /// exposed here so both the badge count and this full list read the
  /// exact same query and can never disagree about what "new" means.
  static Stream<QuerySnapshot<Map<String, dynamic>>> newStream() =>
      FirebaseFirestore.instance
          .collection(collection)
          .where('status', isEqualTo: 'new')
          .snapshots();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text(
          'Call Services',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(collection)
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load call services.',
                  style: GoogleFonts.outfit(color: _muted)),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: _green));
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No calls have surfaced a customer request yet. This '
                  'fills in on its own whenever Chitti acts on something '
                  'during an in-app call.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: _muted, fontSize: 12.5, height: 1.4),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: docs.length,
            itemBuilder: (context, i) => _CallCard(doc: docs[i]),
          );
        },
      ),
    );
  }
}

class _CallCard extends StatelessWidget {
  const _CallCard({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final status = (data['status'] as String?) ?? 'new';
    final name = (data['customerName'] as String?)?.trim();
    final phone = (data['customerPhone'] as String?)?.trim();
    final intents = (data['intents'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final endedAt = (data['callEndedAt'] as Timestamp?)?.toDate();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: status == 'new' ? _amber.withValues(alpha: 0.4) : _border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (name?.isNotEmpty ?? false) ? name! : (phone ?? 'Unknown caller'),
                    style: GoogleFonts.outfit(
                      color: _text,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                _StatusChip(status: status),
              ],
            ),
            if (endedAt != null) ...[
              const SizedBox(height: 2),
              Text(_ago(endedAt),
                  style: GoogleFonts.outfit(color: _muted, fontSize: 11)),
            ],
            const SizedBox(height: 10),
            for (final intent in intents) _IntentLine(intent: intent),
            if (status != 'resolved') ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (status == 'new')
                    TextButton(
                      onPressed: () => doc.reference.update({'status': 'seen'}),
                      child: Text('Mark seen',
                          style: GoogleFonts.outfit(color: _muted, fontSize: 12)),
                    ),
                  TextButton(
                    onPressed: () => doc.reference.update({'status': 'resolved'}),
                    style: TextButton.styleFrom(foregroundColor: _green),
                    child: Text('Resolved',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _ago(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _IntentLine extends StatelessWidget {
  const _IntentLine({required this.intent});

  final Map<String, dynamic> intent;

  @override
  Widget build(BuildContext context) {
    final actionType = (intent['actionType'] as String?) ?? 'unknown';
    final detail = intent['detail'] as Map<String, dynamic>? ?? const {};
    // A short, human-readable rendering of whatever arguments the tool
    // call carried — this deliberately does not know the shape of any
    // specific tool, so a new tool added to the registry shows up here
    // correctly with zero changes to this screen.
    final detailText = detail.entries
        .where((e) => e.value != null && e.value.toString().trim().isNotEmpty)
        .map((e) => '${e.key}: ${e.value}')
        .join('  ·  ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, size: 5, color: _amber),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  actionType.replaceAll('_', ' '),
                  style: GoogleFonts.outfit(
                    color: _text,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                if (detailText.isNotEmpty)
                  Text(
                    detailText,
                    style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'new' => (_amber, 'New'),
      'seen' => (_muted, 'Seen'),
      'resolved' => (_green, 'Resolved'),
      _ => (_muted, status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(color: color, fontWeight: FontWeight.w700, fontSize: 10.5),
      ),
    );
  }
}
