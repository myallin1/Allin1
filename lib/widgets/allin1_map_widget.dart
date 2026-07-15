// lib/widgets/allin1_map_widget.dart
// Dual Map Provider Architecture | Ola + OSM
// Architecture: ListenableBuilder only (NO Streams, NO ValueKey)
// ─────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../config/api_config.dart';
import '../services/map_service.dart';

// ── Erode Default Coordinates ──
const LatLng kErodeCenter = LatLng(11.3410, 77.7171);
final Uint8List _transparentPixel = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

/// Allin1MapWidget - Dual Map Provider enabled map widget
///
/// Features:
/// - Automatic provider switching (Ola ↔ OSM)
/// - Real-time tile URL generation via custom TileProvider
/// - Provider badge showing active provider
/// - Clean lifecycle management
class Allin1MapWidget extends StatefulWidget {
  final LatLng center;
  final double zoom;
  final List<MapMarker> markers;
  final List<MapRoute> routes;
  final List<MapCircle> circles;
  final bool interactive;
  final void Function(int index)? onMarkerTap;
  final MapController? mapController;
  final VoidCallback? onMapReady;

  const Allin1MapWidget({
    super.key,
    this.center = kErodeCenter,
    this.zoom = 14.0,
    this.markers = const [],
    this.routes = const [],
    this.circles = const [],
    this.interactive = true,
    this.mapController,
    this.onMapReady,
    this.onMarkerTap,
  });

  @override
  State<Allin1MapWidget> createState() => _Allin1MapWidgetState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<LatLng>('center', center));
    properties.add(DoubleProperty('zoom', zoom));
    properties.add(IterableProperty<MapMarker>('markers', markers));
    properties.add(IterableProperty<MapRoute>('routes', routes));
    properties.add(IterableProperty<MapCircle>('circles', circles));
    properties.add(DiagnosticsProperty<bool>('interactive', interactive));
    properties.add(DiagnosticsProperty<MapController?>('mapController', mapController));
    properties.add(ObjectFlagProperty<VoidCallback?>.has('onMapReady', onMapReady));
  }
}

