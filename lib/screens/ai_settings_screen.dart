import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/ai_activation_service.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  final FocusNode _apiKeyFocusNode = FocusNode();
  // NEW (Nizam's report — "Gemini key apply panna vali irukka ilaya?"):
  // second, independent field for the Gemini key — mirrors the Groq
  // field's own sync/focus pattern exactly, saved via
  // AiActivationService.saveGeminiApiKey() (new, additive method; the
  // existing saveApiKey()/apiKey Groq path above is untouched).
  final TextEditingController _geminiKeyController = TextEditingController();
  final FocusNode _geminiKeyFocusNode = FocusNode();
  bool _saving = false;
  String _lastSyncedApiKey = '';
  String _lastSyncedGeminiKey = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final aiActivation = context.watch<AiActivationService>();
    final savedApiKey = aiActivation.apiKey;
    if (!_apiKeyFocusNode.hasFocus && savedApiKey != _lastSyncedApiKey) {
      _apiKeyController.value = TextEditingValue(
        text: savedApiKey,
        selection: TextSelection.collapsed(offset: savedApiKey.length),
      );
      _lastSyncedApiKey = savedApiKey;
    }
    final savedGeminiKey = aiActivation.geminiApiKey;
    if (!_geminiKeyFocusNode.hasFocus && savedGeminiKey != _lastSyncedGeminiKey) {
      _geminiKeyController.value = TextEditingValue(
        text: savedGeminiKey,
        selection: TextSelection.collapsed(offset: savedGeminiKey.length),
      );
      _lastSyncedGeminiKey = savedGeminiKey;
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiKeyFocusNode.dispose();
    _geminiKeyController.dispose();
    _geminiKeyFocusNode.dispose();
    super.dispose();
  }

  Future<void> _saveAiConfiguration() async {
    final aiActivation = context.read<AiActivationService>();
    final key = _apiKeyController.text.trim();
    final geminiKey = _geminiKeyController.text.trim();

    setState(() => _saving = true);
    await aiActivation.saveApiKey(key);
    await aiActivation.saveGeminiApiKey(geminiKey);
    if (!mounted) {
      return;
    }

    _lastSyncedApiKey = key;
    _lastSyncedGeminiKey = geminiKey;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          key.isEmpty && geminiKey.isEmpty
              ? 'Chitti AI configuration cleared for this device.'
              : 'Chitti AI is ready on this device.',
        ),
        backgroundColor: key.isEmpty && geminiKey.isEmpty
            ? const Color(0xFFFFB74D)
            : const Color(0xFFFF4FA3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aiActivation = context.watch<AiActivationService>();
    // FIX (Nizam's report — "gemini api potta apayum groq key already
    // available nu varuthu"): ROOT CAUSE was that the header icon/text
    // AND the Save button's label below were both driven by this one
    // `activated` value alone (Groq-only, via isAiActivated) — so once
    // Groq was saved, EVERYTHING on this screen kept saying "already
    // activated," including while pasting/saving a fresh Gemini key,
    // because nothing here ever actually read isGeminiActivated. Each
    // key now gets its OWN status, shown right under its own field
    // (see the two _KeyStatusChip additions below); the shared header
    // and button below are reworded to be honest about summarizing
    // BOTH keys instead of implying one covers the other.
    final groqActivated = aiActivation.isAiActivated;
    final geminiActivated = aiActivation.isGeminiActivated;
    final activated = groqActivated; // kept for the top icon only — see header text fix below

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBFE),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'AI Configuration',
          style: GoogleFonts.outfit(
            color: const Color(0xFF4A1236),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0x33FF4FA3)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF4FA3).withValues(alpha: 0.14),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF4FA3), Color(0xFFB21FFF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      activated
                          ? Icons.auto_awesome_rounded
                          : Icons.key_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Personal AI Configuration',
                          style: GoogleFonts.outfit(
                            color: const Color(0xFF4A1236),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          groqActivated
                              ? (geminiActivated
                                  ? 'Groq and Gemini are both activated on this device.'
                                  : 'Groq is activated. Gemini is optional — add it below for photo-reading.')
                              : 'Save your Groq API key to unlock the full Chitti AI chat.',
                          style: GoogleFonts.outfit(
                            color: const Color(0xFF8A4E72),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text(
                    'Groq API Key',
                    style: GoogleFonts.outfit(
                      color: const Color(0xFF4A1236),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _KeyStatusChip(activated: groqActivated),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _apiKeyController,
                focusNode: _apiKeyFocusNode,
                obscureText: true,
                style: GoogleFonts.outfit(
                  color: const Color(0xFF351124),
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Paste your Groq API key',
                  hintStyle: GoogleFonts.outfit(
                    color: const Color(0xFF94697E),
                  ),
                  prefixIcon: const Icon(
                    Icons.key_rounded,
                    color: Color(0xFFFF4FA3),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFFF1F8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(
                      color: Color(0xFFFF4FA3),
                      width: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // NEW (per Nizam/CTO's "bring your own key" pivot): this
              // key is the spark that activates the customer's personal
              // AI superhero — free to get from Groq's own console, kept
              // securely on-device (flutter_secure_storage, see
              // AiActivationService), never sent anywhere but Groq's API.
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x33FF4FA3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🦸', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This key activates YOUR personal AI superhero — free to generate from Groq\'s console, stored securely on this device, never shared with anyone but Groq\'s own API.',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFF8A4E72),
                          fontSize: 12.5,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // NEW (Nizam's report — Gemini key had no paste/save UI
              // anywhere in the app). Optional: leaving this blank just
              // means the Multi-Agent Handoff's Gemini vision step
              // (analyze_screen_with_vision / DMart "I Need This")
              // degrades to "couldn't read that photo" instead of
              // failing loudly — same non-fatal pattern as an unset
              // Groq key, never a crash.
              Row(
                children: [
                  Text(
                    'Gemini API Key (optional)',
                    style: GoogleFonts.outfit(
                      color: const Color(0xFF4A1236),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _KeyStatusChip(activated: geminiActivated),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _geminiKeyController,
                focusNode: _geminiKeyFocusNode,
                obscureText: true,
                style: GoogleFonts.outfit(
                  color: const Color(0xFF351124),
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Paste your Gemini API key',
                  hintStyle: GoogleFonts.outfit(
                    color: const Color(0xFF94697E),
                  ),
                  prefixIcon: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Color(0xFFB21FFF),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFFF1F8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(
                      color: Color(0xFFB21FFF),
                      width: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Used for the deeper photo-reading step when you tap "I Need This" in DMart or attach a photo in chat.',
                style: GoogleFonts.outfit(
                  color: const Color(0xFF8A4E72),
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _saveAiConfiguration,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(
                    // FIX (same root cause as above): this used to say
                    // "Update Chitti AI Key" whenever Groq alone was
                    // already saved — misleading while the customer was
                    // actually trying to save a NEW Gemini key for the
                    // first time. Neutral wording that's accurate no
                    // matter which of the two fields changed.
                    (groqActivated || geminiActivated) ? 'Update AI Keys' : 'Save & Activate Chitti AI',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF4FA3),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// NEW (Nizam's report fix — per-key status, not one shared "activated"
// flag for the whole screen). Tiny stateless chip, no logic beyond
// displaying a bool — the actual root-cause fix is in build() reading
// isAiActivated and isGeminiActivated separately and passing each in.
class _KeyStatusChip extends StatelessWidget {
  const _KeyStatusChip({required this.activated});
  final bool activated;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: activated ? const Color(0xFFE8F9EE) : const Color(0xFFF3F0F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        activated ? '✓ Saved' : 'Not set',
        style: GoogleFonts.outfit(
          color: activated ? const Color(0xFF2E9E5B) : const Color(0xFF9A8AA5),
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
