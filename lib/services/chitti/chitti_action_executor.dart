// ================================================================
// chitti_action_executor.dart — ONE implementation of what each
// Chitti tool actually does.
// ================================================================
// WHY (Aug 27 2026 — Nizam: "a to z namma app la yenna sonnalum avan
// panna therila").
//
// Chitti has two front ends: the full-screen GuruChatScreen and the
// floating GuruOverlayService bubble. Each had its own copy of every
// handler, and they had already drifted — the overlay could book a
// ride but not place an order, because create_service_request existed
// only in the chat screen. Adding twenty more tools to that structure
// would have meant writing each one twice and hoping.
//
// So the WORK lives here, once, and the two surfaces keep only what
// genuinely differs: how they show a message (a _GuruMessage in a
// setState vs a GuruChatTurn plus notifyListeners) and which
// Navigator they push on. The executor returns a description of what
// should happen rather than doing the UI itself — that is what lets
// one implementation serve two very different hosts without either of
// them leaking into it.
//
// WHAT STAYS OUT: analyze_screen_with_vision. It needs the attached
// image bytes, which only the chat screen can produce (the overlay has
// no attachment UI), and it hands off to a different provider
// entirely. The registry already refuses to offer that tool when no
// image is attached, so the overlay is never even tempted.
//
// CONFIRMATION is not decided here. The caller asks
// ChittiToolRegistry.requiresConfirmation() first and runs its own
// Yes/No flow; by the time execute() is called, the answer is yes.
import '../chitti_memory_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../config/app_variant.dart';
import '../../screens/bike_taxi/bike_booking_screen.dart';
import '../../screens/sos_screen.dart';
import '../auth_prompt_service.dart';
import '../auth_service.dart';
import '../chitti_order_memory_service.dart';
import '../chitti_status_lookup_service.dart';
import '../grocery_ai_notes_service.dart';
import '../localization_service.dart';
import '../service_request_service.dart';
import '../voice_booking_intent_service.dart';
import 'chitti_screen_guide.dart';
import 'chitti_hero_voice.dart';
import 'chitti_host_bridge.dart';
import 'chitti_role_lookup_service.dart';
import 'chitti_section_registry.dart';
import 'chitti_tool_registry.dart';

/// What the host should do as a result of running one tool.
///
/// Everything is optional so a handler can say "just talk", "just
/// navigate", or both — and [pendingConfirmAction] lets a tool resolve
/// into a DIFFERENT tool that still needs a human yes (repeat_last_order
/// turning into a create_service_request is the case that motivated it).
@immutable
class ChittiActionResult {
  const ChittiActionResult({
    this.text = '',
    this.suggestions = const <String>[],
    this.openScreen,
    this.openScreenLabel,
    this.pendingConfirmAction,
    this.videoId,
    this.spokenTextOverride,
  });

  /// Message to show the user. Empty means say nothing.
  final String text;

  /// What to SPEAK, when that differs from what is shown.
  ///
  /// Only Thanglish needs this today: the reader sees Latin
  /// but a ta-IN engine can only pronounce the Tamil source.
  /// Null means speak [text] as written.
  final String? spokenTextOverride;

  /// Quick-reply chips to show alongside [text].
  final List<String> suggestions;

  /// A screen for the host to push on its own Navigator.
  final WidgetBuilder? openScreen;

  /// What that screen is called.
  ///
  /// Carried alongside the builder because a WidgetBuilder cannot be
  /// asked what it returns without running it, and the host needs the
  /// name to put in RouteSettings — without it, Chitti opens a screen
  /// and then cannot tell you which screen you are on.
  final String? openScreenLabel;

  /// An action that must now be confirmed before it runs.
  final Map<String, dynamic>? pendingConfirmAction;

  /// A YouTube video to show under the reply — see ChittiLocalAnswer.
  final String? videoId;
}

class ChittiActionExecutor {
  ChittiActionExecutor._();

  static final VoiceBookingIntentService _voiceIntent =
      VoiceBookingIntentService();

