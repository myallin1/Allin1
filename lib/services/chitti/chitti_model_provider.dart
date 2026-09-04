// ================================================================
// chitti_model_provider.dart — which brain Chitti is using.
// ================================================================
// NEW (Aug 28 2026 — Nizam: "namma app groq, gemini, deepseek all
// model available so admin ketta atha chitti agent app kulla udane
// [use pannanum]").
//
// WHY A PROVIDER LAYER AND NOT THREE SERVICES
// All three speak the SAME wire format. Groq and DeepSeek both expose
// an OpenAI-compatible /chat/completions endpoint, and Gemini exposes
// one at its openai/ compatibility path. So the only things that
// actually differ are the URL, the model id, and which key to send —
// which is exactly what this class holds. Writing three chat services
// would mean three copies of the tool-calling loop, and the two nobody
// tests would rot.
//
// WHY THE ADMIN CHOOSES, AND ONLY THE ADMIN
// Nizam's brief is that the ADMIN can ask for a different model. A
// customer has no way to know what a model is, and letting the choice
// leak into the customer build would mean a support call the first
// time somebody picked a slow one. The picker lives in admin settings;
// every other variant is pinned to the default.
//
// FALLING BACK IS PART OF THE CONTRACT
// A key that is missing, revoked, or rate-limited must not leave the
// admin with a dead assistant mid-shift. [resolve] never returns a
// provider whose key is absent — it degrades to whichever is
// configured, and only reports "no model" when nothing is.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One LLM backend.
@immutable
class ChittiModel {
  const ChittiModel({
    required this.id,
    required this.label,
    required this.endpoint,
    required this.textModel,
    required this.visionModel,
    required this.envKeyName,
    required this.prefsKeyName,
    this.modelPrefsKeyName,
    this.supportsTools = true,
  });

  /// Stable id used in prefs and in the picker. Renaming one silently
  /// resets every admin's saved choice, so treat it as permanent.
  final String id;

  /// What the admin sees.
  final String label;

  /// OpenAI-compatible chat-completions URL.
  final String endpoint;

  final String textModel;

  /// The model to switch to when a screenshot is attached. Vision
  /// models are slower and pricier, so this is used per-request rather
  /// than as the default.
  final String visionModel;

  /// dart-define name, for keys baked in at build time.
  final String envKeyName;

  /// SharedPreferences key, for a key the admin pastes in at runtime.
  ///
  /// These are NOT new names. admin_ai_settings_screen.dart has been
  /// storing all three keys under these exact keys since Aug 12 2026,
  /// and the CTO has already pasted them in. Inventing a parallel set
  /// would have left Chitti reporting "no model configured" on a phone
  /// where the settings screen plainly shows three saved keys — the
  /// kind of bug that takes an hour to see because both halves look
  /// right on their own.
  final String prefsKeyName;

  /// Where the admin's per-provider model choice is stored, also
  /// owned by admin_ai_settings_screen.dart.
  ///
  /// Null means this provider has no picker there yet, so
  /// [textModel] stands.
  final String? modelPrefsKeyName;

  /// Whether this backend can do tool calling.
  ///
  /// Chitti's whole design is tools, so a backend without them can
  /// answer questions but cannot ACT. Surfaced rather than assumed so
  /// the picker can say so instead of the admin discovering it when a
  /// command silently turns into a paragraph.
  final bool supportsTools;
}

