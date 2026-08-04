import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiActivationService extends ChangeNotifier {
  static const String _apiKeyPrefsKey = 'personal_ai_api_key';

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

    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      await prefs.remove(_apiKeyPrefsKey);
    } else {
      await prefs.setString(_apiKeyPrefsKey, trimmed);
    }

    notifyListeners();
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString(_apiKeyPrefsKey) ?? '';
  }
}
