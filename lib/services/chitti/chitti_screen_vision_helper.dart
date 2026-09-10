// ================================================================
// chitti_screen_vision_helper.dart — lets Chitti actually LOOK at the
// current screen when it cannot resolve a question from words alone.
// ================================================================
// NEW (Sep 10 2026 — Nizam: "chitti ku current screen la yenna
// nadakuthunu theriyanum gemini vision model moolama gemini pathutu
// action yedukanum ... Chitti confuse agumbothu").
//
// WHY THIS IS SEPARATE FROM analyze_screen_with_vision
// That tool (guru_chat_screen.dart's _actOnVisionHandoffAction) is
// hardcoded to ONE job: recognizing grocery products from a photo the
// CUSTOMER manually attaches. It never looks at the app's own UI, and
// nothing captures a screenshot automatically. This file is the
// missing piece: an on-demand, programmatic capture of whatever is
// currently on screen, paired with a general "answer this question
// about what you see" Gemini vision call (GeminiApiService.
// describeScreen) — admin-only, and ONLY reached when Chitti's normal
// resolution (local intent engine, then a model tool-call attempt)
// already came up empty. See guru_overlay_service.dart's sendMessage
// for the exact trigger point.
//
// WHY IT IS GATED, NOT ON EVERY MESSAGE
// Every call here is a real, billed Gemini vision request. Calling it
// on every message would multiply API cost for no benefit on the
// large majority of turns that already resolve cleanly through
// existing tools — the same token-budget discipline
// chitti_tool_registry.dart's domain router already documents.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../gemini_api_service.dart';

class ChittiScreenVisionHelper {
  ChittiScreenVisionHelper._();

  /// Wraps the admin app's content in main_admin.dart. A screen that
  /// never mounted this (a dialog painted on a separate overlay
  /// route, say) simply produces no capture — see [captureScreen]'s
  /// null-safe contract below.
  static final GlobalKey screenCaptureKey = GlobalKey();

  /// Captures whatever is currently painted under [screenCaptureKey]
  /// as JPEG bytes. Returns null rather than throwing — a failed
  /// capture must fall back to Chitti's normal reply, never crash the
  /// chat turn that triggered it.
  ///
  /// pixelRatio is deliberately capped at 1.5 (not the device's real
  /// ratio, often 2.5-3x on modern phones): Gemini's vision model
  /// reads UI text and layout just as well at this size, and every
  /// extra pixel is upload bandwidth and tokens neither the answer
  /// nor the admin's data plan need to pay for.
  static Future<Uint8List?> captureScreen() async {
    try {
      final context = screenCaptureKey.currentContext;
      if (context == null) return null;
      final boundary = context.findRenderObject();
      if (boundary is! RenderRepaintBoundary) return null;
      // A boundary mid-layout (the frame that just changed screens)
      // has no paint to capture yet — wait one frame rather than
      // capturing a blank/stale image.
      if (boundary.debugNeedsPaint) {
        await WidgetsBinding.instance.endOfFrame;
      }
      final image = await boundary.toImage(pixelRatio: 1.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[ChittiScreenVision] capture failed: $e');
      return null;
    }
  }

  /// Captures the current screen and asks Gemini vision to answer
  /// [question] about it. Returns null on any failure (no key
  /// configured, capture failed, API call failed) so the caller can
  /// fall through to Chitti's existing plain-text reply unchanged.
  static Future<String?> describeCurrentScreen({
    required String question,
    bool isTamil = false,
  }) async {
    final apiKey = await GeminiApiService().resolveApiKey();
    if (apiKey.trim().isEmpty) return null;

    final bytes = await captureScreen();
    if (bytes == null) return null;

    return GeminiApiService().describeScreen(
      imageBytes: bytes,
      question: question,
      apiKey: apiKey,
      isTamil: isTamil,
    );
  }
}
