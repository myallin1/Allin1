// ================================================================
// AdminKycVisionService — OCR document-number matching + facial
// comparison for the Admin AI Co-Pilot's KYC reports.
// ================================================================
// NEW (CTO mandate — Advanced KYC & Facial Verification). Routes both
// checks through the SAME Groq vision model the customer app already
// uses for screenshot troubleshooting (guru_api_service.dart's
// `_visionModel`, meta-llama/llama-4-scout-17b-16e-instruct) —
// deliberately not introducing a second vision provider/model just for
// this, and reusing a model already proven to work against this app's
// Groq account.
//
// IMPORTANT — read before trusting this output as a final decision:
//   - This is a general-purpose vision-LANGUAGE model doing OCR and a
//     face-similarity judgment via a text prompt. It is NOT a
//     certified biometric/face-recognition system, has no liveness
//     detection, and can be wrong — confidently. Treat every result
//     here as an input to human review, never as a standalone
//     approval/rejection authority. That is also why every method in
//     admin_quick_task_service.dart that consumes this output still
//     requires the CTO's own explicit Yes/No before any real write
//     happens — this file only ever informs that decision, never makes
//     it.
//   - Facial comparison additionally has real privacy/compliance
//     weight (biometric data processing, e.g. under India's DPDP Act)
//     that is a policy decision, not a purely technical one — flagged
//     here for visibility, not resolved by this code.
//   - Zero writes anywhere in this file — it only downloads public doc
//     photo URLs (the same ones already rendered in the approval
//     screens today) and calls Groq's chat/completions endpoint.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

class KycVisionResult {
  const KycVisionResult({
    required this.notes,
    required this.strictRecommendation,
    this.numberMatches,
    this.faceMatches,
  });
  final List<String> notes;
  // CTO mandate #4 — exact strict decision line, one of exactly two
  // fixed strings by design (not freeform model output) so the chatbox
  // message is predictable regardless of what the model says elsewhere.
  final String strictRecommendation;
  final bool? numberMatches;
  final bool? faceMatches;
}

class AdminKycVisionService {
  AdminKycVisionService._();

  static const String _endpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const String _visionModel = 'meta-llama/llama-4-scout-17b-16e-instruct';

