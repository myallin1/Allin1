import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

const Color _quizPink = Color(0xFFFF4FA3);
const Color _paytmBlue = Color(0xFF00B9F1);
const Color _quizWhite = Color(0xFFFFFFFF);
const Color _quizText = Color(0xFF09324A);

class _QuizQuestion {
  const _QuizQuestion({
    required this.question,
    required this.options,
    required this.answerIndex,
  });

  final String question;
  final List<String> options;
  final int answerIndex;
}

const List<_QuizQuestion> _quizQuestions = [
  _QuizQuestion(
    question: 'Who is the founder of Paytm?',
    options: [
      'Vijay Shekhar Sharma',
      'N. R. Narayana Murthy',
      'Sundar Pichai',
      'Azim Premji',
    ],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'Which Paytm device speaks payment confirmations in shops?',
    options: [
      'Paytm Soundbox',
      'Paytm Scooter',
      'Paytm Printer',
      'Paytm Camera',
    ],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'Which river is closely associated with Erode district?',
    options: ['Kaveri', 'Yamuna', 'Narmada', 'Ganga'],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'What is Erode popularly known for in Tamil Nadu?',
    options: [
      'Turmeric and textiles',
      'Snowfall',
      'Tea gardens only',
      'Ship building',
    ],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'Which Allin1 partner helps with mobile and laptop service?',
    options: ['NJ Tech', 'Moon Bakery', 'City Stadium', 'River Port'],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'What should you listen for in the NJ Tech audio clue?',
    options: [
      'The ringtone keyword',
      'A train number',
      'A cricket score',
      'A movie title',
    ],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'Which Paytm feature helps merchants confirm received money?',
    options: [
      'Instant payment alert',
      'Weather report',
      'Music playlist',
      'Photo editor',
    ],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'Which city is the Allin1 Super App focused on first?',
    options: ['Erode', 'Delhi', 'Mumbai', 'Kolkata'],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'What color is strongly linked with the Allin1 NJ Tech brand?',
    options: ['Pink', 'Brown', 'Grey', 'Black only'],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'Which Paytm product is useful for shop counter voice alerts?',
    options: ['Soundbox', 'Keyboard', 'Smart TV', 'Helmet'],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'Erode is located in which Indian state?',
    options: ['Tamil Nadu', 'Kerala', 'Punjab', 'Assam'],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'What does a ringtone/audio clue task ask users to identify?',
    options: [
      'A sound clue',
      'A bus ticket',
      'A receipt number',
      'A map route',
    ],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'Which payment brand is featured in this Mega Quiz theme?',
    options: ['Paytm', 'Only Cash', 'ChequeBook', 'Postal Order'],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'Which Erode product has a famous market identity?',
    options: ['Turmeric', 'Apples', 'Saffron from Kashmir', 'Sea pearls'],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'What does NJ Tech mainly support in the app ecosystem?',
    options: [
      'Tech service and support',
      'Airline pilots',
      'Ocean shipping',
      'Mining only',
    ],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'Which Paytm color is used in the quiz theme?',
    options: ['Blue', 'Brown', 'Maroon', 'Olive'],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'What is the local trust phrase behind the Super App idea?',
    options: [
      'All in one for Erode',
      'Only outside cities',
      'No local service',
      'No support',
    ],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'Which clue type may be played as part of daily NJ Tech tasks?',
    options: [
      'Ringtone/audio clue',
      'Stone carving clue',
      'Paper boat clue',
      'Traffic fine clue',
    ],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'What is the main use of a Paytm QR at a shop?',
    options: [
      'Accept digital payments',
      'Unlock a bicycle',
      'Print newspapers',
      'Measure distance',
    ],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'Which district identity is connected to Erode?',
    options: [
      'Textile markets',
      'Snow mountains',
      'Sea port docks',
      'Desert safari',
    ],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'What should users do after finding an audio clue?',
    options: [
      'Answer the quiz task',
      'Delete the app',
      'Ignore the clue',
      'Call a random number',
    ],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'Which Paytm product can announce “payment received”?',
    options: ['Paytm Soundbox', 'Paytm Chair', 'Paytm Mirror', 'Paytm Fan'],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'Which city name appears in the Mega Quiz local questions?',
    options: ['Erode', 'London', 'Tokyo', 'Paris'],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'What does NJ Tech help customers repair?',
    options: [
      'Mobile and laptop devices',
      'Ships',
      'Aeroplanes',
      'Rail tracks',
    ],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'What type of answer should users pick in the daily quiz?',
    options: [
      'One correct option',
      'All random options',
      'No answer',
      'Only emojis',
    ],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question:
        'Which Paytm feature helps small businesses reduce payment confusion?',
    options: [
      'Voice confirmation',
      'Movie streaming',
      'Bus horn',
      'Torch light',
    ],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'Which Tamil Nadu city is famous as “Turmeric City”?',
    options: ['Erode', 'Ooty', 'Rameswaram', 'Kanyakumari'],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'What is the app’s premium assistant called?',
    options: ['Guru AI', 'Silent Bot', 'Metro AI', 'River AI'],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'Which clue is most likely part of the NJ Tech ringtone game?',
    options: [
      'A short audio keyword',
      'A passport stamp',
      'A train platform',
      'A fuel bill',
    ],
    answerIndex: 0,
  ),
  _QuizQuestion(
    question: 'What is the goal of completing the 30-day Mega Quiz?',
    options: [
      'Win rewards up to ₹1500',
      'Lose points',
      'Close account',
      'Skip all services',
    ],
    answerIndex: 0,
  ),
];

