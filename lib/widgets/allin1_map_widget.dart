// lib/widgets/allin1_map_widget.dart
// Dual Map Provider Architecture | Ola + OSM
// Architecture: ListenableBuilder only (NO Streams, NO ValueKey)
// ─────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../config/api_config.dart';
import '../services/map_service.dart';
import '../services/ola_maps_provider.dart';

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

// Ola Vector Tiles (real MapLibre-style rendering) -- surgical addition.
// Cached at module level so the style is fetched from Ola ONCE per app
// session and reused by every map screen (taxi, food, hero, etc.), not
// re-fetched on every single screen open. If it ever fails (bad key, Ola
// quota/limit genuinely exhausted, network error), the cached Future
// resolves to null and stays that way for the rest of the session -- every
// map screen then just renders the existing OSM TileLayer below, exactly
// as it always has. This is a pure fallback: the OSM path is completely
// untouched.
Future<vmt.Style?>? _olaVectorStyleFuture;

Future<vmt.Style?> _loadOlaVectorStyle() {
  return _olaVectorStyleFuture ??= () async {
    // REGRESSION FIX (per Nizam's report: Ola never opens, every session,
    // even once the key is confirmed present) -- this used to check
    // ApiConfig.olaMapsApiKey immediately on the very first call. On web
    // especially, dotenv is still loading at that exact moment (same race
    // _initializeMapService() below already guards against with this same
    // wait loop), so the key read as empty, vectorStyleUriFor() returned
    // null, and because this Future is cached at module level, that
    // "no key yet" result got permanently frozen in as "Ola failed" for
    // the rest of the session -- every later map screen kept rendering
    // OSM even after the key had long since loaded. Wait for it first.
    const maxWaitMs = 3000;
    const stepMs = 100;
    var waited = 0;
    while (ApiConfig.olaMapsApiKey.isEmpty && waited < maxWaitMs) {
      await Future<void>.delayed(const Duration(milliseconds: stepMs));
      waited += stepMs;
    }

    final key = ApiConfig.olaMapsApiKey.trim();
    final uri = OlaMapsProvider.vectorStyleUriFor(key);
    if (uri == null) {
      debugPrint(
        '[Allin1MapWidget] Ola vector style skipped (no valid key after '
        '${waited}ms wait)',
      );
      return null;
    }
    try {
      final style = await _buildOlaStyleManually(key);
      debugPrint('[Allin1MapWidget] Ola vector style loaded OK');
      return style;
    } catch (e) {
      debugPrint(
        '[Allin1MapWidget] Ola vector style load FAILED, staying on OSM: $e',
      );
      return null;
    }
  }();
}

