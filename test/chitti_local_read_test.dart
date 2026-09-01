// ================================================================
// chitti_local_read_test.dart
// ================================================================
// Nizam's WhatsApp model has one rule that costs real money if it
// slips: read from the phone, not from the database. The wallet is the
// single exception, because it is money and must stay
// server-authoritative — "wallet la change nadantha than database ah
// read pannanum".
//
// The query paths need Firestore itself and are covered by the app;
// what is pinned here is the wallet's dirty-flag state machine, which
// is where a mistake is silent: a stale balance that looks
// authoritative, or a server read on every glance.
import 'package:flutter_test/flutter_test.dart';

import 'package:erode_superapp/services/chitti/chitti_local_read.dart';

void main() {
  setUp(ChittiLocalRead.resetForTesting);

  group('wallet freshness', () {
    test('the first read of a session goes to the server', () {
      // A balance can have moved on another device since the app was
      // last open, and there is no cheap way to know — so the session
      // starts dirty rather than trusting a cold cache.
      expect(ChittiLocalRead.walletNeedsServerRead, isTrue);
    });

    test('spending or crediting marks it dirty again', () {
      ChittiLocalRead.markWalletChanged();
      expect(ChittiLocalRead.walletNeedsServerRead, isTrue);
    });

    test('marking is idempotent', () {
      ChittiLocalRead.markWalletChanged();
      ChittiLocalRead.markWalletChanged();
      expect(ChittiLocalRead.walletNeedsServerRead, isTrue);
    });
  });
}
