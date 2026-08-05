// ================================================================
// GroceryAiNotesService — bridge between Guru (chat/voice/vision) and
// the EXISTING grocery order form's free-text list field.
// ================================================================
// NEW (CTO mandate — Dual-Mode Grocery Cart, Modes 2 & 3). Deliberately
// tiny and deliberately dumb: it holds a queue of plain text lines
// ("2 packs of milk") that GroceryOrderScreen's existing `_listCtrl`
// (already a real, working field — "Text list and/or photo of a
// handwritten list; at least one is required", see
// grocery_order_screen.dart's header comment) appends into on open.
//
// This is the whole reason Modes 2/3 can be "strictly additive" and
// not touch a single line of the existing image-upload/submit logic:
// GroceryOrderScreen's `_submit()`, `_canSubmit`, Cloudinary upload,
// and Firestore write are completely untouched. Guru never writes to
// Firestore or constructs an order itself — it only pre-fills the same
// text box the customer would have typed into themselves, and the
// customer still reviews/edits/submits it exactly as before.
import 'package:flutter/foundation.dart';

class GroceryAiNotesService extends ChangeNotifier {
  GroceryAiNotesService._();
  static final GroceryAiNotesService instance = GroceryAiNotesService._();

  final List<String> _pending = [];

  bool get hasPending => _pending.isNotEmpty;
  List<String> get pending => List.unmodifiable(_pending);

  /// Called by Guru's `add_to_grocery_cart` tool handler (chat + overlay)
  /// and by the "I Need This" vision-extraction flow in dmart_screen.dart.
  void addItem(String item, {String? quantity}) {
    final trimmedItem = item.trim();
    if (trimmedItem.isEmpty) return;
    final q = quantity?.trim();
    _pending.add((q != null && q.isNotEmpty) ? '$q $trimmedItem' : trimmedItem);
    notifyListeners();
  }

  /// Called once by GroceryOrderScreen.initState() — returns everything
  /// queued so far and clears the queue, so re-opening the screen later
  /// doesn't re-append the same items a second time.
  List<String> consumeAll() {
    if (_pending.isEmpty) return const [];
    final items = List<String>.from(_pending);
    _pending.clear();
    notifyListeners();
    return items;
  }
}
