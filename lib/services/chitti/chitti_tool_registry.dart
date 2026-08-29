// ================================================================
// chitti_tool_registry.dart — the SINGLE source of truth for every
// tool Chitti can call, in every app variant.
// ================================================================
// WHY THIS FILE EXISTS (Aug 27 2026 — Nizam: "ovvoru work um
// pannuvan ... ipothikku avanuku taxi and transport pathi sonna
// mattum than pandrane thavira a to z namma app la yenna sonnalum
// avan panna therila").
//
// The old setup had the tool list written inline inside
// GuruApiService.extractAgentAction, and then the SET OF ACTIONS THAT
// ARE ACTUALLY ALLOWED TO RUN hard-coded a second and third time, as
// long `if (action != 'x' && action != 'y' ...)` chains in BOTH
// guru_chat_screen.dart and guru_overlay_service.dart.
//
// That is what made the agent feel transport-only. The floating
// overlay bubble — the Chitti users actually reach from any screen —
// listed only SIX actions. create_service_request, report_app_bug and
// analyze_screen_with_vision were defined, described to the model,
// and successfully called by it... and then silently dropped on the
// floor by the overlay's allow-list, falling through to a prose
// reply. Booking a ride worked because book_transport happened to be
// in that list. Ordering food did not.
//
// So the registry does not just hold schemas. It holds the ONE
// answer to all three questions the two executors used to answer
// separately and inconsistently:
//   • is this action real?              → isKnownAction()
//   • may THIS app variant run it?      → isAllowedFor()
//   • must a human confirm it first?    → requiresConfirmation()
// A new tool added here is live in both surfaces at once. There is no
// second list to remember, which is precisely the bug class this
// replaces.
//
// TOKEN BUDGET — why the domain router exists.
// Nizam has already been burned by API quota drain ("api key limit
// theenthurum"). Going from 9 tools to ~30 would multiply the tool
// block on EVERY message by roughly 3-4x, and a bigger menu also
// measurably raises wrong-tool picks. So the tool list sent on a
// request is filtered twice before it leaves the device:
//   1. by app variant  — a Hero is never shown customer order tools;
//   2. by DOMAIN       — routeDomains() reads the user's own words
//                        and sends only the 1-3 relevant groups.
// The router is local keyword matching, not a model call: it costs
// zero tokens and zero latency, and when it cannot decide it widens
// to the variant's core bundle rather than guessing. That keeps the
// common case cheaper than the old 9-tool flat list while covering
// three times as much of the app.
//
// NOT IN SCOPE: the Admin Quick Task co-pilot
// (admin_quick_task_service.dart + admin_ai_tools_schema.dart) is a
// separate, already-working pipeline with its own 5 tools and its own
// propose-then-confirm write gate. It is deliberately untouched. What
// the 'admin' variant gets here is the Chitti bubble's own
// navigation/support/read tools, which is what was missing.
library;

import '../../config/app_variant.dart';
import 'chitti_section_registry.dart';

/// Tool groups. The router picks these, not individual tools, because
/// tools within a group get confused with each other far more often
/// than across groups — sending a whole coherent group is what keeps
/// the model's choice sensible.
enum ChittiDomain {
  /// Rides, parcels, trucks, SOS transport.
  transport,

  /// Placing / repeating / cancelling orders and cart edits.
  ordering,

  /// Opening a screen.
  navigation,

  /// Balances, points, history, profile, language — mostly reads.
  account,

  /// Bugs, updates, vision, referral — "help me with the app itself".
  support,

  /// Hero-only working tools.
  hero,

  /// Seller-only shop tools.
  seller,

  /// Admin-only oversight reads — approval queues, today's volume,
  /// open bugs, waiting enquiries.
  ///
  /// Separate from [support] on purpose. Support is "something in the
  /// app is broken, help me"; this is "how is the business doing right
  /// now". An owner asking about the approval backlog and a customer
  /// reporting a crash want opposite tools, and folding them together
  /// made the model reach for report_app_bug on every admin question
  /// containing the word "problem".
  admin,
}

