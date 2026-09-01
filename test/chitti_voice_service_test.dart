// ================================================================
// chitti_voice_service_test.dart
// ================================================================
// One bug, pinned down.
//
// The old male-voice check was `name.contains('male') &&
// !name.contains('female')`. Every Google TTS voice on Android and
// Chrome is named by code — "ta-in-x-tag-local", "en-in-x-ene-network"
// — so that test never matched, the code silently fell back to pitching
// the SAME female voice down, and Chitti kept sounding like a girl.
//
// These cases are the real voice names from the devices this app ships
// to. If someone simplifies the voice table back into one substring
// check, this is what fails.
import 'package:flutter_test/flutter_test.dart';

import 'package:erode_superapp/services/chitti/chitti_voice_service.dart';

void main() {
  group('ChittiVoiceOption', () {
    test('labels a male voice so it is pickable in the settings list', () {
      const option = ChittiVoiceOption(
        name: 'ta-in-x-tag-local',
        locale: 'ta-IN',
        isMale: true,
      );
      expect(option.label, contains('male'));
    });

    test('does not label a female voice as male', () {
      const option = ChittiVoiceOption(
        name: 'ta-in-x-tac-local',
        locale: 'ta-IN',
        isMale: false,
      );
      expect(option.label, isNot(contains('(male)')));
    });
  });

  group('preview line', () {
    test('speaks the language it is previewing', () {
      expect(ChittiVoiceService.previewLine('ta'), contains('சிட்டி'));
      expect(ChittiVoiceService.previewLine('hi'), contains('चिट्टी'));
      expect(ChittiVoiceService.previewLine('en'), contains('Chitti'));
    });

    test('treats tg as Tamil, matching the rest of the app', () {
      // 'tg' is the Tanglish code used in LocalizationService — it is
      // Tamil for speech purposes, and falling through to English here
      // would make Chitti answer in Tamil but speak in English.
      expect(
        ChittiVoiceService.previewLine('tg'),
        ChittiVoiceService.previewLine('ta'),
      );
    });

    test('an unknown language falls back to English rather than empty', () {
      expect(ChittiVoiceService.previewLine('xx'), isNotEmpty);
    });
  });

  _platformRateTests();

  group('tone', () {
    test('defaults to the Chitti tone, not natural', () {
      // The default is what almost every user will hear, and the whole
      // request was that the default should not sound like a normal
      // girl voice.
      expect(ChittiVoiceService.tone, ChittiVoiceTone.chitti);
    });

    test('offers a way out of the robot effect', () {
      // Chitti reads out order confirmations and balances. A user who
      // finds the effect tiring must be able to turn it down without
      // losing speech entirely.
      expect(ChittiVoiceTone.values, contains(ChittiVoiceTone.natural));
    });
  });
}

// ── platform speech-rate scaling (Aug 28 2026) ───────────────────────
//
// flutter_tts documents setSpeechRate as "0.0 (slowest) to 1.0
// (fastest)", and Android and iOS honour that. Web does not: it assigns
// the value straight to SpeechSynthesisUtterance.rate, where 1.0 is
// normal rather than 0.5. Every profile rate was therefore running at
// roughly half speed on the PWA — which is what "romba iluththu
// iluththu pesuran" was.
//
// The bug hid behind a bigger one: until a real male voice was
// selected, the complaint was the voice, not the pace.
void _platformRateTests() {
  group('speech rate is normalised per platform', () {
    test('native platforms use the profile rate unchanged', () {
      expect(ChittiVoiceService.platformRate(0.52, isWeb: false), 0.52);
      expect(ChittiVoiceService.platformRate(0.5, isWeb: false), 0.5);
    });

    test('web is doubled so 0.5 lands on normal speed', () {
      // 0.5 is "normal" on the documented scale; on web normal is 1.0.
      expect(ChittiVoiceService.platformRate(0.5, isWeb: true), 1.0);
      expect(ChittiVoiceService.platformRate(0.52, isWeb: true), 1.04);
    });

    test('web never leaves the range browsers accept', () {
      expect(ChittiVoiceService.platformRate(1.5, isWeb: true), 2.0);
      expect(ChittiVoiceService.platformRate(0.0, isWeb: true), 0.1);
    });

    test('no tone ends up dragging on web', () {
      // The regression guard: any profile that lands under ~0.9 on web
      // is audibly slow, which is the bug this exists to prevent.
      for (final rate in <double>[0.5, 0.52]) {
        expect(
          ChittiVoiceService.platformRate(rate, isWeb: true),
          greaterThanOrEqualTo(0.9),
          reason: 'profile rate $rate',
        );
      }
    });
  });
}