  /// Cross-checks every doc number that has BOTH a typed value and a
  /// photo (Aadhaar/PAN/License, whichever are present), then — if a
  /// selfie is on file — compares the selfie's face against the first
  /// available doc photo. Degrades cleanly at every step: missing
  /// selfie, missing doc photo, or an API failure all become a plain
  /// note in the report rather than a crash or a silent skip.
  static Future<KycVisionResult> crossCheck({
    required String apiKey,
    String? aadhaarNumber,
    String? aadhaarDocUrl,
    String? panNumber,
    String? panDocUrl,
    String? licenseNumber,
    String? licenseDocUrl,
    String? selfieUrl,
  }) async {
    final notes = <String>[];
    final numberResults = <bool>[];

    if (apiKey.trim().isEmpty) {
      notes.add('Vision cross-check skipped — no Groq API key configured for the Admin AI.');
      return KycVisionResult(
        notes: notes,
        strictRecommendation: 'Mismatch detected in KYC. Manual CTO verification required.',
      );
    }

    final docs = <({String label, String? number, String? url})>[
      (label: 'Aadhaar', number: aadhaarNumber, url: aadhaarDocUrl),
      (label: 'PAN', number: panNumber, url: panDocUrl),
      (label: 'License', number: licenseNumber, url: licenseDocUrl),
    ];

    String? primaryDocUrl;
    for (final doc in docs) {
      final number = doc.number?.trim() ?? '';
      final url = doc.url?.trim() ?? '';
      if (number.isEmpty) continue; // nothing typed for this doc type
      if (url.isEmpty) {
        notes.add('${doc.label} document photo is missing — cannot OCR-verify the typed number.');
        continue;
      }
      primaryDocUrl ??= url;
      try {
        final bytes = await _downloadImage(url);
        if (bytes == null) {
          notes.add('${doc.label} document photo could not be downloaded for OCR.');
          continue;
        }
        final raw = await _askVision(
          apiKey: apiKey,
          images: [bytes],
          prompt: 'This is a photo of an Indian ${doc.label} document. Read the '
              'printed ID number exactly as shown, ignoring any other numbers on '
              'the card. Respond with ONLY strict JSON, no other text: '
              '{"number": "<the ID number you read, empty string if unreadable>", '
              '"readable": true or false}.',
        );
        final parsed = _tryParseJson(raw);
        final extracted = (parsed?['number'] as String?)?.trim() ?? '';
        final readable = parsed?['readable'] as bool? ?? false;
        if (!readable || extracted.isEmpty) {
          notes.add('${doc.label} document photo was too unclear for the AI to read a number.');
          continue;
        }
        final normalizedExtracted = extracted.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
        final normalizedTyped = number.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
        final matches = normalizedExtracted.isNotEmpty && normalizedExtracted == normalizedTyped;
        numberResults.add(matches);
        notes.add(matches
            ? '${doc.label} number MATCHES: typed "$number" vs. document reads "$extracted".'
            : '${doc.label} number MISMATCH: typed "$number" vs. document reads "$extracted".');
      } catch (e) {
        notes.add('${doc.label} OCR check failed: $e');
        debugPrint('[AdminKycVisionService] OCR failed for ${doc.label}: $e');
      }
    }

    bool? faceMatches;
    final selfie = selfieUrl?.trim() ?? '';
    if (selfie.isEmpty) {
      notes.add('No live selfie on file — facial comparison skipped (manual identity '
          'verification required).');
    } else if (primaryDocUrl == null) {
      notes.add('No ID document photo available to compare the selfie against.');
    } else {
      try {
        final docBytes = await _downloadImage(primaryDocUrl);
        final selfieBytes = await _downloadImage(selfie);
        if (docBytes == null || selfieBytes == null) {
          notes.add('Could not download the ID photo and/or selfie for facial comparison.');
        } else {
          final raw = await _askVision(
            apiKey: apiKey,
            images: [docBytes, selfieBytes],
            prompt: 'The FIRST image is a photo from an ID document. The SECOND '
                'image is a live selfie. Compare the face shown in both images. '
                'Respond with ONLY strict JSON, no other text: {"sameFace": true or '
                'false, "confidence": "high" or "medium" or "low"}.',
          );
          final parsed = _tryParseJson(raw);
          faceMatches = parsed?['sameFace'] as bool?;
          final confidence = parsed?['confidence'] as String? ?? 'unknown';
          notes.add(faceMatches == true
              ? 'Facial comparison: appears to be the SAME person (confidence: $confidence).'
              : faceMatches == false
                  ? 'Facial comparison: face does NOT appear to match (confidence: $confidence).'
                  : 'Facial comparison was inconclusive.');
        }
      } catch (e) {
        notes.add('Facial comparison failed: $e');
        debugPrint('[AdminKycVisionService] face compare failed: $e');
      }
    }

    notes.add('Note: AI-assisted OCR/face comparison, not a certified biometric system — '
        'a flag for human review, not a final identity determination.');

    // CTO mandate #4, applied literally: ALL numbers checked must
    // match AND the face must match for the confident-approval line;
    // any missing/failed/mismatched signal falls to the manual-review
    // line, including when there simply wasn't enough data to check
    // (e.g. no selfie yet) — "needs review" is the safe default, never
    // "approve" by omission.
    final allNumbersOk = numberResults.isNotEmpty && numberResults.every((m) => m);
    final strict = (allNumbersOk && faceMatches == true)
        ? 'All proofs and face match perfectly. Recommended for Approval.'
        : 'Mismatch detected in KYC. Manual CTO verification required.';

    return KycVisionResult(
      notes: notes,
      strictRecommendation: strict,
      numberMatches: numberResults.isEmpty ? null : allNumbersOk,
      faceMatches: faceMatches,
    );
  }

  static Future<Uint8List?> _downloadImage(String url) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      return res.bodyBytes;
    } catch (e) {
      debugPrint('[AdminKycVisionService] image download failed: $e');
      return null;
    }
  }

  static Future<String> _askVision({
    required String apiKey,
    required List<Uint8List> images,
    required String prompt,
  }) async {
    final content = <Map<String, dynamic>>[
      {'type': 'text', 'text': prompt},
      for (final bytes in images)
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/jpeg;base64,${base64Encode(bytes)}'},
        },
    ];
    final response = await http
        .post(
          Uri.parse(_endpoint),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
          body: jsonEncode({
            'model': _visionModel,
            'messages': [
              {'role': 'user', 'content': content},
            ],
            'temperature': 0,
            'max_tokens': 200,
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Groq vision request failed: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = body['choices'] as List<dynamic>? ?? const [];
    if (choices.isEmpty) throw Exception('empty response from Groq vision');
    final msg = (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
    return (msg?['content'] as String?)?.trim() ?? '';
  }

  static Map<String, dynamic>? _tryParseJson(String raw) {
    try {
      final cleaned = raw.replaceAll(RegExp(r'```json|```'), '').trim();
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
