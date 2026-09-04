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
import 'package:flutter_tts/flutter_tts.dart';

import '../../services/chitti/chitti_model_provider.dart';
import '../../services/chitti/chitti_voice_service.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/chitti/chitti_accessibility_bridge.dart';
import 'chitti_debug_logs_screen.dart';
import 'chitti_dev_monitor_screen.dart';
import '../../services/chitti/chitti_summarizer.dart';
import '../../services/cloudinary_upload_service.dart';
import '../../services/firestore_usage_tracking.dart';

const String _kGroqKeyPrefsKey = 'personal_ai_api_key';
const String _kGeminiKeyPrefsKey = 'personal_gemini_api_key';
// Aug 11 2026 — admin-only third agent. Must match
// DeepSeekApiService._savedApiKeyPrefsKey exactly; a mismatch here is
// silent (the key saves, the agent just never sees it).
const String _kDeepSeekKeyPrefsKey = 'personal_deepseek_api_key';
const String _kAnthropicKeyPrefsKey = 'personal_anthropic_api_key';

// NEW (Aug 12 2026 — Nizam: "api key podumbothu athuku keelaye model
// select pannalam"): one model-selection dropdown per provider,
// directly under its key field. Prefs keys here must match each
// service's own _modelPrefsKey exactly (guru_admin_api_service.dart,
// gemini_api_service.dart, deepseek_api_service.dart) — same
// "silent mismatch" risk called out for the key-prefs constants
// above, so triple-checked to match.
const String _kGroqModelPrefsKey = 'personal_groq_model';
const String _kGeminiModelPrefsKey = 'personal_gemini_model';
const String _kDeepSeekModelPrefsKey = 'personal_deepseek_model';
const String _kAnthropicModelPrefsKey = 'personal_anthropic_model';

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
  'deepseek-v4-flash',
  'deepseek-v4-pro',
];
const List<String> _kAnthropicModels = [
  'claude-3-5-sonnet-20241022',
  'claude-3-5-haiku-20241022',
  'claude-3-7-sonnet-20250219',
];

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF0D0D18);
const Color _card = Color(0xFF141420);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);
const Color _red = Color(0xFFE05555);
const Color _purple = Color(0xFFB21FFF);
const Color _amberWarn = Color(0xFFFFB020);

class AdminAiSettingsScreen extends StatefulWidget {
  const AdminAiSettingsScreen({super.key});

  @override
  State<AdminAiSettingsScreen> createState() => _AdminAiSettingsScreenState();
}

