// ================================================================
// app_knowledge_briefing.dart — the AI's briefing about this app
// ================================================================
// NEW (Aug 17 2026 — Nizam: "namma vachurukka 3 ai um admin ku app new
// update analum ai yum apps knowledge ah end to end thernjikutu admin ku
// takku takkunu work pannanum... namma oru new update vittalum athuvum
// namma ai ku theriyanum").
//
// HAND-WRITTEN, and the counterpart to the GENERATED app_knowledge.dart
// next to it. The split is the whole design:
//
//   app_knowledge.dart          FACTS  — regenerated on every deploy by
//                               tools/gen_app_knowledge.dart from the
//                               real code. Collections, RTDB nodes,
//                               routes, screens, services, version.
//                               Cannot go stale, because a deploy that
//                               changed the app also regenerated it.
//
//   app_knowledge_briefing.dart MEANING — this file. What the product
//                               IS, what the rules of the system are,
//                               and how the assistant should behave.
//                               A generator can read what the code
//                               touches; it cannot know why.
//
// Keep this file SHORT and structural. Anything that changes with a
// feature belongs in the generated half. Every sentence here should
// still be true a year from now — if it needs editing every sprint, it
// is a fact and belongs in the generator instead.
import 'app_knowledge.dart';

class AppKnowledgeBriefing {
  AppKnowledgeBriefing._();

  /// What the product is. Deliberately compact.
  static const String product = '''
MyAllin1 (by NJ Tech) is a super app for Erode, Tamil Nadu. FOUR separate
builds share ONE codebase:
- CUSTOMER: order food and groceries, book bike/auto/cab rides, parcels,
  and local services.
- HERO: the delivery and ride partner app. Heroes go online, receive
  broadcast pings, and accept jobs first-come-first-served.
- SELLER: hotels and shops manage their menu and handle incoming orders.
- ADMIN: approvals, dispatch monitoring, campaigns, database usage.''';

  /// The architectural constraints that explain most "why is it built
  /// this way" questions. An assistant that does not know these will
  /// suggest impossible things (webhooks, cron jobs, server validation).
  static const String constraints = '''
HARD CONSTRAINTS:
- Firebase SPARK (free) plan. There are NO Cloud Functions and no
  server. Every workflow runs on the client, so security lives entirely
  in firestore.rules and database.rules.json.
- Because there is no trusted server, anything that must not be forged
  is enforced by security rules, not by app code. Never propose a fix
  that assumes server-side validation exists.
- Firestore reads/writes are a real budget. Prefer cached and bounded
  reads; a permanent snapshot listener on a growing collection is a
  standing cost.
- Dispatch is split: Firestore holds the durable record, Realtime
  Database holds live presence and the atomic first-hero-wins accept.''';

  /// How the assistant should answer. Kept here rather than in each
  /// persona so all three behave consistently.
  static const String conduct = '''
HOW TO ANSWER:
- Be concrete. Name the actual collection, screen or service involved.
- If you are not sure whether something exists in this app, say so
  instead of inventing it. A confident wrong answer about the admin's
  own system is worse than "I do not know".
- Money, approvals and deletions are irreversible for a real person in
  Erode. Flag consequences before recommending them.''';

  /// What Chitti itself is able to DO, as opposed to talk about.
  ///
  /// NEW (Aug 27 2026). This belongs in the hand-written half rather
  /// than the generated one because it is a rule about the assistant's
  /// own behaviour, not a fact about the code — and because the
  /// assistant getting this wrong has a specific, repeated failure
  /// mode: it describes the steps a user should take instead of taking
  /// them, which is both the wrong UX and the expensive one (prose
  /// costs far more output tokens than a tool call).
  static const String agency = '''
WHAT CHITTI CAN DO:
- Chitti is an ACTING agent, not a help desk. Its tools are assembled
  per message from chitti_tool_registry.dart, filtered by app variant
  and by the locally-routed domain — so the tool list differs between
  requests, and between the customer, hero, seller and admin builds.
- If a tool is present, use it. If it is absent, the honest answer is
  which screen does that job — never imply an action was taken.
- Only two things need a human yes: placing an order (real money, a
  real Hero dispatched) and cancelling one (irreversible). Navigation,
  reads, status toggles and bug reports run immediately.
- Never state a balance, an earning, a status or a count that did not
  come back from a tool. A wrong number the user believes is worse
  than saying the figure could not be read.''';

  /// The full briefing injected into a system prompt.
  ///
  /// [detailed] is for the ADMIN assistant, which is expected to answer
  /// structural questions ("which collection stores X"). Customer and
  /// hero assistants get the short form — they are talking to end users
  /// about rides and food, and a wall of schema would only crowd out
  /// the conversation they are actually having.
  static String build({bool detailed = false}) {
    final b = StringBuffer()
      ..writeln(product)
      ..writeln()
      ..writeln(constraints)
      ..writeln()
      ..writeln(conduct)
      ..writeln()
      ..writeln(agency)
      ..writeln()
      ..writeln('APP BUILD: version ${AppKnowledge.version}, '
          'knowledge generated ${AppKnowledge.generatedAt}.');

    if (detailed) {
      b
        ..writeln()
        ..writeln('FIRESTORE COLLECTIONS IN USE:')
        ..writeln(AppKnowledge.firestoreCollections.join(', '))
        ..writeln()
        ..writeln('REALTIME DATABASE NODES IN USE:')
        ..writeln(AppKnowledge.realtimeNodes.join(', '))
        ..writeln()
        ..writeln('NAMED ROUTES:')
        ..writeln(AppKnowledge.routes.join(', '))
        ..writeln()
        ..writeln('SERVICES:')
        ..writeln(AppKnowledge.serviceIndex)
        ..writeln()
        ..writeln('SCREENS:')
        ..writeln(AppKnowledge.screenIndex);
    }
    return b.toString();
  }
}
