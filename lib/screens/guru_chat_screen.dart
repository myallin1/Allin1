// ================================================================
// GuruChatScreen — "MyAllin1 Super Hero" — Allin1 Super App
// ================================================================
// OVERHAUL (per Nizam's explicit request): full context-aware, premium
// AI assistant rebuild.
// 1. UI/UX: dark, glowing gradient look (Gemini/Claude mobile-app style)
//    instead of the old light off-white theme — modern chat bubbles, a
//    dynamic glowing voice button, and a structured empty state showing
//    the app's services as capability chips.
// 2. Context Injection: system prompt (see guru_api_service.dart) now
//    fully describes every Allin1 service (Bike, Auto, Cab, Parcel, Mini
//    Truck, Lorry, SOS, Food Genie, NJ Tech repair, etc.) so the AI can
//    answer any customer query about the app.
// 3. Freemium model: Free tier = text chat, gated only on
//    AiActivationService.isAiActivated (an admin-provisioned key — see
//    _SuperHeroActivationScreen below). Pro tier = Voice-to-Order; tapping
//    the mic without AiActivationService.isProUnlocked shows a paywall
//    sheet instead of starting voice capture.
// 4. Activation/Onboarding: if the AI isn't activated yet for this
//    customer, the whole screen becomes a beautiful "Unlock your Super
//    Hero" screen instructing them to contact Admin Support, instead of
//    showing (or gating inline inside) the chat itself.
// 5. Voice Intent Parsing + Auto-Navigation (per Nizam's explicit
//    follow-up): a Pro customer's voice command is no longer just sent
//    to the AI as text. VoiceBookingIntentService parses it locally for
//    a service keyword (Bike/Auto/Cab/Parcel/Mini Truck/Lorry/SOS) and a
//    destination phrase, resolves the destination via the same
//    MapService search pipeline the booking screen's own address search
//    uses, then this screen pushes BikeBookingScreen directly with that
//    category + destination pre-filled (or SosScreen for SOS) — the
//    customer lands one tap from confirming, no manual re-typing. Only
//    utterances with no recognizable service keyword fall back to the
//    normal AI text reply.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

import '../services/ai_activation_service.dart';
import '../services/guru_api_service.dart';
import '../services/voice_booking_intent_service.dart';
import '../widgets/server_busy_dialog.dart' show kCallCenterNumberIntl;
import 'bike_taxi/bike_booking_screen.dart';
import 'sos_screen.dart';

// ---- Dark, glowing "Super Hero" palette ---------------------------------
const Color _bg = Color(0xFF0B0B12);
const Color _surface = Color(0xFF15151F);
const Color _surfaceElevated = Color(0xFF1C1C29);
const Color _ink = Color(0xFFF3F1FA);
const Color _muted = Color(0xFF9895AC);
const Color _border = Color(0xFF2A2A3B);
const Color _accentA = Color(0xFFB44CFF); // violet
const Color _accentB = Color(0xFFFF4FA3); // pink
const Color _accentC = Color(0xFF4CC9FF); // cyan (voice glow)
const Color _userBubble = Color(0xFF272736);

const List<_Capability> _capabilities = <_Capability>[
  _Capability('Bike', Icons.two_wheeler_rounded),
  _Capability('Auto', Icons.electric_rickshaw_rounded),
  _Capability('Cab', Icons.local_taxi_rounded),
  _Capability('Parcel', Icons.local_shipping_outlined),
  _Capability('Mini Truck', Icons.fire_truck_rounded),
  _Capability('Lorry', Icons.local_shipping_rounded),
  _Capability('SOS', Icons.sos_rounded),
];

