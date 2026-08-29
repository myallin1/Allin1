// ================================================================
// chitti_offline_capability_test.dart
// ================================================================
// "Does Chitti actually work with no API key?"
//
// That question deserves a verifiable answer rather than a claim, and
// the answer has a boundary that matters: SOME tools resolve entirely
// on device, and some genuinely cannot. This test pins both halves, so
// the boundary is documented in code and cannot drift quietly.
//
// The split is not arbitrary. A tool is locally reachable when its
// arguments are either fixed, or come from a closed set the app owns
// (a section key, a service type, a language code). A tool needs the
// model when an argument is FREE TEXT pulled out of a sentence — the
// items in an order, the summary of a bug, a menu item's name. Guessing
// those wrong places a wrong paid order or hides the wrong dish.
import 'package:flutter_test/flutter_test.dart';

import 'package:erode_superapp/config/app_variant.dart';
import 'package:erode_superapp/services/chitti/chitti_local_intent_engine.dart';
import 'package:erode_superapp/services/chitti/chitti_tool_registry.dart';

void main() {
  final original = currentAppVariant;
  tearDown(() => currentAppVariant = original);

  /// Tools that must keep working with no API key at all.
  const offlineCapable = <String>{
    // customer
    'navigate_to_section',
    'book_transport',
    'check_wallet_balance',
    'check_rewards_balance',
    'check_order_status',
    'list_recent_orders',
    'check_notifications',
    'check_profile_summary',
    'repeat_last_order',
    'cancel_order',
    'share_referral',
    'set_app_language',
    'check_and_update_app',
    // Screen guidance is answered from the section registry, so it is
    // the MOST offline-capable tool there is — see
    // chitti_screen_guide.dart on why it deliberately never asks a
    // model.
    'explain_this_screen',
    // hero
    'hero_set_online_status',
    'hero_today_earnings',
    'hero_active_job_status',
    'hero_wallet_balance',
    'hero_pending_work',
    // seller
    'seller_pending_orders',
    'seller_today_earnings',
    'seller_set_shop_open',
    'seller_shop_status',
    // admin — all four are capped, cache-first counting reads, so they
    // answer from the local cache with no API key and no model call.
    'admin_pending_approvals',
    'admin_today_activity',
    'admin_open_bugs',
    'admin_open_enquiries',
  };

  /// Tools that legitimately need the model. Listed explicitly so that
  /// adding one to the offline set is a deliberate decision with a test
  /// change attached, not an accident.
  const needsModel = <String>{
    'create_service_request', // free-text items and vendor
    'report_app_bug', // needs a written summary
    'add_to_grocery_cart', // free-text item and quantity
    'seller_set_item_availability', // must match a real menu item
    'analyze_screen_with_vision', // needs image bytes and a vision model
  };

  test('every tool is accounted for on one side of the line', () {
    final all = kChittiTools.map((t) => t.name).toSet();
    expect(
      offlineCapable.union(needsModel),
      all,
      reason: 'A new tool was added without deciding whether it works offline.',
    );
    expect(offlineCapable.intersection(needsModel), isEmpty);
  });

  test('the offline half is the majority of the toolset', () {
    // Not a vanity metric: this is the share of requests that can be
    // served with no API call, which is the whole point of Tier 1.
    expect(offlineCapable.length, greaterThan(needsModel.length * 2));
  });

  group('each offline-capable tool is reachable from real phrasing', () {
    // If a tool is claimed offline-capable but no phrasing reaches it,
    // the claim is false — that is exactly the kind of silent gap this
    // whole rework existed to remove.
    const phrases = <String, ({String text, String variant})>{
      'navigate_to_section': (text: 'open my orders', variant: 'customer'),
      'book_transport': (text: 'book an auto to the bus stand', variant: 'customer'),
      'check_wallet_balance': (text: 'what is my wallet balance', variant: 'customer'),
      'check_rewards_balance': (text: 'how many coins do I have', variant: 'customer'),
      'check_order_status': (text: 'where is my hero', variant: 'customer'),
      'list_recent_orders': (text: 'show my past orders', variant: 'customer'),
      'check_notifications': (text: 'any notification for me', variant: 'customer'),
      'check_profile_summary': (text: 'show my profile', variant: 'customer'),
      'repeat_last_order': (text: 'order it again', variant: 'customer'),
      'cancel_order': (text: 'cancel my order', variant: 'customer'),
      'share_referral': (text: 'invite a friend', variant: 'customer'),
      'set_app_language': (text: 'speak in tamil', variant: 'customer'),
      'check_and_update_app': (text: 'update the app', variant: 'customer'),
      'explain_this_screen':
          (text: 'what can i do on this screen', variant: 'customer'),
      'hero_set_online_status': (text: 'go online', variant: 'hero'),
      'hero_today_earnings': (text: 'how much did i earn today', variant: 'hero'),
      'hero_active_job_status': (text: 'my current job', variant: 'hero'),
      'hero_wallet_balance': (text: 'my wallet balance', variant: 'hero'),
      'seller_pending_orders': (text: 'pending orders', variant: 'seller'),
      'seller_today_earnings': (text: 'today sales', variant: 'seller'),
      'seller_set_shop_open': (text: 'close the shop', variant: 'seller'),
      'seller_shop_status': (text: 'is my shop open', variant: 'seller'),
      'hero_pending_work': (text: 'how many jobs are still open', variant: 'hero'),
      'admin_pending_approvals':
          (text: 'how many are waiting for approval', variant: 'admin'),
      'admin_today_activity': (text: 'how many orders today', variant: 'admin'),
      'admin_open_bugs': (text: 'any open bug reports', variant: 'admin'),
      'admin_open_enquiries':
          (text: 'any customer enquiries waiting', variant: 'admin'),
    };

    test('no offline-capable tool is left without a phrasing', () {
      expect(phrases.keys.toSet(), offlineCapable);
    });

    for (final entry in phrases.entries) {
      test('${entry.key} resolves with no API call', () {
        currentAppVariant = entry.value.variant;
        final intent = ChittiLocalIntentEngine.resolve(entry.value.text);
        expect(intent?.action, entry.key, reason: entry.value.text);
      });
    }
  });

  group('the model-only half stays model-only', () {
    test('none of them can be triggered locally', () {
      currentAppVariant = 'customer';
      for (final text in <String>[
        'order 2 plate chicken biryani from Sagar Mess',
        'the wallet screen is blank and keeps crashing',
        'add 2 packs of milk to my list',
      ]) {
        final action = ChittiLocalIntentEngine.resolve(text)?.action;
        expect(needsModel.contains(action), isFalse, reason: text);
      }
    });
  });
}