class MegaQuizScreen extends StatefulWidget {
  const MegaQuizScreen({super.key});

  @override
  State<MegaQuizScreen> createState() => _MegaQuizScreenState();
}

class _MegaQuizScreenState extends State<MegaQuizScreen> {
  final _formKey = GlobalKey<FormState>();
  final _aadhaarController = TextEditingController();
  bool _isSubmitting = false;
  bool _isVerified = false;
  String? _errorMessage;

  @override
  void dispose() {
    _aadhaarController.dispose();
    super.dispose();
  }

  String _hashAadhaar(String aadhaar) {
    return sha256.convert(utf8.encode(aadhaar.trim())).toString();
  }

  Future<void> _submitAadhaar() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _errorMessage = 'Please login before joining the contest.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final db = FirebaseFirestore.instance;
    final aadhaarHash = _hashAadhaar(_aadhaarController.text);
    final participantRef = db.collection('quiz_participants').doc(aadhaarHash);

    try {
      final duplicate = await db
          .collection('quiz_participants')
          .where('aadhaarHash', isEqualTo: aadhaarHash)
          .limit(1)
          .get();

      if (duplicate.docs.isNotEmpty) {
        setState(() {
          _errorMessage = 'This ID has already been used for the contest.';
        });
        return;
      }

      await db.runTransaction((transaction) async {
        final existing = await transaction.get(participantRef);
        if (existing.exists) {
          throw StateError('aadhaar-already-used');
        }
        transaction.set(participantRef, {
          'aadhaarHash': aadhaarHash,
          'campaign': '30_day_mega_quiz_1500',
          'userId': user.uid,
          'userPhone': user.phoneNumber,
          'currentDay': 1,
          'completedDays': <int>[],
          'rawAadhaarStored': false,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) {
        return;
      }
      setState(() {
        _isVerified = true;
        _aadhaarController.clear();
      });
    } on StateError {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'This ID has already been used for the contest.';
      });
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message ?? 'Unable to join the contest now.';
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Mega Quiz',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _paytmBlue,
              _quizWhite,
              _quizPink,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: _isVerified ? _buildThirtyDayGrid() : _buildAadhaarForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildAadhaarForm() {
    return SingleChildScrollView(
      key: const ValueKey('aadhaar-form'),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HeroBanner(),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 32,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Secure Aadhaar Verification',
                    style: GoogleFonts.outfit(
                      color: _quizText,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'We hash your Aadhaar with SHA-256. Raw Aadhaar is never stored.',
                    style: GoogleFonts.outfit(
                      color: _quizText.withValues(alpha: 0.62),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _aadhaarController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(12),
                    ],
                    decoration: InputDecoration(
                      labelText: '12-digit Aadhaar Number',
                      prefixIcon: const Icon(
                        Icons.verified_user_rounded,
                        color: _quizPink,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFFFF5FA),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: _quizPink.withValues(alpha: 0.18),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(
                          color: _quizPink,
                          width: 1.5,
                        ),
                      ),
                    ),
                    validator: (value) {
                      final aadhaar = value?.trim() ?? '';
                      if (!RegExp(r'^\d{12}$').hasMatch(aadhaar)) {
                        return 'Enter a valid 12-digit Aadhaar number.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '*T&C Apply',
                    style: GoogleFonts.outfit(
                      color: _quizText.withValues(alpha: 0.48),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.outfit(
                          color: const Color(0xFFC62828),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitAadhaar,
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                      ),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_quizPink, _paytmBlue],
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Center(
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Unlock Day 1',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThirtyDayGrid() {
    final tasks = [
      'Erode trivia: Where did Allin1 begin?',
      "Ringtone task: Spot today's NJ Tech sound clue.",
      'PayTM trivia: What does Soundbox announce after payment?',
    ];

    return SingleChildScrollView(
      key: const ValueKey('thirty-day-grid'),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HeroBanner(
            subtitle: 'Day 1 unlocked. Complete every day to chase ₹1500.',
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.lock_open_rounded,
                      color: _quizPink,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Day 1 Challenge',
                      style: GoogleFonts.outfit(
                        color: _quizText,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                for (final task in tasks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: _paytmBlue,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            task,
                            style: GoogleFonts.outfit(
                              color: _quizText.withValues(alpha: 0.76),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 30,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.95,
            ),
            itemBuilder: (context, index) {
              final day = index + 1;
              final unlocked = day == 1;
              return _DayTile(
                day: day,
                unlocked: unlocked,
                onTap: unlocked ? () => _openDayQuestion(day) : null,
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openDayQuestion(int day) async {
    final question = _quizQuestions[day - 1];
    int? selectedIndex;
    var recorded = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _quizWhite,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: _paytmBlue.withValues(alpha: 0.28),
                    width: 1.4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _quizPink.withValues(alpha: 0.22),
                      blurRadius: 30,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: recorded
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 70,
                            height: 70,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [_quizPink, _paytmBlue],
                              ),
                            ),
                            child: const Icon(
                              Icons.verified_rounded,
                              color: _quizWhite,
                              size: 38,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Answer Recorded!',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              color: _quizText,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Day $day progress saved for the Mega Quiz.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              color: _quizText.withValues(alpha: 0.68),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _paytmBlue,
                                foregroundColor: _quizWhite,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text('Done'),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: _paytmBlue.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Day $day Question',
                                  style: GoogleFonts.outfit(
                                    color: _paytmBlue,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: _quizText,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            question.question,
                            style: GoogleFonts.outfit(
                              color: _quizText,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 14),
                          for (int i = 0; i < question.options.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: InkWell(
                                onTap: () =>
                                    setSheetState(() => selectedIndex = i),
                                borderRadius: BorderRadius.circular(16),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: selectedIndex == i
                                        ? _quizPink.withValues(alpha: 0.12)
                                        : _paytmBlue.withValues(alpha: 0.07),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: selectedIndex == i
                                          ? _quizPink
                                          : _paytmBlue.withValues(alpha: 0.24),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        selectedIndex == i
                                            ? Icons.radio_button_checked_rounded
                                            : Icons.radio_button_off_rounded,
                                        color: selectedIndex == i
                                            ? _quizPink
                                            : _paytmBlue,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          question.options[i],
                                          style: GoogleFonts.outfit(
                                            color: _quizText,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: selectedIndex == null
                                  ? null
                                  : () => setSheetState(() => recorded = true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _quizPink,
                                disabledBackgroundColor:
                                    _quizPink.withValues(alpha: 0.30),
                                foregroundColor: _quizWhite,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Text(
                                'Submit',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            );
          },
        );
      },
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    this.subtitle = 'Verify once. Play 30 days. Win premium Allin1 rewards.',
  });

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.20),
            Colors.white.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _paytmBlue.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _quizWhite.withValues(alpha: 0.5)),
            ),
            child: Text(
              '30-Day Mega Quiz',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Win up to ₹1500',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 34,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: GoogleFonts.outfit(
              color: Colors.white.withValues(alpha: 0.86),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('subtitle', subtitle));
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.day,
    required this.unlocked,
    this.onTap,
  });

  final int day;
  final bool unlocked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: unlocked
              ? const LinearGradient(
                  colors: [_quizPink, _paytmBlue, _quizWhite],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : LinearGradient(
                  colors: [
                    _quizWhite.withValues(alpha: 0.24),
                    _paytmBlue.withValues(alpha: 0.12),
                  ],
                ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: unlocked
                ? _quizWhite.withValues(alpha: 0.76)
                : _quizWhite.withValues(alpha: 0.22),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              unlocked ? Icons.play_circle_fill_rounded : Icons.lock_rounded,
              color: unlocked ? _quizText : _quizWhite,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              'Day $day',
              style: GoogleFonts.outfit(
                color: unlocked ? _quizText : _quizWhite,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              unlocked ? 'Tap to Play' : 'Locked',
              style: GoogleFonts.outfit(
                color: unlocked
                    ? _quizText.withValues(alpha: 0.78)
                    : _quizWhite.withValues(alpha: 0.78),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(IntProperty('day', day));
    properties.add(DiagnosticsProperty<bool>('unlocked', unlocked));
    properties.add(ObjectFlagProperty<VoidCallback?>.has('onTap', onTap));
  }
}