// REGRESSION FIX (per Nizam's console screenshot: 401 Unauthorized on
// https://api.olamaps.io/tiles/vector/v1/data/planet.json, no query string
// at all): vmt.StyleReader's built-in api-key injection only replaces a
// LITERAL "{key}" placeholder token inside URLs -- that's a convention some
// providers (Stadia Maps, MapTiler) bake into their style.json responses so
// this package can substitute the caller's key. Ola's style.json does NOT
// contain that token in its `sources` entries (confirmed by reading
// StyleReader's actual source on pub.dev/GitHub for this exact package
// version) -- so every nested source/tile request StyleReader made after
// the initial (correctly-keyed) style.json fetch went out with NO api_key
// at all, and Ola correctly 401'd them.
//
// Fix: don't use vmt.StyleReader for Ola. Fetch + walk the style JSON
// ourselves, appending `?api_key=...` (or `&api_key=...`) to every source
// URL we actually use, exactly matching Ola's own documented query-param
// auth convention -- then hand the theme JSON to vector_tile_renderer's
// ThemeReader (the same class StyleReader itself delegates to) and build
// TileProviders by hand. Sprites are intentionally skipped here (Ola's
// style has no `{key}`-token sprite URLs either, and base map rendering --
// roads, water, land, labels via device fonts -- doesn't depend on them);
// can be added later if POI icons are needed.
Future<vmt.Style> _buildOlaStyleManually(String apiKey) async {
  final styleUri = Uri.parse(
    'https://api.olamaps.io/tiles/vector/v1/styles/default-light-standard/style.json',
  ).replace(queryParameters: {'api_key': apiKey});

  final styleResp =
      await http.get(styleUri).timeout(const Duration(seconds: 10));
  if (styleResp.statusCode != 200) {
    throw 'Ola style fetch failed: HTTP ${styleResp.statusCode}';
  }
  final styleJson = json.decode(styleResp.body);
  if (styleJson is! Map<String, dynamic>) {
    throw 'Ola style response is not a JSON object';
  }

  final sourcesJson = styleJson['sources'];
  if (sourcesJson is! Map) {
    throw 'Ola style has no sources';
  }

  String withApiKey(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.queryParameters.containsKey('api_key')) {
      return url;
    }
    return '$url${url.contains('?') ? '&' : '?'}api_key=$apiKey';
  }

  final providerByName = <String, vmt.VectorTileProvider>{};
  for (final entry in sourcesJson.entries) {
    final sourceValue = entry.value;
    if (sourceValue is! Map) continue;
    final sourceTypeName = sourceValue['type'];
    vmt.TileProviderType? providerType;
    for (final candidate in vmt.TileProviderType.values) {
      if (candidate.name.replaceAll('_', '-') == sourceTypeName) {
        providerType = candidate;
        break;
      }
    }
    if (providerType == null) continue;

    Map<String, dynamic> resolvedSource;
    final referencedUrl = sourceValue['url'] as String?;
    if (referencedUrl != null) {
      // Some vector styles point at a separate TileJSON document instead
      // of embedding `tiles` directly -- fetch that too, with the same
      // api_key treatment, before we can find its tile URL template.
      final resolvedUri = Uri.tryParse(withApiKey(referencedUrl));
      if (resolvedUri == null) continue;
      final sourceResp =
          await http.get(resolvedUri).timeout(const Duration(seconds: 10));
      if (sourceResp.statusCode != 200) continue;
      final decoded = json.decode(sourceResp.body);
      if (decoded is! Map<String, dynamic>) continue;
      resolvedSource = decoded;
    } else {
      resolvedSource = Map<String, dynamic>.from(sourceValue);
    }

    final tiles = resolvedSource['tiles'];
    if (tiles is! List || tiles.isEmpty) continue;
    final tileUrl = withApiKey(tiles.first as String);
    providerByName[entry.key as String] = vmt.NetworkVectorTileProvider(
      type: providerType,
      urlTemplate: tileUrl,
      maximumZoom: (resolvedSource['maxzoom'] as num?)?.toInt() ?? 14,
      minimumZoom: (resolvedSource['minzoom'] as num?)?.toInt() ?? 1,
    );
  }

  if (providerByName.isEmpty) {
    throw 'Ola style has no usable vector sources';
  }

  return vmt.Style(
    name: styleJson['name'] as String?,
    theme: vtr.ThemeReader().read(styleJson),
    providers: vmt.TileProviders(providerByName),
  );
}

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

  /// Fires as the map is panned/zoomed, with the new centre point.
  /// Used by LocationPickerScreen to keep a fixed centre pin's address
  /// in sync while the customer drags the map underneath it.
  final void Function(LatLng center, bool gestureFinished)? onCenterChanged;

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
    this.onCenterChanged,
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
  vmt.Style? _olaStyle;

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
    unawaited(_loadOlaVectorStyleForThisScreen());
  }

  Future<void> _loadOlaVectorStyleForThisScreen() async {
    // Reuses the module-level cached Future -- on the very first map
    // screen this actually hits the network; every screen after that
    // (this session) gets the already-resolved style or null instantly.
    final style = await _loadOlaVectorStyle();
    if (mounted && style != null) {
      setState(() => _olaStyle = style);
    }
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
    // FIX (Nizam's back-button stutter report): wraps the whole map
    // subtree in a RepaintBoundary. _mapService is a global singleton
    // shared by EVERY Allin1MapWidget instance across the taxi/food/
    // hero flows -- without this, a repaint triggered by this map (tile
    // decode, marker move) forces Flutter to also re-examine unrelated
    // sibling widgets on the same screen (e.g. during a pop transition),
    // which is a common cause of a brief 1-2s jank right when leaving a
    // map-heavy screen. RepaintBoundary isolates this widget's paint
    // layer so that cost stays contained to the map itself. Pure
    // performance isolation -- no behavior change.
    return RepaintBoundary(
      child: _buildMap(context),
    );
  }

  Widget _buildMap(BuildContext context) {
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
                onPositionChanged: (camera, hasGesture) {
                  widget.onCenterChanged?.call(camera.center, !hasGesture);
                },
                interactionOptions: InteractionOptions(
                  flags: widget.interactive
                      ? InteractiveFlag.all
                      : InteractiveFlag.none,
                ),
              ),
              children: [
                // Ola Vector Tiles (real MapLibre-style rendering) when the
                // background-loaded style is ready AND Ola is still the
                // active provider (MapService already flips selectedProvider
                // to osm on genuine failure elsewhere). Decided BEFORE this
                // build runs -- never flashes OSM-then-Ola or vice versa,
                // per Nizam's explicit requirement. Any failure here just
                // means _olaStyle stayed null and the OSM TileLayer below
                // renders exactly as it always has -- zero change to that
                // path.
                if (_olaStyle != null &&
                    _mapService.selectedProvider == MapProviderType.ola)
                  vmt.VectorTileLayer(
                    theme: _olaStyle!.theme,
                    sprites: _olaStyle!.sprites,
                    tileProviders: _olaStyle!.providers,
                    // AGGRESSIVE PERSISTENT CACHE (per Nizam's cost-control
                    // request -- we're on Ola's free tier): the package
                    // already ships a real persistent byte-cache under the
                    // hood -- IndexedDB via idb_shim on Web/PWA
                    // (lib/src/cache/byte_storage_idb.dart), the device
                    // filesystem on Android/iOS
                    // (lib/src/cache/byte_storage_io.dart) -- keyed by tile
                    // coordinate + source, so a tile fetched once is
                    // reused across ENTIRE APP RESTARTS, not just this
                    // session, and any tile still within fileCacheTtl is
                    // served straight from that store with zero network
                    // call to Ola. Default was 30 days / 50MB; bumped to
                    // 180 days / 150MB so a hero/customer's regular
                    // Erode-area tiles realistically never re-fetch, while
                    // still bounding worst-case storage if someone
                    // explores many different cities. logCacheStats is
                    // debug-only so we can see hit/miss counts locally
                    // without spamming production consoles.
                    fileCacheTtl: const Duration(days: 180),
                    fileCacheMaximumSizeInBytes: 150 * 1024 * 1024,
                    logCacheStats: kDebugMode,
                  )
                else
                  TileLayer(
                    tileProvider: _DynamicTileProvider(_mapService),
                    userAgentPackageName: 'com.allin1.superapp',
                    maxZoom: 18,
                    // FIX (blank-map-tile audit, per Nizam's report): tile
                    // load failures used to be completely silent -- OSM's
                    // public tile.openstreetmap.org server can 403/429 a
                    // request with no visible error anywhere (Flutter's
                    // image pipeline just swallows it), leaving the map
                    // area permanently blank with zero feedback. This
                    // surfaces genuine tile failures to MapService so the
                    // existing "Allin1 map loading..." error overlay
                    // (gated on hasUiError) actually appears instead of a
                    // dead blank screen, and gives us a debug log to
                    // confirm whether OSM is actually rate-limiting us.
                    errorTileCallback: (tile, error, stackTrace) {
                      debugPrint(
                        '[Allin1MapWidget] Tile load FAILED provider='
                        '${_mapService.currentProvider.name} '
                        'coords=${tile.coordinates} error=$error',
                      );
                      _mapService.markFailure();
                    },
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

  // FIX (blank-map-tile audit, per Nizam's report): requests to
  // tile.openstreetmap.org (which is what every tile URL currently
  // resolves to -- see OlaMapsProvider.getTileUrl()/OSMProvider) went
  // out via a bare `NetworkImage(url)` with NO headers at all. Because a
  // custom TileProvider is supplied here, flutter_map's own mechanism
  // that turns TileLayer.userAgentPackageName into a real `User-Agent`
  // header never runs (that only happens inside flutter_map's built-in
  // NetworkTileProvider) -- so despite userAgentPackageName being set
  // above, tile requests were actually going out with no identifying
  // header at all. OSM's tile usage policy explicitly blocks/rate-limits
  // exactly this pattern (see operations.osmfoundation.org/policies/tiles),
  // which is the most likely reason the map area goes blank with no
  // error: OSM silently drops/403s unidentified high-volume requests.
  static const Map<String, String> _tileHeaders = {
    'User-Agent': 'Allin1SuperApp/1.0 (Erode Tamil Nadu; contact via app)',
  };

  // REGRESSION FIX (web crash report): browsers enforce the XHR/fetch
  // "forbidden header" list, which includes User-Agent -- it can never be
  // set by page JS, only by the browser itself. On Android/iOS this header
  // is what satisfies OSM's tile usage policy; on web, attempting to set it
  // throws "Refused to set unsafe header" and kills the tile fetch outright,
  // which is what was silently forcing every web map onto the OSM/Ola
  // failure path. Native platforms keep the header exactly as before; web
  // sends no custom headers (flutter_map/dart:html already identifies the
  // request via the browser's own real User-Agent).
  static Map<String, String>? get _platformTileHeaders =>
      kIsWeb ? null : _tileHeaders;

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
      return NetworkImage(url, headers: _platformTileHeaders);
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

