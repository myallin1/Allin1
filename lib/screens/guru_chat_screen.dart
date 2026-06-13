import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/guru_api_service.dart';

class GuruChatScreen extends StatefulWidget {
  const GuruChatScreen({super.key});

  @override
  State<GuruChatScreen> createState() => _GuruChatScreenState();
}

class _GuruChatScreenState extends State<GuruChatScreen> {
  final GuruApiService _api = GuruApiService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_GuruMessage> _messages = <_GuruMessage>[
    const _GuruMessage(
      role: 'assistant',
      text:
          'Vanakkam. I am Guru AI, your Allin1 Super App assistant for Erode rides, NJ Tech repairs, Chamunda Spares, and local support.',
    ),
  ];

  bool _isTyping = false;

  @override
  void dispose() {
    _api.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final input = _inputController.text.trim();
    if (input.isEmpty || _isTyping) {
      return;
    }

    setState(() {
      _messages.add(_GuruMessage(role: 'user', text: input));
      _isTyping = true;
      _inputController.clear();
    });
    _scrollToBottom();

    final history = _messages
        .where(
          (message) => message.role == 'user' || message.role == 'assistant',
        )
        .map(
          (message) => <String, String>{
            'role': message.role,
            'content': message.text,
          },
        )
        .toList();

    final reply = await _api.sendMessage(
      message: input,
      history: history,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _messages.add(_GuruMessage(role: 'assistant', text: reply));
      _isTyping = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      unawaited(
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071A35),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF071A35),
              Color(0xFF111B4A),
              Color(0xFFFF4FA3),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.96),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 28,
                        offset: const Offset(0, -8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildConciergeStrip(),
                      Expanded(child: _buildMessages()),
                      if (_isTyping) const _GuruTypingIndicator(),
                      _buildInputBar(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFFF8BC6), Color(0xFFFFFFFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF4FA3).withValues(alpha: 0.55),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFF071A35),
              size: 30,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Guru AI',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  'Allin1 concierge for Erode',
                  style: GoogleFonts.notoSansTamil(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF64FFDA),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Live',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConciergeStrip() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF0F8), Color(0xFFEAF3FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFFC2DE)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.location_city_rounded,
            color: Color(0xFFFF4FA3),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Ask about Bike Taxi, NJ Tech mobile service, Chamunda Spares, wallet help, or anything around Erode.',
              style: GoogleFonts.notoSansTamil(
                color: const Color(0xFF26325C),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _GuruMessageBubble(message: message);
      },
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
        child: Row(
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF7FAFF),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE3E9F7)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF071A35).withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _inputController,
                  minLines: 1,
                  maxLines: 4,
                  onSubmitted: (_) => _sendMessage(),
                  textInputAction: TextInputAction.send,
                  style: GoogleFonts.notoSansTamil(
                    color: const Color(0xFF111B4A),
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Ask Guru AI...',
                    hintStyle: GoogleFonts.outfit(
                      color: const Color(0xFF7E8AA8),
                      fontWeight: FontWeight.w600,
                    ),
                    prefixIcon: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: Color(0xFFFF4FA3),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 15,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF4FA3), Color(0xFF1C2E72)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF4FA3).withValues(alpha: 0.34),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: _isTyping ? null : _sendMessage,
                icon: const Icon(Icons.send_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuruMessageBubble extends StatelessWidget {
  const _GuruMessageBubble({required this.message});

  final _GuruMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isUser) ...[
              const _GuruAvatar(size: 34),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 360),
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isUser
                        ? const [Color(0xFF1C2E72), Color(0xFF071A35)]
                        : const [Color(0xFFFFF1F8), Color(0xFFEAF3FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(22),
                    topRight: const Radius.circular(22),
                    bottomLeft: Radius.circular(isUser ? 22 : 6),
                    bottomRight: Radius.circular(isUser ? 6 : 22),
                  ),
                  border: Border.all(
                    color: isUser
                        ? Colors.white.withValues(alpha: 0.08)
                        : const Color(0xFFFFC8E1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isUser
                              ? const Color(0xFF071A35)
                              : const Color(0xFFFF4FA3))
                          .withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Text(
                  message.text,
                  style: GoogleFonts.notoSansTamil(
                    color: isUser ? Colors.white : const Color(0xFF17224D),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ],
        ),
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
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: Row(
        children: [
          const _GuruAvatar(size: 30),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F8),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFFC8E1)),
            ),
            child: AnimatedBuilder(
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
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF4FA3)
                              .withValues(alpha: 0.45 + scale * 0.35),
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
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
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFFF4FA3), Color(0xFF1C2E72)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF4FA3).withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        Icons.auto_awesome_rounded,
        color: Colors.white,
        size: size * 0.56,
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('size', size));
  }
}

class _GuruMessage {
  const _GuruMessage({
    required this.role,
    required this.text,
  });

  final String role;
  final String text;
}
