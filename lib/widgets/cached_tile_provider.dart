// lib/widgets/cached_tile_provider.dart
// ================================================================
// Persistent, offline-first map tile caching for ALL flutter_map
// TileLayers in the app.
// ================================================================
// FIX (Aug 28 2026 — Nizam: "image and map yethume once open panita
// again network recall pogama full and full offline la irukanum").
//
// THE GAP THIS CLOSES
// Cloudinary photos were already offline-safe on both platforms
// (cached_network_image on native, the cache-first branch in
// web/pwa_fallback_sw.js on web). MAP TILES were not, on either:
//
//   * native — every TileLayer resolved to a bare `NetworkImage(url)`.
//     NetworkImage caches into Flutter's in-memory ImageCache only.
//     That cache is capped (~100MB / 1000 entries), is evicted under
//     pressure, and is thrown away completely when the process dies.
//     So every cold start, and often every scroll away and back,
//     re-downloaded tiles the user had already paid for — and with no
//     network the map was simply blank.
//
//   * web — tile hosts fell through pwa_fallback_sw.js's
//     `url.origin !== self.location.origin` bail-out and were never
//     cached at all. Fixed in that file in the same change.
//
// WHY A DEDICATED CacheManager
// The default flutter_cache_manager instance keeps 200 objects for 30
// days. A single map screen can easily reference more than 200 tiles
// across a couple of pan/zoom gestures, so sharing the default bucket
// would have the tiles evicting each other AND evicting the Cloudinary
// product images that share it — trading one cache miss for another.
// Tiles get their own bucket, sized for the job.
//
// A tile at a given z/x/y is immutable content at a versionless URL, so
// a long stalePeriod is correct here, not a risk: there is no "newer"
// version of the same tile to miss.
//
// WEB BEHAVIOUR
// On web this deliberately falls back to a plain NetworkImage. The
// service worker already provides cache-first tile storage there (a
// real Cache Storage bucket, shared with the installed PWA and
// surviving reloads), and layering flutter_cache_manager on top would
// duplicate every tile into IndexedDB for no benefit. One cache per
// platform, each the right one for that platform.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_map/flutter_map.dart';

/// Shared on-disk cache for map tiles, kept separate from the default
/// image cache so tiles and product photos never evict one another.
class MapTileCacheManager {
  static const key = 'allin1MapTileCache';

  static final CacheManager instance = CacheManager(
    Config(
      key,
      // Tiles are immutable per z/x/y — see the file header. A year is
      // not a staleness risk, it is simply "keep it until the user
      // clears app data".
      stalePeriod: const Duration(days: 365),
      // Erode-sized coverage at the zoom levels the booking screens
      // actually use, with generous headroom. Each OSM tile is ~15-30KB,
      // so 4000 objects is roughly 60-120MB worst case — in line with
      // what any map app reserves, and self-limiting because the app
      // only ever renders one city.
      maxNrOfCacheObjects: 4000,
    ),
  );
}

/// A [TileProvider] that stores every tile it fetches on disk, so a tile
/// is downloaded exactly once per device and is then available instantly
/// and offline forever after.
///
/// [headers] is passed through unchanged. It matters: OSM's tile usage
/// policy requires an identifying `User-Agent`, and requests without one
/// are silently dropped — the cause of a previously-fixed blank-map bug.
/// Browsers forbid setting `User-Agent` from page code, which is one
/// more reason the web path below stays on a plain [NetworkImage].
class CachedTileProvider extends TileProvider {
  /// OSM's tile usage policy requires an identifying User-Agent and
  /// silently drops requests without one. flutter_map's built-in
  /// NetworkTileProvider derives this from `TileLayer.userAgentPackageName`;
  /// a custom TileProvider bypasses that machinery entirely, so any call
  /// site that swaps in this class MUST carry the header itself or it
  /// reintroduces the previously-fixed blank-map bug. Defaulted here
  /// rather than left to each call site to remember.
  static const Map<String, String> defaultTileHeaders = {
    'User-Agent': 'Allin1SuperApp/1.0 (Erode Tamil Nadu; contact via app)',
  };

  /// `headers` is inherited from [TileProvider] (non-nullable there), so
  /// it is populated through `super` rather than redeclared. Pass
  /// [headers] only to override; the OSM-compliant default is used
  /// otherwise. Web deliberately gets an EMPTY map — browsers forbid
  /// page code from setting User-Agent, and attempting it throws and
  /// kills the tile fetch outright.
  CachedTileProvider({Map<String, String>? headers})
      : super(
          headers: kIsWeb
              ? const <String, String>{}
              : (headers ?? defaultTileHeaders),
        );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return imageProviderFor(getTileUrl(coordinates, options), headers);
  }

  /// Shared by this provider and by the app's own dynamic (multi-source)
  /// tile provider in allin1_map_widget.dart, so both platforms make the
  /// same decision in exactly one place.
  static ImageProvider imageProviderFor(
    String url,
    Map<String, String>? headers,
  ) {
    if (kIsWeb) {
      // Service worker owns caching on web — see the file header.
      return NetworkImage(url, headers: headers);
    }
    return CachedNetworkImageProvider(
      url,
      headers: headers,
      cacheManager: MapTileCacheManager.instance,
    );
  }
}
