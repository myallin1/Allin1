// ================================================================
// chitti_dev_monitor_screen.dart — the admin app's Development
// Monitor: one screen showing where every change currently stands.
// ================================================================
// NEW (Sep 1 2026 — Nizam: "as a ceo and admin other nan oruthane
// pakkurathunala athuku thani monitoring ui namma admin app la
// irukanum nan multitasking pandren so nan kulappamillama understand
// and athula separate section la nan namma development ah continue
// pannanum").
//
// Deliberately THREE fixed sections in pipeline order — task opened →
// build running → APK ready to install — because the question this
// screen exists to answer is "where is my change right now, and can I
// test it yet". A single merged activity feed would technically show
// the same rows but would make that question harder, not easier, which
// is the opposite of the ask.
//
// Read-only by design. Nothing here triggers a build or edits code —
// Chitti opens dev tasks (ChittiDevTaskService) and GitHub Actions
// does the rest; this is the window onto that, not a second control
// surface that could drift out of sync with it.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/chitti/chitti_dev_monitor_service.dart';
import '../../services/chitti/chitti_dev_task_service.dart';
import 'admin_app_versions_screen.dart';
import 'github_embedded_screen.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _card = Color(0xFF141420);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);
const Color _red = Color(0xFFE05555);
const Color _green = Color(0xFF4ADE80);
const Color _amber = Color(0xFFFFB020);
const Color _purple = Color(0xFFB21FFF);

class ChittiDevMonitorScreen extends StatefulWidget {
  const ChittiDevMonitorScreen({super.key});

  @override
  State<ChittiDevMonitorScreen> createState() => _ChittiDevMonitorScreenState();
}