  /// Runs [args]['action'] and returns what the host should render.
  ///
  /// [context] is needed for the handful of actions that legitimately
  /// require one (sign-in prompts, the language provider). The overlay
  /// passes `navigatorKey.currentContext`, which is a real, mounted
  /// context — it has a Navigator above it by definition, since that is
  /// where the key is attached.
  ///
  /// Never throws: a tool that fails returns a sentence saying so.
  /// Chitti apologising is a bad outcome; Chitti throwing into a chat
  /// bubble and going silent is a worse one.
  static Future<ChittiActionResult> execute(
    Map<String, dynamic> args, {
    required BuildContext context,
  }) async {
    final action = args['action'] as String?;
    // The customer's own language, for anything Chitti says in its own
    // voice rather than relaying from a lookup. read(), not watch():
    // this is a one-shot value inside an async handler, and watching
    // here would subscribe a widget that is about to be popped.
    final languageCode = context.read<LocalizationService>().languageCode;

    // Belt and braces. Both callers already gate on the registry, but
    // this is the last point before a real Firestore write, and the
    // cost of the check is nothing.
    if (!ChittiToolRegistry.isAllowedFor(action)) {
      debugPrint('[ChittiActionExecutor] refused "$action" in $currentAppVariant');
      return const ChittiActionResult();
    }

    try {
      switch (action) {
        case 'navigate_to_section':
          return _navigate(args);
        case 'book_transport':
          return await _bookTransport(args);
        case 'add_to_grocery_cart':
          return _addToGroceryList(args);
        case 'create_service_request':
          return await _createServiceRequest(args, context);
        case 'repeat_last_order':
          return _repeatLastOrder();
        case 'cancel_order':
          return await _cancelOrder(args);
        case 'report_app_bug':
          return await _reportBug(args);
        case 'set_app_language':
          return await _setLanguage(args, context);
        case 'share_referral':
          return _shareReferral();

        // ── reads ──────────────────────────────────────────────────
        //
        // Every read carries follow-up chips. A read otherwise ends the
        // turn dead: Chitti reads out a balance and the user has to
        // type to do anything with it. The chips are the obvious next
        // thing you would want after hearing that particular answer —
        // which is also what makes them safe to tap without reading.
        case 'check_wallet_balance':
          return ChittiActionResult(
            text: await ChittiStatusLookupService.walletBalanceSummary(),
            suggestions: const <String>[
              'Open my wallet',
              'Show my rewards',
              'My orders',
            ],
          );
        case 'explain_this_screen':
          // Local, not the model: the explanation is constant, must be
          // right with no API key, and a model asked about a screen it
          // has never heard of invents a plausible one.
          final guide = ChittiScreenGuide.forSection(
            ChittiScreenGuide.currentSectionKey(
              ChittiMemoryService.instance.currentScreen,
              currentAppVariant,
            ),
            languageCode,
          );
          return ChittiActionResult(
            text: guide.shown,
            spokenTextOverride: guide.spoken,
            suggestions: const <String>[
              'What needs my attention?',
              'Open something else',
            ],
          );
        case 'check_order_status':
          final status =
              await ChittiStatusLookupService.activeOrderStatusSummary();
          return ChittiActionResult(
            // Chitti puts in a word for the Hero (Aug 28 2026 — Nizam:
            // "customer kita hero ungalukkaga romba ulaikkuraru... mulu
            // manasoda amount kudunga"). Appended, not substituted: the
            // customer asked where their order is, and burying that
            // answer under a message about somebody else would be
            // answering a question they did not ask.
            text: _withHeroWord(status, languageCode),
            suggestions: const <String>[
              'Track it on the map',
              'Cancel my order',
              'Order something else',
            ],
          );
        case 'check_rewards_balance':
          return ChittiActionResult(
            text: await ChittiStatusLookupService.rewardsBalanceSummary(),
            suggestions: const <String>[
              'Open Rewards',
              'How do I earn more?',
              'Show offers',
            ],
          );
        case 'list_recent_orders':
          return ChittiActionResult(
            text: await ChittiStatusLookupService.recentOrdersSummary(),
            suggestions: const <String>[
              'Order the same again',
              'Open My Orders',
              'Book a ride',
            ],
          );
        case 'check_notifications':
          return ChittiActionResult(
            text: await ChittiStatusLookupService.unreadNotificationsSummary(),
            suggestions: const <String>[
              'Open Notifications',
              'Check my orders',
            ],
          );
        case 'check_profile_summary':
          return ChittiActionResult(
            text: await ChittiStatusLookupService.profileSummary(),
            suggestions: const <String>[
              'Open my profile',
              'Complete SOS KYC',
              'Change language',
            ],
          );

        // ── hero ───────────────────────────────────────────────────
        case 'hero_set_online_status':
          return await _heroSetOnline(args);
        case 'hero_today_earnings':
          return ChittiActionResult(
            text: await ChittiRoleLookupService.heroTodayEarningsSummary(),
            suggestions: const <String>[
              'Open Earnings',
              'My wallet balance',
              'Go online',
            ],
          );
        case 'hero_active_job_status':
          final job = await ChittiRoleLookupService.heroActiveJobSummary();
          return ChittiActionResult(
            // "Boss, naan unga dude iruken." The pep line rides along
            // with the facts rather than replacing them — a rider asking
            // about their job wants the job, and encouragement instead
            // of an answer is the fastest way to make them stop asking.
            text: '$job\n\n'
                '${ChittiHeroVoice.heroPep(languageCode, seed: DateTime.now().day)}',
            suggestions: const <String>[
              'Show incomplete tasks',
              'Today earnings',
            ],
          );
        case 'hero_wallet_balance':
          return ChittiActionResult(
            text: await ChittiRoleLookupService.heroWalletSummary(),
            suggestions: const <String>[
              'Open Hero Wallet',
              'Today earnings',
            ],
          );

        // ── seller ─────────────────────────────────────────────────
        case 'hero_pending_work':
          return ChittiActionResult(
            text: await ChittiRoleLookupService.heroPendingWorkSummary(),
            suggestions: const <String>[
              'My active job',
              "Today's earnings",
              'Go online',
            ],
          );
        case 'seller_shop_status':
          return ChittiActionResult(
            text: await ChittiRoleLookupService.sellerShopStatusSummary(),
            suggestions: const <String>[
              'Open the shop',
              'Close the shop',
              'Pending orders',
            ],
          );
        case 'admin_pending_approvals':
          return ChittiActionResult(
            text: await ChittiRoleLookupService.adminPendingApprovalsSummary(),
            suggestions: const <String>[
              'Hero approvals',
              'Seller approvals',
              "Today's orders",
            ],
          );
        case 'admin_today_activity':
          return ChittiActionResult(
            text: await ChittiRoleLookupService.adminTodayActivitySummary(),
            suggestions: const <String>[
              'New orders',
              'Pending approvals',
              'Open enquiries',
            ],
          );
        case 'admin_open_bugs':
          return ChittiActionResult(
            text: await ChittiRoleLookupService.adminOpenBugsSummary(),
            suggestions: const <String>[
              'Open bug reports',
              "Today's orders",
            ],
          );
        case 'admin_open_enquiries':
          return ChittiActionResult(
            text: await ChittiRoleLookupService.adminOpenEnquiriesSummary(),
            suggestions: const <String>[
              'Open enquiries',
              'Pending approvals',
            ],
          );
        case 'seller_pending_orders':
          return ChittiActionResult(
            text: await ChittiRoleLookupService.sellerPendingOrdersSummary(),
            suggestions: const <String>[
              'Open dashboard',
              'Close the shop',
              'Today sales',
            ],
          );
        case 'seller_today_earnings':
          return ChittiActionResult(
            text: await ChittiRoleLookupService.sellerTodayEarningsSummary(),
            suggestions: const <String>[
              'Open Earnings',
              'Pending orders',
            ],
          );
        case 'seller_set_shop_open':
          return await _sellerSetShopOpen(args);
        case 'seller_set_item_availability':
          return _sellerSetItemAvailability(args);

        default:
          // check_and_update_app and analyze_screen_with_vision are
          // handled by the hosts themselves — the update flow needs the
          // host's own PWA/native branch, and vision needs image bytes.
          return const ChittiActionResult();
      }
    } catch (e, stack) {
      debugPrint('[ChittiActionExecutor] "$action" failed: $e\n$stack');
      return const ChittiActionResult(
        text: "That didn't go through just now. Please try again in a moment.",
      );
    }
  }

