import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/localization_service.dart';
import 'bike_taxi/bike_booking_screen.dart';

const Color _card = Colors.white;
const Color _card2 = Color(0xFFFFEEF7);
const Color _green = Color(0xFF00A86B);
const Color _gold = Color(0xFFFF2F92);
const Color _orange = Color(0xFFFF4FA3);
const Color _red = Color(0xFFFF5252);
const Color _text = Color(0xFF3D1230);
const Color _muted = Color(0xFF8F5A78);
const Color _border = Color(0x33FF4FA3);

class PaymentScreen extends StatefulWidget {
  final double? amount;
  final String? note;
  final String? rideId;
  final String? rideDocId;

  const PaymentScreen({
    super.key,
    this.amount,
    this.note,
    this.rideId,
    this.rideDocId,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DoubleProperty('amount', amount))
      ..add(StringProperty('note', note))
      ..add(StringProperty('rideId', rideId))
      ..add(StringProperty('rideDocId', rideDocId));
  }
}

class _PaymentScreenState extends State<PaymentScreen>
    with SingleTickerProviderStateMixin {
  double _fare = 0;
  double _walletBal = 0;
  bool _payingWallet = false;
  bool _paid = false;
  bool _awaitingHeroConfirmation = false;
  int _selectedRating = 0;
  String _summaryPaymentMethod = 'Payment';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _rideSubscription;

  late final AnimationController _successCtrl;
  late final Animation<double> _successAnim;

  @override
  void initState() {
    super.initState();
    _fare = widget.amount ?? 45.0;
    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successAnim = CurvedAnimation(
      parent: _successCtrl,
      curve: Curves.elasticOut,
    );
    _bindRideStatus();
    _loadWalletBalance();
  }

  @override
  void dispose() {
    _rideSubscription?.cancel();
    _successCtrl.dispose();
    super.dispose();
  }

  String? get _rideDocId {
    final value = widget.rideId ?? widget.rideDocId;
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  void _bindRideStatus() {
    final rideDocId = _rideDocId;
    if (rideDocId == null) {
      return;
    }

    _rideSubscription?.cancel();
    _rideSubscription = FirebaseFirestore.instance
        .collection('rides')
        .doc(rideDocId)
        .snapshots()
        .listen((snap) {
          if (!mounted || !snap.exists) {
            return;
          }
          final data = snap.data();
          if (data == null) {
            return;
          }

          final liveFare =
              (data['actualFare'] as num?)?.toDouble() ??
              (data['amountPaid'] as num?)?.toDouble() ??
              (data['estimatedFare'] as num?)?.toDouble() ??
              (data['fare'] as num?)?.toDouble();
          final paymentStatus = (data['paymentStatus'] as String? ?? '').trim();
          final paymentMethod =
              (data['paymentMethod'] as String? ?? 'Payment').trim();
          final shouldUnlock = <String>{
            'paid',
            'paid_by_wallet',
            'paid_offline_p2p',
            'completed',
          }.contains(paymentStatus);

          if (liveFare != null && liveFare > 0 && liveFare != _fare) {
            setState(() {
              _fare = liveFare;
            });
          }

          if (shouldUnlock && !_paid) {
            setState(() {
              _summaryPaymentMethod = paymentMethod.replaceAll('_', ' ');
              _paid = true;
              _awaitingHeroConfirmation = false;
            });
            _successCtrl
              ..reset()
              ..forward();
          }
        });
  }

  Future<void> _loadWalletBalance() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        return;
      }

      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!mounted || !doc.exists) {
        return;
      }

      setState(() {
        _walletBal = (doc.data()?['walletBalance'] as num?)?.toDouble() ?? 0.0;
      });
    } catch (e) {
      debugPrint('Wallet load failed: $e');
    }
  }

  Future<void> _payWithWallet() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final rideDocId = _rideDocId;
    if (uid == null) {
      return;
    }
    if (_walletBal < _fare) {
      _snack('Insufficient wallet balance!', _red);
      return;
    }

    setState(() => _payingWallet = true);
    try {
      final db = FirebaseFirestore.instance;
      final userRef = db.collection('users').doc(uid);

      await db.runTransaction((txn) async {
        final userSnap = await txn.get(userRef);
        final userBalance =
            (userSnap.data()?['walletBalance'] as num?)?.toDouble() ?? 0.0;
        if (userBalance < _fare) {
          throw Exception('Insufficient balance');
        }

        String? heroId;
        if (rideDocId != null) {
          final rideSnap = await txn.get(db.collection('rides').doc(rideDocId));
          heroId = rideSnap.data()?['heroId'] as String?;
        }

        txn.update(userRef, {'walletBalance': userBalance - _fare});

        if (rideDocId != null) {
          txn.update(db.collection('rides').doc(rideDocId), {
            'status': 'paid',
            'paymentStatus': 'paid_by_wallet',
            'paidAt': FieldValue.serverTimestamp(),
            'paymentMethod': 'wallet',
            'amountPaid': _fare,
            'paymentReceivedBy': uid,
          });
        }

        if (heroId != null && heroId.isNotEmpty) {
          final heroRef = db.collection('heroes').doc(heroId);
          final heroSnap = await txn.get(heroRef);
          final heroBalance =
              (heroSnap.data()?['walletBalance'] as num?)?.toDouble() ?? 0.0;
          final totalEarnings =
              (heroSnap.data()?['totalEarnings'] as num?)?.toDouble() ?? 0.0;
          final totalRides =
              (heroSnap.data()?['totalRides'] as num?)?.toInt() ?? 0;

          txn.set(
            heroRef,
            {
              'walletBalance': heroBalance + _fare,
              'totalEarnings': totalEarnings + _fare,
              'totalRides': totalRides + 1,
              'lastRideCompletedAt': FieldValue.serverTimestamp(),
              'status': 'online',
              'isAvailable': true,
              'activeRideId': null,
            },
            SetOptions(merge: true),
          );

          txn.set(db.collection('wallet_transactions').doc(), {
            'heroId': heroId,
            'type': 'credit',
            'amount': _fare,
            'rideId': rideDocId,
            'description': 'Wallet payment received for ride',
            'timestamp': FieldValue.serverTimestamp(),
          });
        }

        txn.set(db.collection('wallet_transactions').doc(), {
          'userId': uid,
          'type': 'debit',
          'amount': _fare,
          'rideId': rideDocId ?? '',
          'balanceBefore': userBalance,
          'balanceAfter': userBalance - _fare,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _payingWallet = false;
        _awaitingHeroConfirmation = false;
      });
      _snack(
        'Payment successful! ₹${_fare.toStringAsFixed(0)} paid via Wallet',
        _green,
      );
      await _loadWalletBalance();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _payingWallet = false);
      _snack('Payment failed: $e', _red);
    }
  }

  Future<void> _launchUpi() async {
    final rideDocId = _rideDocId ?? '';
    final safeRideId = rideDocId.replaceAll(RegExp('[^A-Za-z0-9]'), '');
    final transactionRef =
        'NJTECH${safeRideId.isNotEmpty ? safeRideId : DateTime.now().millisecondsSinceEpoch}';
    final uri = Uri.parse(
      'upi://pay?pa=njtech@oksbi'
      '&pn=NJTECH'
      '&mc=0000'
      '&tr=$transactionRef'
      '&tn=RidePayment'
      '&am=${_fare.toStringAsFixed(2)}'
      '&cu=INR',
    );

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) {
        return;
      }
      if (launched) {
        setState(() => _awaitingHeroConfirmation = true);
        _snack(
          'UPI app opened. Scan the Paytm Soundbox and wait for hero confirmation.',
          _gold,
        );
      } else {
        _snack(
          'No UPI app opened. Please install or enable a UPI app.',
          _orange,
        );
      }
    } catch (e) {
      debugPrint('UPI launch failed: $e');
      if (!mounted) {
        return;
      }
      _snack('Unable to open UPI app right now.', _red);
    }
  }

  Future<void> _submitRatingAndReturn(int rating) async {
    if (!mounted) {
      return;
    }
    setState(() => _selectedRating = rating);

    final rideDocId = _rideDocId;
    if (rideDocId != null) {
      try {
        await FirebaseFirestore.instance.collection('rides').doc(rideDocId).set(
          {
            'customerRating': rating,
            'customerRatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } catch (e) {
        debugPrint('Rating update failed: $e');
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) {
      return;
    }
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const BikeBookingScreen()),
      (route) => false,
    );
  }

  void _snack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _gold,
        surfaceTintColor: _gold,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 16,
            color: Colors.white,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Paytm Soundbox Bill',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body:
          _paid
              ? _buildSuccessView()
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildPaytmBillHero(),
                    const SizedBox(height: 16),
                    _buildFareCard(),
                    const SizedBox(height: 16),
                    if (_walletBal >= _fare) ...[
                      _buildWalletCard(),
                      const SizedBox(height: 12),
                    ],
                    _buildUpiSection(),
                    if (_awaitingHeroConfirmation) ...[
                      const SizedBox(height: 16),
                      _buildAwaitingHeroCard(),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      'Erode la all in one vanthachu inimel yentha kavalayum vendam 😊',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: _muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
    );
  }

  Widget _buildFareCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14FF4FA3),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          const Text('🏍️', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.note ?? 'Bike Taxi Ride',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: _text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Allin1 Super App · Erode',
                  style: GoogleFonts.outfit(fontSize: 10, color: _muted),
                ),
              ],
            ),
          ),
          Text(
            '₹${_fare.toStringAsFixed(2)}',
            style: GoogleFonts.outfit(
              fontSize: 22,
              color: _gold,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaytmBillHero() {
    final localization = context.read<LocalizationService>();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF5FA), Color(0xFFFFFFFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18FF4FA3),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 68,
                height: 68,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _border),
                ),
                child: Image.asset(
                  'assets/images/paytm_soundbox.png',
                  fit: BoxFit.contain,
                  errorBuilder:
                      (context, error, stackTrace) => const Icon(
                        Icons.speaker_group_rounded,
                        color: _orange,
                        size: 34,
                      ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localization.t('pay_via_soundbox'),
                      style: GoogleFonts.outfit(
                        color: _text,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      localization.t('scan_soundbox_qr'),
                      style: GoogleFonts.outfit(
                        color: _muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Generated Bill',
                  style: GoogleFonts.outfit(
                    color: _muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '₹${_fare.toStringAsFixed(2)}',
                  style: GoogleFonts.outfit(
                    color: _orange,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  localization.t('scan_and_wait_hero'),
                  style: GoogleFonts.outfit(
                    color: _text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAwaitingHeroCard() {
    final localization = context.read<LocalizationService>();
    return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4FA),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x12FF4FA3),
          blurRadius: 20,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border),
          ),
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: _gold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localization.t('awaiting_hero_payment'),
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  color: _text,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                localization.t('scan_and_wait_hero'),
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: _muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  }

  Widget _buildWalletCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _walletBal >= _fare ? const Color(0xFFEFFFF6) : _card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: _walletBal >= _fare ? _green.withValues(alpha: 0.4) : _border,
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color:
                _walletBal >= _fare ? _green.withValues(alpha: 0.12) : _card2,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              _walletBal >= _fare ? '💚' : '💳',
              style: const TextStyle(fontSize: 22),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Allin1 Wallet',
                style: TextStyle(
                  fontSize: 13,
                  color: _text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Balance: ₹${_walletBal.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 11,
                  color: _walletBal >= _fare ? _green : _muted,
                ),
              ),
            ],
          ),
        ),
        if (_walletBal >= _fare)
          GestureDetector(
            onTap: _payingWallet ? null : _payWithWallet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _green,
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  _payingWallet
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                      : Text(
                        'Send via Wallet',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
            ),
          )
        else
          Text(
            'Low balance',
            style: GoogleFonts.outfit(fontSize: 10, color: _red),
          ),
      ],
    ),
  );

  Widget _buildUpiSection() {
    final localization = context.read<LocalizationService>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localization.t('pay_via_soundbox'),
          style: GoogleFonts.outfit(
            fontSize: 14,
            color: _text,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          localization.t('open_upi_scan_soundbox'),
          style: GoogleFonts.outfit(
            fontSize: 12,
            color: _muted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _launchUpi,
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF2F8), Color(0xFFFFD5E9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x12FF4FA3),
                  blurRadius: 18,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: _gold,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localization.t('pay_via_soundbox'),
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          color: _text,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Exact bill amount: ₹${_fare.toStringAsFixed(2)}',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: _muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: _muted,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _successAnim,
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: const Color(0xFFFCE7F3),
                shape: BoxShape.circle,
                border: Border.all(color: _border),
              ),
              child: const Icon(
                Icons.favorite_rounded,
                color: _gold,
                size: 42,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Thanks for riding with Allin1 Stay with us 🙂💥',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 24,
              color: _text,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$_summaryPaymentMethod confirmed · ₹${_fare.toStringAsFixed(2)}',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: _muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 26),
          Text(
            'Rate your ride',
            style: GoogleFonts.outfit(
              fontSize: 16,
              color: _gold,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(5, (index) {
              final star = index + 1;
              final selected = _selectedRating >= star;
              return IconButton(
                onPressed: () => _submitRatingAndReturn(star),
                icon: Icon(
                  selected ? Icons.star_rounded : Icons.star_border_rounded,
                  color: _gold,
                  size: 34,
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedRating == 0
                ? 'Tap a star and we will take you back to booking.'
                : 'Redirecting you back to booking...',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: _muted,
            ),
          ),
        ],
      ),
    ),
  );
}
