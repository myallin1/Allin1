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
  bool _saving = false;
  String _lastSyncedApiKey = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final savedApiKey = context.watch<AiActivationService>().apiKey;
    if (_apiKeyFocusNode.hasFocus || savedApiKey == _lastSyncedApiKey) {
      return;
    }
    _apiKeyController.value = TextEditingValue(
      text: savedApiKey,
      selection: TextSelection.collapsed(offset: savedApiKey.length),
    );
    _lastSyncedApiKey = savedApiKey;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiKeyFocusNode.dispose();
    super.dispose();
  }

  Future<void> _saveAiConfiguration() async {
    final aiActivation = context.read<AiActivationService>();
    final key = _apiKeyController.text.trim();

    setState(() => _saving = true);
    await aiActivation.saveApiKey(key);
    if (!mounted) {
      return;
    }

    _lastSyncedApiKey = key;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          key.isEmpty
              ? 'Guru AI configuration cleared for this device.'
              : 'Guru AI is ready on this device.',
        ),
        backgroundColor: key.isEmpty
            ? const Color(0xFFFFB74D)
            : const Color(0xFFFF4FA3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aiActivation = context.watch<AiActivationService>();
    final activated = aiActivation.isAiActivated;

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
                          activated
                              ? 'Guru AI is activated on this device.'
                              : 'Save your Groq API key to unlock the full Guru AI chat.',
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
              Text(
                'Groq API Key',
                style: GoogleFonts.outfit(
                  color: const Color(0xFF4A1236),
                  fontWeight: FontWeight.w700,
                ),
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
              Text(
                'Your key stays on this device. As soon as you save it, Guru AI becomes ready on the home dashboard.',
                style: GoogleFonts.outfit(
                  color: const Color(0xFF8A4E72),
                  fontSize: 12.5,
                  height: 1.45,
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
                    activated ? 'Update Guru AI Key' : 'Save & Activate Guru AI',
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
