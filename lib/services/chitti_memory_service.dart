// ================================================================
// ChittiMemoryService — what Chitti remembers, and for how long
// Allin1 (Aug 19 2026)
// ================================================================
// Nizam's brief: "avan namma app ku oru guide ah customer oda ovooru
// new service layum new memory chat oda iruppan, antha service
// mudiravarayum avanuku antha knowledge irukuramari irukanum."
//
// So memory is scoped to a SERVICE SESSION, not to the app and not to
// the user's lifetime:
//
//   ride booked ──▶ Chitti remembers this ride ──▶ ride completes
//                                              └──▶ memory cleared
//
// WHY SESSION-SCOPED AND NOT PERMANENT
//   A permanent transcript would mean every message Chitti has ever
//   exchanged gets re-sent to the model as context on every new
//   question. Token cost grows without bound, latency grows with it,
//   and the answers get WORSE — a model asked about today's grocery
//   order while carrying three weeks of unrelated taxi chatter will
//   reliably drag in the wrong details. Scoping to the active service
//   keeps the context small, cheap, and about the thing in front of
//   the customer.
//
// WHY IN-MEMORY AND NOT FIRESTORE
//   This is conversational scratch state that is worthless once the
//   service ends. Persisting it would mean a write per message and a
//   read per app open, on the Spark plan, to store something we intend
//   to throw away within the hour.
//
//   The deliberate consequence: killing the app loses the thread. That
//   is the right trade — a customer who force-quits mid-ride and comes
//   back gets a Chitti who asks once what they need, rather than a
//   Chitti who costs money all day to avoid asking.
// ================================================================

import 'package:flutter/foundation.dart';

import 'chitti_order_memory_service.dart';

/// One thing Chitti is currently helping with. `serviceId` is whatever
/// the owning flow already uses as its identifier (a rideId, a
/// requestId, an orderId) so nothing new has to be minted or tracked.
@immutable
class ChittiServiceContext {
  /// e.g. 'taxi', 'food', 'grocery', 'mobile'. Drives which system
  /// prompt Chitti answers with.
  final String serviceType;

  /// The live document id for this service, when there is one.
  final String? serviceId;

  /// Human label shown in Chitti's bubble: "Tracking your ride".
  final String label;

  /// Free-form facts the owning screen chose to hand over — pickup
  /// point, restaurant name, phone model. Kept small on purpose; this
  /// is injected into the prompt, so every key costs tokens on every
  /// message.
  final Map<String, String> facts;

  const ChittiServiceContext({
    required this.serviceType,
    required this.label,
    this.serviceId,
    this.facts = const <String, String>{},
  });
}

/// A single turn in the current service conversation.
@immutable
class ChittiTurn {
  final bool fromUser;
  final String text;
  final DateTime at;

  ChittiTurn({required this.fromUser, required this.text, DateTime? at})
      : at = at ?? DateTime.now();
}

class ChittiMemoryService extends ChangeNotifier {
  ChittiMemoryService._();
  static final ChittiMemoryService instance = ChittiMemoryService._();

  ChittiServiceContext? _active;
  final List<ChittiTurn> _turns = <ChittiTurn>[];

  // ── PASSIVE SCREEN AWARENESS (Aug 25 2026 — Super Chitti Phase 1,
  // Step 1) ────────────────────────────────────────────────────────
  // Deliberately NOT the same thing as `_active`/ChittiServiceContext
  // above. `_active` means "the customer is mid-way through a real
  // service (a ride, an order) and Chitti is following it" — it is
  // set/cleared explicitly by that flow via beginService()/endService().
  //
  // `_currentScreen` means only "this widget is the one on screen right
  // now", updated on every navigation regardless of whether anything is
  // actually happening there. It's what lets a vague command like "book
  // it for me" resolve correctly depending on whether the customer is
  // sitting on the Food Dashboard or the Bike Taxi screen. See
  // route_breadcrumb_observer.dart, which is the single call site that
  // updates this on every push/replace across the app.
  String? _currentScreen;
  String? get currentScreen => _currentScreen;

  /// [screenLabel] should be a short, human-readable name Chitti can
  /// reason about directly in a prompt (e.g. "Food Dashboard", "Bike
  /// Taxi booking") — not a raw route path or widget class name.
  void setCurrentScreen(String? screenLabel) {
    final trimmed = screenLabel?.trim();
    final next = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    if (next == _currentScreen) return;
    _currentScreen = next;
    notifyListeners();
  }

  /// Hard ceiling on remembered turns. Beyond this the oldest are
  /// dropped rather than the list growing forever — an unbounded
  /// transcript is the single easiest way to turn a working assistant
  /// into a slow, expensive one.
  static const int kMaxTurns = 24;

