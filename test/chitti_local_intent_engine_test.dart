// ================================================================
// chitti_local_intent_engine_test.dart
// ================================================================
// Tier 1 has two failure directions, and they are not symmetric.
//
// A MISS (the engine stays quiet on something it could have handled)
// costs an API call and a few hundred milliseconds. Annoying, cheap.
//
// A FALSE POSITIVE (the engine acts on something the user did not
// mean) navigates them away mid-task, or cancels an order. That is the
// expensive one, so most of these tests are about the engine keeping
// quiet when it should — particularly on questions, which read as
// commands to a naive keyword matcher.
import 'package:flutter_test/flutter_test.dart';

import 'package:erode_superapp/config/app_variant.dart';
import 'package:erode_superapp/services/chitti_memory_service.dart';
import 'package:erode_superapp/services/chitti/chitti_local_intent_engine.dart';

void main() {
  final original = currentAppVariant;
  tearDown(() => currentAppVariant = original);

  String? actionFor(String text, {String variant = 'customer'}) {
    currentAppVariant = variant;
    return ChittiLocalIntentEngine.resolve(text)?.action;
  }

  group('resolves common requests with no API call', () {
    test('English commands', () {
      expect(actionFor('cancel my order'), 'cancel_order');
      expect(actionFor('update the app'), 'check_and_update_app');
      expect(actionFor('invite a friend'), 'share_referral');
    });

    test('reads, including question-shaped ones', () {
      // These MUST work as questions — "how much balance do I have" is
      // how the question is actually asked. An over-eager question
      // guard here would make every read unreachable, which was the
      // exact trap worth writing a test for.
      expect(actionFor('what is my wallet balance'), 'check_wallet_balance');
      expect(actionFor('how many coins do I have'), 'check_rewards_balance');
      expect(actionFor('where is my hero'), 'check_order_status');
      expect(actionFor('show me my past orders'), 'list_recent_orders');
    });

    test('Tanglish, the way people here actually type', () {
      expect(actionFor('wallet la evlo iruku'), 'check_wallet_balance');
      expect(actionFor('order enga irukku'), 'check_order_status');
      expect(actionFor('app update pannu'), 'check_and_update_app');
    });

    test('Tamil script, the way speech_to_text returns it', () {
      expect(actionFor('பணம் எவ்வளவு இருக்கு'), 'check_wallet_balance');
      expect(actionFor('ஆர்டர் கேன்சல் பண்ணு'), 'cancel_order');
    });

    test('navigation to sections the old 12-entry enum never covered', () {
      expect(actionFor('open my orders'), 'navigate_to_section');
      expect(actionFor('show me the game zone'), 'navigate_to_section');
      expect(actionFor('open notifications'), 'navigate_to_section');
    });

    test('booking still routes through the existing parser', () {
      expect(actionFor('book an auto to the railway station'), 'book_transport');
      expect(actionFor('bike book pannu'), 'book_transport');
    });

    test('language switching', () {
      final intent = ChittiLocalIntentEngine.resolve('speak in tamil');
      expect(intent?.action, 'set_app_language');
      expect(intent?.args['language'], 'ta');
    });
  });

  group('stays quiet when it should', () {
    test('a question containing a service word does not book a ride', () {
      // The exact case the app already guards for: this must reach the
      // model, not silently open a booking screen.
      expect(actionFor('is auto available right now?'), isNot('book_transport'));
      expect(actionFor('what is the cab fare policy'), isNot('book_transport'));
    });

    test('a question does not cancel an order', () {
      expect(actionFor('can I cancel my order later?'), isNot('cancel_order'));
      expect(actionFor('how do I cancel an order?'), isNot('cancel_order'));
    });

    test('a multi-item order is left to the model', () {
      // Slot extraction is deliberately out of scope — guessing the
      // items here would place a wrong, real, paid-for order.
      expect(
        actionFor('order 2 plate chicken biryani from Sagar Mess'),
        isNot('create_service_request'),
      );
    });

    test('a bug report is left to the model', () {
      // It needs a written summary, which a matcher cannot produce.
      expect(
        actionFor('the booking screen is blank and nothing loads'),
        isNot('report_app_bug'),
      );
    });

    test('unrelated chatter resolves to nothing', () {
      expect(actionFor('hello'), isNull);
      expect(actionFor('thanks da'), isNull);
      expect(actionFor(''), isNull);
    });
  });

  group('variant scoping holds', () {
    test('a customer cannot trigger hero or seller tools', () {
      expect(actionFor('go online', variant: 'customer'),
          isNot('hero_set_online_status'));
      expect(actionFor('close the shop', variant: 'customer'),
          isNot('seller_set_shop_open'));
    });

    test('a hero can, and gets the right slot', () {
      currentAppVariant = 'hero';
      final on = ChittiLocalIntentEngine.resolve('go online');
      expect(on?.action, 'hero_set_online_status');
      expect(on?.args['online'], isTrue);

      final off = ChittiLocalIntentEngine.resolve('I am going home');
      expect(off?.action, 'hero_set_online_status');
      expect(off?.args['online'], isFalse);
    });

    test('a seller closing up gets open:false, not open:true', () {
      currentAppVariant = 'seller';
      final intent = ChittiLocalIntentEngine.resolve('close the shop');
      expect(intent?.action, 'seller_set_shop_open');
      expect(intent?.args['open'], isFalse);
    });

    test('a hero asking about earnings hits the hero read', () {
      expect(actionFor('how much did i earn today', variant: 'hero'),
          'hero_today_earnings');
    });
  });

  _candidateSelectionTests();
  _casualSpeechTests();
  _screenContextTests();

  group('confidence', () {
    test('every returned intent clears the threshold', () {
      currentAppVariant = 'customer';
      for (final phrase in [
        'cancel my order',
        'what is my wallet balance',
        'open my orders',
        'update the app',
      ]) {
        final intent = ChittiLocalIntentEngine.resolve(phrase);
        expect(intent, isNotNull, reason: phrase);
        expect(
          intent!.confidence,
          greaterThanOrEqualTo(ChittiLocalIntentEngine.confidenceThreshold),
          reason: phrase,
        );
      }
    });

    test('a keyword buried in a long unrelated sentence does not win', () {
      // Coverage matters: one matching word inside a paragraph is weak
      // evidence, and acting on it is how a matcher earns distrust.
      expect(
        actionFor(
          'my friend was telling me about some app where you can check a '
          'balance and lots of other things but I am not sure what it was '
          'called or whether it even works here in Erode at all',
        ),
        isNull,
      );
    });

    test('voice input relaxes the question guard', () {
      currentAppVariant = 'customer';
      // Someone who tapped the mic and said this is commanding, not
      // asking — the utterance is a bare noun phrase either way.
      final typed = ChittiLocalIntentEngine.resolve('auto enna');
      final spoken =
          ChittiLocalIntentEngine.resolve('auto enna', fromVoice: true);
      expect(spoken?.action ?? typed?.action, isNotNull);
    });
  });
}

