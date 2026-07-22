// ================================================================
// floating_companion.dart — DEPRECATED, kept only as a pointer.
//
// The FloatingCompanion widget (a bouncing on-screen mascot with an
// always-running AnimationController..repeat()) was confirmed dead: no
// file in lib/ imports it or builds it. The only near-match in the
// codebase is AiActivationService.showFloatingCompanion, which is an
// unrelated boolean flag and does not reference this widget.
//
// It's reduced to a no-op stub rather than left in place because the
// original carried a per-frame repeating animation, and dead code that
// still compiles can be revived by accident. Nothing to build here.
//
// If nothing imports FloatingCompanion, this file can be deleted
// outright in a future cleanup pass.
// ================================================================
import 'package:flutter/material.dart';

class FloatingCompanion extends StatelessWidget {
  final VoidCallback? onTap;

  const FloatingCompanion({super.key, this.onTap});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