  ChittiServiceContext? get activeContext => _active;
  bool get isEngaged => _active != null;
  List<ChittiTurn> get turns => List.unmodifiable(_turns);

  /// Called when the customer starts a service Chitti should follow.
  /// Starting a DIFFERENT service clears the previous thread — Chitti
  /// helps with one thing at a time, which is also what keeps the
  /// context small enough to stay accurate.
  void beginService(ChittiServiceContext ctx) {
    final sameThread = _active?.serviceType == ctx.serviceType &&
        _active?.serviceId == ctx.serviceId;
    if (!sameThread) _turns.clear();
    _active = ctx;
    notifyListeners();
  }

  /// Merges newly-learned facts into the live context without
  /// restarting the thread — e.g. a driver gets assigned mid-ride.
  void updateFacts(Map<String, String> newFacts) {
    final a = _active;
    if (a == null || newFacts.isEmpty) return;
    _active = ChittiServiceContext(
      serviceType: a.serviceType,
      label: a.label,
      serviceId: a.serviceId,
      facts: <String, String>{...a.facts, ...newFacts},
    );
    notifyListeners();
  }

  void remember(ChittiTurn turn) {
    _turns.add(turn);
    if (_turns.length > kMaxTurns) {
      _turns.removeRange(0, _turns.length - kMaxTurns);
    }
    notifyListeners();
  }

  /// Service finished — Chitti forgets it and goes back to being a
  /// general guide. Call this from the SAME place that marks the ride
  /// or order complete, so the two can never disagree.
  void endService() {
    if (_active == null && _turns.isEmpty) return;
    _active = null;
    _turns.clear();
    notifyListeners();
  }

  // ── KNOWLEDGE BASE HOOK ────────────────────────────────────────
  // Prep for the planned local Knowledge Base (app features, updates,
  // how-tos) that Chitti will read to guide users.
  //
  // Deliberately a FUNCTION, not a stored string or a service import.
  // Three things that buys us:
  //   1. This service stays decoupled — it never imports the knowledge
  //      base, so the KB can be Hive-backed, asset-backed, or remote
  //      later without touching this file or its tests.
  //   2. It is called per-message with the live question, so the KB can
  //      return only the RELEVANT few hundred tokens instead of the
  //      whole corpus. Injecting an entire knowledge base into every
  //      prompt is the classic way this feature becomes unaffordable.
  //   3. It stays synchronous by contract. If the lookup needs to be
  //      async, the KB should keep a warm in-memory index and refresh
  //      it off the message path — see the note below on why "async"
  //      alone does not protect the UI thread.
  //
  /// Set once at startup, e.g.
  ///   ChittiMemoryService.instance.knowledgeLookup = AppKnowledge.find;
  String Function(String query)? knowledgeLookup;

  /// Compact context block for the model. Deliberately short: this is
  /// prepended to every single message, so anything added here is paid
  /// for on every turn of the conversation.
  ///
  /// [query] is the customer's current question, used only to let the
  /// knowledge base narrow what it returns.
  String buildPromptContext({String query = ''}) {
    final buf = StringBuffer();

    final a = _active;
    if (a != null) {
      buf.writeln('The customer is currently using: ${a.label} '
          '(service: ${a.serviceType}).');
      if (a.facts.isNotEmpty) {
        buf.writeln('Known details:');
        a.facts.forEach((k, v) => buf.writeln('- $k: $v'));
      }
      buf.writeln('Stay focused on helping with this until it is finished.');
    } else if (_currentScreen != null) {
      // Only shown when there's no active service context above — an
      // in-progress ride/order is always the more specific, more
      // useful signal, so it takes priority over the passive screen.
      buf.writeln('The customer is currently looking at the '
          '$_currentScreen screen of the app. If they say something '
          'vague like "book it for me" or "order this", assume they '
          'mean whatever that screen is for unless they say otherwise.');
    }

    final recentOrders = ChittiOrderMemoryService.recentSummary();
    if (recentOrders.isNotEmpty) {
      buf
        ..writeln()
        ..writeln(recentOrders);
    }

    final lookup = knowledgeLookup;
    if (lookup != null && query.trim().isNotEmpty) {
      // Guarded: a knowledge base is exactly the kind of component that
      // gets swapped and refactored later, and a throw from it must
      // degrade Chitti to "no app knowledge", never break the reply.
      try {
        final kb = lookup(query).trim();
        if (kb.isNotEmpty) {
          buf
            ..writeln()
            ..writeln('App knowledge that may help:')
            ..writeln(kb);
        }
      } catch (_) {
        // Intentionally silent — see above.
      }
    }

    return buf.toString();
  }
}
