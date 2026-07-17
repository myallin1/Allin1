import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiActivationService extends ChangeNotifier {
  static const String _apiKeyPrefsKey = 'personal_ai_api_key';

  String _apiKey = '';
  bool _isAiClaimed = false;

  String get apiKey => _apiKey;
  bool get isAiClaimed => _isAiClaimed;
  bool get isAiActivated => _apiKey.trim().isNotEmpty;
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
      if (_isAiClaimed) {
        _isAiClaimed = false;
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
          (data['promoClaims'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final nextClaimed = claims['ai_assistant'] == true;

      if (_isAiClaimed != nextClaimed) {
        _isAiClaimed = nextClaimed;
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
