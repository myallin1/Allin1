// ================================================================
// AdminAiSettingsScreen — paste/save the admin app's Groq + Gemini
// keys.
// ================================================================
// NEW (Nizam's report — "admin appkulla api key pottu activate panna
// screen wire connection panitaya ila?"). Audited: it wasn't. Both
// GuruAdminApiService._resolveApiKey() and .resolveGeminiApiKey()
// (lib/services/guru_admin_api_service.dart) already read
// SharedPreferences keys 'personal_ai_api_key' /
// 'personal_gemini_api_key' as their fallback after the env vars — but
// no screen anywhere in the admin app ever wrote to them. This screen
// is that missing writer, writing to the EXACT same keys, so no change
// to guru_admin_api_service.dart itself was needed.
//
// Deliberately plain SharedPreferences, not flutter_secure_storage —
// matches what the existing reader already expects (see that file's
// _resolveApiKey()/resolveGeminiApiKey()), same reasoning as the
// customer-side Gemini fix in ai_activation_service.dart.
//
// Purely additive: a new screen + one new drawer entry in
// super_admin_home_screen.dart. Nothing else was touched.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kGroqKeyPrefsKey = 'personal_ai_api_key';
const String _kGeminiKeyPrefsKey = 'personal_gemini_api_key';
// Aug 11 2026 — admin-only third agent. Must match
// DeepSeekApiService._savedApiKeyPrefsKey exactly; a mismatch here is
// silent (the key saves, the agent just never sees it).
const String _kDeepSeekKeyPrefsKey = 'personal_deepseek_api_key';

// NEW (Aug 12 2026 — Nizam: "api key podumbothu athuku keelaye model
// select pannalam"): one model-selection dropdown per provider,
// directly under its key field. Prefs keys here must match each
// service's own _modelPrefsKey exactly (guru_admin_api_service.dart,
// gemini_api_service.dart, deepseek_api_service.dart) — same
// "silent mismatch" risk called out for the key-prefs constants
// above, so triple-checked to match.
const String _kGroqModelPrefsKey = 'personal_ai_model';
const String _kGeminiModelPrefsKey = 'personal_gemini_model';
const String _kDeepSeekModelPrefsKey = 'personal_deepseek_model';

// Hardcoded per the CTO's own approved answer ("Hardcoded known-models
// list per provider") — avoids an extra network call just to populate
// a dropdown, and these three lists mirror the exact model IDs each
// service already knows how to call (Groq's _textModel default,
// Gemini's _modelCandidates fallback order, DeepSeek's _model
// default/documented alternative).
const List<String> _kGroqModels = [
  'llama-3.1-8b-instant',
  'llama-3.3-70b-versatile',
  'gemma2-9b-it',
  'mixtral-8x7b-32768',
];
const List<String> _kGeminiModels = [
  'gemini-2.0-flash',
  'gemini-2.0-flash-001',
  'gemini-1.5-flash',
  'gemini-1.5-pro',
  'gemini-flash-latest',
];
const List<String> _kDeepSeekModels = [
  'deepseek-chat',
  'deepseek-reasoner',
];

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF0D0D18);
const Color _card = Color(0xFF141420);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);
const Color _red = Color(0xFFE05555);
const Color _purple = Color(0xFFB21FFF);

class AdminAiSettingsScreen extends StatefulWidget {
  const AdminAiSettingsScreen({super.key});

  @override
  State<AdminAiSettingsScreen> createState() => _AdminAiSettingsScreenState();
}

