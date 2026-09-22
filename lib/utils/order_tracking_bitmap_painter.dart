// ================================================================
// order_tracking_bitmap_painter.dart — Phase 3 of the live-order-
// tracking-notification feature (branch: feature/live-order-tracking-
// notification)
// ================================================================
// Renders the Blinkit-style "icon moving along a path" image shown in
// the notification's BigPictureStyle, entirely in Dart via dart:ui —
// no native Android RemoteViews/Kotlin code, no new image assets. Pure
// vector shapes (a road line + a circular vehicle marker), which keeps
// this self-contained and avoids depending on any icon asset that
// might not exist for every requestType.
//
// WHY NO REAL MAP / GPS-ACCURATE PATH
// hero/customer lat-lng are real GPS coordinates, but projecting them
// onto an actual road-following curve needs a routing API call per
// frame — real cost, real latency, and a new external dependency this
// feature doesn't need. Instead this draws a simple S-curve between a
// fixed start and end point on the canvas, and positions the icon
// along that curve using [progressFraction] — a 0..1 value derived
// from how far along the hero actually is (straight-line distance
// hero-to-destination vs. the total pickup-to-destination distance).
// The visual reads as "your rider is X% of the way there," which is
// the actual information a customer wants — it was never meant to be
// a literal live map (service_request_live_map_screen.dart already
// exists for that).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/tracking_snapshot.dart';

class OrderTrackingBitmapPainter {
  OrderTrackingBitmapPainter._();

  static const int width = 700;
  static const int height = 300;

  /// Renders the current tracking state as a PNG. Returns null (never
  /// throws) if anything about the render fails — a failed bitmap must
  /// never take down the notification update; the caller falls back to
  /// a plain text notification instead.
  static Future<Uint8List?> render(TrackingSnapshot snapshot) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      );

      _paintBackground(canvas);
      _paintPath(canvas);
      _paintIcon(canvas, snapshot);

      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) return null;
      return byteData.buffer.asUint8List();
    } catch (e) {
      debugPrint('[OrderTrackingBitmapPainter] render failed (non-fatal): $e');
      return null;
    }
  }

  static void _paintBackground(Canvas canvas) {
    final paint = Paint()..color = const Color(0xFF12121E);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      paint,
    );
  }

  // The fixed S-curve the icon travels along — same start/end points
  // regardless of requestType, so _pointOnPath below has one shape to
  // reason about.
  static Path _pathShape() {
    final path = Path();
    final startY = height * 0.5;
    path.moveTo(40, startY);
    path.cubicTo(
      width * 0.35, startY - 60,
      width * 0.65, startY + 60,
      width - 40, startY,
    );
    return path;
  }

  static void _paintPath(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0xFF2ECC71)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(_pathShape(), paint);

    // Start/end dots, same green-line convention the in-app tracking
    // timeline already uses elsewhere in this codebase.
    final dotPaint = Paint()..color = const Color(0xFF2ECC71);
    canvas.drawCircle(Offset(40, height * 0.5), 8, dotPaint);
    final destPaint = Paint()..color = const Color(0xFFFF4FA3);
    canvas.drawCircle(Offset(width - 40, height * 0.5), 8, destPaint);
  }

  /// Walks the cubic path's metric to find the point at [t] (0..1)
  /// along its actual arc length — NOT the raw Bezier parameter, which
  /// would bunch the icon unevenly near the curve's bends.
  static Offset _pointOnPath(double t) {
    final metrics = _pathShape().computeMetrics().toList();
    if (metrics.isEmpty) return const Offset(40, height * 0.5);
    final metric = metrics.first;
    final clampedT = t.clamp(0.0, 1.0);
    final tangent = metric.getTangentForOffset(metric.length * clampedT);
    return tangent?.position ?? const Offset(40, height * 0.5);
  }

  /// 0..1 progress along the path for the current snapshot. Prefers
  /// real GPS-derived progress (straight-line hero-to-destination
  /// distance vs. a remembered starting distance) when both hero and
  /// destination coordinates are known; falls back to a fixed
  /// per-phase estimate otherwise — this is a deliberately rough
  /// indicator, not a promised ETA (see this file's header).
  static double _progressFraction(TrackingSnapshot snapshot) {
    switch (snapshot.phase) {
      case TrackingPhase.waiting:
        return 0.0;
      case TrackingPhase.assigned:
        return 0.15;
      case TrackingPhase.enRoute:
        if (snapshot.hasLiveLocation &&
            snapshot.destinationLat != null &&
            snapshot.destinationLng != null) {
          // No remembered "starting distance" is threaded through yet
          // (would need the pickup point, which not every requestType
          // carries) — approximated instead via how CLOSE the hero
          // currently is on a fixed 0-3km scale, clamped. Rougher than
          // a true fraction-of-total-trip, but still visibly moves the
          // icon forward as the hero gets nearer, and never needs a
          // remembered "start" state the notification would lose on
          // an app restart.
          final distanceKm = _distanceKm(
            snapshot.heroLat!,
            snapshot.heroLng!,
            snapshot.destinationLat!,
            snapshot.destinationLng!,
          );
          final closeness = 1.0 - (distanceKm / 3.0).clamp(0.0, 1.0);
          return 0.25 + (closeness * 0.55); // 0.25..0.80 while en route
        }
        return 0.5;
      case TrackingPhase.nearingCompletion:
        return 0.9;
      case TrackingPhase.completed:
        return 1.0;
      case TrackingPhase.cancelled:
        return 0.0;
    }
  }

  static double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);

  static void _paintIcon(Canvas canvas, TrackingSnapshot snapshot) {
    final t = _progressFraction(snapshot);
    final position = _pointOnPath(t);

    // Soft glow, then the vehicle marker itself — a filled circle with
    // a simple direction wedge rather than a bitmap asset (see this
    // file's header for why no image assets).
    final glowPaint = Paint()
      ..color = const Color(0xFFFF4FA3).withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(position, 26, glowPaint);

    final bodyPaint = Paint()..color = const Color(0xFFFF4FA3);
    canvas.drawCircle(position, 18, bodyPaint);

    final iconPaint = Paint()..color = Colors.white;
    final glyph = _glyphFor(snapshot.requestType);
    canvas.drawPath(glyph.shift(position - const Offset(8, 8)), iconPaint);
  }

  /// A minimal 16x16 vector glyph per vertical — deliberately crude
  /// (a couple of rectangles/triangles), just enough to visually
  /// distinguish "food" from "ride" from "grocery" at notification
  /// thumbnail size without needing an icon font or asset file.
  static Path _glyphFor(String requestType) {
    switch (requestType) {
      case 'bike_taxi':
      case 'car_taxi':
        // Simple vehicle silhouette: body + two wheel dots.
        final path = Path()
          ..addRRect(RRect.fromRectAndRadius(
            const Rect.fromLTWH(1, 6, 14, 5),
            const Radius.circular(2),
          ))
          ..addOval(const Rect.fromLTWH(2, 10, 4, 4))
          ..addOval(const Rect.fromLTWH(10, 10, 4, 4));
        return path;
      case 'grocery_order':
        // Simple bag silhouette.
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
            const Rect.fromLTWH(2, 5, 12, 10),
            const Radius.circular(2),
          ))
          ..moveTo(5, 5)
          ..lineTo(5, 2)
          ..lineTo(11, 2)
          ..lineTo(11, 5);
      default:
        // Food: a simple round plate/box.
        return Path()..addOval(const Rect.fromLTWH(2, 2, 12, 12));
    }
  }
}
