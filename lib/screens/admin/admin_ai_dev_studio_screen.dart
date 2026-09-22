// ================================================================
// admin_ai_dev_studio_screen.dart — AI Copilot & Dev Studio for Admin
// ================================================================
// Dual-engine AI workspace (Claude Code @claude & Gemini @gemini)
// allowing admin to upload issue screenshots, voice/text prompts,
// and dispatch automated GitHub dev tasks or open interactive consoles
// right inside the Admin App without leaving to an external laptop.
//
// Follows AGENTS.md 4-Phase Protocol (Analyze -> Plan -> Confirm -> Execute).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../services/chitti/chitti_dev_monitor_service.dart';
import '../../services/chitti/chitti_dev_task_service.dart';
import '../../services/cloudinary_upload_service.dart';
import 'admin_app_error_log_screen.dart';
import 'admin_claude_dev_tabs_screen.dart';
import 'chitti_dev_monitor_screen.dart';

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
const Color _cyan = Color(0xFF00E5FF);
const Color _claudeOrange = Color(0xFFD97706);
const Color _geminiBlue = Color(0xFF3B82F6);

class AdminAiDevStudioScreen extends StatefulWidget {
  const AdminAiDevStudioScreen({
    super.key,
    this.initialEngine = ChittiDevEngine.claude,
    this.initialTitle,
    this.initialDescription,
    this.initialAppVariant,
  });

  final ChittiDevEngine initialEngine;
  final String? initialTitle;
  final String? initialDescription;
  final String? initialAppVariant;

  @override
  State<AdminAiDevStudioScreen> createState() => _AdminAiDevStudioScreenState();
}

class _AdminAiDevStudioScreenState extends State<AdminAiDevStudioScreen> {
  late ChittiDevEngine _selectedEngine;
  bool _planFirst = true; // AGENTS.md rule: Plan first before coding
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();

  String _selectedApp = 'Allin1 Super App';
  String _selectedCategory = 'Bug Fix / UI Issue';

  Uint8List? _imageBytes;
  bool _isUploadingImage = false;
  String? _uploadedImageUrl;

  bool _isSubmitting = false;
  String? _lastCreatedIssueUrl;
  int? _lastCreatedIssueNumber;
  String? _statusMessage;
  bool _isStatusError = false;

  // Voice speech-to-text dictation
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  List<DevTaskIssue> _recentIssues = [];
  bool _loadingIssues = false;

  final List<String> _appOptions = [
    'Allin1 Super App',
    'Customer App (main_customer.dart)',
    'Super Hero App (main_hero.dart)',
    'Seller App (main_seller.dart)',
    'Admin App (main_admin.dart)',
    'Backend / Cloud Firestore Rules',
  ];

  final List<String> _categoryOptions = [
    'Bug Fix / UI Issue',
    'New Feature Request',
    'Crash / Error Log Resolution',
    'Layout & UI Reordering',
    'Security / Quota Audit',
  ];