/// One callable tool.
class ChittiTool {
  const ChittiTool({
    required this.name,
    required this.domain,
    required this.variants,
    required this.description,
    this.parameters = const <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{},
      'required': <String>[],
    },
    this.requiresConfirmation = false,
    this.keywords = const <String>[],
    this.needsSectionEnum = false,
  });

  final String name;
  final ChittiDomain domain;
  final Set<String> variants;
  final String description;

  /// JSON-schema `parameters` object, exactly as the OpenAI/Groq
  /// chat-completions API expects it.
  final Map<String, dynamic> parameters;

  /// True for anything that spends money or destroys work — per
  /// Nizam's decision: confirm ONLY for money and cancellations,
  /// everything else executes immediately.
  final bool requiresConfirmation;

  /// Router hints. Never sent to the model.
  final List<String> keywords;

  /// When true, the `section` enum is injected from
  /// [chittiSectionsFor] at build time instead of being written out
  /// here — that is the whole point of the section registry.
  final bool needsSectionEnum;
}

/// Every tool, all variants. Filtered before use — never sent whole.
const List<ChittiTool> kChittiTools = <ChittiTool>[
  // ── TRANSPORT (customer) ────────────────────────────────────────
  ChittiTool(
    name: 'book_transport',
    domain: ChittiDomain.transport,
    variants: {'customer'},
    description:
        'Start booking a transport or delivery service for the customer.',
    keywords: [
      'ride', 'book', 'bike', 'auto', 'cab', 'taxi', 'parcel', 'truck',
      'lorry', 'drop', 'pickup', 'go to', 'sos', 'emergency', 'poganum',
      'send', 'courier', 'shifting',
    ],
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'service': <String, dynamic>{
          'type': 'string',
          'enum': ['bike', 'auto', 'cab', 'parcel', 'mini_truck', 'lorry', 'sos'],
          'description': 'Which service the customer wants.',
        },
        'destination': <String, dynamic>{
          'type': 'string',
          'description':
              'Where the customer wants to go or send something, in their '
              'own words. Omit for sos.',
        },
      },
      'required': ['service'],
    },
  ),

  // ── ORDERING (customer) ─────────────────────────────────────────
  ChittiTool(
    name: 'create_service_request',
    domain: ChittiDomain.ordering,
    variants: {'customer'},
    description:
        'Place a REAL order/booking for the customer and dispatch it to nearby '
        'Heroes. Use for food orders, grocery orders, hero bookings (errands, '
        'pickup/drop, help), and custom orders. Call this as soon as you know '
        'the request type and what the customer wants — do not describe the '
        'steps, just place it.',
    requiresConfirmation: true,
    keywords: [
      'order', 'buy', 'get me', 'bring', 'food', 'biryani', 'meals', 'grocery',
      'vegetables', 'errand', 'vaangi', 'venum', 'sapadu', 'hotel', 'deliver',
    ],
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'request_type': <String, dynamic>{
          'type': 'string',
          'enum': [
            'hero_booking',
            'custom_food_order',
            'grocery_order',
            'custom_order',
          ],
          'description':
              'hero_booking = errand/help/pickup-drop task. '
              'custom_food_order = food from a hotel/restaurant. '
              'grocery_order = groceries/provisions. '
              'custom_order = anything else the customer wants bought/collected.',
        },
        'items': <String, dynamic>{
          'type': 'string',
          'description':
              'What the customer wants, in their own words, including '
              'quantities if they said any.',
        },
        'vendor': <String, dynamic>{
          'type': 'string',
          'description':
              'Hotel/shop/store name if the customer named one. Omit if not '
              'mentioned — never invent one.',
        },
        'address': <String, dynamic>{
          'type': 'string',
          'description':
              'Delivery or task address if the customer gave one. Omit if not '
              'mentioned.',
        },
        'note': <String, dynamic>{
          'type': 'string',
          'description': 'Any extra instruction from the customer.',
        },
      },
      'required': ['request_type', 'items'],
    },
  ),
  ChittiTool(
    name: 'add_to_grocery_cart',
    domain: ChittiDomain.ordering,
    variants: {'customer'},
    description:
        'Add an item to the grocery list. Never executes a purchase — only '
        'notes the item for the existing grocery order form.',
    keywords: ['add', 'list', 'grocery', 'milk', 'rice', 'onion', 'sugar', 'sernthu'],
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'item': <String, dynamic>{
          'type': 'string',
          'description': 'The grocery item name, e.g. "milk".',
        },
        'quantity': <String, dynamic>{
          'type': 'string',
          'description':
              'How much/many, in the customer own words, e.g. "2 packs" or '
              '"1 kg". Omit if not stated.',
        },
      },
      'required': ['item'],
    },
  ),
  ChittiTool(
    name: 'repeat_last_order',
    domain: ChittiDomain.ordering,
    variants: {'customer'},
    description:
        'Re-open the customer most recent order with the same items pre-filled, '
        'so they only have to confirm. Use for "same as last time", "order it '
        'again", "repeat my usual".',
    keywords: ['again', 'repeat', 'same as last', 'usual', 'marupadiyum', 'rethaa'],
  ),
  ChittiTool(
    name: 'cancel_order',
    domain: ChittiDomain.ordering,
    variants: {'customer'},
    description:
        'Cancel the customer current active order or ride. Only call this when '
        'they clearly ask to cancel. This cannot be undone.',
    requiresConfirmation: true,
    keywords: ['cancel', 'stop', 'vendaam', 'venda', 'dont want', 'call off'],
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'reason': <String, dynamic>{
          'type': 'string',
          'description':
              'Why they are cancelling, in their own words. Omit if not said.',
        },
      },
      'required': <String>[],
    },
  ),

  // ── NAVIGATION (all variants) ───────────────────────────────────
  ChittiTool(
    name: 'navigate_to_section',
    domain: ChittiDomain.navigation,
    variants: {'customer', 'hero', 'seller', 'admin'},
    description: 'Open a specific section of the app.',
    needsSectionEnum: true,
    keywords: [
      'open', 'show', 'where', 'go to', 'take me', 'kaatu', 'kaattu', 'page',
      'screen', 'section',
    ],
  ),

  // ── ACCOUNT / READS (customer) ──────────────────────────────────
  ChittiTool(
    name: 'check_wallet_balance',
    domain: ChittiDomain.account,
    variants: {'customer'},
    description:
        'Check the customer current Allin1 wallet balance. Call whenever they '
        'ask how much money/balance they have. Read-only — never call this to '
        'add or spend money.',
    keywords: ['balance', 'wallet', 'money', 'panam', 'how much', 'evlo'],
  ),
  ChittiTool(
    name: 'check_rewards_balance',
    domain: ChittiDomain.account,
    variants: {'customer'},
    description:
        'Check the customer reward coins/points and anything waiting to be '
        'redeemed. Read-only.',
    keywords: ['points', 'coins', 'rewards', 'scratch', 'redeem', 'cashback'],
  ),
  ChittiTool(
    name: 'check_order_status',
    domain: ChittiDomain.account,
    variants: {'customer'},
    description:
        'Check the live status of the customer current ride and active '
        'food/grocery/hero orders. Read-only — never call this to create or '
        'change an order.',
    keywords: [
      'where is', 'status', 'track', 'my hero', 'my ride', 'my order',
      'reach', 'engaya', 'vandhutaanga',
    ],
  ),
  ChittiTool(
    name: 'list_recent_orders',
    domain: ChittiDomain.account,
    variants: {'customer'},
    description:
        'List the customer recent past orders and rides with their dates and '
        'amounts. Read-only. Use for "what did I order last week", "my past '
        'orders", "how much did I spend".',
    keywords: ['past orders', 'history', 'last week', 'spent', 'previous', 'munnadi'],
  ),
  ChittiTool(
    name: 'check_notifications',
    domain: ChittiDomain.account,
    variants: {'customer'},
    description:
        'Read out the customer unread notifications and alerts. Read-only.',
    keywords: ['notification', 'alert', 'message', 'update me', 'anything new'],
  ),
  ChittiTool(
    name: 'check_profile_summary',
    domain: ChittiDomain.account,
    variants: {'customer'},
    description:
        'Read back the customer saved name, phone, and default address, and '
        'whether SOS KYC is approved. Read-only.',
    keywords: ['my address', 'my number', 'my name', 'profile', 'kyc', 'account details'],
  ),
  ChittiTool(
    name: 'set_app_language',
    domain: ChittiDomain.account,
    variants: {'customer', 'hero', 'seller'},
    description:
        'Switch the app language. Call when the user asks to change language '
        'or asks to be spoken to in another language.',
    keywords: ['language', 'tamil', 'english', 'hindi', 'malayalam', 'mozhi'],
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'language': <String, dynamic>{
          'type': 'string',
          'enum': ['ta', 'en', 'hi', 'ml'],
          'description':
              'ta = Tamil, en = English, hi = Hindi, ml = Malayalam.',
        },
      },
      'required': ['language'],
    },
  ),

  // ── SUPPORT (all variants) ──────────────────────────────────────
  ChittiTool(
    name: 'report_app_bug',
    domain: ChittiDomain.support,
    variants: {'customer', 'hero', 'seller', 'admin'},
    description:
        'File a bug report when the user says something in the app is broken, '
        'stuck, not loading, showing a wrong value, or otherwise not working. '
        'Use this INSTEAD of only apologising. Ask at most one short question '
        'first if you do not know which screen, then call this.',
    keywords: [
      'not working', 'broken', 'stuck', 'error', 'crash', 'blank', 'hang',
      'bug', 'problem', 'velai seyyala', 'varala',
    ],
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'summary': <String, dynamic>{
          'type': 'string',
          'description': 'One-line summary of the problem, in plain English.',
        },
        'details': <String, dynamic>{
          'type': 'string',
          'description':
              'What happened, what they expected, and any error text. Use their '
              'own words — do not invent details they did not say.',
        },
        'screen': <String, dynamic>{
          'type': 'string',
          'description':
              'Which screen the problem happened on, if they said. Omit if unknown.',
        },
        'severity': <String, dynamic>{
          'type': 'string',
          'enum': ['low', 'medium', 'high'],
          'description':
              'high = cannot use the app or lost money; medium = a feature is '
              'broken but there is a workaround; low = cosmetic or minor.',
        },
      },
      'required': ['summary', 'details'],
    },
  ),
  ChittiTool(
    name: 'check_and_update_app',
    domain: ChittiDomain.support,
    variants: {'customer', 'hero', 'seller', 'admin'},
    description:
        'Check whether a newer version of the app is available and, if so, '
        'apply the update.',
    keywords: ['update', 'new version', 'latest', 'upgrade', 'puthusa'],
  ),
  ChittiTool(
    name: 'analyze_screen_with_vision',
    domain: ChittiDomain.support,
    variants: {'customer'},
    description:
        'Hand off to the vision agent to read the attached photo/screenshot, '
        'identify the products shown, and add them to the grocery list. Only '
        'call this when an image is attached to the current message.',
    keywords: ['this photo', 'screenshot', 'image', 'what is this', 'padam'],
  ),
  ChittiTool(
    name: 'share_referral',
    domain: ChittiDomain.support,
    variants: {'customer'},
    description:
        'Open the share sheet with the customer own referral/invite link so '
        'they can send it to a friend.',
    keywords: ['invite', 'refer', 'share app', 'friend', 'referral code'],
  ),

  // ── HERO ────────────────────────────────────────────────────────
  ChittiTool(
    name: 'hero_set_online_status',
    domain: ChittiDomain.hero,
    variants: {'hero'},
    description:
        'Take the Hero online (available for job pings) or offline. Call when '
        'they say they are starting work, going home, taking a break, or ask '
        'to go online/offline.',
    keywords: [
      'online', 'offline', 'duty', 'start work', 'break', 'stop', 'going home',
      'veetuku', 'velai',
    ],
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'online': <String, dynamic>{
          'type': 'boolean',
          'description': 'true = go online and receive pings, false = go offline.',
        },
      },
      'required': ['online'],
    },
  ),
  ChittiTool(
    name: 'hero_today_earnings',
    domain: ChittiDomain.hero,
    variants: {'hero'},
    description:
        'Read the Hero earnings so far today — trips completed and amount '
        'earned. Read-only. Never invent a number.',
    keywords: [
      'earned', 'earning', 'income', 'today', 'sambadhichen', 'sambalam',
      'how much', 'evlo',
    ],
  ),
  ChittiTool(
    name: 'hero_active_job_status',
    domain: ChittiDomain.hero,
    variants: {'hero'},
    description:
        'Read the Hero current accepted job — customer, pickup, drop, and '
        'stage. Read-only.',
    keywords: ['current job', 'my ride', 'active', 'pickup', 'drop', 'customer'],
  ),
  ChittiTool(
    name: 'hero_wallet_balance',
    domain: ChittiDomain.hero,
    variants: {'hero'},
    description:
        'Read the Hero wallet balance and how much is due for settlement. '
        'Read-only.',
    keywords: ['wallet', 'balance', 'due', 'settlement', 'panam'],
  ),

  // ── SELLER ──────────────────────────────────────────────────────
  ChittiTool(
    name: 'seller_pending_orders',
    domain: ChittiDomain.seller,
    variants: {'seller'},
    description:
        'Read the orders waiting for this shop to accept or prepare. Read-only.',
    keywords: ['orders', 'pending', 'new order', 'waiting', 'incoming'],
  ),
  ChittiTool(
    name: 'seller_set_shop_open',
    domain: ChittiDomain.seller,
    variants: {'seller'},
    description:
        'Open or close the shop for new orders. Call when the seller says they '
        'are closing, taking a break, or reopening.',
    keywords: ['close', 'open', 'shut', 'break', 'closing', 'moodu', 'thora'],
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'open': <String, dynamic>{
          'type': 'boolean',
          'description': 'true = accepting orders, false = closed.',
        },
      },
      'required': ['open'],
    },
  ),
  ChittiTool(
    name: 'seller_today_earnings',
    domain: ChittiDomain.seller,
    variants: {'seller'},
    description:
        'Read this shop earnings and order count for today. Read-only. Never '
        'invent a number.',
    keywords: ['earning', 'sales', 'today', 'revenue', 'income', 'vyabaram'],
  ),
  ChittiTool(
    name: 'seller_set_item_availability',
    domain: ChittiDomain.seller,
    variants: {'seller'},
    description:
        'Mark a menu item as available or sold out. Call when the seller says '
        'an item is finished, out of stock, or back on.',
    keywords: ['sold out', 'stock', 'finished', 'available', 'theenthiduchu', 'item'],
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'item': <String, dynamic>{
          'type': 'string',
          'description': 'The menu item name, in the seller own words.',
        },
        'available': <String, dynamic>{
          'type': 'boolean',
          'description': 'true = available again, false = sold out.',
        },
      },
      'required': ['item', 'available'],
    },
  ),
  // ── HERO / SELLER / ADMIN parity ────────────────────────────────
  //
  // NEW (Aug 28 2026 — Nizam: "admin, seller, hero app la iruka
  // chittikum intha customer app mari power kudu").
  //
  // The customer build had 17 tools; admin had 3, all navigation or
  // plumbing. Chitti could open the approvals screen for an owner and
  // then had nothing to say about what was on it — which is worse than
  // useless, because its persona in those builds promises exact
  // figures. These close the gap with reads only: no tool here writes.
  ChittiTool(
    name: 'hero_pending_work',
    domain: ChittiDomain.hero,
    variants: {'hero'},
    description:
        'Read how many jobs are still open on this Hero. Read-only. '
        'Never invent a number.',
    keywords: [
      'pending', 'bakki', 'left', 'remaining', 'open job', 'unfinished',
      'still', 'mudikala',
    ],
  ),
  ChittiTool(
    name: 'seller_shop_status',
    domain: ChittiDomain.seller,
    variants: {'seller'},
    description:
        'Read whether this shop is currently open or closed for orders. '
        'Read-only — does NOT change it.',
    keywords: [
      'shop open', 'kadai', 'is my shop', 'open ah', 'closed', 'status',
      'shop status',
    ],
  ),
  ChittiTool(
    name: 'admin_pending_approvals',
    domain: ChittiDomain.admin,
    variants: {'admin'},
    description:
        'Read how many heroes and sellers are waiting for approval. '
        'Read-only. Never invent a number.',
    keywords: [
      'approval', 'approve', 'pending', 'waiting', 'queue', 'new hero',
      'new seller', 'signup',
    ],
  ),
  ChittiTool(
    name: 'admin_today_activity',
    domain: ChittiDomain.admin,
    variants: {'admin'},
    description:
        "Read today's order count across the platform and how many are "
        'still in progress. Read-only.',
    keywords: [
      'today', 'orders today', 'business', 'how many order', 'innaiku',
      'activity', 'sales today',
    ],
  ),
  ChittiTool(
    name: 'admin_open_bugs',
    domain: ChittiDomain.admin,
    variants: {'admin'},
    description:
        'Read how many bug reports are still unresolved, and how many '
        'are high severity. Read-only.',
    keywords: [
      'bug', 'bugs', 'issue', 'crash', 'report', 'problem', 'unresolved',
    ],
  ),
  ChittiTool(
    name: 'admin_open_enquiries',
    domain: ChittiDomain.admin,
    variants: {'admin', 'seller'},
    description:
        'Read the customer price enquiries still waiting for an answer '
        'from NJ Tech. Read-only.',
    keywords: [
      'enquiry', 'enquiries', 'inquiry', 'lead', 'price question',
      'customer asking', 'rate kekuranga', 'quote',
    ],
  ),

  // ── SCREEN GUIDANCE (Aug 28 2026) ───────────────────────────────
  //
  // Nizam: "all screen voice guidance tamil" — answered as ON DEMAND
  // ("kettaa mattum pesanum"). Available in every build, not just
  // admin: a hero or seller who does not know what a screen does has
  // exactly the same problem, and the registry already covers them.
  //
  // Answered locally, never by the model — see chitti_screen_guide.dart
  // on why a screen explanation must work with no key and no signal.
  ChittiTool(
    name: 'explain_this_screen',
    domain: ChittiDomain.support,
    variants: {'customer', 'hero', 'seller', 'admin'},
    description:
        'Explain what the screen the user is currently looking at is '
        'for, and what they can do on it. Use when they ask what this '
        'page is, what to do here, or how something works.',
    keywords: [
      'what is this', 'what can i do', 'how does this work', 'explain',
      'guide me', 'help me here', 'this screen', 'this page',
      'enna pannalam', 'idhu enna', 'eppadi', 'sollu',
      'இது என்ன', 'என்ன பண்ணலாம்', 'எப்படி',
    ],
  ),

];