class _AdminAiSettingsScreenState extends State<AdminAiSettingsScreen>
    with WidgetsBindingObserver {
  final TextEditingController _groqCtrl = TextEditingController();
  final TextEditingController _geminiCtrl = TextEditingController();
  final TextEditingController _deepseekCtrl = TextEditingController();
  final TextEditingController _anthropicCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  // Call Assistant configuration state
  bool _callAssistantEnabled = false;
  bool _morningBriefingEnabled = true;
  bool _hasCallPermission = false;
  bool _hasMicPermission = false;
  bool _hasOverlayPermission = false;

  // NEW (Aug 30 2026 — Nizam: "chitti setting page la oru button vai
  // atha thotta accessibility on aganum, on aiduchu-nnu notification
  // varanum"). This is a SEPARATE OS-level toggle from the three app
  // permissions above (Answer Calls / Record Audio / Appear on Top) —
  // those are granted via the standard Android runtime-permission
  // dialog, but Accessibility Service can only be turned on from
  // Settings > Accessibility itself, no in-app dialog can grant it.
  // Tracked here so returning from that settings screen (caught via
  // WidgetsBindingObserver.didChangeAppLifecycleState below) can tell
  // the difference between "still off" and "just turned on" and show a
  // confirmation the moment it changes, rather than the admin having to
  // guess or back out and back in again to see updated state.
  bool _accessibilityServiceEnabled = false;

  // NEW (Aug 31 2026 — Option A, default-dialer role): "Chitti loud
  // speaker on agala" — confirmed by real testing on Oppo Reno7 Pro AND
  // Lenovo K9 that only the app holding this OS role can control a real
  // call's audio route. Same poll-on-resume pattern as
  // _accessibilityServiceEnabled above — the grant happens in a system
  // dialog this screen doesn't get a direct callback from.
  bool _isDefaultDialer = false;

  static const String _kCallAssistantEnabledKey = 'kChittiCallAssistantEnabled';
  static const String _kMorningBriefingEnabledKey = 'personal_morning_briefing_enabled';

  // NEW (per Nizam's request, Aug 31 2026): "chitti pesurathuku late
  // aguthu, athayum step ah pirikkalam" — two answering modes now
  // exist in ChittiCallScreeningService.startScreening(). 'quick_record'
  // is the new default: one fixed greeting, then the native call
  // recorder captures the rest — no speech-recognition engine, no AI
  // network round-trip, so there's no latency the caller can notice.
  // 'full' is the original live back-and-forth conversation, kept as an
  // option once that flow's latency is tuned.
  static const String _kCallAnsweringModeKey = 'kChittiCallAnsweringMode';
  String _callAnsweringMode = 'quick_record';

  // NEW (Sep 1 2026 — Nizam: "headphone jack la namma technical plan
  // panni athukapram ithe idea va implement pannalam"). Confirmed via
  // real testing that setAudioRoute(SPEAKER) genuinely works now (see
  // ChittiCallScreeningService's SPEAKER ROUTE log line), but the
  // caller still can't hear Chitti — Android's own Acoustic Echo
  // Cancellation on the built-in speaker+mic pair is suppressing the
  // acoustic loop. Trying a wired-headset loopback cable (audio-out
  // wired to mic-in) instead, on the theory that AEC may not scrub a
  // headset's electrical path as aggressively as the speakerphone
  // acoustic one. This toggle is read natively by PhoneCallService.
  // enableSpeakerphone() (key: flutter.kChittiPreferWiredHeadsetRoute)
  // — off by default so nothing changes for admins not running this
  // experiment.
  // UPDATED (Sep 1 2026 — CTO's Bluetooth acoustic-bridge proposal):
  // widened from a wired-only boolean to a three-way route choice, so
  // the neckband experiment is actually testable. Without this the call
  // stays pinned to the phone's own speaker and pairing a headset
  // changes nothing — the test would fail for the wrong reason.
  static const String _kCallAudioRouteKey = 'kChittiCallAudioRoute';
  String _callAudioRoute = 'speaker';

  // NEW (Sep 1 2026 — mic-isolation lever). MediaRecorder with
  // AudioSource.MIC holds the microphone exclusively on many devices,
  // which makes it a suspect in "the caller hears nothing" alongside
  // the audio-mode bug fixed this round. On by default (recording is a
  // real feature); switching it off is a diagnostic step.
  static const String _kCallRecordingEnabledKey = 'kChittiCallRecordingEnabled';
  bool _callRecordingEnabled = true;

  // NEW (Aug 12 2026 — per-key model selection): each provider's
  // currently-selected model, defaulting to that provider's first
  // (fastest/default) hardcoded model until the CTO picks otherwise.
  String _groqModel = _kGroqModels.first;
  String _geminiModel = _kGeminiModels.first;
  String _deepseekModel = _kDeepSeekModels.first;
  String _anthropicModel = _kAnthropicModels.first;

  /// Which provider CHITTI uses (Aug 28 2026 — Nizam: "admin ketta atha
  /// chitti agent app kulla udane [use pannanum]").
  ///
  /// Distinct from the three model dropdowns above, which pick WHICH
  /// model within a provider. This picks which provider the assistant
  /// itself talks to, and is read by ChittiModelProvider.
  String _chittiModelId = defaultChittiModel.id;

  // ── Voice & Tone (Aug 28 2026) ──────────────────────────────────
  //
  // Same gap as Hero and Seller Settings had: the picker existed, but
  // nothing in THIS app could open it. An admin whose phone's own TTS
  // settings already show a male voice had no way to tell Chitti to
  // use it - the heuristic's guess was final.
  final FlutterTts _voicePreviewTts = FlutterTts();
  ChittiVoiceTone _voiceTone = ChittiVoiceTone.chitti;
  String? _pinnedVoice;
  List<ChittiVoiceOption> _voices = const <ChittiVoiceOption>[];
  bool _loadingVoices = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _checkAccessibilityService();
    _checkDefaultDialer();
  }

  Future<void> _setCallAudioRoute(String route) async {
    setState(() => _callAudioRoute = route);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCallAudioRouteKey, route);
  }

  Future<void> _checkDefaultDialer() async {
    final isDefault = await ChittiAccessibilityBridge.instance.isDefaultDialer();
    if (!mounted) return;
    final justTurnedOn = isDefault && !_isDefaultDialer;
    setState(() => _isDefaultDialer = isDefault);
    if (justTurnedOn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Chitti is now the default Phone app — real speaker control is active."),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _checkAccessibilityService() async {
    final enabled = await ChittiAccessibilityBridge.instance.isPermissionGranted();
    if (!mounted) return;
    final justTurnedOn = enabled && !_accessibilityServiceEnabled;
    setState(() => _accessibilityServiceEnabled = enabled);
    if (justTurnedOn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Accessibility enabled — Chitti will now follow you across apps!"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from Settings > Accessibility (where opening it is the
    // only way to grant this) lands back here as a resume — that is the
    // one moment worth re-checking, so this stays a light poll rather
    // than a timer running the whole time the screen is open.
    if (state == AppLifecycleState.resumed) {
      _checkAccessibilityService();
      _checkDefaultDialer();
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _groqCtrl.text = prefs.getString(_kGroqKeyPrefsKey) ?? '';
    _geminiCtrl.text = prefs.getString(_kGeminiKeyPrefsKey) ?? '';
    _deepseekCtrl.text = prefs.getString(_kDeepSeekKeyPrefsKey) ?? '';
    _anthropicCtrl.text = prefs.getString(_kAnthropicKeyPrefsKey) ?? '';
    _chittiModelId =
        prefs.getString(kChittiModelPrefsKey) ?? defaultChittiModel.id;
    final savedGroqModel = prefs.getString(_kGroqModelPrefsKey);
    final savedGeminiModel = prefs.getString(_kGeminiModelPrefsKey);
    final savedDeepSeekModel = prefs.getString(_kDeepSeekModelPrefsKey);
    final savedAnthropicModel = prefs.getString(_kAnthropicModelPrefsKey);
    if (savedGroqModel != null && _kGroqModels.contains(savedGroqModel)) {
      _groqModel = savedGroqModel;
    }
    if (savedGeminiModel != null && _kGeminiModels.contains(savedGeminiModel)) {
      _geminiModel = savedGeminiModel;
    }
    if (savedDeepSeekModel != null && _kDeepSeekModels.contains(savedDeepSeekModel)) {
      _deepseekModel = savedDeepSeekModel;
    }
    if (savedAnthropicModel != null && _kAnthropicModels.contains(savedAnthropicModel)) {
      _anthropicModel = savedAnthropicModel;
    }
    // Admin's own language, same source LocalizationService itself
    // reads from - so the preview list matches whatever locale Chitti
    // is actually replying in, not a hardcoded English guess.
    final locale = _adminVoiceLocale(prefs.getString('customer_language_code'));
    final voices =
        await ChittiVoiceService.availableVoices(_voicePreviewTts, locale);
    if (!mounted) return;
    setState(() {
      _voiceTone = ChittiVoiceService.tone;
      _pinnedVoice = ChittiVoiceService.pinnedVoiceName;
      _voices = voices;
      _loadingVoices = false;
      _loading = false;
      _callAssistantEnabled = prefs.getBool(_kCallAssistantEnabledKey) ?? true;
      _morningBriefingEnabled = prefs.getBool(_kMorningBriefingEnabledKey) ?? true;
      _callAnsweringMode = prefs.getString(_kCallAnsweringModeKey) ?? 'quick_record';
      _callAudioRoute = prefs.getString(_kCallAudioRouteKey) ?? 'speaker';
      _callRecordingEnabled = prefs.getBool(_kCallRecordingEnabledKey) ?? true;
    });

    final statuses = await ChittiAccessibilityBridge.instance.checkCallPermissions();
    final hasOverlay = await ChittiAccessibilityBridge.instance.checkOverlayPermission();
    if (mounted) {
      setState(() {
        _hasCallPermission = (statuses['readPhone'] == true) && (statuses['answerCalls'] == true) && (statuses['readCallLog'] == true);
        _hasMicPermission = statuses['recordAudio'] == true;
        _hasOverlayPermission = hasOverlay;
      });
    }

  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _groqCtrl.dispose();
    _geminiCtrl.dispose();
    _deepseekCtrl.dispose();
    _anthropicCtrl.dispose();
    _voicePreviewTts.stop();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final groq = _groqCtrl.text.trim();
      final gemini = _geminiCtrl.text.trim();
      final deepseek = _deepseekCtrl.text.trim();
      final anthropic = _anthropicCtrl.text.trim();
      if (groq.isEmpty) {
        await prefs.remove(_kGroqKeyPrefsKey);
      } else {
        await prefs.setString(kChittiModelPrefsKey, _chittiModelId);
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
      if (anthropic.isEmpty) {
        await prefs.remove(_kAnthropicKeyPrefsKey);
      } else {
        await prefs.setString(_kAnthropicKeyPrefsKey, anthropic);
      }
      // Model choices always save, independent of whether a key is
      // present — picking a model ahead of pasting a key is fine, the
      // service just won't be called until a key exists.
      await prefs.setString(_kGroqModelPrefsKey, _groqModel);
      await prefs.setString(_kGeminiModelPrefsKey, _geminiModel);
      await prefs.setString(_kDeepSeekModelPrefsKey, _deepseekModel);
      await prefs.setString(_kAnthropicModelPrefsKey, _anthropicModel);
      await prefs.setBool(_kCallAssistantEnabledKey, _callAssistantEnabled);
      await prefs.setBool(_kMorningBriefingEnabledKey, _morningBriefingEnabled);
      await prefs.setString(_kCallAnsweringModeKey, _callAnsweringMode);
      await prefs.setString(_kCallAudioRouteKey, _callAudioRoute);
      await prefs.setBool(_kCallRecordingEnabledKey, _callRecordingEnabled);
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

  static String _adminVoiceLocale(String? languageCode) => switch (languageCode) {
        'ta' || 'tg' => 'ta-IN',
        _ => 'en-IN',
      };

  Future<void> _setVoiceTone(ChittiVoiceTone tone) async {
    setState(() => _voiceTone = tone);
    await ChittiVoiceService.setTone(tone);
  }

  Future<void> _pinVoice(String? name) async {
    setState(() => _pinnedVoice = name);
    final match = _voices.where((v) => v.name == name).firstOrNull;
    await ChittiVoiceService.pinVoice(name: name, locale: match?.locale);
  }

  Widget _buildChittiVoiceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Chitti's Voice",
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          "If your phone's own TTS settings already have a male voice, "
          "pick it below by name rather than relying on Chitti to guess "
          "it from the raw voice list.",
          style: GoogleFonts.outfit(color: _muted, fontSize: 11.5, height: 1.35),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final t in ChittiVoiceTone.values)
              ChoiceChip(
                selected: _voiceTone == t,
                label: Text(
                  t.name,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _voiceTone == t ? Colors.white : _text,
                  ),
                ),
                selectedColor: _red,
                backgroundColor: _bg,
                onSelected: (_) => _setVoiceTone(t),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loadingVoices)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (_voices.isEmpty)
          Text(
            'No voices are installed for this language on this device. '
            'Chitti will still speak using the system default, shaped to '
            'the tone above.',
            style: GoogleFonts.outfit(color: _muted, fontSize: 11.5, height: 1.4),
          )
        else
          DropdownButtonFormField<String>(
            initialValue:
                _voices.any((v) => v.name == _pinnedVoice) ? _pinnedVoice : null,
            isExpanded: true,
            dropdownColor: _card,
            style: GoogleFonts.outfit(fontSize: 13, color: _text),
            decoration: InputDecoration(
              filled: true,
              fillColor: _bg,
              prefixIcon: const Icon(Icons.graphic_eq_rounded, color: _red),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            hint: Text(
              'Auto (pick a male voice for me)',
              style: GoogleFonts.outfit(color: _muted, fontSize: 13),
            ),
            items: [
              DropdownMenuItem<String>(
                child: Text(
                  'Auto (pick a male voice for me)',
                  style: GoogleFonts.outfit(fontSize: 13, color: _text),
                ),
              ),
              for (final voice in _voices)
                DropdownMenuItem<String>(
                  value: voice.name,
                  child: Text(
                    voice.label,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(fontSize: 13, color: _text),
                  ),
                ),
            ],
            onChanged: _pinVoice,
          ),
        // NEW (Aug 29 2026 — Nizam: "oppo phone la chitti ku male
        // voice varuthu, samsung phone la male voice varala"). See the
        // matching note in ai_settings_screen.dart — this is a TTS
        // ENGINE difference between phones, not a code bug, so the fix
        // has to happen in the phone's own settings.
        if (!_loadingVoices &&
            _voices.isNotEmpty &&
            !_voices.any((v) => v.isMale))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              "No male voice showed up above? Some phones (often "
              'Samsung) ship a TTS engine with a smaller voice set. Go '
              'to Settings → General management → Text-to-speech → '
              'Preferred engine, switch it to "Google Text-to-speech", '
              'then come back here.',
              style: GoogleFonts.outfit(
                color: _red,
                fontSize: 11,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _requestCallPermissions() async {
    await ChittiAccessibilityBridge.instance.requestCallPermissions();
    if (!_hasOverlayPermission) {
      await ChittiAccessibilityBridge.instance.requestOverlayPermission();
    }
    await Future.delayed(const Duration(milliseconds: 1000));
    final statuses = await ChittiAccessibilityBridge.instance.checkCallPermissions();
    final hasOverlay = await ChittiAccessibilityBridge.instance.checkOverlayPermission();
    if (mounted) {
      setState(() {
        _hasCallPermission = (statuses['readPhone'] == true) && (statuses['answerCalls'] == true) && (statuses['readCallLog'] == true);
        _hasMicPermission = statuses['recordAudio'] == true;
        _hasOverlayPermission = hasOverlay;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _hasCallPermission && _hasMicPermission && _hasOverlayPermission
                ? 'All Call Assistant permissions granted!'
                : 'Some permissions were denied. Please grant them in Settings.',
          ),
        ),
      );
    }
  }

  Widget _buildCallAssistantSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: _border, height: 32),
        Row(
          children: [
            const Icon(Icons.call_rounded, color: _red, size: 20),
            const SizedBox(width: 8),
            Text(
              "Chitti AI Call Assistant",
              style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          "Auto-answers incoming calls when you are busy, talks to the customer using warm Tamil/English, and takes messages or schedules appointments.",
          style: GoogleFonts.outfit(color: _muted, fontSize: 11.5, height: 1.35),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: Text(
            "Enable Call Assistant",
            style: GoogleFonts.outfit(color: _text, fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            _callAssistantEnabled ? "Active (Auto-answers calls)" : "Inactive",
            style: GoogleFonts.outfit(color: _callAssistantEnabled ? Colors.green : _muted, fontSize: 11),
          ),
          value: _callAssistantEnabled,
          activeColor: _red,
          activeTrackColor: _red.withValues(alpha: 0.3),
          inactiveThumbColor: _muted,
          contentPadding: EdgeInsets.zero,
          onChanged: (val) async {
            setState(() {
              _callAssistantEnabled = val;
            });
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(_kCallAssistantEnabledKey, val);
          },
        ),
        const SizedBox(height: 12),
        // NEW (Aug 31 2026 — Option A, default-dialer role): the real
        // fix for "Chitti loud speaker on agala" — confirmed on both
        // Oppo Reno7 Pro and Lenovo K9 that AudioManager alone cannot
        // route a real SIM call to the speaker, only the app holding
        // this OS role can. See ChittiInCallService.kt for the full
        // root-cause writeup.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isDefaultDialer ? Colors.green.withValues(alpha: 0.1) : _red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _isDefaultDialer ? Colors.green : _red),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _isDefaultDialer ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                    color: _isDefaultDialer ? Colors.green : _red,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isDefaultDialer
                          ? "Chitti is the default Phone app — real speaker control is active"
                          : "Real speaker control needs Chitti to be the default Phone app",
                      style: GoogleFonts.outfit(color: _text, fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                "Without this, Chitti's greeting only plays through the earpiece — "
                "the caller never hears it (confirmed on both Oppo and Lenovo). "
                "This replaces this phone's calling app with Chitti so it can "
                "switch a real call to the speaker.",
                style: GoogleFonts.outfit(color: _muted, fontSize: 11, height: 1.3),
              ),
              if (!_isDefaultDialer) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      final outcome = await ChittiAccessibilityBridge.instance.requestDefaultDialerRole();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(outcome), duration: const Duration(seconds: 5)),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _red),
                      foregroundColor: _red,
                    ),
                    child: const Text('Make Chitti the Default Phone App'),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        // NEW (per Nizam's request, Aug 31 2026): "chitti pesurathuku
        // late aguthu, athayum step ah pirikkalam" — pick which
        // answering mode ChittiCallScreeningService.startScreening()
        // uses for the next call.
        Text(
          "How Chitti answers a screened call",
          style: GoogleFonts.outfit(color: _text, fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _AnsweringModeOption(
          selected: _callAnsweringMode == 'quick_record',
          title: 'Quick Greeting + Record (backup, faster)',
          subtitle: 'Chitti says one fixed line, then just records what the '
              'caller says. No live back-and-forth — check the recording in '
              'File Manager / Dialer when free.',
          onTap: () async {
            setState(() => _callAnsweringMode = 'quick_record');
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_kCallAnsweringModeKey, 'quick_record');
          },
        ),
        const SizedBox(height: 8),
        _AnsweringModeOption(
          selected: _callAnsweringMode == 'full',
          title: 'Full Chitti Conversation',
          subtitle: 'Chitti listens and replies back and forth in real time '
              '— can feel slightly slow while this flow is still being tuned.',
          onTap: () async {
            setState(() => _callAnsweringMode = 'full');
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_kCallAnsweringModeKey, 'full');
          },
        ),
        const SizedBox(height: 12),
        // NEW (Sep 1 2026 — acoustic-bridge experiments). Confirmed via
        // this session's logs that setAudioRoute(SPEAKER)=true genuinely
        // works, yet the caller still hears nothing: Android gives no
        // app any way to inject audio into the cellular UPLINK (that
        // path belongs to the baseband processor). The remaining ideas
        // are all acoustic — get Chitti's voice out of one device and
        // back into the call's microphone, outside the phone's own echo
        // cancellation. This picker only chooses which route Chitti
        // REQUESTS; the device still has to actually be connected, and
        // the SPEAKER ROUTE debug line reports which route really got
        // used (including "requested=X, not available").
        Text(
          "Call audio route (acoustic bridge tests)",
          style: GoogleFonts.outfit(color: _text, fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _AnsweringModeOption(
          selected: _callAudioRoute == 'speaker',
          title: 'Phone speaker (default)',
          subtitle: "Normal loudspeaker. Works as a route, but the phone's own "
              'echo cancellation stops the caller hearing Chitti.',
          onTap: () => _setCallAudioRoute('speaker'),
        ),
        const SizedBox(height: 8),
        _AnsweringModeOption(
          selected: _callAudioRoute == 'bluetooth',
          title: 'Bluetooth headset (neckband bridge test)',
          subtitle: 'Routes the call to a paired Bluetooth headset. Hold its '
              'earbud against its own mic. Use a plain neckband — one with '
              'ENC / noise cancelling will cancel the loop itself.',
          onTap: () => _setCallAudioRoute('bluetooth'),
        ),
        const SizedBox(height: 8),
        _AnsweringModeOption(
          selected: _callAudioRoute == 'wired',
          title: 'Wired headset (loopback cable test)',
          subtitle: 'Routes to a plugged-in wired headset — for the '
              'audio-out-to-mic-in loopback cable idea.',
          onTap: () => _setCallAudioRoute('wired'),
        ),
        const SizedBox(height: 12),
        // NEW (Sep 1 2026 — mic-isolation lever, see the key constant's
        // comment). Turning this OFF frees the microphone entirely, so
        // a test call can show whether call recording was competing
        // with the cellular uplink.
        SwitchListTile(
          title: Text(
            'Record screened calls',
            style: GoogleFonts.outfit(color: _text, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            _callRecordingEnabled
                ? 'On — saves an .m4a of each screened call'
                : 'Off — microphone left completely free (mic-isolation test)',
            style: GoogleFonts.outfit(
              color: _callRecordingEnabled ? Colors.green : _amberWarn,
              fontSize: 11,
            ),
          ),
          value: _callRecordingEnabled,
          activeColor: _red,
          activeTrackColor: _red.withValues(alpha: 0.3),
          inactiveThumbColor: _muted,
          contentPadding: EdgeInsets.zero,
          onChanged: (val) async {
            setState(() => _callRecordingEnabled = val);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(_kCallRecordingEnabledKey, val);
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: Text(
            "Enable Morning Briefing",
            style: GoogleFonts.outfit(color: _text, fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            _morningBriefingEnabled ? "Active (Vocal summary at launch)" : "Inactive",
            style: GoogleFonts.outfit(color: _morningBriefingEnabled ? Colors.green : _muted, fontSize: 11),
          ),
          value: _morningBriefingEnabled,
          activeColor: _red,
          activeTrackColor: _red.withValues(alpha: 0.3),
          inactiveThumbColor: _muted,
          inactiveTrackColor: _bg,
          contentPadding: EdgeInsets.zero,
          onChanged: (val) {
            setState(() {
              _morningBriefingEnabled = val;
            });
          },
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _permissionStatusRow("Answer Phone Calls", _hasCallPermission),
              const SizedBox(height: 8),
              _permissionStatusRow("Record Call Audio", _hasMicPermission),
              const SizedBox(height: 8),
              _permissionStatusRow("Appear on Top (Overlay)", _hasOverlayPermission),
              const SizedBox(height: 8),
              _permissionStatusRow("Follow You Across Apps (Accessibility)", _accessibilityServiceEnabled),
              if (!_accessibilityServiceEnabled) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => ChittiAccessibilityBridge.instance.openSettings(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _red.withValues(alpha: 0.15),
                      side: const BorderSide(color: _red),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: Text(
                      "Enable Accessibility",
                      style: GoogleFonts.outfit(color: _red, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    "Opens system Settings — find Chitti in the list and turn it on. Come back here and you'll see a confirmation.",
                    style: GoogleFonts.outfit(color: _muted, fontSize: 10.5, height: 1.3),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (!_hasCallPermission || !_hasMicPermission || !_hasOverlayPermission)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _requestCallPermissions,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _purple.withValues(alpha: 0.2),
                      side: const BorderSide(color: _purple),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: Text(
                      "Request Call Permissions",
                      style: GoogleFonts.outfit(color: _purple, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      "Permissions configured successfully",
                      style: GoogleFonts.outfit(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // NEW (Aug 31 2026 — debug-log viewer, right where the admin is
        // already looking after a test call).
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ChittiDebugLogsScreen()),
            ),
            icon: const Icon(Icons.bug_report_rounded, color: _red, size: 18),
            label: Text(
              'View Call Debug Logs',
              style: GoogleFonts.outfit(color: _red, fontWeight: FontWeight.w600, fontSize: 12.5),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _red),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // NEW (Sep 1 2026 — Nizam: "as a ceo and admin other nan
        // oruthane pakkurathunala athuku thani monitoring ui namma
        // admin app la irukanum"). One screen showing where every
        // change is: latest installable APK, builds running, and the
        // dev tasks Chitti opened — see chitti_dev_monitor_screen.dart.
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ChittiDevMonitorScreen()),
            ),
            icon: const Icon(Icons.monitor_heart_rounded, color: _purple, size: 18),
            label: Text(
              'Development Monitor (builds & test APK)',
              style: GoogleFonts.outfit(color: _purple, fontWeight: FontWeight.w600, fontSize: 12.5),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _purple),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          "AI-Recorded Appointments",
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        _buildAppointmentsList(),
      ],
    );
  }

  Widget _permissionStatusRow(String label, bool isGranted) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(color: _text, fontSize: 12.5),
        ),
        Row(
          children: [
            Text(
              isGranted ? "Granted" : "Denied",
              style: GoogleFonts.outfit(color: isGranted ? Colors.green : _red, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            Icon(
              isGranted ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
              color: isGranted ? Colors.green : _red,
              size: 16,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAppointmentsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chitti_appointments')
          .orderBy('timestamp', descending: true)
          .limit(10)
          .trackedSnapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              "Error loading appointments: ${snapshot.error}",
              style: GoogleFonts.outfit(color: _red, fontSize: 12),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: _red),
              ),
            ),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: Column(
              children: [
                const Icon(Icons.event_busy_rounded, color: _muted, size: 36),
                const SizedBox(height: 8),
                Text(
                  "No appointments recorded yet",
                  style: GoogleFonts.outfit(color: _muted, fontSize: 12.5),
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final docId = docs[index].id;
            final phone = data['phone'] as String? ?? 'Unknown Caller';
            final name = data['name'] as String? ?? 'New Customer';
            final summary = data['summary'] as String? ?? 'No message summary';
            final localAudioPath = data['localAudioPath'] as String?;
            final localTranscriptPath = data['localTranscriptPath'] as String?;
            final audioUrl = data['audioUrl'] as String?;
            final ts = data['timestamp'] as Timestamp?;
            final dateStr = ts != null
                ? "${ts.toDate().day}/${ts.toDate().month} ${ts.toDate().hour.toString().padLeft(2, '0')}:${ts.toDate().minute.toString().padLeft(2, '0')}"
                : "Just now";

            final oneLineSummary = ChittiSummarizer.heuristicSummary(
              sender: phone,
              message: summary,
              isTamil: true,
            );

            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      Text(
                        dateStr,
                        style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        phone,
                        style: GoogleFonts.outfit(color: _red, fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      if (localAudioPath != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.mic_rounded, color: Colors.green, size: 12),
                              const SizedBox(width: 3),
                              Text(
                                "Recorded",
                                style: GoogleFonts.outfit(color: Colors.green, fontSize: 10, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      oneLineSummary,
                      style: GoogleFonts.outfit(color: _text, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (localAudioPath != null)
                        IconButton(
                          tooltip: 'Play / Share Voice Recording',
                          icon: const Icon(Icons.play_circle_fill_rounded, color: Colors.green, size: 22),
                          onPressed: () async {
                            final file = File(localAudioPath);
                            if (await file.exists()) {
                              await SharePlus.instance.share(
                                ShareParams(
                                  files: [XFile(localAudioPath)],
                                  text: 'Call recording from $phone',
                                ),
                              );
                            } else if (audioUrl != null) {
                              final uri = Uri.parse(audioUrl);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            }
                          },
                        ),
                      if (localTranscriptPath != null)
                        IconButton(
                          tooltip: 'Share Transcript',
                          icon: const Icon(Icons.description_rounded, color: Colors.orange, size: 20),
                          onPressed: () async {
                            final file = File(localTranscriptPath);
                            if (await file.exists()) {
                              await SharePlus.instance.share(
                                ShareParams(
                                  files: [XFile(localTranscriptPath)],
                                  text: 'Call transcript with $phone',
                                ),
                              );
                            }
                          },
                        ),
                      if (localAudioPath != null && audioUrl == null)
                        IconButton(
                          tooltip: 'Backup audio to Cloud',
                          icon: const Icon(Icons.cloud_upload_rounded, color: Colors.blue, size: 20),
                          onPressed: () async {
                            try {
                              final file = File(localAudioPath);
                              if (await file.exists()) {
                                final bytes = await file.readAsBytes();
                                final cleanNumber = phone.replaceAll(RegExp(r'[^0-9+]'), '');
                                final fileName = 'call_${cleanNumber}_${DateTime.now().millisecondsSinceEpoch}.m4a';
                                final url = await CloudinaryUploadService().uploadAudioBytes(
                                  bytes,
                                  fileName: fileName,
                                  folder: 'call_recordings',
                                );
                                await FirebaseFirestore.instance
                                    .collection('chitti_appointments')
                                    .doc(docId)
                                    .trackedUpdate({'audioUrl': url});
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Audio successfully backed up to Cloud!')),
                                  );
                                }
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Upload failed: $e')),
                                );
                              }
                            }
                          },
                        ),
                      IconButton(
                        tooltip: 'Send SMS',
                        icon: const Icon(Icons.sms_rounded, color: _purple, size: 18),
                        onPressed: () async {
                          final uri = Uri.parse('sms:$phone');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          }
                        },
                      ),
                      IconButton(
                        tooltip: 'Call Back',
                        icon: const Icon(Icons.phone_in_talk_rounded, color: Colors.green, size: 18),
                        onPressed: () async {
                          final uri = Uri.parse('tel:$phone');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
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
        title: Text('Admin AI Configuration', style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 16)),
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
                    // Which provider CHITTI itself uses. Placed above
                    // the keys because it is the choice the CTO makes
                    // often; the keys are pasted once and forgotten.
                    Text(
                      "Chitti's brain",
                      style: GoogleFonts.outfit(
                        color: _text,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Which provider the Chitti assistant talks to. If its '
                      'key is missing or revoked, Chitti falls back to '
                      'whichever one is configured rather than going dead.',
                      style: GoogleFonts.outfit(
                        color: _muted,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final m in kChittiModels)
                          ChoiceChip(
                            selected: _chittiModelId == m.id,
                            label: Text(
                              m.label,
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _chittiModelId == m.id
                                    ? Colors.white
                                    : _text,
                              ),
                            ),
                            selectedColor: _red,
                            backgroundColor: _bg,
                            onSelected: (_) =>
                                setState(() => _chittiModelId = m.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildChittiVoiceSection(),
                    _buildCallAssistantSection(),
                    const SizedBox(height: 20),
                    Text('Groq API Key', style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 13)),
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
                    Text('Gemini API Key', style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 13)),
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
                        style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 13),),
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
                    const SizedBox(height: 18),
                    Text('Claude (Anthropic) API Key — Mobile Autonomous Dev',
                        style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 13),),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _anthropicCtrl,
                      obscureText: true,
                      style: const TextStyle(color: _text),
                      decoration: InputDecoration(
                        hintText: 'Paste your Anthropic API key (sk-ant-...)',
                        hintStyle: const TextStyle(color: _muted),
                        prefixIcon: const Icon(Icons.psychology_rounded, color: Colors.deepOrangeAccent),
                        filled: true,
                        fillColor: _bg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _modelDropdown(
                      value: _anthropicModel,
                      options: _kAnthropicModels,
                      accent: Colors.deepOrangeAccent,
                      onChanged: (v) => setState(() => _anthropicModel = v),
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

// NEW (per Nizam's request, Aug 31 2026): a selectable card for the
// "How Chitti answers a screened call" choice above — same tappable-
// card convention as _ManageTile in super_admin_home_screen.dart, just
// with a selected/unselected state instead of a nav arrow.
class _AnsweringModeOption extends StatelessWidget {
  const _AnsweringModeOption({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? _red.withValues(alpha: 0.12) : const Color(0xFF141420),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? _red : _border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              color: selected ? _red : _muted,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(color: _text, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(color: _muted, fontSize: 11, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
