// ================================================================
// admin_antigravity_bridge_screen.dart — Antigravity IDE Mobile Remote Bridge
// ================================================================
// Allows Nizam/Admin to talk directly to the Antigravity IDE coding assistant
// from the Mobile PWA:
// - Upload Screenshots & Photos of bugs / UI designs
// - Send Voice/Text coding prompts
// - Track real-time AI execution logs, test passes, and deployments
// ================================================================

import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/antigravity_bridge_service.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF131326);
const Color _card = Color(0xFF1B1B33);
const Color _pink = Color(0xFFFF4FA3);
const Color _cyan = Color(0xFF00E5FF);
const Color _green = Color(0xFF00E676);
const Color _gold = Color(0xFFFFD600);
const Color _red = Color(0xFFFF5252);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF8888AA);

class AdminAntigravityBridgeScreen extends StatefulWidget {
  const AdminAntigravityBridgeScreen({super.key});

  @override
  State<AdminAntigravityBridgeScreen> createState() =>
      _AdminAntigravityBridgeScreenState();
}

class _AdminAntigravityBridgeScreenState
    extends State<AdminAntigravityBridgeScreen> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  bool _isSubmitting = false;
  String _selectedPriority = 'normal';

  final List<String> _quickPrompts = [
    '📱 Fix Mobile UI Alignment',
    '🐞 Fix Red Screen Error',
    '🎨 Polish Theme & Colors',
    '⚡ Speed up Splash / Loading',
    '🚀 Deploy Fresh Build',
  ];

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null) {
          setState(() {
            _selectedImageBytes = file.bytes;
            _selectedImageName = file.name;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not pick image: $e'),
          backgroundColor: _red,
        ),
      );
    }
  }

  void _clearImage() {
    setState(() {
      _selectedImageBytes = null;
      _selectedImageName = null;
    });
  }

  Future<void> _submitTask() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty && _selectedImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a prompt or attach a screenshot.'),
          backgroundColor: _red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      String? imageUrl;
      if (_selectedImageBytes != null) {
        imageUrl = await AntigravityBridgeService.instance.uploadScreenshot(
          _selectedImageBytes!,
          filename: _selectedImageName,
        );
      }

      await AntigravityBridgeService.instance.submitTask(
        prompt: prompt.isEmpty ? 'Screenshot submitted for analysis' : prompt,
        imageUrl: imageUrl,
        priority: _selectedPriority,
        clientContext: {
          'submittedFrom': 'Admin Mobile PWA',
          'url': Uri.base.toString(),
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      _promptController.clear();
      _clearImage();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚡ Task sent to Antigravity IDE Engine!'),
          backgroundColor: _green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Submission failed: $e'),
          backgroundColor: _red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _cyan.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bolt_rounded, color: _cyan, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Antigravity IDE Remote',
                    style: GoogleFonts.outfit(
                      color: _text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: _green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Live Bridge Connected',
                        style: GoogleFonts.inter(
                          color: _green,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Prompt & Attachment Input Card
          _buildComposerCard(),

          // Task History & Live Feed
          Expanded(
            child: StreamBuilder<List<AntigravityBridgeTask>>(
              stream: AntigravityBridgeService.instance.streamTasks(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: _cyan),
                  );
                }

                final tasks = snapshot.data ?? [];
                if (tasks.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.terminal_rounded,
                              size: 56, color: _muted.withValues(alpha: 0.5)),
                          const SizedBox(height: 16),
                          Text(
                            'No Active Tasks',
                            style: GoogleFonts.outfit(
                              color: _text,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Type a prompt or attach a mobile screenshot above to dispatch work directly to Antigravity IDE on your laptop.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: _muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return _buildTaskCard(task);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposerCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cyan.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: _cyan.withValues(alpha: 0.05),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick prompts horizontal list
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _quickPrompts.map((p) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 10),
                  child: ActionChip(
                    backgroundColor: _card,
                    side: BorderSide(color: _muted.withValues(alpha: 0.2)),
                    label: Text(
                      p,
                      style: GoogleFonts.inter(
                        color: _text,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onPressed: () {
                      _promptController.text = p;
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          // Main Prompt Field
          TextField(
            controller: _promptController,
            maxLines: 3,
            minLines: 2,
            style: GoogleFonts.inter(color: _text, fontSize: 13),
            decoration: InputDecoration(
              hintText:
                  'Tell Antigravity what to do (e.g. "Fix button color", "Why is checkout failing", etc.)...',
              hintStyle: GoogleFonts.inter(color: _muted, fontSize: 12),
              filled: true,
              fillColor: _card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),

          const SizedBox(height: 10),

          // Attached Image Preview if any
          if (_selectedImageBytes != null)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _pink.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      _selectedImageBytes!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedImageName ?? 'Screenshot attached',
                          style: GoogleFonts.inter(
                            color: _text,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${(_selectedImageBytes!.lengthInBytes / 1024).toStringAsFixed(1)} KB',
                          style: GoogleFonts.inter(
                            color: _muted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: _red, size: 20),
                    onPressed: _clearImage,
                  ),
                ],
              ),
            ),

          // Action Toolbar (Attach Screenshot + Submit)
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _isSubmitting ? null : _pickImage,
                icon: const Icon(Icons.add_photo_alternate_rounded,
                    color: _pink, size: 18),
                label: Text(
                  'Attach Screen',
                  style: GoogleFonts.inter(
                    color: _pink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _pink.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitTask,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 18),
                label: Text(
                  _isSubmitting ? 'Sending...' : 'Send to IDE',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _cyan,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(AntigravityBridgeTask task) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (task.status) {
      case AntigravityTaskStatus.inProgress:
        statusColor = _gold;
        statusLabel = 'IDE Executing';
        statusIcon = Icons.sync_rounded;
        break;
      case AntigravityTaskStatus.completed:
        statusColor = _green;
        statusLabel = 'Deployed & Verified';
        statusIcon = Icons.check_circle_rounded;
        break;
      case AntigravityTaskStatus.failed:
        statusColor = _red;
        statusLabel = 'Failed';
        statusIcon = Icons.error_rounded;
        break;
      case AntigravityTaskStatus.pending:
      default:
        statusColor = _cyan;
        statusLabel = 'Queued for IDE';
        statusIcon = Icons.schedule_rounded;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Status Badge & Time
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: statusColor, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: GoogleFonts.inter(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                _formatTime(task.createdAt),
                style: GoogleFonts.inter(
                  color: _muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Prompt text
          Text(
            task.prompt,
            style: GoogleFonts.inter(
              color: _text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),

          // Attached Screenshot Thumbnail
          if (task.imageUrl != null && task.imageUrl!.isNotEmpty) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _showImageDialog(context, task.imageUrl!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 120,
                  width: double.infinity,
                  color: _card,
                  child: Image.network(
                    task.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_rounded, color: _muted),
                    ),
                  ),
                ),
              ),
            ),
          ],

          // Agent Response / Notes
          if (task.agentResponse != null &&
              task.agentResponse!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _green.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.smart_toy_rounded,
                          color: _green, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'Antigravity Result',
                        style: GoogleFonts.inter(
                          color: _green,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    task.agentResponse!,
                    style: GoogleFonts.inter(
                      color: _text,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Logs
          if (task.logs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              task.logs.last,
              style: GoogleFonts.inter(
                color: _muted,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(imageUrl, fit: BoxFit.contain),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}';
  }
}
