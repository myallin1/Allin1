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

  String _apiKey = '';
  bool _isAiClaimed = false;
  // "MyAllin1 Pro" — the Voice-to-Order tier. Free tier (text chat) only
  // needs isAiActivated (a Groq key present, provisioned by Admin after a
  // support call). Pro is a separate, admin-set flag on top of that —
  // customers who've paid/been granted Pro can also use voice ordering.
  // Stored exactly like _isAiClaimed: a boolean under promoClaims on the
  // user's Firestore doc, flipped by Admin, never by the client.
  bool _isProUnlocked = false;

  String get apiKey => _apiKey;
  bool get isAiClaimed => _isAiClaimed;
  bool get isAiActivated => _apiKey.trim().isNotEmpty;
  bool get isProUnlocked => _isProUnlocked;
  bool get showFloatingCompanion => _isAiClaimed && !isAiActivated;

  AiActivationService() {
    unawaited(initialize());
  }

  Future<void> initialize() async {
    await _loadApiKey();
    await refreshForUser(FirebaseAuth.instance.currentUser, notify: false);
    notifyListeners();
  }

  Future<void> refreshForUser(
    User? user, {
    bool notify = true,
  }) async {
    if (user == null) {
      if (_isAiClaimed || _isProUnlocked) {
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
