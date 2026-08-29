// ================================================================
// chitti_admin_assistant_test.dart
// ================================================================
// NEW (Aug 28 2026 — Nizam: admin Chitti as an end-to-end P.A., three
// models the admin can pick between, and Tamil screen guidance on
// demand).
import 'package:flutter_test/flutter_test.dart';
import 'package:erode_superapp/services/chitti/chitti_model_provider.dart';
import 'package:erode_superapp/services/chitti/chitti_screen_guide.dart';
import 'package:erode_superapp/services/chitti/chitti_tool_registry.dart';
import 'package:erode_superapp/services/tamil_transliteration.dart';

void main() {
  group('the model picker', () {
    test('all three backends Nizam has keys for are present', () {
      final ids = kChittiModels.map((m) => m.id).toSet();
      expect(ids, containsAll(<String>['groq', 'gemini', 'deepseek']));
    });

    test('an unknown id falls back rather than throwing', () {
      // A saved preference can outlive the model it names — a renamed
      // or removed backend must not brick the assistant on next launch.
      expect(chittiModelById('a_model_we_removed'), defaultChittiModel);
      expect(chittiModelById(null), defaultChittiModel);
    });

    test('DeepSeek is honest about not seeing images', () {
      // Declared rather than pointed at a model that would 400 on an
      // image, so callers can route that one request elsewhere.
      final ds = chittiModelById('deepseek');
      expect(chittiModelSupportsVision(ds), isFalse);
    });

    test('Groq and Gemini can see images', () {
      expect(chittiModelSupportsVision(chittiModelById('groq')), isTrue);
      expect(chittiModelSupportsVision(chittiModelById('gemini')), isTrue);
    });

    test('model ids are unique and stable-looking', () {
      final ids = kChittiModels.map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('resolving which backend to use', () {
    String only(String id) => id == 'gemini' ? 'KEY' : '';

    test('the chosen model wins when it has a key', () {
      final m = resolveChittiModel(
        preferredId: 'gemini',
        keyFor: (x) => only(x.id),
      );
      expect(m?.id, 'gemini');
    });

    test('a chosen model with NO key degrades instead of dying', () {
      // An admin mid-shift whose DeepSeek key was revoked must not be
      // left with a dead assistant.
      final m = resolveChittiModel(
        preferredId: 'deepseek',
        keyFor: (x) => only(x.id),
      );
      expect(m?.id, 'gemini');
    });

    test('no keys at all is reported, not papered over', () {
      final m = resolveChittiModel(
        preferredId: 'groq',
        keyFor: (_) => '',
      );
      expect(m, isNull);
    });

    test('a screenshot skips a text-only backend', () {
      final m = resolveChittiModel(
        preferredId: 'deepseek',
        keyFor: (_) => 'KEY',
        needsVision: true,
      );
      expect(m, isNotNull);
      expect(chittiModelSupportsVision(m!), isTrue);
    });

    test('a screenshot with only a text-only key returns null', () {
      final m = resolveChittiModel(
        preferredId: 'deepseek',
        keyFor: (x) => x.id == 'deepseek' ? 'KEY' : '',
        needsVision: true,
      );
      expect(m, isNull);
    });
  });

  group('screen guidance', () {
    test('the tool exists in every build', () {
      final tool =
          kChittiTools.firstWhere((t) => t.name == 'explain_this_screen');
      expect(
        tool.variants,
        containsAll(<String>['customer', 'hero', 'seller', 'admin']),
      );
    });

    test('it needs no confirmation — it changes nothing', () {
      expect(
        ChittiToolRegistry.requiresConfirmation('explain_this_screen'),
        isFalse,
      );
    });

    test('the admin screens an owner works in have written Tamil', () {
      for (final key in <String>[
        'admin_dashboard',
        'admin_new_orders',
        'admin_hero_approvals',
        'admin_seller_approvals',
        'chitti_enquiries',
      ]) {
        expect(ChittiScreenGuide.hasWrittenLine(key), isTrue, reason: key);
      }
    });

    test('every written line really is Tamil', () {
      for (final key in ChittiScreenGuide.writtenSections) {
        final g = ChittiScreenGuide.forSection(key, 'ta');
        expect(TamilTransliteration.hasTamil(g.shown), isTrue, reason: key);
      }
    });

    test('an unknown screen still gets a useful sentence', () {
      // Silence from the app's own assistant is worse than a plain
      // answer, so this must never come back empty.
      for (final lang in ['en', 'ta', 'tg']) {
        final g = ChittiScreenGuide.forSection('not_a_screen', lang);
        expect(g.shown.trim(), isNotEmpty, reason: lang);
        expect(g.spoken.trim(), isNotEmpty, reason: lang);
      }
    });

    test('Thanglish is READ in Latin but SPOKEN in Tamil', () {
      final g = ChittiScreenGuide.forSection('admin_dashboard', 'tg');
      expect(TamilTransliteration.hasTamil(g.shown), isFalse, reason: g.shown);
      expect(TamilTransliteration.hasTamil(g.spoken), isTrue);
    });

    test('Tamil and English read and speak the same', () {
      for (final lang in ['ta', 'en']) {
        final g = ChittiScreenGuide.forSection('admin_dashboard', lang);
        expect(g.shown, g.spoken, reason: lang);
      }
    });

    test('English guidance carries no Tamil script', () {
      for (final key in ChittiScreenGuide.writtenSections) {
        expect(
          TamilTransliteration.hasTamil(
            ChittiScreenGuide.forSection(key, 'en').shown,
          ),
          isFalse,
          reason: key,
        );
      }
    });
  });

  group('mapping the current screen back to a section', () {
    test('a known label resolves', () {
      expect(
        ChittiScreenGuide.currentSectionKey('Customer Enquiries', 'admin'),
        'chitti_enquiries',
      );
    });

    test('matching is case-insensitive', () {
      expect(
        ChittiScreenGuide.currentSectionKey('customer enquiries', 'admin'),
        'chitti_enquiries',
      );
    });

    test('an unknown label resolves to null, not to the wrong screen', () {
      // The dangerous failure is confidently explaining a DIFFERENT
      // page, which a substring match would do.
      expect(
        ChittiScreenGuide.currentSectionKey('Some Random Page', 'admin'),
        isNull,
      );
      expect(ChittiScreenGuide.currentSectionKey(null, 'admin'), isNull);
      expect(ChittiScreenGuide.currentSectionKey('  ', 'admin'), isNull);
    });
  });
}
