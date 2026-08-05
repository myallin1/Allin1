// ================================================================
// QaVisionService — Phase 1.5 vision-analysis step for the Synthetic
// QA Test-Bot.
// ================================================================
// NEW (CTO mandate — Phase 1.5). Takes a screenshot the QA bot already
// captured in integration_test/qa_five_screens_test.dart and asks the
// SAME Groq vision model the rest of this app's AI features already
// use (meta-llama/llama-4-scout-17b-16e-instruct, see
// admin_kyc_vision_service.dart / guru_api_service.dart) whether
// anything looks visually broken — overlapping text, cut-off buttons,
// blank/empty states that shouldn't be empty, obviously misaligned
// layout, etc.
//
// Deliberately a standalone file rather than reusing
// AdminKycVisionService: that file's job is KYC document/face
// comparison specifically; this one's job is general screenshot
// QA, and keeping them separate means neither has to grow unrelated
// responsibilities. The Groq HTTP call pattern is intentionally
// mirrored (same endpoint, same model, same JSON-only response
// contract) rather than copy-pasted in a way that fights DRY, since
// admin_kyc_vision_service.dart's `_askVision` helper is private
// (`_`-prefixed) and not exported — extracting a shared helper into
// its own file was judged out of scope for this additive patch and
// left as a future cleanup rather than risking a change to a file
// that already has explicit "never remove/break this" boundaries
// around it (the KYC decision logic).
//
// Zero writes — this file only ever returns text. The caller
// (qa_five_screens_test.dart) decides what to do with it (append to
// findingText). Never called from anywhere in the live customer or
// admin write paths.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

class QaVisionService {
  QaVisionService._();

  static const String _endpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const String _visionModel = 'meta-llama/llama-4-scout-17b-16e-instruct';

  /// Returns null when the screenshot looks fine, or a short
  /// human-readable description of the visual problem when it doesn't.
  /// Never throws — any failure (missing key, network error, bad
  /// model response) degrades to a null-with-debugPrint so a vision
  /// hiccup never fails the underlying widget-tree assertion it rides
  /// alongside in the test.
  static Future<String?> analyzeScreenshot({
    required String apiKey,
    required Uint8List screenshotBytes,
    required String screenName,
  }) async {
    if (apiKey.trim().isEmpty) {
      debugPrint('[QaVisionService] no API key configured — skipping vision check for $screenName.');
      return null;
    }
    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
            body: jsonEncode({
              'model': _visionModel,
              'messages': [
                {
                  'role': 'user',
                  'content': [
                    {
                      'type': 'text',
                      'text':
                          'This is an automated screenshot of the "$screenName" screen in a '
                          'Flutter mobile app, taken by a QA test bot. Look for clear visual '
                          'bugs only: overlapping or cut-off text, buttons/icons rendered '
                          'off-screen or on top of each other, obviously broken layout, a '
                          'blank/empty area where content should clearly be, or a visible '
                          'error message on screen. Do NOT comment on color choices, general '
                          'design taste, or anything that is a subjective style opinion — '
                          'only genuine bugs. Respond with ONLY strict JSON, no other text: '
                          '{"hasIssue": true or false, "description": "<short one-sentence '
                          'description of the bug, empty string if hasIssue is false>"}.',
                    },
                    {
                      'type': 'image_url',
                      'image_url': {'url': 'data:image/png;base64,${base64Encode(screenshotBytes)}'},
                    },
                  ],
                },
              ],
              'temperature': 0,
              'max_tokens': 150,
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[QaVisionService] Groq vision request failed (${response.statusCode}) for $screenName.');
        return null;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = body['choices'] as List<dynamic>? ?? const [];
      if (choices.isEmpty) return null;
      final msg = (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
      final raw = (msg?['content'] as String?)?.trim() ?? '';
      final cleaned = raw.replaceAll(RegExp(r'```json|```'), '').trim();
      final parsed = jsonDecode(cleaned) as Map<String, dynamic>?;
      final hasIssue = parsed?['hasIssue'] as bool? ?? false;
      final description = (parsed?['description'] as String?)?.trim() ?? '';
      if (!hasIssue || description.isEmpty) return null;
      return 'Vision check: $description';
    } catch (e) {
      debugPrint('[QaVisionService] vision analysis failed for $screenName: $e');
      return null;
    }
  }
}
