// ================================================================
// GuruChatScreen — Allin1 Super App
// ================================================================
// FIX (per Nizam's request): the old version was a heavy pink/blue
// gradient "chat widget" look — Nizam explicitly asked for this to
// read like a real mobile AI app (Claude-style): clean off-white
// background, minimal top bar, plain-text assistant replies (no
// speech-bubble chrome) vs a simple filled bubble for the user's own
// messages, a welcome state with tappable suggested-prompt chips when
// the conversation is empty, and a docked pill-shaped input bar.
// GuruApiService integration and message-history logic are unchanged
// from before — this is a visual redesign only.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/guru_api_service.dart';

const Color _bg = Color(0xFFF7F7F8);
const Color _surface = Colors.white;
const Color _ink = Color(0xFF1F1F23);
const Color _muted = Color(0xFF6E6E78);
const Color _accent = Color(0xFFD97757); // Claude-esque warm accent
const Color _userBubble = Color(0xFFEFEFF2);
const Color _border = Color(0xFFE7E7EB);

const List<String> _suggestedPrompts = [
  'Book a bike taxi in Erode',
  'Track my food order',
  'NJ Tech mobile repair status',
  'How does the wallet work?',
];

class GuruChatScreen extends StatefulWidget {
  const GuruChatScreen({super.key});

  @override
  State<GuruChatScreen> createState() => _GuruChatScreenState();
}

class _GuruChatScreenState extends State<GuruChatScreen> {
  final GuruApiService _api = GuruApiService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_GuruMessage> _messages = <_GuruMessage>[];

  bool _isTyping = false;

  @override
  void dispose() {
    _api.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage([String? presetText]) async {
    final input = (presetText ?? _inputController.text).trim();
    if (input.isEmpty || _isTyping) return;

    setState(() {
      _messages.add(_GuruMessage(role: 'user', text: input));
      _isTyping = true;
      _inputController.clear();
    });
    _scrollToBottom();

    final history = _messages
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .map((m) => <String, String>{'role': m.role, 'content': m.text})
        .toList();

    final reply = await _api.sendMessage(message: input, history: history);

    if (!mounted) return;

    setState(() {
      _messages.add(_GuruMessage(role: 'assistant', text: reply));
      _isTyping = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      unawaited(
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 160,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  void _startNewChat() {
    setState(() {
      _messages.clear();
      _inputController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(context),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? _buildWelcomeState()
                  : _buildMessages(),
            ),
            if (_isTyping) const _GuruTypingIndicator(),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: _surface,
      surfaceTintColor: _surface,
      elevation: 0,
      leading: IconButton(
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_rounded, color: _ink),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _GuruAvatar(size: 30),
          const SizedBox(width: 10),
          Text(
            'Guru AI',
            style: GoogleFonts.outfit(color: _ink, fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: _startNewChat,
          tooltip: 'New chat',
          icon: const Icon(Icons.add_comment_outlined, color: _muted),
        ),
        const SizedBox(width: 6),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _border),
      ),
    );
  }

  Widget _buildWelcomeState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _GuruAvatar(size: 56),
            const SizedBox(height: 18),
            Text(
              'Vanakkam! I\'m Guru AI.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: _ink, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Your Allin1 assistant for Erode rides, NJ Tech repairs, Chamunda Spares, and local support.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: _muted, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: _suggestedPrompts
                  .map((p) => _PromptChip(label: p, onTap: () => unawaited(_sendMessage(p))))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) => _GuruMessageBubble(message: _messages[index]),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 48, maxHeight: 140),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: TextField(
                  controller: _inputController,
                  minLines: 1,
                  maxLines: 5,
                  onSubmitted: (_) => unawaited(_sendMessage()),
                  textInputAction: TextInputAction.send,
                  style: GoogleFonts.notoSansTamil(color: _ink, fontWeight: FontWeight.w500, fontSize: 14.5),
                  decoration: InputDecoration(
                    hintText: 'Message Guru AI...',
                    hintStyle: GoogleFonts.outfit(color: _muted, fontWeight: FontWeight.w500),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              height: 44,
              child: DecoratedBox(
                decoration: BoxDecoration(color: _accent, shape: BoxShape.circle),
                child: IconButton(
                  onPressed: _isTyping ? null : () => unawaited(_sendMessage()),
                  icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PromptChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border),
        ),
        child: Text(label, style: GoogleFonts.outfit(color: _ink, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// FIX (per Nizam's request): a customer who claims the AI-quiz reward
// on the Rewards page WhatsApps us directly and we manually add their
// API key server-side to activate their subscription (see
// rewards_screen.dart's _AiQuizDialog._claimViaWhatsApp) — nothing
// about that manual admin step is exposed anywhere in this chat UI.
// The chat screen itself never asks for or displays API keys, plan
// status, or billing details; it's a plain chat experience regardless
// of whether a given customer's key has been provisioned yet.
class _GuruMessageBubble extends StatelessWidget {
  const _GuruMessageBubble({required this.message});

  final _GuruMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _userBubble,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              message.text,
              style: GoogleFonts.notoSansTamil(color: _ink, fontWeight: FontWeight.w500, fontSize: 14.5, height: 1.4),
            ),
          ),
        ),
      );
    }

    // Assistant replies render as plain text with a small avatar, no
    // bubble chrome — matches Claude's mobile-app message style.
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _GuruAvatar(size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message.text,
              style: GoogleFonts.notoSansTamil(color: _ink, fontWeight: FontWeight.w500, fontSize: 14.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<_GuruMessage>('message', message));
  }
}

class _GuruTypingIndicator extends StatefulWidget {
  const _GuruTypingIndicator();

  @override
  State<_GuruTypingIndicator> createState() => _GuruTypingIndicatorState();
}

class _GuruTypingIndicatorState extends State<_GuruTypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          const _GuruAvatar(size: 26),
          const SizedBox(width: 10),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (index) {
                  final phase = (_controller.value + index * 0.22) % 1;
                  final scale = 0.7 + (phase < 0.5 ? phase : 1 - phase) * 0.8;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      decoration: BoxDecoration(
                        color: _muted.withValues(alpha: 0.5 + scale * 0.3),
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _GuruAvatar extends StatelessWidget {
  const _GuruAvatar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: _accent,
      ),
      child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: size * 0.56),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('size', size));
  }
}

class _GuruMessage {
  const _GuruMessage({required this.role, required this.text});

  final String role;
  final String text;
}
