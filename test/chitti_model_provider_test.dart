// ================================================================
// chitti_model_provider_test.dart
// ================================================================
// The in-chat model picker (chitti_model_picker_sheet.dart) trusts two
// things completely: that resolveChittiModel never hands back a model
// with no usable key, and that setChittiModelId/getChittiModelId round-
// trip through the exact same prefs key guru_api_service.dart's
// _resolveBackend reads on every real request. A bug in either would
// look, from the admin's chair, exactly like tapping a model in the
// picker and having Chitti silently keep using the old one.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:erode_superapp/services/chitti/chitti_model_provider.dart';

void main() {
  group('chittiModelById', () {
    test('finds a model by its exact id', () {
      expect(chittiModelById('gemini').id, 'gemini');
    });

    test('falls back to the default for an unknown id', () {
      expect(chittiModelById('not-a-real-model').id, defaultChittiModel.id);
    });

    test('falls back to the default for null', () {
      expect(chittiModelById(null).id, defaultChittiModel.id);
    });
  });

  group('chittiModelSupportsVision', () {
    test('true for a model with a vision model configured', () {
      expect(chittiModelSupportsVision(chittiModelById('groq')), isTrue);
    });

    test('false for DeepSeek, which is text-only', () {
      expect(chittiModelSupportsVision(chittiModelById('deepseek')), isFalse);
    });
  });

  group('resolveChittiModel', () {
    test('returns the preferred model when it has a key', () {
      final resolved = resolveChittiModel(
        preferredId: 'gemini',
        keyFor: (m) => m.id == 'gemini' ? 'a-real-key' : '',
      );
      expect(resolved?.id, 'gemini');
    });

    test('degrades to another configured model when the preferred one '
        'has no key', () {
      final resolved = resolveChittiModel(
        preferredId: 'groq',
        keyFor: (m) => m.id == 'deepseek' ? 'a-real-key' : '',
      );
      expect(resolved?.id, 'deepseek');
    });

    test('returns null when nothing has a key at all — the one case '
        'the caller must report rather than paper over', () {
      final resolved = resolveChittiModel(
        preferredId: 'groq',
        keyFor: (_) => '',
      );
      expect(resolved, isNull);
    });

    test('a vision request skips a configured model that cannot see '
        'images', () {
      final resolved = resolveChittiModel(
        preferredId: 'deepseek',
        // Both configured, but DeepSeek is text-only.
        keyFor: (_) => 'a-real-key',
        needsVision: true,
      );
      expect(resolved?.id, isNot('deepseek'));
      expect(chittiModelSupportsVision(resolved!), isTrue);
    });

    test('a vision request with only a text-only model configured '
        'returns null rather than a model that would 400 on the image',
        () {
      final resolved = resolveChittiModel(
        preferredId: 'deepseek',
        keyFor: (m) => m.id == 'deepseek' ? 'a-real-key' : '',
        needsVision: true,
      );
      expect(resolved, isNull);
    });
  });

  group('setChittiModelId / getChittiModelId', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('round-trips through kChittiModelPrefsKey', () async {
      expect(await getChittiModelId(), isNull);

      await setChittiModelId('anthropic');
      expect(await getChittiModelId(), 'anthropic');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kChittiModelPrefsKey), 'anthropic');
    });

    test('a later call overwrites an earlier choice', () async {
      await setChittiModelId('groq');
      await setChittiModelId('gemini');
      expect(await getChittiModelId(), 'gemini');
    });
  });
}
