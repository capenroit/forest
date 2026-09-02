import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widget/map_basemap.dart';
import 'offline_sync_service.dart';

/// Persistent on-disk caching for the dashboard map tiles.
///
/// flutter_map 8.2+ already caches tiles itself, but two of its defaults work
/// against us here:
///
///  * it stores them in the OS *cache* directory, which Android is free to
///    purge whenever it wants storage back, and
///  * it takes tile freshness from each response's `Cache-Control` header.
///    Esri and OSM both send roughly a week, so once that lapses every tile
///    costs a revalidation round-trip on every app open — exactly the
///    "reloads every time" behaviour we want gone.
///
/// [configure] fixes both: it moves the cache into the app's support
/// directory (only cleared by an explicit "Clear data" or an uninstall) and
/// pins a long freshness age so a cached tile is served straight off disk
/// without touching the network.
///
/// [seedPanayIslandOnFirstRun] then warms that cache once, on the first
/// launch, so the map is already populated the first time the user opens the
/// dashboard.
class MapTileCacheService {
  MapTileCacheService._();

  /// Bumping this re-seeds on the next launch — do it if the default basemap
  /// or the seeded area/zoom range changes.
  static const String _seededKey = 'map_tiles_seeded_panay_v1';

  /// How long a cached tile is served without revalidating against the
  /// server. Basemap imagery changes on a scale of months at most, and a
  /// stale tile is a cosmetic problem, not a correctness one.
  static const Duration _freshAge = Duration(days: 90);

  /// Hard ceiling on the cache. The seed below is far smaller than this; the
  /// headroom is for tiles cached on demand as users zoom into their sites.
  static const int _maxCacheBytes = 512 * 1024 * 1024;

  // ─── Seeded region: Panay Island ────────────────────────────────────────
  //
  // Covers all four provinces (Aklan, Antique, Capiz, Iloilo) plus a small
  // coastal margin, and reaches just far enough north to include Boracay.

  static const double _panayMinLat = 10.30;
  static const double _panayMaxLat = 12.00;
  static const double _panayMinLon = 121.80;
  static const double _panayMaxLon = 123.35;

  /// The dashboard opens at zoom 9.8, so this range covers the initial view
  /// plus a few steps of zooming in over the whole island (~550 tiles per
  /// tile layer, a handful of MB).
  ///
  /// Seeding deeper than this is not practical — Panay at zoom 16 is
  /// hundreds of thousands of tiles — so site-level zoom levels are left to
  /// cache on demand the first time someone actually looks at them.
  static const int _minSeedZoom = 9;
  static const int _maxSeedZoom = 12;

  /// Safety net in case the bounds or zoom range are widened later without
  /// the tile-count implications being worked through.
  static const int _maxSeedTiles = 3000;

  /// Simultaneous tile downloads during seeding. Deliberately modest — this
  /// runs in the background behind the login screen and should not starve
  /// the Supabase calls happening at the same time.
  static const int _seedConcurrency = 6;

  /// Disk caching needs `dart:io`, so it is native-only. On web the browser's
  /// own HTTP cache already covers this.
  static bool get isSupported => !kIsWeb;

  static bool _configured = false;

  /// Points flutter_map's built-in tile cache at a directory that survives
  /// Android reclaiming space, and pins tile freshness to [_freshAge].
  ///
  /// Must run before the first tile is requested — the caching provider is a
  /// singleton whose configuration is fixed by whoever creates it first, and
  /// [NetworkTileProvider] will create a default one otherwise.
  static Future<void> configure() async {
    if (!isSupported || _configured) return;
    _configured = true;

    try {
      final dir = await getApplicationSupportDirectory();
      BuiltInMapCachingProvider.getOrCreateInstance(
        cacheDirectory: dir.path,
        maxCacheSize: _maxCacheBytes,
        overrideFreshAge: _freshAge,
      );
    } catch (e) {
      // A cache we couldn't configure is not worth failing startup over —
      // flutter_map falls back to its own default provider.
      debugPrint('[map cache] configure failed: $e');
      _configured = false;
    }
  }