class _ChittiDevMonitorScreenState extends State<ChittiDevMonitorScreen> {
  DevMonitorSnapshot? _snapshot;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final snap = await ChittiDevMonitorService.fetch();
    if (!mounted) return;
    setState(() {
      _snapshot = snap;
      _loading = false;
    });
  }

  Future<void> _open(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openInApp(BuildContext context, String url) async {
    if (url.isEmpty) return;
    if (url.toLowerCase().endsWith('.apk')) {
      final uri = Uri.tryParse(url);
      if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GitHubEmbeddedScreen(url: url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text(
          'Development Monitor',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 16),
        ),
        actions: [
          // NEW (Sep 2026 — CTO review of PR #61): "App Versions &
          // Rollback" used to appear only conditionally, buried inside
          // the release card, when that release happened to carry more
          // than one .apk asset — no route existed on a fresh release
          // (one asset) or before the card had finished loading. Always
          // visible here instead — disabled only for the brief window
          // before the first release has loaded, not hidden.
          IconButton(
            icon: const Icon(Icons.history_rounded, color: _text),
            tooltip: 'App Versions & Rollback',
            onPressed: snap?.latestRelease == null
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AdminAppVersionsScreen(
                          release: snap!.latestRelease!,
                        ),
                      ),
                    ),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, color: _text),
            tooltip: 'Open GitHub in-app',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const GitHubEmbeddedScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _text),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _purple,
        backgroundColor: _card,
        child: _loading && snap == null
            ? const Center(child: CircularProgressIndicator(color: _purple))
            : ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  if (snap != null && snap.hasError) _errorCard(snap.error!),
                  _sectionHeader('1 · LATEST BUILD YOU CAN TEST', Icons.android_rounded),
                  _releaseCard(snap?.latestRelease),
                  const SizedBox(height: 18),
                  _sectionHeader('2 · BUILDS RUNNING / RECENT', Icons.build_circle_outlined),
                  if (snap == null || snap.runs.isEmpty)
                    _emptyCard('No workflow runs found yet.')
                  else
                    ...snap.runs.map(_runTile),
                  const SizedBox(height: 18),
                  _sectionHeader('3 · DEV TASKS (Chitti → Claude)', Icons.task_alt_rounded),
                  if (snap == null || snap.issues.isEmpty)
                    _emptyCard('No dev tasks opened yet.')
                  else
                    ...snap.issues.map(_issueTile),
                  const SizedBox(height: 18),
                  _sectionHeader('4 · REPO CONFIGURATION', Icons.rocket_launch_rounded),
                  const _GithubRepoConfigCard(),
                  const SizedBox(height: 30),
                ],
              ),
      ),
    );
  }

  Widget _sectionHeader(String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
      child: Row(
        children: [
          Icon(icon, color: _muted, size: 15),
          const SizedBox(width: 7),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: _muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _red),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: _red, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.outfit(color: _red, fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Text(message, style: GoogleFonts.outfit(color: _muted, fontSize: 12)),
    );
  }

  // The section that answers "can I install and test something right
  // now" — kept first and visually heaviest for exactly that reason.
  Widget _releaseCard(DevRelease? release) {
    if (release == null) {
      return _emptyCard('No published release yet. Once a build finishes, the '
          'installable APK appears here.');
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _green.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded, color: _green, size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  release.name,
                  style: GoogleFonts.outfit(color: _text, fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (release.publishedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Published ${_ago(release.publishedAt!)}  ·  ${release.tag}',
                style: GoogleFonts.outfit(color: _muted, fontSize: 11),
              ),
            ),
          const SizedBox(height: 12),
          if (release.apkUrl != null) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _open(release.apkUrl!),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Download APK & Test'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Sharing the link is how this reaches a second device (or
            // WhatsApp) without needing a messaging integration at all —
            // the OS share sheet already goes everywhere.
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => SharePlus.instance.share(
                  ShareParams(
                    text: 'Allin1 Admin test build — ${release.name}\n${release.apkUrl}',
                    subject: 'Allin1 test build',
                  ),
                ),
                icon: const Icon(Icons.share_rounded, size: 17),
                label: const Text('Share APK link'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _green,
                  side: const BorderSide(color: _green),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
            // NEW (Sep 4 2026 — Nizam: "suppose lastversion problem
            // iruntha admin previous versionuku poi switch panni
            // pathukuramari set pannnamuidyuma?"). Every build's APK is
            // already kept on this same release, so this is one tap to
            // the full list — see AdminAppVersionsScreen.
            if (release.apkAssets.length > 1) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AdminAppVersionsScreen(release: release),
                    ),
                  ),
                  icon: const Icon(Icons.history_rounded, size: 17),
                  label: Text(
                    'All versions (${release.apkAssets.length}) · roll back',
                  ),
                  style: TextButton.styleFrom(foregroundColor: _muted),
                ),
              ),
            ],
          ] else
            Text(
              'This release has no .apk attached yet.',
              style: GoogleFonts.outfit(color: _amber, fontSize: 11.5),
            ),
        ],
      ),
    );
  }

  Widget _runTile(DevWorkflowRun run) {
    final (Color color, IconData icon, String label) = run.isRunning
        ? (_amber, Icons.autorenew_rounded, 'Running')
        : run.isSuccess
            ? (_green, Icons.check_circle_outline_rounded, 'Passed')
            : run.isFailure
                ? (_red, Icons.error_outline_rounded, 'Failed')
                : (_muted, Icons.remove_circle_outline_rounded, run.conclusion ?? 'Done');

    return _rowCard(
      onTap: () => _openInApp(context, run.url),
      leading: Icon(icon, color: color, size: 17),
      title: run.name,
      subtitleWidgets: [
        Text(label, style: GoogleFonts.outfit(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        if (run.branch.isNotEmpty)
          Text('  ·  ${run.branch}', style: GoogleFonts.outfit(color: _muted, fontSize: 11)),
        if (run.updatedAt != null)
          Text('  ·  ${_ago(run.updatedAt!)}', style: GoogleFonts.outfit(color: _muted, fontSize: 11)),
      ],
    );
  }

  Widget _issueTile(DevTaskIssue issue) {
    final isOpen = issue.state == 'open';
    return _rowCard(
      onTap: () => _openInApp(context, issue.url),
      leading: Icon(
        isOpen ? Icons.radio_button_unchecked_rounded : Icons.check_circle_outline_rounded,
        color: isOpen ? _amber : _green,
        size: 17,
      ),
      title: '#${issue.number}  ${issue.title}',
      subtitleWidgets: [
        Text(
          isOpen ? 'Open' : 'Done',
          style: GoogleFonts.outfit(
            color: isOpen ? _amber : _green,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (issue.updatedAt != null)
          Text('  ·  ${_ago(issue.updatedAt!)}', style: GoogleFonts.outfit(color: _muted, fontSize: 11)),
      ],
    );
  }

  Widget _rowCard({
    required VoidCallback onTap,
    required Widget leading,
    required String title,
    required List<Widget> subtitleWidgets,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(color: _text, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Row(children: subtitleWidgets),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new_rounded, color: _muted, size: 14),
            ],
          ),
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

// MOVED (Sep 2 2026 — Nizam: "developer option la app automation la
// repo name, owner name, git token inthellam Iruku atha apdiye line
// and logic maarama namma dev option kulla vachuru"). Same three
// fields, same ChittiDevTaskService.readToken/readRepo/saveToken/
// saveRepo calls as before on the Chitti AI settings screen — only
// moved to live under this Dev tab, next to everything else about the
// automation pipeline. Starts read-only (so the token never sits
// visible on screen by accident); "Edit" reveals the fields, "Save"
// writes through the same secure storage and collapses back.
class _GithubRepoConfigCard extends StatefulWidget {
  const _GithubRepoConfigCard();

  @override
  State<_GithubRepoConfigCard> createState() => _GithubRepoConfigCardState();
}

class _GithubRepoConfigCardState extends State<_GithubRepoConfigCard> {
  final _tokenCtrl = TextEditingController();
  final _ownerCtrl = TextEditingController();
  final _repoCtrl = TextEditingController();
  bool _editing = false;
  bool _saving = false;
  bool _loading = true;
  bool _hasToken = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = await ChittiDevTaskService.readToken();
    final repo = await ChittiDevTaskService.readRepo();
    if (!mounted) return;
    setState(() {
      _tokenCtrl.text = token ?? '';
      _ownerCtrl.text = repo.owner;
      _repoCtrl.text = repo.name;
      _hasToken = (token ?? '').isNotEmpty;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ChittiDevTaskService.saveToken(_tokenCtrl.text);
      await ChittiDevTaskService.saveRepo(owner: _ownerCtrl.text, name: _repoCtrl.text);
      if (!mounted) return;
      setState(() {
        _editing = false;
        _hasToken = _tokenCtrl.text.trim().isNotEmpty;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GitHub automation settings saved.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _ownerCtrl.dispose();
    _repoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: _purple)),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Lets Chitti open a GitHub issue tagging @claude when you ask it "
            "to build or fix something — the Claude Code GitHub App picks it "
            "up automatically. Use a fine-grained token scoped to ONLY this "
            "repo, with ONLY 'Issues: Write' permission.",
            style: GoogleFonts.outfit(color: _muted, fontSize: 11.5, height: 1.35),
          ),
          const SizedBox(height: 12),
          if (!_editing) ...[
            _readOnlyRow('Owner', _ownerCtrl.text.isEmpty ? '—' : _ownerCtrl.text),
            _readOnlyRow('Repo', _repoCtrl.text.isEmpty ? '—' : _repoCtrl.text),
            _readOnlyRow('Token', _hasToken ? '•' * 24 : 'Not set'),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _editing = true),
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: const Text('Edit'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _purple,
                  side: const BorderSide(color: _purple),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ownerCtrl,
                    style: const TextStyle(color: _text),
                    decoration: InputDecoration(
                      hintText: 'Repo owner (e.g. myallin1)',
                      hintStyle: const TextStyle(color: _muted),
                      filled: true,
                      fillColor: _bg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _repoCtrl,
                    style: const TextStyle(color: _text),
                    decoration: InputDecoration(
                      hintText: 'Repo name (e.g. Allin1)',
                      hintStyle: const TextStyle(color: _muted),
                      filled: true,
                      fillColor: _bg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tokenCtrl,
              obscureText: true,
              style: const TextStyle(color: _text),
              decoration: InputDecoration(
                hintText: 'Paste your GitHub fine-grained token',
                hintStyle: const TextStyle(color: _muted),
                prefixIcon: const Icon(Icons.key_rounded, color: _red),
                filled: true,
                fillColor: _bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => setState(() { _editing = false; _load(); }),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _muted,
                      side: const BorderSide(color: _border),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.check_rounded, size: 17),
                    label: const Text('Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _readOnlyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(label, style: GoogleFonts.outfit(color: _muted, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(color: _text, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
