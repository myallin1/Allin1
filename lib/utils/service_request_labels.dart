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