/// The backends this app knows how to talk to.
///
/// Order matters: [kChittiModels.first] is the default, and the
/// fallback order when a chosen model has no key.
const List<ChittiModel> kChittiModels = <ChittiModel>[
  ChittiModel(
    id: 'groq',
    label: 'Groq (fastest)',
    endpoint: 'https://api.groq.com/openai/v1/chat/completions',
    textModel: 'llama-3.3-70b-versatile',
    // Maverick was deprecated Feb 2026; Scout is the current vision
    // model — see the note in guru_api_service.dart.
    visionModel: 'meta-llama/llama-4-scout-17b-16e-instruct',
    envKeyName: 'GROQ_API_KEY',
    prefsKeyName: 'personal_ai_api_key',
    modelPrefsKeyName: 'personal_groq_model',
  ),
  ChittiModel(
    id: 'gemini',
    label: 'Gemini (best reasoning)',
    // Google's OpenAI-compatibility endpoint, so the same request
    // builder works unchanged.
    endpoint:
        'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
    textModel: 'gemini-2.0-flash',
    visionModel: 'gemini-2.0-flash',
    envKeyName: 'GEMINI_API_KEY',
    prefsKeyName: 'personal_gemini_api_key',
    modelPrefsKeyName: 'personal_gemini_model',
  ),
  ChittiModel(
    id: 'deepseek',
    label: 'DeepSeek (deep thinking)',
    endpoint: 'https://api.deepseek.com/chat/completions',
    textModel: 'deepseek-chat',
    // DeepSeek's chat model is text-only. Declared honestly rather
    // than pointed at a model that would 400 on an image: callers
    // check this and fall back to a vision-capable provider for that
    // one request.
    visionModel: '',
    envKeyName: 'DEEPSEEK_API_KEY',
    prefsKeyName: 'personal_deepseek_api_key',
    modelPrefsKeyName: 'personal_deepseek_model',
  ),
  ChittiModel(
    id: 'anthropic',
    label: 'Claude (Anthropic Code & Architect)',
    endpoint: 'https://api.anthropic.com/v1/messages',
    textModel: 'claude-opus-5',
    visionModel: 'claude-opus-5',
    envKeyName: 'ANTHROPIC_API_KEY',
    prefsKeyName: 'personal_anthropic_api_key',
    modelPrefsKeyName: 'personal_anthropic_model',
  ),
];

/// Where the admin's chosen model id is stored.
const String kChittiModelPrefsKey = 'chitti_model_id';

/// Persists the admin's model choice.
///
/// Written by the new in-chat picker (chitti_model_picker_sheet.dart).
/// admin_ai_settings_screen.dart keeps writing this same key directly
/// as part of its own batched settings save — same key, same effect,
/// left untouched rather than risking that save's existing grouping.
/// Nothing needs to be notified after either write: guru_api_service.
/// dart's _resolveBackend reads this key fresh on every request rather
/// than caching it, specifically so a change here reaches the very next
/// message with no extra plumbing.
Future<void> setChittiModelId(String id) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kChittiModelPrefsKey, id);
}

/// The admin's currently chosen model id, or null if none has been
/// picked yet (callers fall back to [defaultChittiModel] in that case).
Future<String?> getChittiModelId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(kChittiModelPrefsKey);
}

/// Looks up a model by id, or the default when the id is unknown.
ChittiModel chittiModelById(String? id) => kChittiModels.firstWhere(
      (m) => m.id == id,
      orElse: () => kChittiModels.first,
    );

/// The default, used by every variant except admin.
ChittiModel get defaultChittiModel => kChittiModels.first;

/// True when this model can look at a screenshot.
bool chittiModelSupportsVision(ChittiModel m) => m.visionModel.isNotEmpty;

/// The first model that has a usable key, starting from [preferred].
///
/// [keyFor] is injected rather than read here so this stays a pure
/// function — the key sources (dart-define, prefs) live in the service
/// that owns them, and this can be tested without either.
///
/// Returns null only when NO model has a key, which is the one case
/// the caller must report rather than paper over.
ChittiModel? resolveChittiModel({
  required String? preferredId,
  required String Function(ChittiModel) keyFor,
  bool needsVision = false,
}) {
  bool usable(ChittiModel m) {
    if (keyFor(m).trim().isEmpty) return false;
    if (needsVision && !chittiModelSupportsVision(m)) return false;
    return true;
  }

  final preferred = chittiModelById(preferredId);
  if (usable(preferred)) return preferred;

  // Preferred one is unusable — a missing key, a revoked key, or a
  // text-only model asked to read a screenshot. Degrade rather than
  // leave the admin with a dead assistant mid-shift.
  for (final m in kChittiModels) {
    if (usable(m)) return m;
  }
  return null;
}
