// ================================================================
// chitti_conversation_controller_test.dart
// ================================================================
// The hands-free loop has one catastrophic failure mode and one
// annoying one, and neither is visible by reading the code.
//
// CATASTROPHIC: barge-in means the mic is open while Chitti speaks, so
// on a phone speaker the mic hears the TTS. Unguarded, Chitti answers
// itself in a loop that never ends and burns the API quota doing it.
//
// ANNOYING: a mic that never closes. Battery, privacy, and a customer
// who put the phone in their pocket ten minutes ago.
//
// Everything here is about pinning those two.
import 'package:flutter_test/flutter_test.dart';

import 'package:erode_superapp/services/chitti/chitti_conversation_controller.dart';

void main() {
  late ChittiConversationController c;

  setUp(() {
    c = ChittiConversationController()..start();
  });

  group('echo guard', () {
    test('discards Chitti hearing its own sentence back', () {
      c.markSpeaking('Opening your wallet now, boss.');
      expect(c.isSelfEcho('opening your wallet now boss'), isTrue);
      // Partial pickup is the realistic case — the mic catches the
      // middle of the sentence, not all of it.
      expect(c.isSelfEcho('your wallet now'), isTrue);
    });

    test('lets a real interruption through', () {
      c.markSpeaking('Opening your wallet now, boss.');
      expect(c.isSelfEcho('no stop'), isFalse);
      expect(c.isSelfEcho('cancel my order'), isFalse);
      expect(c.isSelfEcho('book an auto instead'), isFalse);
    });

    test('is inert when Chitti is not speaking', () {
      // A customer repeating a phrase later must never be swallowed.
      c.markSpeaking('Opening your wallet now.');
      c.markSpokenDone();
      expect(c.isSelfEcho('opening your wallet now'), isFalse);
    });

    test('ignores short filler that overlaps by accident', () {
      c.markSpeaking('Your order is on the way.');
      // Words of 3 letters or fewer are not evidence either way.
      expect(c.isSelfEcho('is it'), isFalse);
    });
  });

  group('stop words', () {
    test('English, Tanglish and Tamil all end the loop', () {
      for (final word in [
        'stop',
        'enough',
        'podhum',
        'sari podhum',
        'போதும்',
        'நிறுத்து',
        'vendaam',
      ]) {
        final fresh = ChittiConversationController()..start();
        expect(
          fresh.onUserSaid(word, resolvedAnIntent: false, awaitingReply: false),
          ChittiConversationStep.stop,
          reason: word,
        );
        expect(fresh.isActive, isFalse, reason: word);
      }
    });

    test('a stop word wins even mid-question', () {
      expect(
        c.onUserSaid('stop', resolvedAnIntent: false, awaitingReply: true),
        ChittiConversationStep.stop,
      );
    });
  });

  group('auto-stop mode', () {
    test('ends after a completed task with nothing pending', () {
      expect(
        c.onUserSaid('cancel my order',
            resolvedAnIntent: true, awaitingReply: false),
        ChittiConversationStep.stop,
      );
    });

    test('keeps going while Chitti is waiting on an answer', () {
      // The one thing a hands-free assistant must never do is hang up
      // in the middle of its own question.
      expect(
        c.onUserSaid('book a ride',
            resolvedAnIntent: true, awaitingReply: true),
        ChittiConversationStep.speak,
      );
      expect(c.isActive, isTrue);
    });

    test('ends after two silent turns', () {
      expect(
        c.onUserSaid('', resolvedAnIntent: false, awaitingReply: false),
        ChittiConversationStep.listen,
      );
      expect(
        c.onUserSaid('', resolvedAnIntent: false, awaitingReply: false),
        ChittiConversationStep.stop,
      );
    });

    test('a real utterance resets the silence count', () {
      c.onUserSaid('', resolvedAnIntent: false, awaitingReply: false);
      c.onUserSaid('what is my balance',
          resolvedAnIntent: false, awaitingReply: false);
      expect(c.emptyTurns, 0);
      // One silent turn after that must not end it.
      expect(
        c.onUserSaid('', resolvedAnIntent: false, awaitingReply: false),
        ChittiConversationStep.listen,
      );
    });

    test('has a silence timeout', () {
      expect(c.idleTimeout, isNotNull);
    });
  });

  group('call mode', () {
    setUp(() {
      c = ChittiConversationController(mode: ChittiConversationMode.call)
        ..start();
    });

    test('stays connected after a completed task', () {
      expect(
        c.onUserSaid('cancel my order',
            resolvedAnIntent: true, awaitingReply: false),
        ChittiConversationStep.speak,
      );
      expect(c.isActive, isTrue);
    });

    test('does not hang up on silence', () {
      c.onUserSaid('', resolvedAnIntent: false, awaitingReply: false);
      expect(
        c.onUserSaid('', resolvedAnIntent: false, awaitingReply: false),
        ChittiConversationStep.listen,
      );
      expect(c.isActive, isTrue);
    });

    test('still obeys an explicit stop', () {
      expect(
        c.onUserSaid('podhum', resolvedAnIntent: false, awaitingReply: false),
        ChittiConversationStep.stop,
      );
    });

    test('has no silence timeout', () {
      expect(c.idleTimeout, isNull);
    });
  });

  group('lifecycle', () {
    test('nothing happens before start', () {
      final idle = ChittiConversationController();
      expect(idle.isActive, isFalse);
      expect(
        idle.onUserSaid('hello',
            resolvedAnIntent: false, awaitingReply: false),
        ChittiConversationStep.stop,
      );
    });

    test('afterSpeaking reopens the mic while active', () {
      c.markSpeaking('Sure, opening it.');
      expect(c.isSpeaking, isTrue);
      expect(c.afterSpeaking(), ChittiConversationStep.listen);
      expect(c.isSpeaking, isFalse);
    });

    test('afterSpeaking does not reopen the mic once stopped', () {
      c.markSpeaking('Okay, stopping.');
      c.stop();
      expect(c.afterSpeaking(), ChittiConversationStep.stop);
    });

    test('stop is idempotent', () {
      c.stop();
      c.stop();
      expect(c.isActive, isFalse);
    });
  });

  group('pending topic queue (mid-speech interruption memory)', () {
    test('queues background topic while speaking', () {
      c.markSpeaking('Checking your today earnings now, boss.');
      expect(c.hasPendingTopic, isFalse);

      c.queuePendingTopic('read my recent sms');
      expect(c.hasPendingTopic, isTrue);
      expect(c.pendingTopic?.text, 'read my recent sms');

      final popped = c.popPendingTopic();
      expect(popped?.text, 'read my recent sms');
      expect(c.hasPendingTopic, isFalse);
    });

    test('ignores stop words from being queued as pending topics', () {
      c.markSpeaking('Processing your order now.');
      c.queuePendingTopic('stop');
      expect(c.hasPendingTopic, isFalse);
      c.queuePendingTopic('podhum');
      expect(c.hasPendingTopic, isFalse);
    });

    test('auto-stop does not exit when pending topic is queued', () {
      c.queuePendingTopic('send sms to 9876543210');
      expect(c.hasPendingTopic, isTrue);

      final step = c.onUserSaid('check orders', resolvedAnIntent: true, awaitingReply: false);
      expect(step, ChittiConversationStep.speak);
      expect(c.isActive, isTrue);
    });

    test('stop clears pending topic', () {
      c.queuePendingTopic('check open bugs');
      expect(c.hasPendingTopic, isTrue);
      c.stop();
      expect(c.hasPendingTopic, isFalse);
      expect(c.pendingTopic, isNull);
    });
  });
}