  @override
  void initState() {
    super.initState();
    _selectedEngine = widget.initialEngine;
    if (widget.initialTitle != null) {
      _titleCtrl.text = widget.initialTitle!;
    }
    if (widget.initialDescription != null) {
      _descCtrl.text = widget.initialDescription!;
    }
    if (widget.initialAppVariant != null &&
        _appOptions.contains(widget.initialAppVariant)) {
      _selectedApp = widget.initialAppVariant!;
    }
    _initSpeech();
    _loadRecentIssues();
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speech.initialize(
        onError: (err) => debugPrint('[AdminAiDevStudio] STT Error: $err'),
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
      );
      if (mounted) setState(() => _speechAvailable = available);
    } catch (_) {
      if (mounted) setState(() => _speechAvailable = false);
    }
  }

  Future<void> _toggleVoiceInput() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition is not available on this device.')),
      );
      return;
    }

    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
    } else {
      final baseText = _descCtrl.text.trim();
      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (result) {
          if (mounted) {
            setState(() {
              final recognized = result.recognizedWords.trim();
              if (recognized.isNotEmpty) {
                final text = baseText.isEmpty ? recognized : '$baseText $recognized';
                _descCtrl.text = text;
                _descCtrl.selection = TextSelection.collapsed(offset: text.length);
              }
            });
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _loadRecentIssues() async {
    setState(() => _loadingIssues = true);
    try {
      final snapshot = await ChittiDevMonitorService.fetch();
      if (mounted) {
        setState(() {
          _recentIssues = snapshot.issues.take(5).toList();
          _loadingIssues = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingIssues = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _uploadedImageUrl = null;
      });

      // Upload to Cloudinary in the background
      _uploadImageToCloudinary(bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _red,
            content: Text('Could not pick image: $e', style: const TextStyle(color: Colors.white)),
          ),
        );
      }
    }
  }

  Future<void> _uploadImageToCloudinary(Uint8List bytes) async {
    setState(() => _isUploadingImage = true);
    try {
      final uploadService = CloudinaryUploadService();
      if (uploadService.isConfigured) {
        final url = await uploadService.uploadImageBytes(
          bytes,
          folder: 'dev_issues',
          fileName: 'issue_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        if (mounted) {
          setState(() {
            _uploadedImageUrl = url;
            _isUploadingImage = false;
          });
        }
      } else {
        if (mounted) setState(() => _isUploadingImage = false);
      }
    } catch (e) {
      debugPrint('[AdminAiDevStudio] Image upload error: $e');
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  void _clearImage() {
    setState(() {
      _imageBytes = null;
      _uploadedImageUrl = null;
    });
  }

  Future<void> _dispatchTask() async {
    final title = _titleCtrl.text.trim();
    final description = _descCtrl.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: _red,
          content: Text('Please enter an issue title.', style: TextStyle(color: Colors.white)),
        ),
      );
      return;
    }

    // If image is still uploading, wait a moment for completion
    if (_isUploadingImage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Image is still uploading... finishing upload first.'),
          duration: Duration(seconds: 2),
        ),
      );
      int attempts = 0;
      while (_isUploadingImage && attempts < 10) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        attempts++;
      }
    }

    setState(() {
      _isSubmitting = true;
      _statusMessage = null;
      _isStatusError = false;
    });

    // Build structured Markdown body
    final buffer = StringBuffer();
    buffer.writeln('### 📱 Target Application / Component');
    buffer.writeln('**App:** $_selectedApp');
    buffer.writeln('**Category:** $_selectedCategory');
    buffer.writeln('**Target AI Engine:** ${_selectedEngine.label} (${_selectedEngine.mention})');
    buffer.writeln();

    buffer.writeln('### 📝 Problem Description & Requirements');
    buffer.writeln(description.isEmpty ? title : description);
    buffer.writeln();

    if (_uploadedImageUrl != null && _uploadedImageUrl!.isNotEmpty) {
      buffer.writeln('### 🖼️ Attached Screenshot / Reference');
      buffer.writeln('![$title]($_uploadedImageUrl)');
      buffer.writeln();
    }

    buffer.writeln('### 🛡️ AGENTS.md 4-Phase Protocol');
    buffer.writeln('1. **Phase 1 (Analyze):** Inspect existing codebase and grep references.');
    buffer.writeln('2. **Phase 2 (Plan):** Propose exact files to modify with zero breakage.');
    buffer.writeln('3. **Phase 3 (Confirm):** Await admin confirmation before merge.');
    buffer.writeln('4. **Phase 4 (Execute):** Minimal surgical edits, flutter analyze and unit tests.');

    final finalDescription = buffer.toString();

    ChittiDevTaskResult result;
    if (_planFirst) {
      result = await ChittiDevTaskService.createPlanIssue(
        title: '[$_selectedApp] $title',
        description: finalDescription,
        engine: _selectedEngine,
      );
    } else {
      result = await ChittiDevTaskService.createIssue(
        title: '[$_selectedApp] $title',
        description: finalDescription,
        engine: _selectedEngine,
      );
    }

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
      if (result.success) {
        _lastCreatedIssueUrl = result.issueUrl;
        _lastCreatedIssueNumber = result.issueNumber;
        _statusMessage = 'Task #${result.issueNumber ?? ''} created successfully and assigned to ${_selectedEngine.label}!';
        _isStatusError = false;
        _titleCtrl.clear();
        _descCtrl.clear();
        _clearImage();
        _loadRecentIssues();
      } else {
        _statusMessage = result.error ?? 'Failed to create dev task.';
        _isStatusError = true;
      }
    });
  }

  // FIX (Sep 22 2026 reaudit — real wiring collision, see
  // admin_claude_dev_tabs_screen.dart's openInClaudeBrowserTab() for
  // the full explanation): this used to call AdminTabbedBrowserScreen.
  // openInNewTab() directly, which is correct about WHICH tab/url to
  // show but not about bringing the admin (currently on the AI Studio
  // tab) to where that browser actually lives now — the dedicated
  // Claude bottom tab.
  void _openInAppBrowser(String url, {String? title}) {
    unawaited(
      openInClaudeBrowserTab(
        context,
        url,
        title: title ?? 'AI Dev Workspace',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_purple, _accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Text(
              'AI Dev Studio',
              style: GoogleFonts.outfit(
                color: _text,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined, color: _amber),
            tooltip: 'In-App Error Log',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminAppErrorLogScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.monitor_heart_outlined, color: _cyan),
            tooltip: 'Dev Monitor',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ChittiDevMonitorScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.language_rounded, color: _text),
            tooltip: 'Open In-App Browser',
            onPressed: () => _openInAppBrowser('https://github.com/myallin1/Allin1/issues', title: 'GitHub Issues'),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _purple,
        backgroundColor: _card,
        onRefresh: _loadRecentIssues,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // 1. Dual Engine Selector (Top Tabs: Claude vs Gemini)
            _buildEngineSelector(),
            const SizedBox(height: 16),

            // 2. Engine Info & Quick Launcher Card
            _buildEngineStatusCard(),
            const SizedBox(height: 16),

            // 3. Task Composer Form
            _buildTaskComposerCard(),
            const SizedBox(height: 20),

            // 4. Status / Result Banner (if any)
            if (_statusMessage != null) ...[
              _buildStatusBanner(),
              const SizedBox(height: 20),
            ],

            // 5. Recent Active Dev Tasks Feed
            _buildRecentTasksSection(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildEngineSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          // Claude Tab
          Expanded(
            child: _buildEngineTabButton(
              engine: ChittiDevEngine.claude,
              label: 'Claude Code',
              tag: '@claude',
              color: _claudeOrange,
              icon: Icons.code_rounded,
            ),
          ),
          const SizedBox(width: 4),
          // Gemini Tab
          Expanded(
            child: _buildEngineTabButton(
              engine: ChittiDevEngine.gemini,
              label: 'Gemini Coder',
              tag: '@gemini',
              color: _geminiBlue,
              icon: Icons.stars_rounded,
            ),
          ),
          const SizedBox(width: 4),
          // Antigravity Tab
          Expanded(
            child: _buildEngineTabButton(
              engine: ChittiDevEngine.antigravity,
              label: 'Antigravity',
              tag: '@agy',
              color: _green,
              icon: Icons.rocket_launch_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEngineTabButton({
    required ChittiDevEngine engine,
    required String label,
    required String tag,
    required Color color,
    required IconData icon,
  }) {
    final isSelected = _selectedEngine == engine;
    return InkWell(
      onTap: () => setState(() => _selectedEngine = engine),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: color, width: 1.5) : Border.all(color: Colors.transparent),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? color : _muted, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: isSelected ? _text : _muted,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              tag,
              style: TextStyle(
                color: isSelected ? color : _muted.withValues(alpha: 0.6),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEngineStatusCard() {
    Color engineColor;
    String engineDesc;
    String consoleUrl;

    switch (_selectedEngine) {
      case ChittiDevEngine.claude:
        engineColor = _claudeOrange;
        engineDesc = 'Claude Sonnet 5 / Claude Code automated GitHub action workflow. Best for deep refactoring and architectural fixes.';
        // FIX (Sep 21 2026 — Nizam: "claude desktop code... embedded
        // view la access"): was the generic claude.ai homepage. Points
        // at Claude's actual code workspace now, opened via the same
        // embedded in-app tabbed browser as everything else on this
        // card — not the device's external browser.
        consoleUrl = 'https://claude.ai/code';
        break;
      case ChittiDevEngine.gemini:
        engineColor = _geminiBlue;
        engineDesc = 'Gemini 2.5 Flash / Pro coding engine with high context window. Best for UI layouts, multimodal screenshots, and rapid patches.';
        consoleUrl = 'https://aistudio.google.com';
        break;
      case ChittiDevEngine.antigravity:
        engineColor = _green;
        engineDesc = 'Antigravity autonomous developer pipeline with multi-agent verification and system audits.';
        consoleUrl = 'https://github.com/myallin1/Allin1/actions';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: engineColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: engineColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'ACTIVE ENGINE: ${_selectedEngine.label.toUpperCase()}',
                  style: TextStyle(
                    color: engineColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => _openInAppBrowser(consoleUrl, title: '${_selectedEngine.label} Console'),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: [
                      Icon(Icons.open_in_new, size: 12, color: engineColor),
                      const SizedBox(width: 4),
                      Text(
                        'Open Web Console',
                        style: TextStyle(
                          color: engineColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            engineDesc,
            style: GoogleFonts.outfit(
              color: _text.withValues(alpha: 0.85),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskComposerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'COMPOSE AI DEV TASK',
            style: GoogleFonts.outfit(
              color: _muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 14),

          // App Selector Dropdown
          Text('Target App / Module', style: GoogleFonts.outfit(color: _text, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedApp,
                isExpanded: true,
                dropdownColor: _surface,
                icon: const Icon(Icons.arrow_drop_down, color: _muted),
                items: _appOptions.map((app) {
                  return DropdownMenuItem<String>(
                    value: app,
                    child: Text(app, style: const TextStyle(color: _text, fontSize: 13)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedApp = val);
                },
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Category Selector Dropdown
          Text('Task Category', style: GoogleFonts.outfit(color: _text, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedCategory,
                isExpanded: true,
                dropdownColor: _surface,
                icon: const Icon(Icons.arrow_drop_down, color: _muted),
                items: _categoryOptions.map((cat) {
                  return DropdownMenuItem<String>(
                    value: cat,
                    child: Text(cat, style: const TextStyle(color: _text, fontSize: 13)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedCategory = val);
                },
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Title Input Field
          Text('Task / Problem Title', style: GoogleFonts.outfit(color: _text, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _titleCtrl,
            style: const TextStyle(color: _text, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'e.g. Fix Hero Taxi accept popup not opening',
              hintStyle: const TextStyle(color: _muted, fontSize: 13),
              filled: true,
              fillColor: _surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _purple),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 14),

          // Description / Details Input Field with Voice Dictation Button
          Row(
            children: [
              Text('Detailed Instructions (Tamil/English)', style: GoogleFonts.outfit(color: _text, fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_speechAvailable)
                InkWell(
                  onTap: _toggleVoiceInput,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _isListening ? _red.withValues(alpha: 0.2) : _purple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _isListening ? _red : _purple),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_isListening ? Icons.mic : Icons.mic_none, size: 14, color: _isListening ? _red : _purple),
                        const SizedBox(width: 4),
                        Text(
                          _isListening ? 'Listening...' : 'Voice Input',
                          style: TextStyle(color: _isListening ? _red : _purple, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _descCtrl,
            maxLines: 4,
            style: const TextStyle(color: _text, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Describe what needs to be fixed or built. Include exact screen name or behavior...',
              hintStyle: const TextStyle(color: _muted, fontSize: 12),
              filled: true,
              fillColor: _surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _purple),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 14),

          // Quick Preset Chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildQuickPresetChip('🐞 Fix UI Bug', 'Fix layout overflow and alignment issue'),
              _buildQuickPresetChip('⚡ Add Feature', 'Add new customizable button and tile'),
              _buildQuickPresetChip('🛡️ Quota Safety', 'Audit Firestore reads and optimize stream listeners'),
              _buildQuickPresetChip('🔄 Reset Layout', 'Reset section tiles order to default layout'),
            ],
          ),
          const SizedBox(height: 16),

          // Image Attachment Preview / Selector
          Text('Attached Screenshot / Image', style: GoogleFonts.outfit(color: _text, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_imageBytes != null)
            Stack(
              children: [
                Container(
                  height: 160,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                    image: DecorationImage(
                      image: MemoryImage(_imageBytes!),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                if (_isUploadingImage)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: _purple, strokeWidth: 2),
                            SizedBox(height: 8),
                            Text('Uploading image...', style: TextStyle(color: Colors.white, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: InkWell(
                    onTap: _clearImage,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.black87,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined, size: 16),
                    label: const Text('Gallery', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _text,
                      side: const BorderSide(color: _border),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined, size: 16),
                    label: const Text('Camera', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _text,
                      side: const BorderSide(color: _border),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),

          // Plan-First Protocol Toggle (AGENTS.md compliance)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _planFirst ? _green.withValues(alpha: 0.3) : _border),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, color: _planFirst ? _green : _muted, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Plan First (AGENTS.md Safe Protocol)',
                        style: TextStyle(
                          color: _planFirst ? _green : _text,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      const Text(
                        'AI posts an audit plan first before creating code changes.',
                        style: TextStyle(color: _muted, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _planFirst,
                  activeThumbColor: _green,
                  onChanged: (val) => setState(() => _planFirst = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Submit Dispatch Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _dispatchTask,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Icon(
                      _selectedEngine == ChittiDevEngine.claude
                          ? Icons.code_rounded
                          : (_selectedEngine == ChittiDevEngine.gemini ? Icons.stars_rounded : Icons.rocket_launch_rounded),
                      size: 18,
                    ),
              label: Text(
                _isSubmitting
                    ? 'Dispatching Task...'
                    : 'Dispatch to ${_selectedEngine.label} (${_selectedEngine.mention})',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedEngine == ChittiDevEngine.claude
                    ? _claudeOrange
                    : (_selectedEngine == ChittiDevEngine.gemini ? _geminiBlue : _green),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickPresetChip(String label, String promptText) {
    return InkWell(
      onTap: () {
        setState(() {
          if (_descCtrl.text.isEmpty) {
            _descCtrl.text = promptText;
          } else {
            _descCtrl.text = '${_descCtrl.text}\n$promptText';
          }
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border),
        ),
        child: Text(
          label,
          style: const TextStyle(color: _text, fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    final isError = _isStatusError;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError ? _red.withValues(alpha: 0.15) : _green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isError ? _red : _green),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.check_circle_outline,
                color: isError ? _red : _green,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _statusMessage ?? '',
                  style: TextStyle(
                    color: isError ? _red : _green,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if (!isError && _lastCreatedIssueUrl != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _openInAppBrowser(
                    _lastCreatedIssueUrl!,
                    title: 'Issue #${_lastCreatedIssueNumber ?? ''}',
                  ),
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: const Text('View in In-App Browser', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _lastCreatedIssueUrl!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Issue link copied to clipboard!'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: const Text('Copy Link', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _text,
                    side: const BorderSide(color: _border),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentTasksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.history_rounded, color: _muted, size: 16),
            const SizedBox(width: 6),
            Text(
              'RECENT DEV TASKS',
              style: GoogleFonts.outfit(
                color: _muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            if (_loadingIssues)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: _purple),
              )
            else
              InkWell(
                onTap: _loadRecentIssues,
                child: const Icon(Icons.refresh, color: _muted, size: 16),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_recentIssues.isEmpty && !_loadingIssues)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: const Center(
              child: Text(
                'No dev tasks found in this repo yet.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ),
          )
        else
          ..._recentIssues.map((issue) {
            final isClosed = issue.state == 'closed';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isClosed ? _muted.withValues(alpha: 0.15) : _green.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isClosed ? Icons.check_circle : Icons.radio_button_checked,
                      color: isClosed ? _muted : _green,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#${issue.number} · ${issue.title}',
                          style: GoogleFonts.outfit(
                            color: _text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Status: ${issue.state.toUpperCase()}',
                          style: const TextStyle(color: _muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.open_in_new, color: _muted, size: 16),
                    tooltip: 'Open in In-App Browser',
                    onPressed: () => _openInAppBrowser(issue.url, title: '#${issue.number}'),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
