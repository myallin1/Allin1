// ================================================================
// admin_whats_new_sheet.dart — "here is what is actually in the build
// you just installed".
// ================================================================
// NEW (Sep 4 2026 — Nizam: "admin app open pannumbothe antha app la
// Yenna feauture add pannirukonu admin ku pop kaatanum app main page
// open anathum apram admin ok kuduthuruvaru then setting la version ku
// keela yennena feautures add pannirukomnu list kaatanum").
//
// Shown once per build, on first open. It exists to answer a
// verification question, not to celebrate a release: he merges a PR,
// installs an APK, and needs to see the merge in the app in his hand.
// That check had already failed him twice — the Dev tab once served an
// APK from hours earlier, and a PR was reported merged when it had
// actually been closed.
//
// The same list is reachable any time from Settings, because the
// popup is dismissible and a thing you can only see once is not a
// record.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/app_changelog_service.dart';

const Color _card = Color(0xFF16162A);
const Color _bg = Color(0xFF0A0A1A);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _purple = Color(0xFFB21FFF);
const Color _green = Color(0xFF4ADE80);

/// Shows the sheet if this build hasn't been acknowledged yet.
/// Safe to call unconditionally on startup — it self-checks and
/// returns immediately when there is nothing to show.
Future<void> maybeShowWhatsNew(BuildContext context) async {
  if (!await AppChangelogService.shouldShowWhatsNew()) return;
  final log = await AppChangelogService.load();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: _card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => AdminWhatsNewSheet(log: log),
  );
  await AppChangelogService.markSeen();
}

class AdminWhatsNewSheet extends StatelessWidget {
  const AdminWhatsNewSheet({super.key, required this.log, this.embedded = false});

  final AppChangelog log;

  /// True when rendered inside Settings rather than as a popup — drops
  /// the grabber and the dismiss button.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!embedded) ...[
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, color: _green, size: 19),
            const SizedBox(width: 8),
            Text(
              embedded ? 'In this build' : "What's new",
              style: GoogleFonts.outfit(
                  color: _text, fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Build ${log.buildNumber}  ·  ${log.sha}  ·  ${log.date}',
          style: GoogleFonts.outfit(color: _muted, fontSize: 11.5),
        ),
        const SizedBox(height: 14),
        if (log.isEmpty)
          Text('No changes recorded for this build.',
              style: GoogleFonts.outfit(color: _muted, fontSize: 13))
        else
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: log.changes.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 6, right: 9),
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                          color: _purple, shape: BoxShape.circle),
                    ),
                    Expanded(
                      child: Text(
                        AppChangelogService.prettify(log.changes[i]),
                        style: GoogleFonts.outfit(
                            color: _text, fontSize: 13, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (!embedded) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: _purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Got it'),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text('Also under Settings → version',
                style: GoogleFonts.outfit(color: _muted, fontSize: 11)),
          ),
        ],
      ],
    );

    if (embedded) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: content,
      );
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: content,
      ),
    );
  }
}
