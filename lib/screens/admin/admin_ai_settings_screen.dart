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
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _groqCtrl.text = prefs.getString(_kGroqKeyPrefsKey) ?? '';
    _geminiCtrl.text = prefs.getString(_kGeminiKeyPrefsKey) ?? '';
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _groqCtrl.dispose();
    _geminiCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final groq = _groqCtrl.text.trim();
      final gemini = _geminiCtrl.text.trim();
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
                            'These keys power the Quick Task chatbox\'s two agents — Groq (Fast Logic) and Gemini (Deep Reasoning).',
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