  // ── handlers ──────────────────────────────────────────────────────

  static ChittiActionResult _navigate(Map<String, dynamic> args) {
    final section = chittiSectionByKey(
      args['section'] as String?,
      currentAppVariant,
    );
    if (section == null) {
      // A hallucinated or wrong-variant key. Saying so beats pushing
      // something arbitrary and leaving the user on a screen they did
      // not ask for.
      return const ChittiActionResult(
        text: "I couldn't find that section. Tell me what you want to do and "
            "I'll take you to the right place.",
        suggestions: <String>['Order food', 'Book a ride', 'My orders'],
      );
    }
    return ChittiActionResult(
      text: 'Sure! Opening ${section.label} for you now.',
      suggestions: const ['Show me something else', 'Go back to chat'],
      openScreen: section.builder,
      openScreenLabel: section.label,
    );
  }

  static Future<ChittiActionResult> _bookTransport(
    Map<String, dynamic> args,
  ) async {
    final service = _voiceServiceFromKey(args['service'] as String?);
    if (service == null) {
      return const ChittiActionResult(
        text: 'Which service — bike, auto, or cab?',
        suggestions: <String>['Bike', 'Auto', 'Cab'],
      );
    }

    final destinationRaw = (args['destination'] as String?)?.trim();
    final intent = VoiceBookingIntent(
      service: service,
      destinationQuery:
          (destinationRaw != null && destinationRaw.isNotEmpty) ? destinationRaw : null,
    );

    // SOS has its own KYC gate on its own screen — never pre-fill or
    // pre-empt it, just open it.
    if (service == VoiceService.sos) {
      return ChittiActionResult(
        text: "I've opened SOS for you — please confirm there so we can get "
            'you help right away.',
        openScreen: (_) => const SosScreen(),
        openScreenLabel: 'Safety / SOS',
      );
    }

    // Only ever PRE-FILLS. The customer still taps Confirm on the
    // booking screen — Chitti has never dispatched a ride by itself and
    // this does not change that.
    if (intent.destinationQuery == null) {
      return ChittiActionResult(
        text: "I've got it! Setting up your ${intent.displayName} booking now "
            '— review the details and press Confirm to book your Hero.',
        suggestions: const [
          'Change destination',
          'Cancel this booking',
          'Ask something else',
        ],
        openScreen: (_) => BikeBookingScreen(initialCategory: intent.categoryKey),
        openScreenLabel: intent.displayName,
      );
    }

    final resolved = await _voiceIntent.resolve(intent);
    return ChittiActionResult(
      text: "I've got it! Setting up your ${intent.displayName} booking now — "
          'review the details and press Confirm to book your Hero.',
      suggestions: const [
        'Change destination',
        'Cancel this booking',
        'Ask something else',
      ],
      openScreen: (_) => BikeBookingScreen(
        initialCategory: intent.categoryKey,
        initialDropLocation: resolved.destination,
      ),
      openScreenLabel: intent.displayName,
    );
  }

