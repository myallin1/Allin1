// ================================================================
// chitti_video_service_test.dart
// ================================================================
// Chitti can attach a video to a reply. The risk is not that it fails
// to find one — it is that it attaches one to an unrelated answer.
// Clutter in a chat bubble is worse than clutter in a carousel,
// because the customer came here to get something done.
//
// So these mostly pin the restraint.
import 'package:flutter_test/flutter_test.dart';

import 'package:erode_superapp/services/chitti/chitti_video_service.dart';

void main() {
  setUp(() {
    ChittiVideoService.seedForTesting(const <ChittiVideo>[
      ChittiVideo(
        videoId: 'aaaaaaaaaaa',
        shop: 'Sagar Mess',
        offer: 'Chicken biryani combo offer',
        category: 'Food',
      ),
      ChittiVideo(
        videoId: 'bbbbbbbbbbb',
        shop: 'NJ Tech',
        offer: 'Mobile display replacement in 30 minutes',
        category: 'Electronics',
      ),
    ]);
  });

  tearDown(ChittiVideoService.resetForTesting);

  group('finds a genuinely relevant clip', () {
    test('matches on the shop name', () {
      expect(
        ChittiVideoService.findFor('what is sagar mess biryani')?.videoId,
        'aaaaaaaaaaa',
      );
    });

    test('matches on the offer text', () {
      expect(
        ChittiVideoService.findFor('mobile display replacement')?.videoId,
        'bbbbbbbbbbb',
      );
    });

    test('a section key alone is enough', () {
      expect(
        ChittiVideoService.findFor('', sectionKey: 'Electronics')?.videoId,
        'bbbbbbbbbbb',
      );
    });
  });

  group('restraint', () {
    test('one incidental word is NOT enough', () {
      // "offer" appears in the ad text, but a question about offers in
      // general does not mean this particular shop's clip belongs
      // under the answer.
      expect(ChittiVideoService.findFor('offer'), isNull);
    });

    test('an unrelated question gets no video', () {
      expect(ChittiVideoService.findFor('cancel my order'), isNull);
      expect(ChittiVideoService.findFor('what is my wallet balance'), isNull);
    });

    test('short words are ignored so they cannot carry a match', () {
      expect(ChittiVideoService.findFor('is it in the'), isNull);
    });

    test('an empty catalogue is not an error', () {
      ChittiVideoService.seedForTesting(const <ChittiVideo>[]);
      expect(ChittiVideoService.findFor('sagar mess biryani'), isNull);
    });

    test('nothing is returned before the cache is loaded', () {
      ChittiVideoService.resetForTesting();
      expect(ChittiVideoService.findFor('sagar mess'), isNull);
    });
  });
}
