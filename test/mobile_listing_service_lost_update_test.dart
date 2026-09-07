// ================================================================
// Regression test — MobileListingService.updateListing() lost-update
// race fix (Sep 6 2026 audit).
// ================================================================
// Verifies, against a real (fake, in-memory) Firestore transaction
// engine rather than just re-reading the code:
//   1. A normal edit (no one else touched the listing since it loaded)
//      still succeeds exactly as before.
//   2. A STALE edit (someone else saved a newer version since this
//      editor session loaded the listing) is now REJECTED with a
//      StateError, instead of silently overwriting the newer save.
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:erode_superapp/models/mobile_models.dart';
import 'package:erode_superapp/services/mobile_listing_service.dart';

void main() {
  const sellerId = 'seller1';
  const listingId = 'listing1';

  MobileListing baseListing({DateTime? updatedAt, double price = 10000}) =>
      MobileListing(
        id: listingId,
        sellerId: sellerId,
        sellerName: 'Test Shop',
        condition: MobileCondition.isNew,
        brand: 'TestBrand',
        model: 'TestModel',
        price: price,
        updatedAt: updatedAt,
      );

  test('a fresh (non-stale) edit succeeds and persists the new price',
      () async {
    final firestore = FakeFirebaseFirestore();
    final docRef = firestore
        .collection('sellers')
        .doc(sellerId)
        .collection('mobile_listings')
        .doc(listingId);

    await docRef.set({
      ...baseListing().toJson(),
      'updatedAt': Timestamp.now(),
    });
    final loadedSnap = await docRef.get();
    final loadedUpdatedAt =
        (loadedSnap.data()!['updatedAt'] as Timestamp).toDate();

    final service = MobileListingService(firestore: firestore);
    final edited = baseListing(updatedAt: loadedUpdatedAt, price: 12000);

    await service.updateListing(edited);

    final after = await docRef.get();
    expect(after.data()!['price'], 12000);
  });

  test(
      'a STALE edit (someone else saved a newer version since this '
      'editor loaded) is rejected instead of silently overwriting it',
      () async {
    final firestore = FakeFirebaseFirestore();
    final docRef = firestore
        .collection('sellers')
        .doc(sellerId)
        .collection('mobile_listings')
        .doc(listingId);

    // Editor session A loads the listing at T1.
    final t1 = DateTime.now().subtract(const Duration(minutes: 5));
    await docRef.set({
      ...baseListing().toJson(),
      'updatedAt': Timestamp.fromDate(t1),
    });
    final sessionAUpdatedAt = t1;

    // Meanwhile, editor session B (a second device/tab) saves first,
    // bumping updatedAt to a newer time T2 and changing the price.
    final t2 = DateTime.now();
    await docRef.update({
      'price': 15000,
      'updatedAt': Timestamp.fromDate(t2),
    });

    // Now session A finally saves, unaware of B's change — its
    // in-memory `listing.updatedAt` is still the STALE T1.
    final service = MobileListingService(firestore: firestore);
    final staleEdit =
        baseListing(updatedAt: sessionAUpdatedAt, price: 11000);

    await expectLater(
      () => service.updateListing(staleEdit),
      throwsA(isA<StateError>()),
    );

    // Confirm session B's save was NOT clobbered by session A's stale
    // write — the price is still B's 15000, not A's 11000.
    final after = await docRef.get();
    expect(after.data()!['price'], 15000);
  });

  test('editing a listing that no longer exists throws a clear StateError',
      () async {
    final firestore = FakeFirebaseFirestore();
    final service = MobileListingService(firestore: firestore);
    final edit = baseListing(updatedAt: DateTime.now());

    await expectLater(
      () => service.updateListing(edit),
      throwsA(isA<StateError>()),
    );
  });
}
