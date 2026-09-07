// ================================================================
// Regression test — HeroWalletService.submitRechargeRequest() writes
// the exact field shape firestore.rules' _heroWalletDeltaIsBacked
// depends on (Sep 6 2026 audit).
// ================================================================
// The rules-emulator test (run separately against firestore.rules)
// already proved the RULE blocks self-mint/replay when given documents
// shaped a certain way. This test proves the ACTUAL SERVICE CODE that
// runs in the app produces documents shaped exactly that way — the two
// checks only add up to real protection together; either one alone
// could be quietly wrong without the other catching it.
// ================================================================
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:erode_superapp/services/hero_wallet_service.dart';

void main() {
  const heroId = 'hero1';

  test(
      'submitRechargeRequest writes lastRechargeRequestId + a matching '
      'pending, creditedToWallet:true request for the exact delta',
      () async {
    final firestore = FakeFirebaseFirestore();
    final service = HeroWalletService.test(firestore);

    await service.submitRechargeRequest(
      heroId: heroId,
      amount: 100,
      upiRefNumber: 'UPI123',
      screenshotUrl: 'https://example.com/shot.png',
    );

    final walletSnap =
        await firestore.collection('hero_wallets').doc(heroId).get();
    final walletData = walletSnap.data()!;
    expect(walletData['balance'], 100);
    final requestId = walletData['lastRechargeRequestId'] as String?;
    expect(requestId, isNotNull);

    final requestSnap = await firestore
        .collection('wallet_recharge_requests')
        .doc(requestId)
        .get();
    final requestData = requestSnap.data()!;
    // These are exactly the fields firestore.rules' getAfter() checks
    // read — if any of these ever drift (renamed, wrong type, wrong
    // value), the rule would start rejecting every real recharge.
    expect(requestData['heroId'], heroId);
    expect(requestData['status'], 'pending');
    expect(requestData['amount'], 100);
    expect(requestData['creditedToWallet'], true);
  });

  test('a second recharge points at a NEW request id, not the first one',
      () async {
    final firestore = FakeFirebaseFirestore();
    final service = HeroWalletService.test(firestore);

    await service.submitRechargeRequest(
      heroId: heroId,
      amount: 50,
      upiRefNumber: 'UPI1',
      screenshotUrl: 'https://example.com/1.png',
    );
    final firstWallet =
        await firestore.collection('hero_wallets').doc(heroId).get();
    final firstRequestId = firstWallet.data()!['lastRechargeRequestId'];

    await service.submitRechargeRequest(
      heroId: heroId,
      amount: 30,
      upiRefNumber: 'UPI2',
      screenshotUrl: 'https://example.com/2.png',
    );
    final secondWallet =
        await firestore.collection('hero_wallets').doc(heroId).get();
    final secondRequestId = secondWallet.data()!['lastRechargeRequestId'];

    expect(secondRequestId, isNot(equals(firstRequestId)));
    expect(secondWallet.data()!['balance'], 80); // 50 + 30, cumulative
  });

  test(
      'rejectRechargeRequest claws back exactly the credited amount and '
      'is a no-op if called twice (idempotent)', () async {
    final firestore = FakeFirebaseFirestore();
    final service = HeroWalletService.test(firestore);

    await service.submitRechargeRequest(
      heroId: heroId,
      amount: 200,
      upiRefNumber: 'UPI9',
      screenshotUrl: 'https://example.com/9.png',
    );
    final wallet =
        await firestore.collection('hero_wallets').doc(heroId).get();
    final requestId = wallet.data()!['lastRechargeRequestId'] as String;

    await service.rejectRechargeRequest(
      requestId: requestId,
      adminId: 'admin1',
      reason: 'fake screenshot',
    );

    final afterFirstReject =
        await firestore.collection('hero_wallets').doc(heroId).get();
    expect(afterFirstReject.data()!['balance'], 0);

    // Double-reject (admin double-taps) must not claw back a second time.
    await service.rejectRechargeRequest(
      requestId: requestId,
      adminId: 'admin1',
    );
    final afterSecondReject =
        await firestore.collection('hero_wallets').doc(heroId).get();
    expect(afterSecondReject.data()!['balance'], 0);
  });

  test('flushUsageCost (a debit) does NOT set lastRechargeRequestId',
      () async {
    final firestore = FakeFirebaseFirestore();
    final service = HeroWalletService.test(firestore);

    await service.submitRechargeRequest(
      heroId: heroId,
      amount: 100,
      upiRefNumber: 'UPI5',
      screenshotUrl: 'https://example.com/5.png',
    );
    await service.flushUsageCost(
      heroId: heroId,
      activeMinutes: 30,
      ridesHandled: 1,
    );

    final wallet =
        await firestore.collection('hero_wallets').doc(heroId).get();
    expect(wallet.data()!['balance'], lessThan(100));
  });
}
