import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// The basemap styles offered on the dashboard maps.
///
/// All of these are keyless raster tile services — CartoDB's
/// basemaps.cartocdn.com now stamps an "API KEY REQUIRED" watermark on its
/// free tiles, so it is deliberately not used here.
enum MapBasemap {
  /// Muted grey canvas. Vegetation polygons and markers read strongest on
  /// this one, so it is the default.
  light,

  /// Aerial imagery — useful for eyeballing actual canopy / mangrove cover
  /// against the recorded polygons.
  satellite,

  /// Shaded relief with contours, for terrain context on upland sites.
  terrain,

  /// Standard OpenStreetMap, kept for road and place-name detail.
  street,
}

extension MapBasemapStyle on MapBasemap {
  String get label {
    switch (this) {
      case MapBasemap.light:
        return 'Light';
      case MapBasemap.satellite:
        return 'Satellite';
      case MapBasemap.terrain:
        return 'Terrain';
      case MapBasemap.street:
        return 'Street';
    }
  }

  IconData get icon {
    switch (this) {
      case MapBasemap.light:
        return Icons.map_outlined;
      case MapBasemap.satellite:
        return Icons.satellite_alt_outlined;
      case MapBasemap.terrain:
        return Icons.terrain_outlined;
      case MapBasemap.street:
        return Icons.alt_route_outlined;
    }
  }

  String get attribution {
    switch (this) {
      case MapBasemap.light:
      case MapBasemap.terrain:
        return 'Esri, HERE, Garmin, USGS';
      case MapBasemap.satellite:
        return 'Esri, Maxar, Earthstar Geographics';
      case MapBasemap.street:
        return '© OpenStreetMap contributors';
    }
  }

  /// True when the basemap is dark enough that overlays need light colours
  /// and a heavier outline to stay legible.
  bool get isDark => this == MapBasemap.satellite;
}

/// The raster tile URL templates that make up [basemap], in draw order.
///
/// Exposed as plain data (rather than being buried inside [TileLayer]s) so the
/// first-run prefetcher in `MapTileCacheService` can seed exactly the same
/// URLs that the map will later ask for.
List<String> basemapUrlTemplates(MapBasemap basemap) {
  switch (basemap) {
    case MapBasemap.light:
      return const [
        '$_esri/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}',
        '$_esri/Canvas/World_Light_Gray_Reference/MapServer/tile/{z}/{y}/{x}',
      ];
    case MapBasemap.satellite:
      return const [
        '$_esri/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        '$_esri/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
      ];
    case MapBasemap.terrain:
      return const ['$_esri/World_Topo_Map/MapServer/tile/{z}/{y}/{x}'];
    case MapBasemap.street:
      return const ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'];
  }
}

const _esri = 'https://server.arcgisonline.com/ArcGIS/rest/services';

/// The deepest zoom level [basemap] actually has tiles for.
///
/// Esri's raster caches stop at zoom 16-19 depending on the service, so each
/// layer sets `maxNativeZoom` and lets flutter_map upscale beyond it rather
/// than dropping to blank tiles when the user zooms in on a cluster.
int basemapMaxNativeZoom(MapBasemap basemap) =>
    basemap == MapBasemap.light ? 16 : 19;

/// Tile layers for [basemap], ready to splat into `FlutterMap.children`.
///
/// Tiles are fetched through [NetworkTileProvider], which reads and writes
/// flutter_map's built-in on-disk cache — configured once at startup by
/// `MapTileCacheService.configure()`.
List<Widget> basemapTileLayers(MapBasemap basemap) {
  final maxNativeZoom = basemapMaxNativeZoom(basemap);
  return [
    for (final urlTemplate in basemapUrlTemplates(basemap))
      TileLayer(
        urlTemplate: urlTemplate,
        userAgentPackageName: 'com.example.envi_app',
        maxNativeZoom: maxNativeZoom,
        maxZoom: 20,
        // Keep a tile on screen while its replacement loads, so panning over
        // an already-cached area doesn't flash grey.
        keepBuffer: 3,
      ),
  ];
}

/// Small attribution chip. Add it as the last `FlutterMap` child so it sits
/// above the tiles and is included in the exported map capture.
class BasemapAttribution extends StatelessWidget {
  const BasemapAttribution({super.key, required this.basemap});

  final MapBasemap basemap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              basemap.attribution,
              style: const TextStyle(fontSize: 9, color: Colors.black87),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact vertical basemap picker shown over the map.
///
/// Collapsed it is a single tile-style button; tapping it fans out the other
/// styles so the control stays out of the way of the map itself.
class BasemapSwitcher extends StatefulWidget {
  const BasemapSwitcher({
    super.key,
    required this.selected,
    required this.onChanged,
    this.accentColor = const Color(0xFF00796B),
  });

  final MapBasemap selected;
  final ValueChanged<MapBasemap> onChanged;
  final Color accentColor;

  @override
  State<BasemapSwitcher> createState() => _BasemapSwitcherState();
}

class _BasemapSwitcherState extends State<BasemapSwitcher> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final options =
        _expanded ? MapBasemap.values : <MapBasemap>[widget.selected];

    return Material(
      color: Colors.white,
      elevation: 3,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in options)
              _BasemapOption(
                basemap: option,
                selected: option == widget.selected,
                accentColor: widget.accentColor,
                showLabel: _expanded,
                onTap: () {
                  if (!_expanded) {
                    setState(() => _expanded = true);
                    return;
                  }
                  setState(() => _expanded = false);
                  if (option != widget.selected) widget.onChanged(option);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _BasemapOption extends StatelessWidget {
  const _BasemapOption({
    required this.basemap,
    required this.selected,
    required this.accentColor,
    required this.showLabel,
    required this.onTap,
  });

  final MapBasemap basemap;
  final bool selected;
  final Color accentColor;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? accentColor : Colors.black54;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected && showLabel
            ? accentColor.withValues(alpha: 0.10)
            : Colors.transparent,
        padding: EdgeInsets.symmetric(
          horizontal: showLabel ? 10 : 8,
          vertical: 8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(basemap.icon, size: 18, color: foreground),
            if (showLabel) ...[
              const SizedBox(width: 8),
              Text(
                basemap.label,
                style: TextStyle(
                  fontSize: 12,
                  color: foreground,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
