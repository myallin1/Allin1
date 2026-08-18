import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color _kPink = Color(0xFFFF4FA3);

class AiLoadingDialog extends StatefulWidget {
  const AiLoadingDialog({super.key});

  /// Helper to show the dialog
  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (_) => const AiLoadingDialog(),
    );
  }

  /// Helper to hide the dialog
  static void hide(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  State<AiLoadingDialog> createState() => _AiLoadingDialogState();
}

class _AiLoadingDialogState extends State<AiLoadingDialog> with SingleTickerProviderStateMixin {
  int _step = 0;
  Timer? _timer;
  late final AnimationController _pulseController;

  static const List<String> _texts = [
    'wait',
    'AI processing for u',
    'Almost finish'
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    // Step through the texts exactly once, without looping.
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_step < _texts.length - 1) {
        if (mounted) setState(() => _step++);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A mini popup screen with a white theme, pink text, and thunder loading animation.
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Center(
          child: Container(
          width: 220,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 20,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 0.9 + (_pulseController.value * 0.2),
                    child: child,
                  );
                },
                child: const Icon(Icons.bolt_rounded, color: _kPink, size: 48),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _texts[_step],
                  key: ValueKey<int>(_step),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: _kPink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}