class _AdminAiSettingsScreenState extends State<AdminAiSettingsScreen> {
  final TextEditingController _groqCtrl = TextEditingController();
  final TextEditingController _geminiCtrl = TextEditingController();
  final TextEditingController _deepseekCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  // NEW (Aug 12 2026 — per-key model selection): each provider's
  // currently-selected model, defaulting to that provider's first
  // (fastest/default) hardcoded model until the CTO picks otherwise.
  String _groqModel = _kGroqModels.first;
  String _geminiModel = _kGeminiModels.first;
  String _deepseekModel = _kDeepSeekModels.first;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _groqCtrl.text = prefs.getString(_kGroqKeyPrefsKey) ?? '';
    _geminiCtrl.text = prefs.getString(_kGeminiKeyPrefsKey) ?? '';
    _deepseekCtrl.text = prefs.getString(_kDeepSeekKeyPrefsKey) ?? '';
    final savedGroqModel = prefs.getString(_kGroqModelPrefsKey);
    final savedGeminiModel = prefs.getString(_kGeminiModelPrefsKey);
    final savedDeepSeekModel = prefs.getString(_kDeepSeekModelPrefsKey);
    if (savedGroqModel != null && _kGroqModels.contains(savedGroqModel)) {
      _groqModel = savedGroqModel;
    }
    if (savedGeminiModel != null && _kGeminiModels.contains(savedGeminiModel)) {
      _geminiModel = savedGeminiModel;
    }
    if (savedDeepSeekModel != null && _kDeepSeekModels.contains(savedDeepSeekModel)) {
      _deepseekModel = savedDeepSeekModel;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _groqCtrl.dispose();
    _geminiCtrl.dispose();
    _deepseekCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final groq = _groqCtrl.text.trim();
      final gemini = _geminiCtrl.text.trim();
      final deepseek = _deepseekCtrl.text.trim();
      if (groq.isEmpty) {
        await prefs.remove(_kGroqKeyPrefsKey);
      } else {
        await prefs.setString(_kGroqKeyPrefsKey, groq);
      }
      if (gemini.isEmpty) {
        await prefs.remove(_kGeminiKeyPrefsKey);
      } else {
        await prefs.setString(_kGeminiKeyPrefsKey, gemini);
      }
      if (deepseek.isEmpty) {
        await prefs.remove(_kDeepSeekKeyPrefsKey);
      } else {
        await prefs.setString(_kDeepSeekKeyPrefsKey, deepseek);
      }
      // Model choices always save, independent of whether a key is
      // present — picking a model ahead of pasting a key is fine, the
      // service just won't be called until a key exists.
      await prefs.setString(_kGroqModelPrefsKey, _groqModel);
      await prefs.setString(_kGeminiModelPrefsKey, _geminiModel);
      await prefs.setString(_kDeepSeekModelPrefsKey, _deepseekModel);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin AI Co-Pilot keys saved on this device.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save keys: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // NEW (Aug 12 2026 — per-key model selection): one shared dropdown
  // builder for all three providers, styled to match the existing
  // TextFields directly above each of them.
  Widget _modelDropdown({
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
    required Color accent,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      dropdownColor: _card,
      icon: Icon(Icons.expand_more_rounded, color: accent),
      style: const TextStyle(color: _text, fontSize: 13.5),
      decoration: InputDecoration(
        filled: true,
        fillColor: _bg,
        prefixIcon: Icon(Icons.smart_toy_rounded, color: accent, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: options
          .map((m) => DropdownMenuItem<String>(value: m, child: Text(m, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        title: Text('Admin AI Configuration', style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _red))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.support_agent_rounded, color: _red, size: 26),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'These keys power the Quick Task chatbox\'s three agents — Groq, Gemini, and DeepSeek. '
                            'Pick a model under each key; whichever agent is active in Quick Task uses that model as '
                            'your full admin assistant.',
                            style: GoogleFonts.outfit(color: _muted, fontSize: 12.5, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text('Groq API Key', style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _groqCtrl,
                      obscureText: true,
                      style: const TextStyle(color: _text),
                      decoration: InputDecoration(
                        hintText: 'Paste your Groq API key',
                        hintStyle: const TextStyle(color: _muted),
                        prefixIcon: const Icon(Icons.key_rounded, color: _red),
                        filled: true,
                        fillColor: _bg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _modelDropdown(
                      value: _groqModel,
                      options: _kGroqModels,
                      accent: _red,
                      onChanged: (v) => setState(() => _groqModel = v),
                    ),
                    const SizedBox(height: 20),
                    Text('Gemini API Key', style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _geminiCtrl,
                      obscureText: true,
                      style: const TextStyle(color: _text),
                      decoration: InputDecoration(
                        hintText: 'Paste your Gemini API key',
                        hintStyle: const TextStyle(color: _muted),
                        prefixIcon: const Icon(Icons.auto_awesome_rounded, color: _purple),
                        filled: true,
                        fillColor: _bg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _modelDropdown(
                      value: _geminiModel,
                      options: _kGeminiModels,
                      accent: _purple,
                      onChanged: (v) => setState(() => _geminiModel = v),
                    ),
                    const SizedBox(height: 18),
                    // NEW (Aug 11 2026): admin-only third agent, used as
                    // the backup when Groq/Gemini free limits run out.
                    Text('DeepSeek API Key (backup agent)',
                        style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700),),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _deepseekCtrl,
                      obscureText: true,
                      style: const TextStyle(color: _text),
                      decoration: InputDecoration(
                        hintText: 'Paste your DeepSeek API key',
                        hintStyle: const TextStyle(color: _muted),
                        prefixIcon: const Icon(Icons.bolt_rounded, color: _purple),
                        filled: true,
                        fillColor: _bg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _modelDropdown(
                      value: _deepseekModel,
                      options: _kDeepSeekModels,
                      accent: _purple,
                      onChanged: (v) => setState(() => _deepseekModel = v),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save_rounded, color: Colors.white),
                        label: Text(
                          _saving ? 'Saving...' : 'Save Keys',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _red,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
