// ================================================================
// admin_tabbed_browser_screen.dart — Multi-tab In-App Browser with
// Offline Reader View for Allin1 Admin
// ================================================================
// Allows admin to open build runs, dev tasks, and status links in
// separate tabs inside the app without leaving to an external browser.
// Preserves tab scroll position and DOM state across switches.
// Persists visited pages into local Hive storage (AdminInAppBrowserService)
// with lightweight text snapshots for offline reading when disconnected.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../services/admin_in_app_browser_service.dart';
import '../../services/admin_webview_power.dart';
import '../../widgets/admin_apk_download_progress_sheet.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _card = Color(0xFF141420);
const Color _surface = Color(0xFF1B1B2C);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);
const Color _purple = Color(0xFFB21FFF);
const Color _accent = Color(0xFF6C63FF);
const Color _green = Color(0xFF4ADE80);
const Color _amber = Color(0xFFFFB020);
const Color _red = Color(0xFFE05555);

/// An individual tab state holding its controller and offline snapshot.
class BrowserTabItem {
  BrowserTabItem({
    required this.id,
    required this.url,
    required this.title,
    required this.controller,
    this.isLoading = true,
    this.progress = 0,
    this.isOffline = false,
    this.offlineSnapshot,
  });

  final String id;
  String url;
  String title;
  final WebViewController controller;
  bool isLoading;
  int progress;
  bool isOffline;
  AdminBrowserHistoryEntry? offlineSnapshot;
}

class AdminTabbedBrowserScreen extends StatefulWidget {
  const AdminTabbedBrowserScreen({super.key});

  /// The active tabs preserved in memory so existing tabs, scroll
  /// positions, and DOM states survive navigation.
  static final List<BrowserTabItem> _tabs = [];
  static int _activeTabIndex = 0;
  static _AdminTabbedBrowserScreenState? _live;

  // NEW (Sep 21 2026 — Nizam: "app close pannitu reopen pannunalum
  // same stage la irukanum"). _tabs above only survives while the app
  // PROCESS is alive — a real close (swipe away from recents, or
  // Android killing a backgrounded process) resets it to empty, and
  // initState below used to always fall back to a hardcoded GitHub
  // homepage in that case, silently discarding whatever the admin
  // actually had open (a Claude Code session, a specific PR, etc.).
  // This persists just the open tabs' URL + title (not scroll
  // position/DOM — that genuinely cannot survive a killed WebView, no
  // different from a real browser losing scroll on a cold-start
  // restore) so the SAME pages reopen automatically, matching how
  // every other admin section already restores its own last state.
  static const String _kPersistedTabsKey = 'admin_browser_persisted_tabs_v1';