const List<String> _suggestedPrompts = <String>[
  'Book a bike taxi in Erode',
  'Send a parcel across town',
  'Which service fits shifting furniture?',
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
  final stt.SpeechToText _speech = stt.SpeechToText();
  final VoiceBookingIntentService _voiceIntent = VoiceBookingIntentService();

  bool _isTyping = false;
  bool _isListening = false;
  bool _speechReady = false;
  // Guards against a stray extra speech_to_text onResult firing after
  // we've already actioned the finalResult once (dispatched an intent or
  // sent a fallback chat message) for this listening session.
  bool _voiceResultHandled = false;

  @override
  void dispose() {
    _api.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    if (_isListening) {
      unawaited(_speech.stop());
    }
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

  // -- Voice-to-Order (Pro) ------------------------------------------------

  Future<void> _onMicTapped() async {
    final activation = context.read<AiActivationService>();
    if (!activation.isProUnlocked) {
      unawaited(_showProPaywall());
      return;
    }

    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        onStatus: (status) {
          if (status == 'notListening' || status == 'done') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (error) {
          debugPrint('[GuruChatScreen] speech error: $error');
          if (mounted) setState(() => _isListening = false);
        },
      );
    }

    if (!_speechReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone not available on this device.'),
        ),
      );
      return;
    }

    setState(() {
      _isListening = true;
      _voiceResultHandled = false;
    });
    unawaited(
      _speech.listen(
        onResult: (result) {
          _inputController.text = result.recognizedWords;
          _inputController.selection = TextSelection.collapsed(
            offset: _inputController.text.length,
          );
          if (result.finalResult &&
              result.recognizedWords.trim().isNotEmpty &&
              !_voiceResultHandled) {
            _voiceResultHandled = true;
            setState(() => _isListening = false);
            unawaited(_handleVoiceUtterance(result.recognizedWords.trim()));
          }
        },
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  // Execute the action, don't just describe it: parse the transcribed
  // utterance for a service + destination and, when recognized, push the
  // real booking screen with everything pre-filled — falling back to a
  // normal AI chat reply only when no service keyword is understood at
  // all. See voice_booking_intent_service.dart for the parsing rules.
  Future<void> _handleVoiceUtterance(String utterance) async {
    final intent = _voiceIntent.parse(utterance);
    if (intent == null) {
      // Nothing service-shaped in there — treat it as a normal question.
      unawaited(_sendMessage('🎙 $utterance'));
      return;
    }

    if (intent.service == VoiceService.sos) {
      _showVoiceToast('Opening SOS...');
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SosScreen()),
        ),
      );
      return;
    }

    if (intent.destinationQuery == null) {
      // Heard a service ("book an auto") but no destination at all —
      // still take the customer straight to that service's booking
      // screen rather than making them repeat themselves in text.
      _showVoiceToast('Opening ${intent.displayName} booking...');
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BikeBookingScreen(initialCategory: intent.categoryKey),
          ),
        ),
      );
      return;
    }

    _showVoiceToast('Finding "${intent.destinationQuery}"...');
    final resolved = await _voiceIntent.resolve(intent);
    if (!mounted) return;

    if (resolved.destination == null) {
      // Recognized the service but couldn't geocode the spoken place —
      // don't silently fail; open the booking screen with the category
      // already selected so the customer only has to type/search the
      // destination once, and say plainly why.
      _showVoiceToast(
        'Couldn\'t find "${intent.destinationQuery}" — opening ${intent.displayName} so you can search it.',
      );
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BikeBookingScreen(initialCategory: intent.categoryKey),
          ),
        ),
      );
      return;
    }

    _showVoiceToast(
      'Opening ${intent.displayName} to ${resolved.destination!['name'] ?? intent.destinationQuery}...',
    );
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BikeBookingScreen(
            initialCategory: intent.categoryKey,
            initialDropLocation: resolved.destination,
          ),
        ),
      ),
    );
  }

  void _showVoiceToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _surfaceElevated,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showProPaywall() {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _ProPaywallSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activation = context.watch<AiActivationService>();

    return Scaffold(
      backgroundColor: _bg,
      body: !activation.isAiActivated
          ? const _SuperHeroActivationScreen()
          : SafeArea(
              child: Stack(
                children: [
                  const _GlowBackdrop(),
                  Column(
                    children: [
                      _buildAppBar(context, activation),
                      Expanded(
                        child: _messages.isEmpty
                            ? _buildWelcomeState()
                            : _buildMessages(),
                      ),
                      if (_isTyping) const _GuruTypingIndicator(),
                      _buildInputBar(activation),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildAppBar(BuildContext context, AiActivationService activation) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, color: _ink),
          ),
          const _GuruAvatar(size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'MyAllin1 Super Hero',
                  style: GoogleFonts.outfit(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  activation.isProUnlocked ? 'Pro • Voice unlocked' : 'Free plan',
                  style: GoogleFonts.outfit(
                    color: activation.isProUnlocked ? _accentC : _muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _startNewChat,
            tooltip: 'New chat',
            icon: const Icon(Icons.add_comment_outlined, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _GuruAvatar(size: 64, glow: true),
            const SizedBox(height: 18),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [_accentB, _accentA],
              ).createShader(bounds),
              child: Text(
                'Vanakkam! I\'m your Super Hero.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask me anything about rides, deliveries, or services in Erode.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: _muted, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _capabilities
                  .map((c) => _CapabilityChip(capability: c))
                  .toList(),
            ),
            const SizedBox(height: 22),
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

  Widget _buildInputBar(AiActivationService activation) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _VoiceMicButton(
              isListening: _isListening,
              isPro: activation.isProUnlocked,
              onTap: () => unawaited(_onMicTapped()),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 48, maxHeight: 140),
                decoration: BoxDecoration(
                  color: _surfaceElevated,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _border),
                ),
                child: TextField(
                  controller: _inputController,
                  minLines: 1,
                  maxLines: 5,
                  onSubmitted: (_) => unawaited(_sendMessage()),
                  textInputAction: TextInputAction.send,
                  style: GoogleFonts.notoSansTamil(color: _ink, fontWeight: FontWeight.w500, fontSize: 14.5),
                  decoration: InputDecoration(
                    hintText: _isListening ? 'Listening...' : 'Message your Super Hero...',
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
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [_accentB, _accentA]),
                  shape: BoxShape.circle,
                ),
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

// ================================================================
// Activation / Onboarding — "Unlock your Super Hero"
// ================================================================
// Shown instead of the chat whenever AiActivationService.isAiActivated
// is false. Per Nizam's request: no API-key form here anymore — the
// customer is told to contact Admin Support, who provisions the key on
// the backend/via ai_settings_screen; once that happens this screen
// swaps to the real chat automatically (AiActivationService notifies
// listeners on refresh).
class _SuperHeroActivationScreen extends StatelessWidget {
  const _SuperHeroActivationScreen();

  Future<void> _contactAdmin(BuildContext context) async {
    final message = Uri.encodeComponent(
      "Hi NJ Tech! I'd like to unlock MyAllin1 Super Hero (AI Assistant) on my account.",
    );
    final uri = Uri.parse('https://wa.me/$kCallCenterNumberIntl?text=$message');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp. Please call Admin Support directly.')),
      );
    }
  }

  Future<void> _callAdmin(BuildContext context) async {
    final uri = Uri.parse('tel:+$kCallCenterNumberIntl');
    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the call.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const _GlowBackdrop(),
        SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded, color: _ink),
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _GuruAvatar(size: 84, glow: true),
                        const SizedBox(height: 26),
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [_accentB, _accentA],
                          ).createShader(bounds),
                          child: Text(
                            'Unlock your Super Hero',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'MyAllin1 Super Hero is your always-on assistant for '
                          'Bike, Auto, Cab, Parcel, Mini Truck, Lorry, and SOS — '
                          'plus every other service in the app.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(color: _muted, fontSize: 14, height: 1.5),
                        ),
                        const SizedBox(height: 26),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: _capabilities
                              .map((c) => _CapabilityChip(capability: c))
                              .toList(),
                        ),
                        const SizedBox(height: 30),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: _border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(colors: [_accentA, _accentC]),
                                      borderRadius: BorderRadius.all(Radius.circular(14)),
                                    ),
                                    child: const Icon(Icons.support_agent_rounded, color: Colors.white),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Call or WhatsApp Admin Support to claim your access. '
                                      'Once activated, your full chat unlocks instantly.',
                                      style: GoogleFonts.outfit(
                                        color: _ink,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => unawaited(_callAdmin(context)),
                                      icon: const Icon(Icons.call_rounded, size: 18),
                                      label: const Text('Call'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _ink,
                                        side: const BorderSide(color: _border),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => unawaited(_contactAdmin(context)),
                                      icon: const Icon(Icons.chat_rounded, size: 18),
                                      label: const Text('WhatsApp'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF25D366),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                      ),
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
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ================================================================
// Pro paywall — shown when a Free-tier customer taps the mic.
// ================================================================
class _ProPaywallSheet extends StatelessWidget {
  const _ProPaywallSheet();

  Future<void> _upgrade(BuildContext context) async {
    final message = Uri.encodeComponent(
      "Hi NJ Tech! I'd like to upgrade to MyAllin1 Pro for Voice-to-Order.",
    );
    final uri = Uri.parse('https://wa.me/$kCallCenterNumberIntl?text=$message');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (context.mounted) Navigator.of(context).maybePop();
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [_accentC, _accentA]),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic_rounded, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              'Voice-to-Order is a Pro feature',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: _ink, fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Speak your booking — "Book an auto to the railway station" — and '
              'let Super Hero understand and place it for you. Upgrade to '
              'MyAllin1 Pro to unlock voice ordering. Text chat stays free, always.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: _muted, fontSize: 13.5, height: 1.5),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => unawaited(_upgrade(context)),
                icon: const Icon(Icons.workspace_premium_rounded),
                label: const Text('Upgrade to MyAllin1 Pro'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentB,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text('Maybe later', style: GoogleFonts.outfit(color: _muted, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// Small presentational widgets
// ================================================================

class _Capability {
  const _Capability(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({required this.capability});
  final _Capability capability;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: _surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(capability.icon, size: 15, color: _accentC),
          const SizedBox(width: 6),
          Text(
            capability.label,
            style: GoogleFonts.outfit(color: _ink, fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ],
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

class _VoiceMicButton extends StatefulWidget {
  const _VoiceMicButton({
    required this.isListening,
    required this.isPro,
    required this.onTap,
  });

  final bool isListening;
  final bool isPro;
  final VoidCallback onTap;

  @override
  State<_VoiceMicButton> createState() => _VoiceMicButtonState();
}

class _VoiceMicButtonState extends State<_VoiceMicButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final glow = widget.isListening ? 0.35 + _pulse.value * 0.45 : 0.0;
        return Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.isListening ? _accentC.withValues(alpha: 0.18) : _surfaceElevated,
            border: Border.all(
              color: widget.isListening ? _accentC : _border,
              width: widget.isListening ? 1.6 : 1,
            ),
            boxShadow: widget.isListening
                ? [
                    BoxShadow(
                      color: _accentC.withValues(alpha: glow),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                onPressed: widget.onTap,
                icon: Icon(
                  widget.isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                  color: widget.isListening ? _accentC : (widget.isPro ? _ink : _muted),
                  size: 20,
                ),
                padding: EdgeInsets.zero,
              ),
              if (!widget.isPro)
                const Positioned(
                  right: 2,
                  top: 2,
                  child: Icon(Icons.workspace_premium_rounded, size: 11, color: _accentB),
                ),
            ],
          ),
        );
      },
    );
  }
}

// Assistant replies render as plain text with a small avatar, no
// bubble chrome — matches Claude's mobile-app message style, on the
// new dark backdrop.
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
              border: Border.all(color: _border),
            ),
            child: Text(
              message.text,
              style: GoogleFonts.notoSansTamil(color: _ink, fontWeight: FontWeight.w500, fontSize: 14.5, height: 1.4),
            ),
          ),
        ),
      );
    }

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
                        color: _accentC.withValues(alpha: 0.5 + scale * 0.3),
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
  const _GuruAvatar({required this.size, this.glow = false});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [_accentB, _accentA],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: glow
            ? [
                BoxShadow(color: _accentA.withValues(alpha: 0.45), blurRadius: 34, spreadRadius: 4),
                BoxShadow(color: _accentB.withValues(alpha: 0.3), blurRadius: 18, spreadRadius: 1),
              ]
            : null,
      ),
      child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: size * 0.5),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('size', size));
    properties.add(FlagProperty('glow', value: glow, ifTrue: 'glow'));
  }
}

// Soft, blurred gradient orbs behind the whole screen — the "glowing
// gradient" backdrop Nizam asked for, Gemini/Claude-app style. Static
// (no animation) to keep it cheap on low-end devices.
class _GlowBackdrop extends StatelessWidget {
  const _GlowBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -90,
            left: -60,
            child: _GlowOrb(color: _accentA, size: 260, opacity: 0.22),
          ),
          Positioned(
            top: 120,
            right: -80,
            child: _GlowOrb(color: _accentB, size: 220, opacity: 0.16),
          ),
          Positioned(
            bottom: -100,
            left: 40,
            child: _GlowOrb(color: _accentC, size: 240, opacity: 0.14),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size, required this.opacity});

  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class _GuruMessage {
  const _GuruMessage({required this.role, required this.text});

  final String role;
  final String text;
}