  static ChittiActionResult _addToGroceryList(Map<String, dynamic> args) {
    final item = (args['item'] as String?)?.trim() ?? '';
    if (item.isEmpty) {
      return const ChittiActionResult(
        text: 'What should I add to your list?',
        suggestions: <String>['Milk', 'Rice', 'Vegetables'],
      );
    }
    final quantity = (args['quantity'] as String?)?.trim();
    GroceryAiNotesService.instance.addItem(item, quantity: quantity);
    final label =
        (quantity != null && quantity.isNotEmpty) ? '$quantity $item' : item;
    return ChittiActionResult(
      text: 'Added "$label" to your grocery list — open Grocery Order to '
          'review and submit.',
      suggestions: const ['Open Grocery Order', 'Add another item'],
    );
  }

  static Future<ChittiActionResult> _createServiceRequest(
    Map<String, dynamic> args,
    BuildContext context,
  ) async {
    // Runs the SAME ServiceRequestService.createServiceRequest() path
    // the booking forms use, so hero broadcast, admin alerting and the
    // usage-fee flush behave identically whether the order came from a
    // form or from Chitti.
    if (!await requireRealAuth(
      context,
      reason: 'Sign in and I will place this order for you right away',
    )) {
      return const ChittiActionResult(
        text: 'No problem — sign in whenever you are ready and I will place '
            'it for you.',
        suggestions: <String>['Sign in now', 'Show me the menu first'],
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const ChittiActionResult(
        text: 'Please sign in first — I need an account to place the order '
            'under.',
        suggestions: <String>['Sign in now', 'Ask something else'],
      );
    }

    final requestType = (args['request_type'] as String?)?.trim();
    final items = (args['items'] as String?)?.trim() ?? '';
    if (requestType == null || requestType.isEmpty || items.isEmpty) {
      return const ChittiActionResult(
        text: "I didn't catch what to order. Tell me the item and I'll place it.",
        suggestions: <String>['Order food', 'Order groceries', 'Book a Hero'],
      );
    }

    final phone = await AuthService().resolveCustomerPhone(user);
    final details = <String, dynamic>{
      'items': items,
      'placedByAi': true,
      if ((args['vendor'] as String?)?.trim().isNotEmpty ?? false)
        'hotelName': (args['vendor'] as String).trim(),
      if ((args['address'] as String?)?.trim().isNotEmpty ?? false)
        'dropAddress': (args['address'] as String).trim(),
      if ((args['note'] as String?)?.trim().isNotEmpty ?? false)
        'note': (args['note'] as String).trim(),
    };

    await ServiceRequestService().createServiceRequest(
      requestType: requestType,
      customerId: user.uid,
      customerName: user.displayName?.trim().isNotEmpty ?? false
          ? user.displayName!.trim()
          : 'Customer',
      customerPhone: phone,
      details: details,
    );

    return ChittiActionResult(
      text: 'Done — your ${requestTypeLabel(requestType)} is placed and sent '
          'to nearby Heroes. You can track it under Booking Status.',
      suggestions: const ['Track my order', 'Order something else'],
    );
  }

  /// "Same as last time."
  ///
  /// Resolves into a create_service_request that STILL needs a yes —
  /// repeating an order spends real money, and "same as last time" is
  /// exactly the phrase people use when they are not looking closely.
  /// Naming the order back to them before charging for it is the point.
  static ChittiActionResult _repeatLastOrder() {
    final last = ChittiOrderMemoryService.mostRecentEntry();
    if (last == null) {
      return const ChittiActionResult(
        text: "I don't have a previous order saved yet. Tell me what you want "
            "and I'll place it.",
        suggestions: <String>['Order food', 'Order groceries', 'Book a ride'],
      );
    }
    final service = (last['service'] as String?)?.trim() ?? '';
    final summary = (last['summary'] as String?)?.trim() ?? '';
    if (summary.isEmpty) {
      return const ChittiActionResult(
        text: "I couldn't read your last order clearly. Tell me what you want "
            'and I will place it.',
        suggestions: <String>['Order food', 'Order groceries', 'My orders'],
      );
    }

    // Transport is not a service_request — send those back through the
    // booking screen instead of inventing an order document.
    final voiceService = _voiceServiceFromKey(service.toLowerCase());
    if (voiceService != null) {
      return ChittiActionResult(
        pendingConfirmAction: <String, dynamic>{
          'action': 'book_transport',
          'service': service.toLowerCase(),
          if (summary.isNotEmpty) 'destination': summary,
        },
      );
    }

    return ChittiActionResult(
      pendingConfirmAction: <String, dynamic>{
        'action': 'create_service_request',
        'request_type': _requestTypeForService(service),
        'items': summary,
      },
    );
  }

  static Future<ChittiActionResult> _cancelOrder(
    Map<String, dynamic> args,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const ChittiActionResult(
        text: "You don't seem to be signed in, so I can't cancel anything.",
        suggestions: <String>['Sign in now'],
      );
    }

    // Only ever cancels a request that is still WAITING for a hero.
    // Once a hero has accepted, they are already on their way and this
    // is no longer Chitti's call to make — see
    // ServiceRequestService.cancelServiceRequest's own accept-race
    // notes. Silently cancelling an accepted job would strand a hero
    // mid-trip, which is exactly the kind of damage a chat command
    // should not be able to do.
    final snap = await FirebaseFirestore.instance
        .collection('service_requests')
        .where('customerId', isEqualTo: uid)
        .limit(20)
        .get();

    final cancellable = snap.docs
        .where((d) => (d.data()['status'] as String?) == 'pending')
        .toList()
      ..sort((a, b) {
        final at = (a.data()['createdAt'] as Timestamp?)?.toDate();
        final bt = (b.data()['createdAt'] as Timestamp?)?.toDate();
        if (at == null || bt == null) return 0;
        return bt.compareTo(at);
      });

    if (cancellable.isEmpty) {
      return const ChittiActionResult(
        text: 'I could not find an order that can still be cancelled. If a '
            'Hero has already accepted, please call them from the tracking '
            'screen.',
        suggestions: <String>['Track my order', 'My orders'],
      );
    }

    final target = cancellable.first;
    await ServiceRequestService().cancelServiceRequest(
      target.id,
      reason: (args['reason'] as String?)?.trim(),
    );
    return const ChittiActionResult(
      text: 'Cancelled — that order will not be sent to any Hero.',
      suggestions: <String>['Order something else', 'My orders'],
    );
  }