  static Future<void> _persistTabs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_tabs.isEmpty) {
        await prefs.remove(_kPersistedTabsKey);
        return;
      }
      final data = <String, dynamic>{
        'activeIndex': _activeTabIndex,
        'tabs': _tabs
            .map((t) => <String, String>{'url': t.url, 'title': t.title})
            .toList(),
      };
      await prefs.setString(_kPersistedTabsKey, jsonEncode(data));
    } catch (e) {
      debugPrint('[AdminTabbedBrowserScreen] persist tabs failed: $e');
    }
  }

  /// Recreates every previously-open tab from the last saved session.
  /// Returns true if anything was restored, so the caller knows not to
  /// fall back to the default GitHub tab.
  static Future<bool> _restoreTabs(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPersistedTabsKey);
      if (raw == null || raw.isEmpty) return false;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final savedTabs = (data['tabs'] as List<dynamic>?) ?? const [];
      if (savedTabs.isEmpty) return false;

      for (final entry in savedTabs) {
        final map = entry as Map<String, dynamic>;
        final url = map['url'] as String? ?? '';
        if (url.isEmpty) continue;
        final tabId = 'tab_${DateTime.now().microsecondsSinceEpoch}';
        final controller = WebViewController();
        final tab = BrowserTabItem(
          id: tabId,
          url: url,
          title: (map['title'] as String?) ?? url,
          controller: controller,
        );
        _tabs.add(tab);
        _setupTabController(tab);
        unawaited(controller.loadRequest(Uri.parse(url)));
      }
      if (_tabs.isEmpty) return false;

      final savedActive = (data['activeIndex'] as num?)?.toInt() ?? 0;
      _activeTabIndex = savedActive.clamp(0, _tabs.length - 1);
      return true;
    } catch (e) {
      debugPrint('[AdminTabbedBrowserScreen] restore tabs failed: $e');
      return false;
    }
  }

  /// Hands a URL to the browser, creating a new tab or selecting an existing
  /// one, and brings AdminTabbedBrowserScreen onto screen.
  static Future<void> openInNewTab(
    BuildContext context,
    String url, {
    String? title,
  }) async {
    var cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }

    // Check if the URL is already open in an existing tab
    final existingIndex = _tabs.indexWhere((t) => t.url == cleanUrl);
    if (existingIndex >= 0) {
      _activeTabIndex = existingIndex;
      unawaited(_persistTabs());
      if (_live != null && _live!.mounted) {
        _live!._refreshUI();
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const AdminTabbedBrowserScreen(),
          ),
        );
      }
      return;
    }

    // Otherwise, create a new tab
    final tabId = 'tab_${DateTime.now().millisecondsSinceEpoch}';
    final controller = WebViewController();

    final newTab = BrowserTabItem(
      id: tabId,
      url: cleanUrl,
      title: title ?? cleanUrl,
      controller: controller,
    );

    _tabs.add(newTab);
    _activeTabIndex = _tabs.length - 1;

    _setupTabController(newTab);

    // Load URL
    unawaited(controller.loadRequest(Uri.parse(cleanUrl)));
    unawaited(_persistTabs());

    if (_live != null && _live!.mounted) {
      _live!._refreshUI();
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const AdminTabbedBrowserScreen(),
        ),
      );
    }
  }

  static void _setupTabController(BrowserTabItem tab) {
    final c = tab.controller;
    c.setJavaScriptMode(JavaScriptMode.unrestricted);
    // FIX (Sep 21 2026 — Nizam: embedded Claude/GitHub access, "finishing
    // touch" gap found auditing the Dev Studio's "Open Web Console"
    // button). webview_flutter's default Android WebView user-agent
    // carries a "; wv)" marker that Google's own sign-in flow actively
    // detects and blocks with "This browser or app may not be secure" —
    // this is a deliberate Google anti-embedded-webview policy, not a
    // bug in this app, and it would have silently broken logging into
    // claude.ai or GitHub's Google-SSO option inside this browser no
    // matter how correct everything else here is. Presenting as a
    // normal mobile Chrome UA (no "wv" token) is the standard, widely
    // documented way apps that legitimately need embedded authenticated
    // browsing for their OWN admin's OWN account work around this —
    // not a way to impersonate someone else or bypass a real security
    // boundary.
    unawaited(
      c.setUserAgent(
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/124.0.0.0 Mobile Safari/537.36',
      ),
    );

    c.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (url) {
          tab.isLoading = true;
          tab.url = url;
          tab.isOffline = false;
          _live?._refreshUI();
        },
        onProgress: (progress) {
          tab.progress = progress;
          _live?._refreshUI();
        },
        onPageFinished: (url) async {
          tab.isLoading = false;
          tab.url = url;
          tab.isOffline = false;
          _live?._refreshUI();

          // Extract title and text snapshot for offline history
          try {
            final titleObj =
                await c.runJavaScriptReturningResult('document.title');
            final pageTitle = _cleanJsString(titleObj.toString());
            if (pageTitle.isNotEmpty) {
              tab.title = pageTitle;
            }

            final textObj = await c.runJavaScriptReturningResult(
              'document.body ? document.body.innerText.substring(0, 40000) : ""',
            );
            final pageText = _cleanJsString(textObj.toString());

            if (pageText.isNotEmpty) {
              await AdminInAppBrowserService.recordVisit(
                url: url,
                title: tab.title,
                textContent: pageText,
              );
            }
          } catch (_) {}
          unawaited(_persistTabs());
          _live?._refreshUI();
        },
        onWebResourceError: (error) async {
          if (error.isForMainFrame ?? true) {
            tab.isLoading = false;
            // Check for cached offline snapshot
            final cached =
                await AdminInAppBrowserService.getEntryByUrl(tab.url);
            if (cached != null && cached.hasSnapshot) {
              tab.isOffline = true;
              tab.offlineSnapshot = cached;
            }
            _live?._refreshUI();
          }
        },
        onNavigationRequest: (request) {
          final reqUrl = request.url;
          if (isApkDownloadUrl(reqUrl)) {
            final ctx = _live?.context;
            if (ctx != null && ctx.mounted) {
              unawaited(
                showApkDownloadProgressSheet(
                  ctx,
                  apkUrl: reqUrl,
                  fileName: apkFileNameFromUrl(reqUrl),
                ),
              );
            }
            return NavigationDecision.prevent;
          }

          final scheme = Uri.tryParse(reqUrl)?.scheme ?? '';
          if (scheme == 'http' || scheme == 'https') {
            return NavigationDecision.navigate;
          }

          unawaited(
            launchUrl(
              Uri.parse(reqUrl),
              mode: LaunchMode.externalApplication,
            ),
          );
          return NavigationDecision.prevent;
        },
      ),
    );

    final platform = c.platform;
    if (platform is AndroidWebViewController) {
      unawaited(
        AndroidWebViewCookieManager(
          const PlatformWebViewCookieManagerCreationParams(),
        ).setAcceptThirdPartyCookies(platform, true),
      );
    }
  }

  static String _cleanJsString(String raw) {
    var s = raw.trim();
    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      s = s.substring(1, s.length - 1);
    }
    return s
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'")
        .replaceAll(r'\\', r'\');
  }

  @override
  State<AdminTabbedBrowserScreen> createState() =>
      _AdminTabbedBrowserScreenState();
}

