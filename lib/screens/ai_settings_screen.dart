import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/ai_activation_service.dart';
import '../services/chitti/chitti_backup_service.dart';
import '../services/chitti/chitti_conversation_controller.dart';
import '../services/chitti/chitti_voice_service.dart';
import '../services/chitti/chitti_welcome_service.dart';
import '../services/localization_service.dart';

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

  // NEW (Aug 28 2026 — Nizam: "Chitti voice innum girl voice ah
  // iruku"). Which voices exist is entirely device-dependent — TTS
  // engine, installed language packs, browser — so no heuristic in
  // ChittiVoiceService can be right on every phone. This section lets
  // the actual voices on THIS device be auditioned and one pinned.
  // That is the only reliable fix; the heuristic is just the default.
  final FlutterTts _previewTts = FlutterTts();
  List<ChittiVoiceOption> _voices = const <ChittiVoiceOption>[];
  bool _loadingVoices = true;
  String? _pinnedVoice;
  ChittiVoiceTone _tone = ChittiVoiceTone.chitti;
  bool _welcomeEnabled = true;
  DateTime? _lastBackupAt;
  bool _backupBusy = false;
  bool _localBackupBusy = false;
  ChittiConversationMode _convoMode = ChittiConversationMode.autoStop;

  @override
  void initState() {
    super.initState();
    unawaited(_loadVoices());
  }

  Future<void> _loadVoices() async {
    // Read the saved tone/pin through a no-op apply first, so the
    // controls below open showing what Chitti is ACTUALLY using
    // rather than the enum default.
    final locale = _ttsLocale();
    await ChittiConversationPrefs.load();
    await ChittiVoiceService.apply(_previewTts, locale);
    final voices =
        await ChittiVoiceService.availableVoices(_previewTts, locale);
    final lastBackup = await ChittiBackupService.instance.lastBackupAt();
    if (!mounted) return;
    setState(() {
      _voices = voices;
      _pinnedVoice = ChittiVoiceService.pinnedVoiceName;
      _tone = ChittiVoiceService.tone;
      _welcomeEnabled = ChittiWelcomeService.enabled;
      _convoMode = ChittiConversationPrefs.mode;
      _lastBackupAt = lastBackup;
      _loadingVoices = false;
    });
  }

  String _ttsLocale() {
    final code = context.read<LocalizationService>().languageCode;
    return switch (code) {
      'ta' || 'tg' => 'ta-IN',
      'hi' => 'hi-IN',
      'ml' => 'ml-IN',
      _ => 'en-IN',
    };
  }

  Future<void> _previewVoice() async {
    final code = context.read<LocalizationService>().languageCode;
    await ChittiVoiceService.apply(_previewTts, _ttsLocale());
    await _previewTts.stop();
    await _previewTts.speak(ChittiVoiceService.previewLine(code));
  }

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
    unawaited(_previewTts.stop());
    _apiKeyController.dispose();
    _apiKeyFocusNode.dispose();
    _geminiKeyController.dispose();
    _geminiKeyFocusNode.dispose();
    super.dispose();
  }

  /// Backup & restore.
  ///
  /// NEW (Aug 28 2026 — Nizam's WhatsApp model). The customer's chat
  /// history, Chitti's memory of them, their order memory and their
  /// preferences live on this device and in THEIR Google Drive — not in
  /// our database. This is where they move it to a new phone.
  ///
  /// The wallet is deliberately absent: money stays server-side, so a
  /// restored file can never be an edited balance.
  Widget _buildBackupSection() {
    const pink = Color(0xFFFF4FA3);
    const deep = Color(0xFF4A1236);
    const muted = Color(0xFF8A4E72);

    final last = _lastBackupAt;
    final subtitle = !ChittiBackupService.isSupported
        ? 'Available in the installed app.'
        : last == null
            ? 'Not backed up yet.'
            : 'Last backup: ${last.day}/${last.month} '
                '${last.hour.toString().padLeft(2, '0')}:'
                '${last.minute.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 36, color: Color(0x22FF4FA3)),
        Row(
          children: [
            const Icon(Icons.cloud_upload_rounded, color: pink, size: 20),
            const SizedBox(width: 8),
            Text(
              'Backup & Restore',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: deep,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Your chats, Chitti\'s memory of you and your settings are saved '
          '— to your own Google Drive, or as a file you keep yourself. '
          'Change phone, restore, and Chitti picks up where you left off. '
          'Your wallet stays safe on our servers and is never in either.',
          style: GoogleFonts.outfit(color: muted, fontSize: 11.5, height: 1.4),
        ),
        const SizedBox(height: 14),
        Text(
          'GOOGLE DRIVE',
          style: GoogleFonts.outfit(
            color: muted,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.outfit(
            color: muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        if (_backupBusy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: LinearProgressIndicator(color: pink, minHeight: 2),
          )
        else
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: ChittiBackupService.isSupported
                      ? () => _runDriveBackup(restore: false)
                      : null,
                  icon: const Icon(Icons.backup_rounded, size: 18),
                  label: Text(
                    'Back Up',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: pink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: ChittiBackupService.isSupported
                      ? () => _runDriveBackup(restore: true)
                      : null,
                  icon: const Icon(Icons.restore_rounded, size: 18, color: pink),
                  label: Text(
                    'Restore',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      color: pink,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: pink),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 18),
        Text(
          'THIS DEVICE',
          style: GoogleFonts.outfit(
            color: muted,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Save a backup file to your phone\'s storage — no Google '
          'account needed. Works offline; share it to keep a copy '
          'anywhere you like.',
          style: GoogleFonts.outfit(
            color: muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        if (_localBackupBusy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: LinearProgressIndicator(color: pink, minHeight: 2),
          )
        else
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _runLocalBackup(restore: false),
                  icon: const Icon(Icons.save_alt_rounded, size: 18),
                  label: Text(
                    'Save File',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: deep,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _runLocalBackup(restore: true),
                  icon: const Icon(Icons.file_open_rounded, size: 18, color: deep),
                  label: Text(
                    'Load File',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      color: deep,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: deep),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _runDriveBackup({required bool restore}) async {
    if (restore) {
      // Restore REPLACES local history rather than merging — merging two
      // phones' conversations would interleave them out of order — so it
      // gets a confirmation. Backing up needs none; it only ever adds.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Restore from Drive?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
          ),
          content: Text(
            'This replaces the chats and history on this phone with what '
            'is in your backup.',
            style: GoogleFonts.outfit(fontSize: 13.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _backupBusy = true);
    final result = restore
        ? await ChittiBackupService.instance.restoreNow()
        : await ChittiBackupService.instance.backupNow();
    if (!mounted) return;
    setState(() {
      _backupBusy = false;
      if (result.ok && !restore) _lastBackupAt = result.at;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  Future<void> _runLocalBackup({required bool restore}) async {
    if (restore) {
      // Same reasoning as the Drive restore confirm above — a local
      // file restore also REPLACES this phone's history, not merges it.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Restore from a file?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
          ),
          content: Text(
            'This replaces the chats and history on this phone with what '
            'is in the backup file you pick.',
            style: GoogleFonts.outfit(fontSize: 13.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _localBackupBusy = true);
    final result = restore
        ? await ChittiBackupService.instance.restoreFromLocalFile()
        : await ChittiBackupService.instance.backupToLocalFile();
    if (!mounted) return;
    setState(() {
      _localBackupBusy = false;
      if (result.ok && !restore) _lastBackupAt = result.at;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  /// Voice controls. Kept in its own builder rather than inlined into
  /// the already-long build() below, purely for readability — it adds
  /// no state of its own beyond the three fields above.
  Widget _buildVoiceSection() {
    const pink = Color(0xFFFF4FA3);
    const deep = Color(0xFF4A1236);
    const muted = Color(0xFF8A4E72);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 36, color: Color(0x22FF4FA3)),
        Row(
          children: [
            const Icon(Icons.record_voice_over_rounded, color: pink, size: 20),
            const SizedBox(width: 8),
            Text(
              'Chitti Voice',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: deep,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Pick how Chitti sounds, then tap Preview to hear it. Which '
          'voices exist depends on this device, so what you hear here is '
          'exactly what Chitti will use.',
          style: GoogleFonts.outfit(
            color: muted,
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tone in ChittiVoiceTone.values)
              ChoiceChip(
                selected: _tone == tone,
                label: Text(
                  switch (tone) {
                    ChittiVoiceTone.natural => 'Natural',
                    ChittiVoiceTone.chitti => 'Chitti',
                    ChittiVoiceTone.robot => 'Full Robot',
                  },
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: _tone == tone ? Colors.white : deep,
                  ),
                ),
                selectedColor: pink,
                backgroundColor: const Color(0xFFFFF1F8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0x33FF4FA3)),
                ),
                onSelected: (_) async {
                  setState(() => _tone = tone);
                  await ChittiVoiceService.setTone(tone);
                  await _previewVoice();
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (_loadingVoices)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(color: pink, minHeight: 2),
          )
        else if (_voices.isEmpty)
          Text(
            'No voices are installed for this language on this device. '
            'Chitti will still speak using the system default, shaped to '
            'the tone above.',
            style: GoogleFonts.outfit(
              color: muted,
              fontSize: 11.5,
              height: 1.4,
            ),
          )
        else
          DropdownButtonFormField<String>(
            initialValue:
                _voices.any((v) => v.name == _pinnedVoice) ? _pinnedVoice : null,
            isExpanded: true,
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFFFF1F8),
              prefixIcon: const Icon(Icons.graphic_eq_rounded, color: pink),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
            hint: Text(
              'Auto (pick a male voice for me)',
              style: GoogleFonts.outfit(color: muted, fontSize: 13),
            ),
            items: [
              DropdownMenuItem<String>(
                child: Text(
                  'Auto (pick a male voice for me)',
                  style: GoogleFonts.outfit(fontSize: 13, color: deep),
                ),
              ),
              for (final voice in _voices)
                DropdownMenuItem<String>(
                  value: voice.name,
                  child: Text(
                    voice.label,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(fontSize: 13, color: deep),
                  ),
                ),
            ],
            onChanged: (name) async {
              setState(() => _pinnedVoice = name);
              final match = _voices.where((v) => v.name == name).firstOrNull;
              await ChittiVoiceService.pinVoice(
                name: name,
                locale: match?.locale,
              );
              await _previewVoice();
            },
          ),
        // NEW (Aug 29 2026 — Nizam: "oppo phone la chitti ku male
        // voice varuthu, samsung phone la male voice varala").
        //
        // Not a code bug — a device difference. Oppo phones generally
        // default to Google's own TTS engine, whose voice catalogue
        // has a male Tamil/English-India option; many Samsung phones
        // default to "Samsung TTS", a separate engine with a smaller
        // catalogue that often has no male option for those languages
        // at all. No amount of app-side name-matching can produce a
        // voice the active engine does not have — the fix has to
        // happen in the phone's own TTS settings. Shown only when
        // voices exist but NONE of them look male, which is exactly
        // this situation (the empty-list case above already covers
        // "no voices at all").
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
                color: pink,
                fontSize: 11,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const SizedBox(height: 14),
        Text(
          'Hands-free conversation',
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: deep,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'After you tap the mic, Chitti keeps listening between its own '
          'replies. You can cut in any time, and saying "stop" or '
          '"podhum" always ends it.',
          style: GoogleFonts.outfit(color: muted, fontSize: 11.5, height: 1.4),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final mode in ChittiConversationMode.values)
              ChoiceChip(
                selected: _convoMode == mode,
                label: Text(
                  mode == ChittiConversationMode.autoStop
                      ? 'Auto-stop'
                      : 'Call mode',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: _convoMode == mode ? Colors.white : deep,
                  ),
                ),
                selectedColor: pink,
                backgroundColor: const Color(0xFFFFF1F8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0x33FF4FA3)),
                ),
                onSelected: (_) async {
                  setState(() => _convoMode = mode);
                  await ChittiConversationPrefs.save(mode);
                },
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _convoMode == ChittiConversationMode.autoStop
              ? 'Ends on its own once the job is done, or after 8 seconds of '
                  'quiet.'
              : 'Stays open like a call until you stop it. Watch your battery.',
          style: GoogleFonts.outfit(color: muted, fontSize: 11, height: 1.4),
        ),
        const SizedBox(height: 4),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _welcomeEnabled,
          activeThumbColor: pink,
          title: Text(
            'Greet me when I open the app',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: deep,
            ),
          ),
          subtitle: Text(
            // Worth stating plainly: on the web build the greeting
            // cannot fire before the first touch, and a user who does
            // not know that will report it as broken.
            'Chitti says hello on your first tap, once per session.',
            style: GoogleFonts.outfit(color: muted, fontSize: 11.5),
          ),
          onChanged: (value) async {
            setState(() => _welcomeEnabled = value);
            await ChittiWelcomeService.setEnabled(value);
          },
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _previewVoice,
            icon: const Icon(Icons.play_arrow_rounded, color: pink),
            label: Text(
              'Preview Chitti',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w700,
                color: pink,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: pink),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
      ],
    );
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
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF4A1236),
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
              _buildVoiceSection(),
              _buildBackupSection(),
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
