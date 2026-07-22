// ================================================================
// service_request_labels.dart — Shared presentation mappings for the
// Broadcast Order System (Hero Booking / Custom Order / Custom Food
// Order / Grocery Order).
//
// This is the SINGLE source of truth for turning a canonical
// `service_requests` status value into a user-facing label / colour.
// Both the single-request tracking screen and the "My Orders" list on
// the food page read from here — never duplicate this mapping.
//
// The canonical status enum itself lives in service_request_service.dart
// (kServiceRequestStatuses). These are presentation-only mappings on
// top of those exact string values.
// ================================================================
import 'package:flutter/material.dart';

// ── Task-type vs Goods-type label sets ───────────────────────────
// Both map onto the exact same 5-value status progression below.
// Index: 0=pending 1=hero_assigned 2=in_progress 3=nearing_completion 4=completed
const List<String> kTaskLabels = [
  'Waiting for hero confirmation',
  'Your hero confirmed',
  'Your process ongoing',
  'Hero reaching you soon',
  'Task completed',
];

const List<String> kGoodsLabels = [
  'Waiting for order confirmation',
  'Order confirmed',
  'Order on process',
  'Order on the way',
  'Order delivered',
];

/// Request types that use the task-style label set. Everything else
/// (custom_order, custom_food_order, grocery_order) uses goods labels.
const Set<String> kTaskTypeRequests = {'hero_booking'};

/// Maps a canonical status string to the 0–4 stepper index. `pending`
/// and `admin_review` both map to 0 (still waiting for a hero).
int serviceRequestStatusIndex(String status) {
  switch (status) {
    case 'pending':
    case 'admin_review':
      return 0;
    case 'hero_assigned':
      return 1;
    case 'in_progress':
      return 2;
    case 'nearing_completion':
      return 3;
    case 'completed':
      return 4;
    default:
      return 0;
  }
}

/// Returns the correct label set (task vs goods) for a request type.
List<String> serviceRequestLabelsFor(String requestType) =>
    kTaskTypeRequests.contains(requestType) ? kTaskLabels : kGoodsLabels;

/// Convenience: the single user-facing label for a given request type +
/// status. `admin_review` gets its own message rather than reusing the
/// index-0 "waiting" label.
String serviceRequestStatusLabel(String requestType, String status) {
  if (status == 'admin_review') return 'Team arranging a hero';
  final labels = serviceRequestLabelsFor(requestType);
  return labels[serviceRequestStatusIndex(status)];
}

/// Approximate stage-duration copy for Hero Booking tasks only. No
/// backend timing/history data exists anywhere in the service_requests
/// flow (see service_request_service.dart) to compute a real ETA, so
/// these are fixed, deliberately-hedged estimates ("usually...").
/// Always keep hedging language in this copy so customers never read
/// it as a guarantee. Returns null for 'completed' (no estimate
/// needed) and for any status not in this switch. Not used by the 3
/// goods-type request categories — call sites should gate on
/// `requestType == 'hero_booking'` before using this.
String? heroBookingEtaLabel(String status) {
  switch (status) {
    case 'pending':
      return 'Usually assigned within 2–5 minutes';
    case 'admin_review':
      return 'Our team is arranging a hero — usually within 10–15 minutes';
    case 'hero_assigned':
      return 'Hero usually starts within 5–10 minutes';
    case 'in_progress':
      return 'Usually wraps up within 20–40 minutes';
    case 'nearing_completion':
      return 'Almost done — usually within 10–15 minutes';
    default:
      return null;
  }
}

/// Hero Booking task categories — single source of truth for both the
/// booking form's category chips (hero_booking_screen.dart) and the
/// detail tracking screen's task-details display
/// (hero_booking_tracking_screen.dart). Purely a customer-facing
/// classification today (stored in details.category) — does not yet
/// drive dispatch/matching logic.
const List<Map<String, String>> kHeroBookingCategories = [
  {'key': 'pickup_delivery', 'label': 'Pickup & Delivery'},
  {'key': 'errand', 'label': 'Errand / Shopping'},
  {'key': 'paperwork', 'label': 'Paperwork / Documents'},
  {'key': 'custom_order', 'label': 'Custom Order'},
  {'key': 'other', 'label': 'Other'},
];

/// Maps a category key to its display label. Returns null for null/
/// empty/unrecognized keys so call sites can decide whether to show a
/// fallback or hide the row entirely.
String? heroBookingCategoryLabel(String? key) {
  if (key == null || key.isEmpty) return null;
  for (final category in kHeroBookingCategories) {
    if (category['key'] == key) return category['label'];
  }
  return null;
}

/// Chip / accent colour for a status, used by the My Orders list.
Color serviceRequestStatusColor(String status) {
  switch (status) {
    case 'completed':
      return const Color(0xFF00C853); // green
    case 'in_progress':
      return const Color(0xFF2979FF); // blue
    case 'nearing_completion':
      return const Color(0xFFFF9100); // amber
    case 'hero_assigned':
      return const Color(0xFFFF4FA3); // pink
    case 'admin_review':
      return const Color(0xFFFF6D00); // deep orange
    case 'pending':
    default:
      return const Color(0xFF9999BB); // muted
  }
}