/// The groups a variant always falls back to when the router cannot
/// tell what the user meant. Deliberately small — this is the bundle
/// that gets sent on vague input, so it must stay cheap.
const Map<String, List<ChittiDomain>> _coreDomains = <String, List<ChittiDomain>>{
  'customer': [ChittiDomain.navigation, ChittiDomain.transport, ChittiDomain.ordering],
  'hero': [ChittiDomain.hero, ChittiDomain.navigation],
  'seller': [ChittiDomain.seller, ChittiDomain.navigation, ChittiDomain.admin],
  'admin': [ChittiDomain.admin, ChittiDomain.navigation, ChittiDomain.support],
};

/// Registry queries + the local domain router.
class ChittiToolRegistry {
  ChittiToolRegistry._();

  /// Tools that exist at all. Used by the executors to reject a
  /// hallucinated tool name before it reaches a switch.
  static bool isKnownAction(String? name) =>
      name != null && kChittiTools.any((t) => t.name == name);

  /// Whether [variant] may run [name]. This is the HARD gate the old
  /// code only had for create_service_request — now every tool gets
  /// it, in code, not only in the prompt. A prompt is a suggestion to
  /// a model; this is not.
  static bool isAllowedFor(String? name, [String? variant]) {
    final tool = byName(name);
    if (tool == null) return false;
    return tool.variants.contains(variant ?? currentAppVariant);
  }

