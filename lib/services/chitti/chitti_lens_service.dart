// ================================================================
// chitti_lens_service.dart — "point the camera at something and let
// Chitti tell you what it is", the way Google Lens does.
// ================================================================
// NEW (Sep 4 2026 — Nizam: "chittiku camara on pannuna udanede athu
// net la google lens open aguramari namma app kulla vachcharlam athula
// chitti kandupichuruvan athukullaye cm details varum atha vachu
// solliruvan").
//
// WHY GOOGLE CLOUD VISION AND NOT THE VISION MODEL THIS APP ALREADY HAS
//   admin_kyc_vision_service.dart already talks to a Groq
//   vision-language model, and reusing it would have avoided a second
//   provider. It cannot do this job: a VLM describes what it SEES
//   ("a man in a white shirt at a podium") and, by policy, generally
//   refuses to name real people. Naming a public figure from a photo
//   is not a description problem, it is a SEARCH problem — you need
//   something that matches the image against the indexed web. That is
//   exactly what Cloud Vision's WEB_DETECTION does, and it is the same
//   machinery behind Google Lens itself.
//
// HONESTY ABOUT WHAT COMES BACK
//   WEB_DETECTION returns a "best guess label" plus ranked web
//   entities with scores. For a well-known public figure this is
//   usually right. For a private person it correctly returns nothing
//   useful. It is a GUESS either way — [LensResult.confidence] is
//   surfaced so the UI can say "looks like…" instead of asserting, and
//   the screen shows the result to the admin BEFORE Chitti says
//   anything out loud. Getting a name wrong quietly on screen is a
//   shrug; getting it wrong out loud in front of the person is not.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// What the lens made of one photo.
@immutable
class LensResult {
  const LensResult({
    required this.bestGuess,
    required this.entities,
    required this.pageTitles,
    this.error,
  });

  /// Cloud Vision's own one-line "what this image is of" guess.
  final String bestGuess;

  /// Ranked entity descriptions, strongest first. For a photo of a
  /// public figure the first entry is usually their name.
  final List<LensEntity> entities;

  /// Titles of web pages containing this image — useful context for
  /// Chitti to say something specific rather than just a name.
  final List<String> pageTitles;

  final String? error;

  bool get hasError => error != null;

  /// True when there is genuinely nothing to say — an unknown face, a
  /// blurry frame, a blank wall.
  bool get isEmpty =>
      bestGuess.trim().isEmpty && entities.isEmpty && pageTitles.isEmpty;

  /// The single best label to show/speak, or empty when unknown.
  String get topLabel {
    if (entities.isNotEmpty) return entities.first.description;
    return bestGuess.trim();
  }

  /// 0.0-1.0 for the top entity. Cloud Vision's scores are not
  /// calibrated probabilities, so this is for ordering and for
  /// hedging the wording — never present it as an accuracy figure.
  double get confidence => entities.isEmpty ? 0 : entities.first.score;
}

@immutable
class LensEntity {
  const LensEntity({required this.description, required this.score});
  final String description;
  final double score;
}

class ChittiLensService {
  ChittiLensService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// Kept in secure storage rather than SharedPreferences: this is a
  /// billable Google Cloud key, closer to ChittiDevTaskService's GitHub
  /// token than to the plain model-name preferences in Admin AI
  /// Settings.
  static const String _keyName = 'chitti_vision_api_key';

  static Future<void> saveApiKey(String key) =>
      _storage.write(key: _keyName, value: key.trim());

  static Future<String?> readApiKey() => _storage.read(key: _keyName);

  static Future<bool> hasApiKey() async {
    final k = await readApiKey();
    return k != null && k.trim().isNotEmpty;
  }

  static const String _endpoint =
      'https://vision.googleapis.com/v1/images:annotate';

  /// Sends [imageBytes] for web detection. Never throws — every
  /// failure comes back as a [LensResult] carrying [LensResult.error],
  /// because this is called from a camera screen where an exception
  /// mid-capture would just look like the app freezing.
  static Future<LensResult> identify(Uint8List imageBytes) async {
    final apiKey = await readApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      return const LensResult(
        bestGuess: '',
        entities: [],
        pageTitles: [],
        error: 'No Vision API key saved yet — add it in Chitti Lens settings.',
      );
    }