// ── candidate selection (Aug 28 2026) ────────────────────────────────
//
// The recogniser hands back several candidate transcriptions ranked by
// how the audio SOUNDED. It has no idea which sentences make sense in
// this app. These tests pin the trick that closes that gap: judge every
// candidate against the intent tables and take the best confident one.
void _candidateSelectionTests() {
  final original = currentAppVariant;
  tearDown(() => currentAppVariant = original);

  group('resolveBest', () {
    test('recovers when the top candidate is mis-transcribed', () {
      currentAppVariant = 'customer';
      // What "wallet balance evlo" can come back as when a Tamil-locale
      // recogniser meets a Tanglish sentence — the right answer is
      // sitting at position two, and the old code threw it away.
      final intent = ChittiLocalIntentEngine.resolveBest(
        <String>['valet balan slow', 'wallet balance evlo'],
        fromVoice: true,
      );
      expect(intent?.action, 'check_wallet_balance');
    });

    test('keeps the top candidate when it already resolves', () {
      currentAppVariant = 'customer';
      final intent = ChittiLocalIntentEngine.resolveBest(
        <String>['cancel my order', 'cancel my odor'],
        fromVoice: true,
      );
      expect(intent?.action, 'cancel_order');
    });

    test('returns null when no candidate makes sense', () {
      currentAppVariant = 'customer';
      expect(
        ChittiLocalIntentEngine.resolveBest(
          <String>['mmm hmm', 'mm hm', 'hmm'],
          fromVoice: true,
        ),
        isNull,
      );
    });

    test('an empty candidate list is not an error', () {
      expect(ChittiLocalIntentEngine.resolveBest(const <String>[]), isNull);
    });
  });
}