  /// Per Nizam decision (Aug 27 2026): confirm ONLY for money and
  /// cancellation. Navigation, reads, status toggles and bug reports
  /// all execute immediately — that is the existing Autonomous
  /// Interaction Rule, preserved.
  static bool requiresConfirmation(String? name) =>
      byName(name)?.requiresConfirmation ?? false;

  static ChittiTool? byName(String? name) {
    if (name == null) return null;
    for (final t in kChittiTools) {
      if (t.name == name) return t;
    }
    return null;
  }

  /// Which tool groups this message is about.
  ///
  /// Pure local keyword scoring — no API call, so it costs nothing and
  /// adds no latency. Returns at most 3 domains, and never fewer than
  /// the variant core bundle, so a miss degrades to "slightly more
  /// tokens" rather than "the tool was not offered at all". Getting
  /// that failure direction right matters more than precision here:
  /// an unmatched tool is invisible to the model, and an invisible
  /// tool is exactly the bug this whole change fixes.
  static Set<ChittiDomain> routeDomains(String message, {String? variant}) {
    final v = variant ?? currentAppVariant;
    final text = message.toLowerCase();
    final core = _coreDomains[v] ?? _coreDomains['customer']!;
    if (text.trim().isEmpty) return core.toSet();

    final scores = <ChittiDomain, int>{};
    void bump(ChittiDomain d, int by) =>
        scores[d] = (scores[d] ?? 0) + by;

    for (final tool in kChittiTools) {
      if (!tool.variants.contains(v)) continue;
      for (final kw in tool.keywords) {
        if (text.contains(kw)) bump(tool.domain, kw.length > 4 ? 2 : 1);
      }
    }
    // Section names are strong navigation signals, and they are the
    // half the old 12-entry enum was missing entirely.
    for (final section in chittiSectionsFor(v)) {
      for (final alias in section.aliases) {
        if (text.contains(alias)) bump(ChittiDomain.navigation, 2);
      }
    }
    // "not working" style complaints must always be able to reach
    // report_app_bug, whatever else the sentence mentions.
    if (scores.containsKey(ChittiDomain.support)) {
      bump(ChittiDomain.support, 1);
    }

    if (scores.isEmpty) return core.toSet();

    final ranked = scores.keys.toList()
      ..sort((a, b) => scores[b]!.compareTo(scores[a]!));
    final picked = ranked.take(3).toSet();
    // Navigation is cheap relative to how often it is the real intent
    // ("show me X"), so it rides along whenever there is room.
    if (picked.length < 3) picked.add(ChittiDomain.navigation);
    return picked;
  }