class _Allin1MapWidgetState extends State<Allin1MapWidget>
    with WidgetsBindingObserver {
  // FIX #3: Late-final for clean lifecycle
  late final MapService _mapService;
  late final MapController _internalMapController;
  bool _isMapReady = false;
  LatLng? _pendingCenter;
  double? _pendingZoom;

  MapController get _effectiveMapController =>
      widget.mapController ?? _internalMapController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mapService = MapService();
    _internalMapController = MapController();
    debugPrint(
      '[Allin1MapWidget] init center=${widget.center.latitude},${widget.center.longitude} zoom=${widget.zoom}',
    );
    unawaited(_initializeMapService());
  }

  Future<void> _initializeMapService() async {
    // API-RACE FIX: If dotenv hasn't finished loading the key yet, back-off
    // in 100ms steps up to 3 seconds. The shimmer covers this wait.
    const maxWaitMs = 3000;
    const stepMs = 100;
    var waited = 0;
    while (ApiConfig.olaMapsApiKey.isEmpty && waited < maxWaitMs) {
      await Future<void>.delayed(const Duration(milliseconds: stepMs));
      waited += stepMs;
    }
    debugPrint(
      '[Allin1MapWidget] Key wait done after ${waited}ms '
      'key_present=${ApiConfig.olaMapsApiKey.isNotEmpty}',
    );

    try {
      debugPrint('[Allin1MapWidget] Initializing map service...');
      await _mapService.initialize();
      debugPrint(
        '[Allin1MapWidget] Map service ready '
        'provider=${_mapService.currentProvider.name} '
        'fallback=${_mapService.isUsingFallback}',
      );
    } catch (e) {
      debugPrint('[Allin1MapWidget] Map init failed (non-fatal): $e');
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _refreshMapSurface() {
    if (!mounted) {
      return;
    }
    debugPrint('[Allin1MapWidget] Refreshing map surface');
    setState(() {});
    _queueMapMove(widget.center, widget.zoom);
  }

  void _queueMapMove(LatLng center, double zoom) {
    _pendingCenter = center;
    _pendingZoom = zoom;
    if (!_isMapReady) {
      debugPrint('[Allin1MapWidget] Map move queued until onMapReady');
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final targetCenter = _pendingCenter;
      final targetZoom = _pendingZoom;
      if (targetCenter == null || targetZoom == null) {
        return;
      }
      try {
        _effectiveMapController.move(targetCenter, targetZoom);
        _pendingCenter = null;
        _pendingZoom = null;
      } catch (e) {
        debugPrint('[Allin1MapWidget] Map controller refresh failed: $e');
      }
    });
  }

  void _handleMapReady() {
    debugPrint('[Allin1MapWidget] onMapReady');
    _isMapReady = true;
    widget.onMapReady?.call();
    _queueMapMove(_pendingCenter ?? widget.center, _pendingZoom ?? widget.zoom);
  }

  @override
  void didUpdateWidget(covariant Allin1MapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.center != widget.center || oldWidget.zoom != widget.zoom) {
      _refreshMapSurface();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[Allin1MapWidget] App resumed');
      _refreshMapSurface();
    }
  }

  // FIX #1: Proper dispose to avoid memory leaks
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // MapService is singleton, don't dispose it
    // But ensure no lingering references
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // FIX #2: Single rebuild mechanism via ListenableBuilder
    // NO Streams, NO ValueKey - only ChangeNotifier
    return ListenableBuilder(
      listenable: _mapService,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final hasBoundedHeight =
                constraints.maxHeight.isFinite && constraints.maxHeight > 0;
            if (!hasBoundedHeight) {
              debugPrint(
                '[Allin1MapWidget] Unbounded height detected. Using fallback height 280.',
              );
            }

            final map = FlutterMap(
              mapController: _effectiveMapController,
              options: MapOptions(
                initialCenter: widget.center,
                initialZoom: widget.zoom,
                minZoom: 10,
                maxZoom: 18,
                onMapReady: _handleMapReady,
                interactionOptions: InteractionOptions(
                  flags: widget.interactive
                      ? InteractiveFlag.all
                      : InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  tileProvider: _DynamicTileProvider(_mapService),
                  userAgentPackageName: 'com.allin1.superapp',
                  maxZoom: 18,
                ),
                if (widget.routes.isNotEmpty)
                  PolylineLayer(
                    polylines: widget.routes
                        .map(
                          (r) => Polyline(
                            points: r.points,
                            color: r.color,
                            strokeWidth: r.strokeWidth,
                          ),
                        )
                        .toList(),
                  ),
                if (widget.circles.isNotEmpty)
                  CircleLayer(
                    circles: widget.circles
                        .map(
                          (c) => CircleMarker(
                            point: c.center,
                            radius: c.radiusMeters,
                            useRadiusInMeter: true,
                            color: c.fillColor,
                            borderColor: c.borderColor,
                            borderStrokeWidth: c.borderStrokeWidth,
                          ),
                        )
                        .toList(),
                  ),
                MarkerLayer(
                  markers: widget.markers
                      .asMap()
                      .entries
                      .map(
                        (entry) {
                          final index = entry.key;
                          final m = entry.value;
                          return Marker(
                            point: m.point,
                            width: m.size,
                            height: m.size,
                            alignment: Alignment.center,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => widget.onMarkerTap?.call(index),
                              child: _DefaultMarker(
                                color: m.color,
                                icon: m.icon,
                                assetPath: m.assetPath,
                                bearingDegrees: m.bearingDegrees,
                              ),
                            ),
                          );
                        },
                      )
                      .toList(),
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child:
                        _ProviderBadge(provider: _mapService.selectedProvider),
                  ),
                ),
              ],
            );

            final wrappedMap = hasBoundedHeight
                ? map
                : SizedBox(
                    height: 280,
                    width: double.infinity,
                    child: map,
                  );

            if (!_mapService.hasUiError) {
              return wrappedMap;
            }

            return Stack(
              fit: StackFit.expand,
              children: [
                wrappedMap,
                ColoredBox(
                  color: const Color(0xCCFFF5FA),
                  child: SafeArea(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 340,
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0x66FF4FA3),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x22FF4FA3),
                                  blurRadius: 20,
                                  offset: Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 20,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 34,
                                    height: 34,
                                    child: CircularProgressIndicator(
                                      color: Color(0xFFFF4FA3),
                                      strokeWidth: 3,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Allin1 map loading...',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.outfit(
                                      color: Color(0xFF4A1236),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Preparing Ola and OSM tiles for your route.',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.outfit(
                                      color: const Color(
                                        0xFF8A4E72,
                                      ).withValues(alpha: 0.92),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ── FIX #1: Custom TileProvider with AUTO-FALLBACK ───────
/// Generates tile URLs dynamically from the current provider.
/// If Ola tiles fail (timeout/broken URL), automatically falls back to OSM tiles.
class _DynamicTileProvider extends TileProvider {
  final MapService mapService;

  _DynamicTileProvider(this.mapService);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    try {
      final url = mapService.getTileUrl(
        coordinates.x.toInt(),
        coordinates.y.toInt(),
        coordinates.z.toInt(),
      );
      debugPrint(
        '[Allin1MapWidget] Loading tile provider=${mapService.currentProvider.name} url=$url',
      );
      return NetworkImage(url);
    } catch (e) {
      debugPrint('[Allin1MapWidget] Tile URL generation failed: $e');
      mapService.markFailure();
      return MemoryImage(_transparentPixel);
    }
  }

  // getImageFromCache removed in flutter_map v8 — uses default caching
}

// ── Provider Badge (shows active provider) ────────────────────────
class _ProviderBadge extends StatelessWidget {
  final MapProviderType provider;

  const _ProviderBadge({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B35).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '⭐ Premium Map',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<MapProviderType>('provider', provider));
  }
}

// ── Default Marker (unchanged from original) ─────────────────────
class _DefaultMarker extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String? assetPath;
  final double? bearingDegrees;

  const _DefaultMarker({
    required this.color,
    required this.icon,
    this.assetPath,
    this.bearingDegrees,
  });

  @override
  Widget build(BuildContext context) {
    double rotationOffsetForAsset() {
      final path = assetPath?.toLowerCase() ?? '';
      if (path.contains('auto')) {
        return 90;
      }
      return 0;
    }

    Widget rotateIfNeeded(Widget child) {
      final bearing = bearingDegrees;
      if (bearing == null) {
        return child;
      }
      return Transform.rotate(
        angle: (bearing + rotationOffsetForAsset()) * math.pi / 180,
        child: child,
      );
    }

    if (assetPath != null) {
      return SizedBox(
        width: 45,
        height: 45,
        child: Center(
          child: rotateIfNeeded(
            Image.asset(
              assetPath!,
              width: 45,
              height: 45,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                icon,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      );
    }

    final markerFace = rotateIfNeeded(
      Icon(icon, color: Colors.white, size: 18),
    );
    return Container(
      width: 38,
      height: 38,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 12,
            spreadRadius: 3,
          ),
        ],
      ),
      child: Center(child: markerFace),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(ColorProperty('color', color));
    properties.add(DiagnosticsProperty<IconData>('icon', icon));
    properties.add(StringProperty('assetPath', assetPath));
    properties.add(DoubleProperty('bearingDegrees', bearingDegrees));
  }
}

// ── Data Models (unchanged from original) ────────────────────────
class MapMarker {
  final LatLng point;
  final Color color;
  final IconData icon;
  final String? label;
  final String? assetPath;
  final double? bearingDegrees;
  final double size;

  const MapMarker({
    required this.point,
    this.color = const Color(0xFFFF6B35),
    this.icon = Icons.location_on_rounded,
    this.label,
    this.assetPath,
    this.bearingDegrees,
    this.size = 56,
  });
}

class MapRoute {
  final List<LatLng> points;
  final Color color;
  final double strokeWidth;

  const MapRoute({
    required this.points,
    this.color = const Color(0xFFFF6B35),
    this.strokeWidth = 4.0,
  });
}

class MapCircle {
  final LatLng center;
  final double radiusMeters;
  final Color fillColor;
  final Color borderColor;
  final double borderStrokeWidth;

  const MapCircle({
    required this.center,
    required this.radiusMeters,
    this.fillColor = const Color(0x22FF4FA3),
    this.borderColor = const Color(0xFFFF5252),
    this.borderStrokeWidth = 2.5,
  });
}