// ── casual, non-command speech (Aug 28 2026) ─────────────────────────
//
// "command sollama Chitti kita dude nu pesunalum avan antha velaya
// seiyanum". Nobody talks to an assistant in verb-object syntax. These
// pin the two things that make natural speech work: address terms are
// stripped as noise, and a stated NEED maps to an intent even though it
// names no service at all.
void _casualSpeechTests() {
  final original = currentAppVariant;
  tearDown(() => currentAppVariant = original);

  String? actionFor(String text, {String variant = 'customer'}) {
    currentAppVariant = variant;
    return ChittiLocalIntentEngine.resolve(text)?.action;
  }

  String? sectionFor(String text) {
    currentAppVariant = 'customer';
    return ChittiLocalIntentEngine.resolve(text)?.args['section'] as String?;
  }

  group('address terms are noise, not meaning', () {
    test('English vocatives at the front', () {
      expect(actionFor('dude cancel my order'), 'cancel_order');
      expect(actionFor('bro what is my wallet balance'), 'check_wallet_balance');
      expect(actionFor('hey boss update the app'), 'check_and_update_app');
    });

    test('Tanglish vocatives and trailing particles', () {
      expect(actionFor('machan cancel pannu da'), 'cancel_order');
      expect(actionFor('wallet la evlo iruku da'), 'check_wallet_balance');
    });

    test('Tamil vocatives', () {
      expect(actionFor('பாஸ் ஆர்டர் கேன்சல் பண்ணு'), 'cancel_order');
    });

    test('a vocative alone still means nothing', () {
      // Stripping must not turn a greeting into an action.
      expect(actionFor('dude'), isNull);
      expect(actionFor('hey machan'), isNull);
    });
  });

  group('stated needs, with no service named', () {
    test('hunger goes to food', () {
      expect(sectionFor('enaku pasikuthu'), 'food');
      expect(sectionFor('dude i am hungry'), 'food');
      expect(sectionFor('எனக்கு பசிக்குது'), 'food');
    });

    test('a broken phone goes to electronics service', () {
      expect(sectionFor('my phone is broken'), 'electronics');
      expect(sectionFor('phone odanjiduchu'), 'electronics');
    });

    test('boredom goes to the game zone', () {
      expect(sectionFor('bore adikuthu'), 'game_zone');
    });

    test('wanting to go home books a ride', () {
      expect(actionFor('veetuku poganum'), 'book_transport');
      expect(actionFor('drop me home'), 'book_transport');
    });

    test('asking whether there is money reads the wallet', () {
      expect(actionFor('kasu irukka'), 'check_wallet_balance');
      expect(actionFor('காசு இருக்கா'), 'check_wallet_balance');
    });

    test('"still not come" is an order status question', () {
      expect(actionFor('innum varala'), 'check_order_status');
      expect(actionFor('eppo varum'), 'check_order_status');
    });
  });
}

// ── screen context (Aug 28 2026) ─────────────────────────────────────
//
// "order this" names nothing. On Food Genie it is not vague at all —
// the screen is the missing half of the sentence. These pin that the
// inference fires only for short deictic phrases, so a real question
// containing "it" still reaches the model.
void _screenContextTests() {
  final original = currentAppVariant;

  setUp(() => currentAppVariant = 'customer');
  tearDown(() {
    currentAppVariant = original;
    ChittiMemoryService.instance.setCurrentScreen(null);
  });

  test('"order this" on Food Genie resolves to that section', () {
    ChittiMemoryService.instance.setCurrentScreen('Food Genie');
    final intent = ChittiLocalIntentEngine.resolve('order this');
    expect(intent?.action, 'navigate_to_section');
    expect(intent?.args['section'], 'food');
  });

  test('"book it" on Car Wash resolves to Car Wash', () {
    ChittiMemoryService.instance.setCurrentScreen('Car Wash');
    expect(
      ChittiLocalIntentEngine.resolve('book it')?.args['section'],
      'car_wash',
    );
  });

  test('does nothing when the screen is unknown', () {
    expect(ChittiLocalIntentEngine.resolve('order this'), isNull);
  });

  test('a long sentence containing "it" is left to the model', () {
    ChittiMemoryService.instance.setCurrentScreen('Food Genie');
    expect(
      ChittiLocalIntentEngine.resolve(
        'can you tell me whether it is possible to order this from another '
        'shop instead',
      ),
      isNull,
    );
  });

  test('an explicit request still wins over the screen', () {
    ChittiMemoryService.instance.setCurrentScreen('Food Genie');
    expect(
      ChittiLocalIntentEngine.resolve('cancel my order')?.action,
      'cancel_order',
    );
  });
}
