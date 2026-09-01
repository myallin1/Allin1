// ================================================================
// quick_order_line_items.dart — Shared "Quick Order" line-item form.
// Replaces the free-paragraph text fields on Grocery / Custom Food /
// Hero Booking with a dynamic S.No / Name / Qty row list, matching the
// itemized `details['items']` shape already used by
// seller_detail_screen.dart's catalog_food_order flow (List<Map>
// instead of a raw String). All colors come from context.colors.* so
// this renders correctly across all 5 app themes.
// ================================================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/theme_context_extensions.dart';

/// Mutable plain-Dart line item — pure form state, no Firestore
/// annotations. S.No is never stored here; it's always derived from
/// list position (index + 1) by the widgets that render it.
class OrderLineItem {
  OrderLineItem({this.name = '', this.qty = ''});

  String name;
  String qty;

  bool get isEmpty => name.trim().isEmpty && qty.trim().isEmpty;
}

/// Converts a list of [OrderLineItem] into the `details['items']`
/// Firestore shape: `[{'sNo': 1, 'name': ..., 'qty': ...}, ...]`.
/// Fully-empty rows (both name and qty blank) are skipped.
List<Map<String, dynamic>> quickOrderItemsToJson(List<OrderLineItem> items) {
  final result = <Map<String, dynamic>>[];
  var sNo = 1;
  for (final item in items) {
    if (item.isEmpty) continue;
    result.add({
      'sNo': sNo,
      'name': item.name.trim(),
      'qty': item.qty.trim(),
    });
    sNo++;
  }
  return result;
}

class QuickOrderLineItemsForm extends StatefulWidget {
  const QuickOrderLineItemsForm({
    super.key,
    required this.items,
    required this.onChanged,
    this.itemLabel = 'Item',
    this.qtyLabel = 'Qty',
  });

  final List<OrderLineItem> items;
  final ValueChanged<List<OrderLineItem>> onChanged;
  final String itemLabel;
  final String qtyLabel;

  @override
  State<QuickOrderLineItemsForm> createState() => _QuickOrderLineItemsFormState();
}

class _QuickOrderLineItemsFormState extends State<QuickOrderLineItemsForm> {
  late List<OrderLineItem> _items;
  late List<TextEditingController> _nameCtrls;
  late List<TextEditingController> _qtyCtrls;

  @override
  void initState() {
    super.initState();
    _items = widget.items.isNotEmpty ? widget.items : [OrderLineItem()];
    _nameCtrls = _items.map((it) => TextEditingController(text: it.name)).toList();
    _qtyCtrls = _items.map((it) => TextEditingController(text: it.qty)).toList();
  }

  @override
  void dispose() {
    for (final c in _nameCtrls) {
      c.dispose();
    }
    for (final c in _qtyCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _notify() {
    widget.onChanged(_items);
  }

  void _addRow() {
    setState(() {
      final item = OrderLineItem();
      _items.add(item);
      _nameCtrls.add(TextEditingController());
      _qtyCtrls.add(TextEditingController());
    });
    _notify();
  }

  void _removeRow(int index) {
    setState(() {
      _items.removeAt(index);
      _nameCtrls.removeAt(index).dispose();
      _qtyCtrls.removeAt(index).dispose();
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.subtleFill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      key: Key('quick_order_name_$i'),
                      controller: _nameCtrls[i],
                      style: TextStyle(fontSize: 13, color: colors.text),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: widget.itemLabel,
                        hintStyle: TextStyle(color: colors.mutedText.withValues(alpha: 0.6), fontSize: 12),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (v) {
                        _items[i].name = v;
                        _notify();
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      key: Key('quick_order_qty_$i'),
                      controller: _qtyCtrls[i],
                      style: TextStyle(fontSize: 13, color: colors.text),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: widget.qtyLabel,
                        hintStyle: TextStyle(color: colors.mutedText.withValues(alpha: 0.6), fontSize: 12),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (v) {
                        _items[i].qty = v;
                        _notify();
                      },
                    ),
                  ),
                  if (_items.length > 1)
                    IconButton(
                      key: Key('quick_order_remove_$i'),
                      icon: Icon(Icons.close_rounded, color: colors.mutedText, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => _removeRow(i),
                    ),
                ],
              ),
            ),
          ),
        TextButton.icon(
          key: const Key('quick_order_add_more'),
          onPressed: _addRow,
          style: TextButton.styleFrom(
            foregroundColor: colors.accent,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          ),
          icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
          label: Text(
            'Add More',
            style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