  /// The `tools` array to send, already filtered by variant and by the
  /// routed domains, with the section enum injected.
  ///
  /// [extraDomains] lets a caller force a group in regardless of the
  /// router — used for the vision domain when an image is attached,
  /// where the trigger is the attachment, not the words.
  static List<Map<String, dynamic>> toolSchemasFor({
    required String message,
    String? variant,
    Set<ChittiDomain> extraDomains = const <ChittiDomain>{},
    bool hasAttachedImage = false,
  }) {
    final v = variant ?? currentAppVariant;
    final domains = <ChittiDomain>{
      ...routeDomains(message, variant: v),
      ...extraDomains,
      // An attached image is itself the intent signal.
      if (hasAttachedImage) ChittiDomain.support,
    };

    final sections = chittiSectionsFor(v);
    final out = <Map<String, dynamic>>[];
    for (final tool in kChittiTools) {
      if (!tool.variants.contains(v)) continue;
      if (!domains.contains(tool.domain)) continue;
      // Nothing to navigate to in this variant — drop the tool rather
      // than send an empty enum, which models handle badly.
      if (tool.needsSectionEnum && sections.isEmpty) continue;
      // Never offer the vision handoff with no image; the model
      // calling it would be a guaranteed dead end.
      if (tool.name == 'analyze_screen_with_vision' && !hasAttachedImage) {
        continue;
      }

      out.add(<String, dynamic>{
        'type': 'function',
        'function': <String, dynamic>{
          'name': tool.name,
          'description': tool.description,
          'parameters': tool.needsSectionEnum
              ? _sectionParameters(sections)
              : tool.parameters,
        },
      });
    }
    return out;
  }

  static Map<String, dynamic> _sectionParameters(List<ChittiSection> sections) {
    // The per-section descriptions are folded into ONE description
    // string rather than emitted as a JSON-schema `oneOf` — the enum
    // plus a compact legend costs roughly a third of the tokens and,
    // in practice, picks correctly at least as often.
    final legend = sections
        .map((s) => '${s.key}=${s.description}')
        .join(' ');
    return <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'section': <String, dynamic>{
          'type': 'string',
          'enum': sections.map((s) => s.key).toList(growable: false),
          'description': 'Which app section to open. $legend',
        },
      },
      'required': ['section'],
    };
  }
}