  static Future<ChittiActionResult> _reportBug(
    Map<String, dynamic> args,
  ) async {
    final summary = (args['summary'] as String?)?.trim() ?? '';
    final details = (args['details'] as String?)?.trim() ?? '';
    if (summary.isEmpty && details.isEmpty) return const ChittiActionResult();

    final user = FirebaseAuth.instance.currentUser;
    // app_bug_reports is isRealUser()-gated: a report under an anonymous
    // uid gives admin nobody to follow up with, and the rules would
    // reject the write anyway.
    if (user == null || user.isAnonymous) {
      return const ChittiActionResult(
        text: 'Noted. Sign in whenever you like and I will pass this to the '
            'team.',
        suggestions: <String>['Sign in now', 'Ask something else'],
      );
    }

    var appVersion = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      // Version is a nice-to-have; never block a report on it.
    }

    await FirebaseFirestore.instance.collection('app_bug_reports').add({
      'summary': summary.isEmpty ? details : summary,
      'details': details,
      'screen': (args['screen'] as String?)?.trim() ?? '',
      'severity': (args['severity'] as String?)?.trim() ?? 'medium',
      'source': 'ai_agent',
      'app': currentAppVariant,
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'appVersion': appVersion,
      'reportedBy': user.uid,
      'reporterName': user.displayName ?? '',
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });

