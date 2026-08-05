import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiActivationService extends ChangeNotifier {
  // FIX (per Nizam/CTO's "bring your own key" pivot — customers now
  // paste their OWN Groq API key in Settings to activate their personal
  // "AI superhero"): moved off SharedPreferences (plaintext, readable by
  // any code/tool with app-storage access) onto flutter_secure_storage
  // (Android Keystore / iOS Keychain-backed, already a project
  // dependency — see pubspec.yaml) now that this key is something the
  // customer directly types in rather than an admin-provisioned value.
  static const String _apiKeyPrefsKey = 'personal_ai_api_key';
  static const String _apiKeySecureKey = 'personal_ai_api_key_secure';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  // NEW (Guru AI "Claim My Free Voice Access" flow): a lightweight,
  // device-local flag separate from the admin-controlled Firestore
  // `promoClaims.ai_pro` flag below — set the moment the customer taps
  // "Claim" in the in-app voice-unlock sheet (see
  // _ProPaywallSheet/_showProPaywall in guru_chat_screen.dart). Plain
  // SharedPreferences is fine here (not sensitive, not a real
  // entitlement/payment record) — this is a marketing/engagement
  // mechanic, not billing.
  static const String _proLocallyClaimedPrefsKey = 'ai_pro_locally_claimed';

  // NEW (Nizam's report — Gemini key had no paste/save UI anywhere):
  // GeminiApiService.resolveApiKey() (lib/services/gemini_api_service.dart)
  // already reads this exact SharedPreferences key as its fallback after
  // the GEMINI_API_KEY env var — this only adds the missing WRITER side.
  // Kept on plain SharedPreferences (not flutter_secure_storage like the
  // Groq key above) to match what the existing reader already expects,
  // rather than silently changing gemini_api_service.dart's own read
  // source as a side effect of this fix.
  static const String _geminiApiKeyPrefsKey = 'personal_gemini_api_key';

  String _apiKey = '';
  String _geminiApiKey = '';
  bool _isAiClaimed = false;
  // "MyAllin1 Pro" — the Voice-to-Order tier. Free tier (text chat) only
  // needs isAiActivated (a Groq key present, provisioned by Admin after a
  // support call). Pro is a separate, admin-set flag on top of that —
  // customers who've paid/been granted Pro can also use voice ordering.
  // Stored exactly like _isAiClaimed: a boolean under promoClaims on the
  // user's Firestore doc, flipped by Admin, never by the client.
  bool _isProUnlocked = false;
  bool _isProLocallyClaimed = false;

  String get apiKey => _apiKey;
  String get geminiApiKey => _geminiApiKey;
  bool get isGeminiActivated => _geminiApiKey.trim().isNotEmpty;
  bool get isAiClaimed => _isAiClaimed;
  bool get isAiActivated => _apiKey.trim().isNotEmpty;
  // Unlocked either the "real" admin-granted way (Firestore) or via the
  // free in-app claim button — either is sufficient.
  bool get isProUnlocked => _isProUnlocked || _isProLocallyClaimed;
  bool get showFloatingCompanion => _isAiClaimed && !isAiActivated;

  /// Called when the customer taps "Claim My Free Voice Access" in the
  /// voice-unlock sheet. Free, instant, no admin/WhatsApp round-trip —
  /// persists locally so it survives app restarts.
  Future<void> claimFreeVoiceAccess() async {
    if (_isProLocallyClaimed) {
      return;
    }
    _isProLocallyClaimed = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_proLocallyClaimedPrefsKey, true);
    } catch (e) {
      debugPrint('[AiActivationService] Failed to persist local Pro claim: $e');
    }
    notifyListeners();
  }

  AiActivationService() {
    unawaited(initialize());
  }

  Future<void> initialize() async {
    await _loadApiKey();
    await _loadGeminiApiKey();
    await _loadLocalProClaim();
    await refreshForUser(FirebaseAuth.instance.currentUser, notify: false);
    notifyListeners();
  }

  Future<void> _loadLocalProClaim() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isProLocallyClaimed = prefs.getBool(_proLocallyClaimedPrefsKey) ?? false;
    } catch (e) {
      debugPrint('[AiActivationService] Failed to load local Pro claim: $e');
    }
  }

  Future<void> refreshForUser(
    User? user, {
    bool notify = true,
  }) async {
    if (user == null) {
      // FIX (CTO mandate — "strictly tied to the active user session"):
      // the personal Groq key used to live purely at the app-INSTALL
      // level (flutter_secure_storage, never cleared on sign-out) —
      // on a shared/handed-down device, the next customer to sign in
      // would inherit and unknowingly burn the previous customer's key
      // and quota. Logout is the one reliable signal we get that the
      // session is ending, so wipe the key here too, not just the
      // Firestore-derived claim flags.
      final hadKey = _apiKey.isNotEmpty;
      if (hadKey) {
        _apiKey = '';
        try {
          await _secureStorage.delete(key: _apiKeySecureKey);
        } catch (e) {
          debugPrint('[AiActivationService] Secure storage delete on logout failed: $e');
        }
      }
      if (_isAiClaimed || _isProUnlocked || hadKey) {
        _isAiClaimed = false;
        _isProUnlocked = false;
        if (notify) {
          notifyListeners();
        }
      }
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snapshot.data() ?? <String, dynamic>{};
      final claims =
          (data['promoClaims'] as Map<String, dynamic>?) ??
              <String, dynamic>{};
      final nextClaimed = claims['ai_assistant'] == true;
      final nextPro = claims['ai_pro'] == true;

      if (_isAiClaimed != nextClaimed || _isProUnlocked != nextPro) {
        _isAiClaimed = nextClaimed;
        _isProUnlocked = nextPro;
        if (notify) {
          notifyListeners();
        }
      }
    } catch (error) {
      debugPrint('AI activation refresh failed: $error');
    }
  }

  Future<void> setAiClaimed(bool claimed) async {
    if (_isAiClaimed == claimed) {
      return;
    }
    _isAiClaimed = claimed;
    notifyListeners();
  }

  Future<void> saveApiKey(String value) async {
    final trimmed = value.trim();
    _apiKey = trimmed;

    if (trimmed.isEmpty) {
      await _secureStorage.delete(key: _apiKeySecureKey);
    } else {
      await _secureStorage.write(key: _apiKeySecureKey, value: trimmed);
    }

    notifyListeners();
  }

  // NEW (Nizam's report — "Gemini key apply panna vali illaya?"): the
  // missing writer for GeminiApiService.resolveApiKey()'s existing
  // SharedPreferences reader. Plain SharedPreferences here (not secure
  // storage) is a conscious, narrower choice than saveApiKey() above —
  // matches what gemini_api_service.dart already reads today without
  // also changing that file. If Gemini's key later needs the same
  // secure-storage/logout-wipe treatment the Groq key got, that's a
  // reasonable follow-up, not silently done here.
  Future<void> saveGeminiApiKey(String value) async {
    final trimmed = value.trim();
    _geminiApiKey = trimmed;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (trimmed.isEmpty) {
        await prefs.remove(_geminiApiKeyPrefsKey);
      } else {
        await prefs.setString(_geminiApiKeyPrefsKey, trimmed);
      }
    } catch (e) {
      debugPrint('[AiActivationService] Failed to save Gemini key: $e');
    }
    notifyListeners();
  }

  Future<void> _loadGeminiApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _geminiApiKey = prefs.getString(_geminiApiKeyPrefsKey)?.trim() ?? '';
    } catch (e) {
      debugPrint('[AiActivationService] Failed to load Gemini key: $e');
    }
  }

  Future<void> _loadApiKey() async {
    try {
      final secureValue = await _secureStorage.read(key: _apiKeySecureKey);
      if (secureValue != null && secureValue.isNotEmpty) {
        _apiKey = secureValue;
        return;
      }
    } catch (e) {
      // Secure storage can throw on some devices/emulators with no
      // Keystore/Keychain available (rare, but not worth crashing AI
      // activation over) -- fall through to the legacy-prefs check
      // below, same as a genuinely-empty secure store.
      debugPrint('[AiActivationService] Secure storage read failed: $e');
    }

    // ONE-TIME MIGRATION: a key saved before this fix was in plain
    // SharedPreferences under the old key name. Pick it up once, move it
    // into secure storage, and stop touching SharedPreferences for this
    // value ever again -- customers who already activated Guru AI before
    // this change don't lose their key or have to re-paste it.
    final prefs = await SharedPreferences.getInstance();
    final legacyValue = prefs.getString(_apiKeyPrefsKey);
    if (legacyValue != null && legacyValue.isNotEmpty) {
      _apiKey = legacyValue;
      await _secureStorage.write(key: _apiKeySecureKey, value: legacyValue);
      await prefs.remove(_apiKeyPrefsKey);
      debugPrint('[AiActivationService] Migrated API key from SharedPreferences to secure storage.');
    } else {
      _apiKey = '';
    }
  }
}