class _AdminTabbedBrowserScreenState extends State<AdminTabbedBrowserScreen>
    with WidgetsBindingObserver {
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    AdminTabbedBrowserScreen._live = this;
    WidgetsBinding.instance.addObserver(this);
    _syncPower();

    // If no tabs exist yet (fresh app process — the in-memory _tabs
    // list doesn't survive a real close), try restoring the last
    // session before falling back to the GitHub default.
    if (AdminTabbedBrowserScreen._tabs.isEmpty) {
      unawaited(_restoreOrDefault());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (AdminTabbedBrowserScreen._live == this) {
      AdminTabbedBrowserScreen._live = null;
    }
    unawaited(AdminWebViewPower.setActive(active: false));
    super.dispose();
  }

  void _syncPower() {
    unawaited(AdminWebViewPower.setActive(active: _foreground));
  }

  Future<void> _restoreOrDefault() async {
    final restored = await AdminTabbedBrowserScreen._restoreTabs(context);
    if (!mounted) return;
    if (restored) {
      setState(() {});
      return;
    }
    unawaited(
      AdminTabbedBrowserScreen.openInNewTab(
        context,
        'https://github.com/myallin1/Allin1',
        title: 'Allin1 GitHub',
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _foreground = state == AppLifecycleState.resumed;
    _syncPower();
  }

  void _refreshUI() {
    if (mounted) setState(() {});
  }

  BrowserTabItem? get _activeTab {
    final tabs = AdminTabbedBrowserScreen._tabs;
    if (tabs.isEmpty) return null;
    final index = AdminTabbedBrowserScreen._activeTabIndex.clamp(
      0,
      tabs.length - 1,
    );
    return tabs[index];
  }

  void _selectTab(int index) {
    setState(() {
      AdminTabbedBrowserScreen._activeTabIndex = index;
    });
    unawaited(AdminTabbedBrowserScreen._persistTabs());
  }

  void _closeTab(int index) {
    setState(() {
      final tabs = AdminTabbedBrowserScreen._tabs;
      if (index >= 0 && index < tabs.length) {
        final closingTab = tabs[index];
        unawaited(closingTab.controller.loadRequest(Uri.parse('about:blank')));
        tabs.removeAt(index);
        if (AdminTabbedBrowserScreen._activeTabIndex >= tabs.length) {
          AdminTabbedBrowserScreen._activeTabIndex =
              tabs.isEmpty ? 0 : tabs.length - 1;
        }
        unawaited(AdminTabbedBrowserScreen._persistTabs());
      }
    });

    if (AdminTabbedBrowserScreen._tabs.isEmpty) {
      Navigator.of(context).maybePop();
    }
  }

  void _openNewBlankTab() {
    _showUrlInputDialog();
  }

  Future<void> _showUrlInputDialog() async {
    final urlController = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(
          'Open URL in New Tab',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: urlController,
          style: GoogleFonts.outfit(color: _text),
          decoration: InputDecoration(
            hintText: 'https://github.com/...',
            hintStyle: GoogleFonts.outfit(color: _muted),
            filled: true,
            fillColor: _bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _border),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: GoogleFonts.outfit(color: _muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(urlController.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
            ),
            child: const Text('Open'),
          ),
        ],
      ),
    );

    if (entered != null && entered.isNotEmpty && mounted) {
      var finalUrl = entered;
      if (!finalUrl.startsWith('http://') && !finalUrl.startsWith('https://')) {
        finalUrl = 'https://$finalUrl';
      }
      AdminTabbedBrowserScreen.openInNewTab(context, finalUrl);
    }
  }

  Future<void> _openOfflineHistorySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _OfflineHistorySheet(
        onSelectUrl: (url, snapshot) {
          Navigator.of(ctx).pop();
          final tab = _activeTab;
          if (tab != null) {
            tab.url = url;
            tab.title = snapshot?.title ?? url;
            if (snapshot != null && snapshot.hasSnapshot) {
              tab.isOffline = true;
              tab.offlineSnapshot = snapshot;
            } else {
              tab.isOffline = false;
            }
            tab.controller.loadRequest(Uri.parse(url));
            _refreshUI();
          } else {
            AdminTabbedBrowserScreen.openInNewTab(context, url);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = AdminTabbedBrowserScreen._tabs;
    final activeTab = _activeTab;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final tab = _activeTab;
        if (tab != null) {
          try {
            if (await tab.controller.canGoBack()) {
              await tab.controller.goBack();
              return;
            }
          } catch (_) {}
        }
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(
            children: [
              // Top App & Navigation Bar
              _topNavigationRow(activeTab),
              // Tab Strip
              _tabStrip(tabs),
              // Loading Progress Bar
              if (activeTab != null && activeTab.isLoading)
                LinearProgressIndicator(
                  value:
                      activeTab.progress > 0 ? activeTab.progress / 100 : null,
                  color: _purple,
                  backgroundColor: _card,
                  minHeight: 2.5,
                ),
              // Web View Stack or Offline Reader Card
              Expanded(
                child: tabs.isEmpty
                    ? _emptyTabsView()
                    : Stack(
                        children: [
                          for (int i = 0; i < tabs.length; i++)
                            Offstage(
                              offstage:
                                  i != AdminTabbedBrowserScreen._activeTabIndex,
                              child: tabs[i].isOffline &&
                                      tabs[i].offlineSnapshot != null
                                  ? _offlineReaderView(tabs[i])
                                  : WebViewWidget(
                                      key: ValueKey(tabs[i].id),
                                      controller: tabs[i].controller,
                                    ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topNavigationRow(BrowserTabItem? tab) {
    return Container(
      color: _card,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: _text, size: 20),
            tooltip: 'Back to Dev Monitor',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, color: _text, size: 22),
            tooltip: 'Web Page Back',
            onPressed: tab == null
                ? null
                : () async {
                    if (await tab.controller.canGoBack()) {
                      await tab.controller.goBack();
                    }
                  },
          ),
          IconButton(
            icon:
                const Icon(Icons.chevron_right_rounded, color: _text, size: 22),
            tooltip: 'Web Page Forward',
            onPressed: tab == null
                ? null
                : () async {
                    if (await tab.controller.canGoForward()) {
                      await tab.controller.goForward();
                    }
                  },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _text, size: 19),
            tooltip: 'Reload Page',
            onPressed: tab == null
                ? null
                : () {
                    tab.isOffline = false;
                    tab.controller.reload();
                    _refreshUI();
                  },
          ),
          // Address / Domain Pill
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  Icon(
                    tab?.isOffline ?? false
                        ? Icons.offline_bolt_rounded
                        : Icons.lock_outline_rounded,
                    size: 13,
                    color: (tab?.isOffline ?? false) ? _amber : _green,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tab?.url ?? 'No URL',
                      style: GoogleFonts.outfit(
                        color: _text,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded, color: _purple, size: 21),
            tooltip: 'Offline Saved History',
            onPressed: _openOfflineHistorySheet,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: _muted, size: 19),
            tooltip: 'Share Link',
            onPressed: tab == null
                ? null
                : () {
                    SharePlus.instance.share(
                      ShareParams(
                        text: tab.url,
                        subject: tab.title,
                      ),
                    );
                  },
          ),
        ],
      ),
    );
  }

  Widget _tabStrip(List<BrowserTabItem> tabs) {
    return Container(
      color: _card,
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              itemBuilder: (ctx, index) {
                final tab = tabs[index];
                final isSelected =
                    index == AdminTabbedBrowserScreen._activeTabIndex;
                return GestureDetector(
                  onTap: () => _selectTab(index),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.only(left: 10, right: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _purple.withValues(alpha: 0.22)
                          : _surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? _purple : _border,
                        width: isSelected ? 1.2 : 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (tab.isOffline)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.offline_pin_rounded,
                              size: 13,
                              color: _amber,
                            ),
                          ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: Text(
                            tab.title.isNotEmpty ? tab.title : 'Tab',
                            style: GoogleFonts.outfit(
                              color: isSelected ? Colors.white : _muted,
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => _closeTab(index),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              size: 13,
                              color: isSelected ? Colors.white70 : _muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded, color: _text, size: 20),
            tooltip: 'New Tab',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _openNewBlankTab,
          ),
        ],
      ),
    );
  }

  Widget _emptyTabsView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.tab_unselected_rounded,
            color: _muted,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'All browser tabs closed',
            style: GoogleFonts.outfit(
              color: _text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _openNewBlankTab,
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Open New Tab'),
          ),
        ],
      ),
    );
  }

  Widget _offlineReaderView(BrowserTabItem tab) {
    final snapshot = tab.offlineSnapshot!;
    return Container(
      color: _bg,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Offline Reader Mode Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _amber.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.wifi_off_rounded, color: _amber, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Offline Reader Snapshot',
                        style: GoogleFonts.outfit(
                          color: _amber,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Saved locally · Visited ${snapshot.date} (${snapshot.visitCount}x)',
                        style: GoogleFonts.outfit(color: _muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    tab.isOffline = false;
                    tab.controller.reload();
                    _refreshUI();
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  label: const Text('Reload Live'),
                  style: TextButton.styleFrom(
                    foregroundColor: _amber,
                    textStyle: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Page Title
          SelectableText(
            snapshot.title,
            style: GoogleFonts.outfit(
              color: _text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          // Page URL
          SelectableText(
            snapshot.url,
            style: GoogleFonts.outfit(
              color: _accent,
              fontSize: 11,
            ),
          ),
          const Divider(color: _border, height: 24),
          // Rendered Text Content
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  snapshot.textContent,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: _text,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineHistorySheet extends StatefulWidget {
  const _OfflineHistorySheet({required this.onSelectUrl});

  final void Function(String url, AdminBrowserHistoryEntry? snapshot)
      onSelectUrl;

  @override
  State<_OfflineHistorySheet> createState() => _OfflineHistorySheetState();
}

class _OfflineHistorySheetState extends State<_OfflineHistorySheet> {
  List<AdminBrowserHistoryEntry> _history = [];
  bool _loading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = _searchQuery.isEmpty
        ? await AdminInAppBrowserService.getHistory()
        : await AdminInAppBrowserService.searchHistory(_searchQuery);
    if (!mounted) return;
    setState(() {
      _history = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: _muted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Offline History & Snapshots',
                style: GoogleFonts.outfit(
                  color: _text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_history.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    await AdminInAppBrowserService.clearAll();
                    _load();
                  },
                  child: Text(
                    'Clear All',
                    style: GoogleFonts.outfit(color: _red, fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Search box
          TextField(
            style: GoogleFonts.outfit(color: _text, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search visited pages and logs...',
              hintStyle: GoogleFonts.outfit(color: _muted, fontSize: 12),
              prefixIcon: const Icon(Icons.search_rounded, color: _muted),
              filled: true,
              fillColor: _card,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _border),
              ),
            ),
            onChanged: (v) {
              _searchQuery = v;
              _load();
            },
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _purple),
                  )
                : _history.isEmpty
                    ? Center(
                        child: Text(
                          'No history or offline snapshots found.',
                          style: GoogleFonts.outfit(color: _muted, fontSize: 13),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _history.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: _border, height: 1),
                        itemBuilder: (ctx, i) {
                          final item = _history[i];
                          return ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 4),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: item.hasSnapshot
                                    ? _amber.withValues(alpha: 0.15)
                                    : _surface,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                item.hasSnapshot
                                    ? Icons.offline_pin_rounded
                                    : Icons.public_rounded,
                                color: item.hasSnapshot ? _amber : _muted,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              item.title.isNotEmpty ? item.title : item.url,
                              style: GoogleFonts.outfit(
                                color: _text,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${item.date} · ${item.visitCount} visits · ${item.hasSnapshot ? "Snapshot saved" : "URL only"}',
                              style: GoogleFonts.outfit(
                                color: _muted,
                                fontSize: 11,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  size: 16, color: _muted,),
                              onPressed: () async {
                                await AdminInAppBrowserService.deleteEntry(
                                  item.id,
                                );
                                _load();
                              },
                            ),
                            onTap: () => widget.onSelectUrl(item.url, item),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
