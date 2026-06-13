import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/ai_activation_service.dart';
import '../services/ai_service.dart';

class AIAssistantScreen extends StatefulWidget {
  const AIAssistantScreen({
    super.key,
    this.persona = AIPersona.customer,
  });

  final AIPersona persona;

  @override
  State<AIAssistantScreen> createState() => _AIAssistantScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<AIPersona>('persona', persona));
  }
}

class _AIAssistantScreenState extends State<AIAssistantScreen> {
  static const int _maxMessages = 50;

  final AIService _aiService = AIService();
  final TextEditingController _messageController = TextEditingController();
  late final List<_ChatMessage> _messages;

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _messages = <_ChatMessage>[
      _ChatMessage(
        role: 'assistant',
        text: widget.persona == AIPersona.hero
            ? 'Vanakkam Hero. I am Guru AI. Ready to help you stay sharp, positive, and focused on your rides.'
            : 'Vanakkam. I am Guru AI. I can help with rides, local services, NJ Tech offers, and quick decisions in Erode.',
      ),
    ];
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final input = _messageController.text.trim();
    final apiKey = context.read<AiActivationService>().apiKey.trim();
    if (input.isEmpty || _sending || apiKey.isEmpty) {
      return;
    }

    setState(() {
      _sending = true;
      _messages.add(_ChatMessage(role: 'user', text: input));
      _messageController.clear();
    });

    final reply = await _aiService.sendMessage(
      input,
      persona: widget.persona,
      history: _messages
          .where((message) => message.role == 'user' || message.role == 'assistant')
          .map(
            (message) => <String, String>{
              'role': message.role,
              'content': message.text,
            },
          )
          .toList(),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _messages.add(_ChatMessage(role: 'assistant', text: reply));
      _sending = false;
      _trimMessages();
    });
  }

  void _trimMessages() {
    if (_messages.length <= _maxMessages) return;
    final excess = _messages.length - _maxMessages;
    _messages.removeRange(1, 1 + excess);
  }

  @override
  Widget build(BuildContext context) {
    final aiActivation = context.watch<AiActivationService>();
    final hasApiKey = aiActivation.apiKey.trim().isNotEmpty;

    if (!hasApiKey) {
      return Scaffold(
        backgroundColor: const Color(0xFFFDF7FB),
        appBar: AppBar(
          title: Text(
            'Guru AI',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_open_rounded,
                  size: 44,
                  color: Color(0xFFFF4FA3),
                ),
                const SizedBox(height: 16),
                Text(
                  'Guru AI needs configuration first.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: const Color(0xFF4A1236),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Open AI Configuration in Settings to add your Groq API key, then come back to chat.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: const Color(0xFF8A4E72),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/ai-settings'),
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('Open AI Configuration'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFDF7FB),
      appBar: AppBar(
        title: Text(
          widget.persona == AIPersona.hero ? 'Guru AI for Heroes' : 'Guru AI',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
      ),
      body: _buildChatView(),
    );
  }

  Widget _buildChatView() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFF0F8), Color(0xFFFFFFFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFFF4FA3).withValues(alpha: 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF4FA3).withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4FA3).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: Color(0xFFFF4FA3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'For a 1-year Guru AI subscription, visit NJ TECH.',
                  style: GoogleFonts.outfit(
                    color: const Color(0xFF412031),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFFD1E6)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4FA3).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.smart_toy_rounded,
                  color: Color(0xFFFF4FA3),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Guru AI is live with your personal Groq key.',
                  style: GoogleFonts.outfit(
                    color: const Color(0xFF412031),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];
              final isUser = message.role == 'user';
              return Align(
                alignment:
                    isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  constraints: const BoxConstraints(maxWidth: 340),
                  decoration: BoxDecoration(
                    color: isUser ? const Color(0xFFFF4FA3) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isUser
                          ? const Color(0xFFFF4FA3)
                          : const Color(0xFFFFD6E8),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (isUser
                                ? const Color(0xFFFF4FA3)
                                : const Color(0xFFFFA4CF))
                            .withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Text(
                    message.text,
                    style: GoogleFonts.notoSansTamil(
                      color: isUser
                          ? Colors.white
                          : const Color(0xFF351124),
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    onSubmitted: (_) => _sendMessage(),
                    style: GoogleFonts.outfit(
                      color: const Color(0xFF351124),
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Ask Guru AI anything',
                      hintStyle: GoogleFonts.outfit(
                        color: const Color(0xFF9A7084),
                      ),
                      prefixIcon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: Color(0xFFFF4FA3),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(
                          color: Color(0xFFFF4FA3),
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _sending ? null : _sendMessage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF4FA3),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.role,
    required this.text,
  });

  final String role;
  final String text;
}