    try {
      final res = await http
          .post(
            Uri.parse('$_endpoint?key=${apiKey.trim()}'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'requests': [
                {
                  'image': {'content': base64Encode(imageBytes)},
                  'features': [
                    {'type': 'WEB_DETECTION', 'maxResults': 8},
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) {
        // Surface Google's own message — "API not enabled" and "key
        // restricted" are the two most likely first-run failures and
        // both are fixable by the admin in a minute, but only if they
        // can see which one it is.
        String detail = 'HTTP ${res.statusCode}';
        try {
          final err = jsonDecode(res.body) as Map<String, dynamic>;
          final m = (err['error'] as Map<String, dynamic>?)?['message'];
          if (m is String && m.trim().isNotEmpty) detail = m.trim();
        } catch (_) {}
        return LensResult(
          bestGuess: '',
          entities: const [],
          pageTitles: const [],
          error: detail,
        );
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final responses = body['responses'] as List<dynamic>? ?? const [];
      if (responses.isEmpty) {
        return const LensResult(bestGuess: '', entities: [], pageTitles: []);
      }
      final web = (responses.first as Map<String, dynamic>)['webDetection']
          as Map<String, dynamic>?;
      if (web == null) {
        return const LensResult(bestGuess: '', entities: [], pageTitles: []);
      }

      final bestGuess = ((web['bestGuessLabels'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>()
              .map((e) => (e['label'] as String?) ?? '')
              .firstWhere((s) => s.trim().isNotEmpty, orElse: () => ''))
          .trim();

      final entities = <LensEntity>[];
      for (final e in (web['webEntities'] as List<dynamic>? ?? const [])) {
        final m = e as Map<String, dynamic>;
        final d = ((m['description'] as String?) ?? '').trim();
        if (d.isEmpty) continue;
        entities.add(LensEntity(
          description: d,
          score: (m['score'] as num?)?.toDouble() ?? 0,
        ));
      }
      entities.sort((a, b) => b.score.compareTo(a.score));

      final titles = <String>[];
      for (final p in (web['pagesWithMatchingImages'] as List<dynamic>? ??
          const [])) {
        final m = p as Map<String, dynamic>;
        final t = ((m['pageTitle'] as String?) ?? '').trim();
        if (t.isNotEmpty) titles.add(t);
        if (titles.length >= 4) break;
      }

      return LensResult(
        bestGuess: bestGuess,
        entities: entities,
        pageTitles: titles,
      );
    } catch (e) {
      return LensResult(
        bestGuess: '',
        entities: const [],
        pageTitles: const [],
        error: '$e',
      );
    }
  }

  /// What Chitti should SAY about [result], in Tamil or English.
  ///
  /// Hedged on purpose ("மாதிரி தெரியுது" / "looks like") — see the
  /// header. A confident-sounding wrong name is the one outcome worth
  /// engineering against here.
  static String spokenLine(LensResult result, {String languageCode = 'ta'}) {
    final ta = languageCode == 'ta';
    if (result.hasError) {
      return ta
          ? 'மன்னிக்கணும் பாஸ், இப்போ இதை பாக்க முடியல.'
          : "Sorry boss, I couldn't look this up right now.";
    }
    if (result.isEmpty) {
      return ta
          ? 'பாஸ், இது யாருன்னு எனக்கு சரியா தெரியல.'
          : "Boss, I can't tell who or what this is.";
    }
    final label = result.topLabel;
    return ta
        ? '$label மாதிரி தெரியுது பாஸ்.'
        : 'This looks like $label, boss.';
  }

  /// A warm greeting for a recognised person — what Nizam actually
  /// wants at the meeting. Separate from [spokenLine] because greeting
  /// someone and identifying an object are different jobs, and only
  /// the admin should decide which one Chitti performs.
  static String greetingLine(String name, {String languageCode = 'ta'}) {
    final n = name.trim();
    if (n.isEmpty) {
      return languageCode == 'ta'
          ? 'வணக்கம் சார், உங்களை சந்திச்சதுல மகிழ்ச்சி!'
          : 'Greetings sir, a pleasure to meet you!';
    }
    return languageCode == 'ta'
        ? 'வணக்கம் $n சார்! உங்களை சந்திச்சதுல ரொம்ப மகிழ்ச்சி சார். '
            'வாழ்த்துக்கள் சார்!'
        : 'Greetings $n sir! It is a real pleasure to meet you. '
            'Congratulations sir!';
  }
}