    return const ChittiActionResult(
      text: "Reported — I've sent this to the team with your app details "
          'attached. Thanks for flagging it.',
      suggestions: <String>['Report something else', 'Ask something else'],
    );
  }

  static Future<ChittiActionResult> _setLanguage(
    Map<String, dynamic> args,
    BuildContext context,
  ) async {
    final code = (args['language'] as String?)?.trim() ?? '';
    if (code.isEmpty) return const ChittiActionResult();
    try {
      await context.read<LocalizationService>().setLanguage(code);
    } catch (e) {
      debugPrint('[ChittiActionExecutor] setLanguage failed: $e');
      return const ChittiActionResult(
        text: "I couldn't switch the language — you can change it from "
            'Settings.',
        suggestions: <String>['Open Settings'],
      );
    }
    return ChittiActionResult(text: _languageConfirmation(code));
  }

  static ChittiActionResult _shareReferral() {
    // Opens the existing Invite Friends screen rather than building a
    // share sheet here: that screen already generates and caches the
    // referral code on users/{uid}.referralCode. A second code path
    // could hand out a code that does not match the one the screen
    // shows, and a mismatched referral code is money.
    final section = chittiSectionByKey('invite_friends', currentAppVariant);
    return ChittiActionResult(
      text: 'Here you go — your invite link and code are on this screen, ready '
          'to share.',
      openScreen: section?.builder,
      openScreenLabel: section?.label,
    );
  }

  static Future<ChittiActionResult> _heroSetOnline(
    Map<String, dynamic> args,
  ) async {
    final online = args['online'] as bool?;
    if (online == null) {
      return const ChittiActionResult(
        text: 'Do you want to go online or offline?',
        suggestions: <String>['Go online', 'Go offline'],
      );
    }
    final handler = ChittiHostBridge.heroOnlineHandler;
    if (handler == null) {
      // The home screen owns the real flow (location fix, radar entry,
      // ping listeners). Without it mounted there is nothing safe to
      // call — so send them there and say so plainly rather than
      // writing a flag that would make them look online to dispatch
      // while receiving nothing.
      final section = chittiSectionByKey('hero_earnings', currentAppVariant);
      return ChittiActionResult(
        text: 'Open your Hero home screen and I can flip that for you there — '
            'going online needs your location active.',
        openScreen: section?.builder,
        openScreenLabel: section?.label,
      );
    }
    return ChittiActionResult(text: await handler(online));
  }

  static Future<ChittiActionResult> _sellerSetShopOpen(
    Map<String, dynamic> args,
  ) async {
    final open = args['open'] as bool?;
    if (open == null) {
      return const ChittiActionResult(
        text: 'Should I open the shop or close it?',
        suggestions: <String>['Open the shop', 'Close the shop'],
      );
    }
    final handler = ChittiHostBridge.sellerShopOpenHandler;
    if (handler == null) {
      final section = chittiSectionByKey('seller_dashboard', currentAppVariant);
      return ChittiActionResult(
        text: 'Open your dashboard and I can switch that for you there.',
        openScreen: section?.builder,
        openScreenLabel: section?.label,
      );
    }
    return ChittiActionResult(text: await handler(open));
  }

  static ChittiActionResult _sellerSetItemAvailability(
    Map<String, dynamic> args,
  ) {
    // Deliberately NOT implemented as a write yet.
    //
    // Marking an item sold out means finding the right document in the
    // seller's menu from a free-text name the model produced. Fuzzy
    // name matching against a live menu is exactly where a confident
    // wrong match does real damage — the wrong dish silently disappears
    // from a busy kitchen's menu and nobody notices until orders stop.
    // Until there is a proper item lookup to match against, the honest
    // behaviour is to take them to the menu, not to guess.
    final item = (args['item'] as String?)?.trim() ?? 'that item';
    final available = args['available'] as bool? ?? false;
    final section = chittiSectionByKey('seller_dashboard', currentAppVariant);
    return ChittiActionResult(
      text: available
          ? 'Opening your menu — switch "$item" back on there and it will show '
              'to customers again.'
          : 'Opening your menu — mark "$item" sold out there so I do not '
              'change the wrong dish.',
      suggestions: const <String>['Show pending orders', 'Close the shop'],
      openScreen: section?.builder,
      openScreenLabel: section?.label,
    );
  }

  // ── helpers ───────────────────────────────────────────────────────

  /// Shared by both hosts' confirmation text, so the preview a customer
  /// approves and the reply they get afterwards use the same words.
  static String requestTypeLabel(String? type) => switch (type) {
        'custom_food_order' => 'food order',
        'grocery_order' => 'grocery order',
        'hero_booking' => 'hero booking',
        _ => 'order',
      };

  static String _requestTypeForService(String service) {
    final s = service.toLowerCase();
    if (s.contains('food') || s.contains('hotel')) return 'custom_food_order';
    if (s.contains('grocer') || s.contains('dmart')) return 'grocery_order';
    if (s.contains('hero') || s.contains('errand')) return 'hero_booking';
    return 'custom_order';
  }

  static String _languageConfirmation(String code) => switch (code) {
        'ta' => 'சரிங்க பாஸ், இனிமே தமிழ்ல பேசுவோம்.',
        'hi' => 'ठीक है, अब मैं हिंदी में बात करूँगा।',
        'ml' => 'ശരി, ഇനി മലയാളത്തിൽ സംസാരിക്കാം.',
        _ => "Done — I'll speak in English from now on.",
      };

  static VoiceService? _voiceServiceFromKey(String? key) => switch (key) {
        'bike' => VoiceService.bike,
        'auto' => VoiceService.auto,
        'cab' => VoiceService.cab,
        'parcel' => VoiceService.parcel,
        'mini_truck' => VoiceService.miniTruck,
        'lorry' => VoiceService.lorry,
        'sos' => VoiceService.sos,
        _ => null,
      };

  /// Appends Chitti's word for the Hero, but only once the work is
  /// actually done.
  ///
  /// Said while the customer is still waiting it reads as the app
  /// making excuses for a delay; said before booking it is a sales
  /// pitch. Only after completion is there a real person to be
  /// grateful to — which is why the moment is derived from the status
  /// text rather than assumed.
  static String _withHeroWord(String statusText, String languageCode) {
    final moment = _momentFrom(statusText);
    if (!ChittiHeroVoice.isGoodMomentToAdvocate(moment)) return statusText;
    final word = ChittiHeroVoice.advocateForHero(
      languageCode,
      moment: moment,
      seed: DateTime.now().day,
    );
    return word == null ? statusText : '$statusText\n\n$word';
  }

  static HeroMoment _momentFrom(String statusText) {
    final t = statusText.toLowerCase();
    if (t.contains('delivered') ||
        t.contains('completed') ||
        t.contains('finished')) {
      return HeroMoment.completed;
    }
    if (t.contains('on the way') ||
        t.contains('on his way') ||
        t.contains('arriving') ||
        t.contains('picked up')) {
      return HeroMoment.onTheWay;
    }
    return HeroMoment.idle;
  }

}