  /// Downloads the Panay Island basemap tiles once, on the first run.
  ///
  /// Safe to call unconditionally on every launch: it returns immediately
  /// once seeding has succeeded. Fire-and-forget — it never blocks the UI,
  /// and if the device is offline it simply leaves the flag unset and tries
  /// again next launch.
  static Future<void> seedPanayIslandOnFirstRun({
    MapBasemap basemap = MapBasemap.light,
  }) async {
    if (!isSupported || !Platform.isAndroid) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seededKey) ?? false) return;

    if (!await OfflineSyncService.hasInternetConnection()) return;

    await configure();
    final cache = BuiltInMapCachingProvider.getOrCreateInstance();
    if (!cache.isSupported) return;

    final urls = _panayTileUrls(basemap);
    debugPrint('[map cache] seeding ${urls.length} Panay tiles');

    final client = http.Client();
    var failures = 0;
    try {
      final queue = urls.iterator;
      Future<void> worker() async {
        while (true) {
          final String url;
          // `iterator` is not concurrency-safe across awaits, so pull the
          // next item synchronously before yielding.
          if (!queue.moveNext()) return;
          url = queue.current;

          if (!await _fetchIntoCache(client, cache, url)) failures++;
        }
      }

      await Future.wait(
        List.generate(_seedConcurrency, (_) => worker()),
      );
    } finally {
      client.close();
    }

    // Don't record a seed that mostly failed — a flaky first launch should
    // get another attempt rather than leaving the map permanently unseeded.
    if (failures > urls.length ~/ 4) {
      debugPrint('[map cache] seed aborted: $failures/${urls.length} failed');
      return;
    }

    // putTile hands the write to a background isolate without awaiting it;
    // give those writes a moment to land before declaring the seed done.
    await Future<void>.delayed(const Duration(seconds: 2));
    await prefs.setBool(_seededKey, true);
    debugPrint('[map cache] seeded ${urls.length - failures}/${urls.length}');
  }

  /// Fetches [url] and stores it, unless a fresh copy is already cached.
  /// Returns whether the tile ended up in the cache.
  static Future<bool> _fetchIntoCache(
    http.Client client,
    MapCachingProvider cache,
    String url,
  ) async {
    try {
      final existing = await cache.getTile(url);
      if (existing != null && !existing.metadata.isStale) return true;
    } catch (_) {
      // Corrupt or unreadable entry — fall through and overwrite it.
    }

    try {
      final response = await client.get(
        Uri.parse(url),
        headers: const {'User-Agent': 'com.example.envi_app'},
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return false;
      }

      await cache.putTile(
        url: url,
        // staleAt is recomputed from `overrideFreshAge` on write, but the
        // field is required, so give it the same value here.
        metadata: CachedMapTileMetadata(
          staleAt: DateTime.timestamp().add(_freshAge),
          lastModified: null,
          etag: response.headers['etag'],
        ),
        bytes: response.bodyBytes,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Every tile URL covering Panay Island, for each layer of [basemap],
  /// across [_minSeedZoom]..[_maxSeedZoom].
  static List<String> _panayTileUrls(MapBasemap basemap) {
    final templates = basemapUrlTemplates(basemap)
        // {s}/{r} placeholders can't be resolved the way flutter_map would,
        // and a mismatched URL would just cache under the wrong key.
        .where((t) => !t.contains('{s}') && !t.contains('{r}'))
        .toList();

    final maxNativeZoom = basemapMaxNativeZoom(basemap);
    final maxZoom = math.min(_maxSeedZoom, maxNativeZoom);

    final urls = <String>[];
    for (var z = _minSeedZoom; z <= maxZoom; z++) {
      final xMin = _lonToTileX(_panayMinLon, z);
      final xMax = _lonToTileX(_panayMaxLon, z);
      // Tile Y runs north to south, so the max latitude gives the min Y.
      final yMin = _latToTileY(_panayMaxLat, z);
      final yMax = _latToTileY(_panayMinLat, z);

      for (var x = xMin; x <= xMax; x++) {
        for (var y = yMin; y <= yMax; y++) {
          for (final template in templates) {
            if (urls.length >= _maxSeedTiles) return urls;
            urls.add(
              template
                  .replaceAll('{z}', '$z')
                  .replaceAll('{x}', '$x')
                  .replaceAll('{y}', '$y'),
            );
          }
        }
      }
    }
    return urls;
  }

  static int _lonToTileX(double lon, int z) =>
      ((lon + 180.0) / 360.0 * (1 << z)).floor();

  static int _latToTileY(double lat, int z) {
    final latRad = lat * math.pi / 180.0;
    final n =
        (1.0 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
            2.0;
    return (n * (1 << z)).floor();
  }
}
