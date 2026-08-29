// ================================================================
// video_warmup_service_test.dart
// ================================================================
// The warm player has two owners with independent lifetimes: the
// Rewards screen that warmed it, and whichever modal borrowed it —
// which may have been opened from Chitti on a different screen
// entirely. Every bug the Aug 28 re-audit found lived in that seam:
//
//   • leaving Rewards while the modal was open closed the player the
//     modal was still rendering;
//   • releasing a borrowed player after that closed it a SECOND time,
//     inside a State.dispose(), which is the worst place to throw.
//
// Those rules live in VideoWarmSlot, deliberately free of any player
// type — building a real YoutubePlayerController needs a platform
// WebView and cannot run in a unit test, which is precisely how these
// bugs got in. A String stands in for the player here; the rules are
// what is being tested.
import 'package:flutter_test/flutter_test.dart';

import 'package:erode_superapp/services/video_warmup_service.dart';

void main() {
  late List<String> closed;
  late VideoWarmSlot<String> slot;

  setUp(() {
    closed = <String>[];
    slot = VideoWarmSlot<String>(onClose: closed.add);
  });

  group('nothing warmed', () {
    test('take returns null', () => expect(slot.take('a'), isNull));

    test('dispose is safe and repeatable', () {
      slot..dispose()..dispose();
      expect(slot.item, isNull);
      expect(closed, isEmpty);
    });
  });

  group('warming', () {
    test('holds the item under its key', () {
      slot.fill('vid1', 'player');
      expect(slot.item, 'player');
      expect(slot.key, 'vid1');
    });

    test('re-pointing keeps the SAME item', () {
      // Building a second player to warm a different video is the
      // memory failure this whole service exists to avoid.
      slot..fill('vid1', 'player')..repoint('vid2');
      expect(slot.item, 'player');
      expect(slot.key, 'vid2');
      expect(closed, isEmpty);
    });
  });

  group('borrowing', () {
    setUp(() => slot.fill('vid1', 'player'));

    test('only hands over a matching key', () {
      expect(slot.take('other'), isNull);
      expect(slot.take('vid1'), 'player');
    });

    test('one borrower at a time', () {
      expect(slot.take('vid1'), 'player');
      // A second modal must build its own rather than share a player
      // about to be paused underneath it.
      expect(slot.take('vid1'), isNull);
    });

    test('releasing makes it borrowable again, and keeps it alive', () {
      final borrowed = slot.take('vid1')!;
      expect(slot.release(borrowed), isTrue, reason: 'caller should keep it');
      expect(closed, isEmpty);
      expect(slot.take('vid1'), 'player');
    });

    test('an item we never owned is closed by whoever returns it', () {
      expect(slot.release('someone elses player'), isFalse);
      expect(closed, <String>['someone elses player']);
    });
  });

  group('teardown while borrowed', () {
    setUp(() => slot.fill('vid1', 'player'));

    test('dispose does NOT close a player a modal is still rendering', () {
      final borrowed = slot.take('vid1')!;
      slot.dispose();
      expect(closed, isEmpty, reason: 'the modal is still using it');
      expect(slot.item, borrowed);
    });

    test('the deferred teardown runs when the modal hands back', () {
      final borrowed = slot.take('vid1')!;
      slot.dispose();
      expect(slot.release(borrowed), isFalse);
      expect(closed, <String>['player']);
      expect(slot.item, isNull);
    });

    test('releasing again does not close twice', () {
      // The exact double-close found in the re-audit: it would have
      // thrown from inside a State.dispose().
      final borrowed = slot.take('vid1')!;
      slot..dispose()..release(borrowed);
      expect(() => slot.release(borrowed), returnsNormally);
      expect(closed, hasLength(1));
    });

    test('dispose after a deferred teardown does not close twice', () {
      final borrowed = slot.take('vid1')!;
      slot..dispose()..release(borrowed)..dispose();
      expect(closed, hasLength(1));
    });
  });
}
