import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_wallet_model.dart';

class WalletProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  UserWalletModel _wallet = const UserWalletModel(userId: 'temp');
  StreamSubscription<DocumentSnapshot>? _walletSubscription;
  bool _isLoading = false;
  String? _error;

  // Getters
  UserWalletModel get wallet => _wallet;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Convenience getters
  int get njCoinsBalance => _wallet.njCoinsBalance;
  int get njCoinsPending => _wallet.njCoinsPending;
  int get currentStreak => _wallet.currentStreak;
  int get userLevel => _wallet.userLevel;
  int get dailyCoinsUsed => _wallet.dailyCoinsUsed;
  int get maxDailyCoinLimit => _wallet.maxDailyCoinLimit;
  int get levelProgress =>
      _wallet.njCoinsBalance % 100; // Mock calculation for UI
  int get levelGoal => 100;
  int get longestStreak => 0; // Temporary stub

  // Initialize live stream (Bulletproof Phase 3)
  void initialize(String userId) {
    if (_walletSubscription != null) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    _walletSubscription =
        _firestore.collection('users').doc(userId).snapshots().listen(
      (snapshot) {
        if (snapshot.exists) {
          _wallet =
              UserWalletModel.fromFirestore(snapshot.data()!, snapshot.id);
          _error = null;
        } else {
          _error = 'Wallet not found';
        }
        _isLoading = false;
        notifyListeners();
      },
      onError: (Object e) {
        _error = e.toString();
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  // Cleanup
  @override
  void dispose() {
    _walletSubscription?.cancel();
    super.dispose();
  }

  // Refresh wallet manually (if needed)
  Future<void> refresh(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        _wallet = UserWalletModel.fromFirestore(doc.data()!, doc.id);
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  // Backwards compatibility for early stage calls
  void loadDummyData(String userId) {
    initialize(userId);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
