import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:file_saver/file_saver.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widget/export_options_dialog.dart';
import '../widget/polygon_calculator.dart';
import '../widget/web_helper.dart' as web_helper;

class CoastalDashboardPage extends StatefulWidget {
  const CoastalDashboardPage({super.key});

  @override
  State<CoastalDashboardPage> createState() => _CoastalDashboardPageState();
}

class _CoastalDashboardPageState extends State<CoastalDashboardPage> {
  static const int _habitatAssessmentTypeId = 8;
  static const int _marineProtectedAreaTypeId = 9;

  int _habitatCount = 0;
  int _marineCount = 0;
  double _totalAreaHa = 0;
  bool _isLoadingStats = true;

  List<Map<String, dynamic>> _projectTypes = [];
  int? _selectedProjectTypeId;
  bool _isLoadingProjectTypes = true;

  List<Map<String, dynamic>> _allLocationRows = [];
  Map<int, Map<String, dynamic>> _habitatById = {};
  Map<int, Map<String, dynamic>> _marineById = {};

  List<Marker> _markers = [];
  List<Polygon> _polygons = [];
  bool _isLoadingMarkers = true;
  bool _hasExpandedCluster = false;
  int _mapTapVersion = 0;
  final GlobalKey _mapCaptureKey = GlobalKey();
  bool _isCapturingMap = false;

  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _loadProjectTypes();
    _refreshDashboard();
  }

  Future<void> _refreshDashboard() async {
    await _loadMarkersAndStats();
  }

  Future<void> _loadProjectTypes() async {
    try {
      final response = await Supabase.instance.client
          .from('project_type')
          .select('id, projectname')
          .inFilter('id', [_habitatAssessmentTypeId, _marineProtectedAreaTypeId])
          .order('id')
          .timeout(const Duration(seconds: 5));

      final typed = response
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _projectTypes = typed;
        _isLoadingProjectTypes = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _projectTypes = const [];
        _isLoadingProjectTypes = false;
      });
    }
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Future<void> _loadMarkersAndStats() async {
    setState(() {
      _isLoadingMarkers = true;
      _isLoadingStats = true;
    });

    try {
      final locationResponse = await Supabase.instance.client
          .from('location')
          .select('id, activity_id, activity_type_id, latitude, longitude')
          .inFilter('activity_type_id', [_habitatAssessmentTypeId, _marineProtectedAreaTypeId])
          .eq('isDeleted', 0)
          .timeout(const Duration(seconds: 5));

      final habitatResponse = await Supabase.instance.client
          .from('crm_habitat_assssment')
          .select()
          .timeout(const Duration(seconds: 5));

      final marineResponse = await Supabase.instance.client
          .from('crm_marine_protected')
          .select()
          .timeout(const Duration(seconds: 5));

      final typedLocationRows = locationResponse
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final typedHabitatRows = habitatResponse
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final typedMarineRows = marineResponse
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

      final habitatById = <int, Map<String, dynamic>>{};
      for (final row in typedHabitatRows) {
        final id = _toInt(row['id']);
        if (id != null) habitatById[id] = row;
      }

      final marineById = <int, Map<String, dynamic>>{};
      for (final row in typedMarineRows) {
        final id = _toInt(row['id']);
        if (id != null) marineById[id] = row;
      }

      double totalArea = 0;
      for (final row in typedHabitatRows) {
        totalArea += (_toDouble(row['area']) ?? 0);
      }
      for (final row in typedMarineRows) {
        totalArea += (_toDouble(row['area']) ?? 0);
      }

      if (!mounted) return;
      setState(() {
        _allLocationRows = typedLocationRows;
        _habitatById = habitatById;
        _marineById = marineById;
        _habitatCount = typedHabitatRows.length;
        _marineCount = typedMarineRows.length;
        _totalAreaHa = totalArea;
        _isLoadingStats = false;
      });

      _applyProjectTypeFilter();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingMarkers = false;
        _isLoadingStats = false;
      });
    }
  }

  void _applyProjectTypeFilter() {
    final pointsByKey = <String, List<ll.LatLng>>{};
    final typeByKey = <String, int>{};
    final activityByKey = <String, int>{};

    for (final row in _allLocationRows) {
      final activityTypeId = _toInt(row['activity_type_id']);
      final activityId = _toInt(row['activity_id']);
      final lat = _toDouble(row['latitude']);
      final lng = _toDouble(row['longitude']);
      if (activityTypeId == null || activityId == null || lat == null || lng == null) {
        continue;
      }

      if (_selectedProjectTypeId != null && activityTypeId != _selectedProjectTypeId) {
        continue;
      }

      final sourceExists = activityTypeId == _habitatAssessmentTypeId
          ? _habitatById.containsKey(activityId)
          : activityTypeId == _marineProtectedAreaTypeId
              ? _marineById.containsKey(activityId)
              : false;
      if (!sourceExists) continue;

      final key = '${activityTypeId}_$activityId';
      pointsByKey.putIfAbsent(key, () => []).add(ll.LatLng(lat, lng));
      typeByKey[key] = activityTypeId;
      activityByKey[key] = activityId;
    }

    final markers = <Marker>[];
    final polygons = <Polygon>[];

    for (final entry in pointsByKey.entries) {
      final points = entry.value;
      final activityTypeId = typeByKey[entry.key]!;
      final activityId = activityByKey[entry.key]!;
      final firstPoint = points.first;

      markers.add(
        Marker(
          point: firstPoint,
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _showMarkerInfo(activityTypeId, activityId),
            child: _RingMarkerIcon(
              seqId: activityId,
              color: activityTypeId == _habitatAssessmentTypeId
                  ? Colors.teal.shade600
                  : Colors.blue.shade600,
            ),
          ),
        ),
      );

      if (points.length >= 4) {
        final areaHectares = PolygonCalculator.calculatePolygonAreaInHectares(points);
        var polygonColor = activityTypeId == _habitatAssessmentTypeId
            ? Colors.teal.shade300
            : Colors.blue.shade300;
        if (areaHectares > 10) {
          polygonColor = Colors.indigo.shade300;
        } else if (areaHectares > 5) {
          polygonColor = Colors.cyan.shade300;
        }

        polygons.add(
          Polygon(
            points: points,
            color: polygonColor.withValues(alpha: 0.4),
            borderColor: polygonColor.withValues(alpha: 0.8),
            borderStrokeWidth: 2.0,
          ),
        );
      }
    }

    setState(() {
      _markers = markers;
      _polygons = polygons;
      _isLoadingMarkers = false;
    });
  }

  void _showMarkerInfo(int activityTypeId, int activityId) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1B8B5E),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(14),
                      topRight: Radius.circular(14),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_rounded, color: Colors.white),
                      const SizedBox(width: 10),
                      Text(
                        activityTypeId == _habitatAssessmentTypeId
                            ? 'Habitat Assessment Details'
                            : 'Marine Protected Area Details',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FutureBuilder<List<MapEntry<String, String>>>(
                    future: _loadDialogDetails(activityTypeId, activityId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final details = snapshot.data ?? const [];

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final entry in details)
                            _buildDetailRow(entry.key, entry.value),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1B8B5E),
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Close'),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<MapEntry<String, String>>> _loadDialogDetails(
    int activityTypeId,
    int activityId,
  ) async {
    final coords = _allLocationRows
        .where((row) =>
            _toInt(row['activity_type_id']) == activityTypeId &&
            _toInt(row['activity_id']) == activityId)
        .map((row) {
          final lat = _toDouble(row['latitude']);
          final lng = _toDouble(row['longitude']);
          if (lat == null || lng == null) return null;
          return ll.LatLng(lat, lng);
        })
        .whereType<ll.LatLng>()
        .toList();

    final latLong = coords.isEmpty
        ? 'N/A'
        : coords.asMap().entries.map((entry) {
            final index = entry.key + 1;
            final point = entry.value;
            return '$index. ${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
          }).join('\n');

    if (activityTypeId == _habitatAssessmentTypeId) {
      final row = _habitatById[activityId] ?? const <String, dynamic>{};

      String area = 'N/A';
      if (coords.length >= 3) {
        final ha = PolygonCalculator.calculatePolygonAreaInHectares(coords);
        area = '${ha.toStringAsFixed(2)} ha';
      } else {
        final storedArea = _toDouble(row['area']);
        if (storedArea != null && storedArea > 0) {
          area = '${storedArea.toStringAsFixed(2)} ha';
        }
      }

      String species = 'N/A';
      try {
        final speciesRows = await Supabase.instance.client
            .from('crm_habitat_assssment_data')
            .select('species_name, count')
            .eq('assssment_id', activityId);

        final names = List<Map<String, dynamic>>.from(speciesRows as List)
            .map((r) => (r['species_name'] ?? '').toString().trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList();
        if (names.isNotEmpty) species = names.join(', ');
      } catch (_) {
        // Keep fallback value.
      }

      return [
        MapEntry('Type', (row['type_assessment'] ?? 'N/A').toString()),
        MapEntry('Municipality', (row['municipality'] ?? 'N/A').toString()),
        MapEntry('Barangay', (row['barangay'] ?? 'N/A').toString()),
        MapEntry('Species', species),
        MapEntry('Area', area),
        MapEntry('Lat & Long', latLong),
        MapEntry('Date', _formatDate(row['created_at'])),
      ];
    } else {
      final row = _marineById[activityId] ?? const <String, dynamic>{};

      String area = 'N/A';
      if (coords.length >= 3) {
        final ha = PolygonCalculator.calculatePolygonAreaInHectares(coords);
        area = '${ha.toStringAsFixed(2)} ha';
      } else {
        final storedArea = _toDouble(row['area']);
        if (storedArea != null && storedArea > 0) {
          area = '${storedArea.toStringAsFixed(2)} ha';
        }
      }

      return [
        MapEntry('Name', (row['name'] ?? 'N/A').toString()),
        MapEntry('Municipality', (row['municipality'] ?? 'N/A').toString()),
        MapEntry('Barangay', (row['barangay'] ?? 'N/A').toString()),
        MapEntry('Ordinance', (row['ordinance'] ?? 'N/A').toString()),
        MapEntry('Area', area),
        MapEntry('Lat & Long', latLong),
        MapEntry('Date', _formatDate(row['created_at'])),
      ];
    }
  }

  String _formatDate(dynamic value) {
    if (value == null) return 'N/A';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    final year = parsed.year.toString().padLeft(4, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE7ECF0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4C5A67),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E2A34),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Offset> _verticalSpiderfyPositions(int markerCount, Offset center) {
    const spacing = 46.0;
    final totalHeight = spacing * (markerCount - 1);
    return List<Offset>.generate(markerCount, (index) {
      return Offset(center.dx, center.dy - totalHeight / 2 + spacing * index);
    });
  }

  Future<void> _captureAndExportMap() async {
    setState(() => _isCapturingMap = true);

    try {
      final boundary = _mapCaptureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();
      final fileName = 'CoastalMap_${DateTime.now().millisecondsSinceEpoch}.png';

      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) => const ExportOptionsDialog(
          title: 'Export Map',
          headerSubtitle: 'Choose how you\'d like to export the map',
          fileTypeLabel: 'map image',
        ),
      );

      if (action == 'save') {
        await _saveMapImage(fileName, pngBytes);
      } else if (action == 'share') {
        await _shareMapImage(fileName, pngBytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error capturing map: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturingMap = false);
    }
  }

  Future<void> _saveMapImage(String fileName, Uint8List bytes) async {
    try {
      if (kIsWeb) {
        web_helper.downloadBytes(bytes, fileName, 'image/png');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Downloaded $fileName')),
          );
        }
        return;
      }

      final baseName = fileName.endsWith('.png')
          ? fileName.substring(0, fileName.length - '.png'.length)
          : fileName;

      final savedPath = await FileSaver.instance.saveAs(
        name: baseName,
        bytes: bytes,
        ext: 'png',
        mimeType: MimeType.png,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              savedPath != null ? 'Saved to $savedPath' : 'Map image saved',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving map image: $e')),
        );
      }
    }
  }

  Future<void> _shareMapImage(String fileName, Uint8List bytes) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(bytes);

      await SharePlus.instance.share(
        ShareParams(files: [XFile(tempFile.path)], text: 'Coastal Resource Map'),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing map image: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 31, 103, 78),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Coastal Resource Management Dashboard',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshDashboard,
        color: const Color.fromARGB(255, 31, 103, 78),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Coastal Resource Management Dashboard',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.teal.shade700,
                ),
              ),
              const SizedBox(height: 20),
              Card(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: DropdownButtonFormField<int?>(
                    value: _selectedProjectTypeId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Map Filter - Project Type',
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.filter_alt_outlined),
                    ),
                    hint: const Text('All coastal project types'),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('All coastal project types'),
                      ),
                      ..._projectTypes.map((projectType) {
                        final id = _toInt(projectType['id']);
                        final name = (projectType['projectname'] ?? '').toString();
                        return DropdownMenuItem<int?>(
                          value: id,
                          child: Text(name.isEmpty ? 'Unnamed Project' : name),
                        );
                      }),
                    ],
                    onChanged: _isLoadingProjectTypes
                        ? null
                        : (selected) {
                            setState(() => _selectedProjectTypeId = selected);
                            _applyProjectTypeFilter();
                          },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: MediaQuery.of(context).size.height * 0.70,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    RepaintBoundary(
                      key: _mapCaptureKey,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: _isLoadingMarkers
                            ? const Center(child: CircularProgressIndicator())
                            : FlutterMap(
                                mapController: _mapController,
                                options: MapOptions(
                                  initialCenter:
                                      const ll.LatLng(11.39815374730887, 122.73605826343467),
                                  initialZoom: 9.8,
                                  interactionOptions: const InteractionOptions(
                                    flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                                  ),
                                  onTap: (_, __) {
                                    if (_hasExpandedCluster) {
                                      _hasExpandedCluster = false;
                                      setState(() => _mapTapVersion++);
                                    }
                                  },
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                                    subdomains: const ['a', 'b', 'c'],
                                    userAgentPackageName: 'com.example.envi_app',
                                  ),
                                  if (_polygons.isNotEmpty)
                                    PolygonLayer(polygons: _polygons),
                                  MarkerClusterLayerWidget(
                                    key: ValueKey(_mapTapVersion),
                                    options: MarkerClusterLayerOptions(
                                      maxClusterRadius: 60,
                                      disableClusteringAtZoom: 16,
                                      size: const Size(40, 40),
                                      markers: _markers,
                                      zoomToBoundsOnClick: false,
                                      onClusterTap: (_) => _hasExpandedCluster = true,
                                      spiderfyShapePositions: _verticalSpiderfyPositions,
                                      builder: (context, markers) {
                                        return Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.teal.shade600,
                                            border: Border.all(color: Colors.white, width: 2),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.25),
                                                blurRadius: 4,
                                              ),
                                            ],
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            markers.length.toString(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      top: 12,
                      child: FloatingActionButton(
                        heroTag: 'coastal_capture_map',
                        onPressed: _isCapturingMap ? null : _captureAndExportMap,
                        mini: true,
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        elevation: 3,
                        child: _isCapturingMap
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.camera_alt_outlined),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Column(
                        children: [
                          FloatingActionButton(
                            heroTag: 'coastal_zoom_in',
                            onPressed: () {
                              _mapController.move(
                                _mapController.camera.center,
                                _mapController.camera.zoom + 1,
                              );
                            },
                            mini: true,
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black87,
                            elevation: 3,
                            child: const Icon(Icons.add),
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton(
                            heroTag: 'coastal_zoom_out',
                            onPressed: () {
                              _mapController.move(
                                _mapController.camera.center,
                                _mapController.camera.zoom - 1,
                              );
                            },
                            mini: true,
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black87,
                            elevation: 3,
                            child: const Icon(Icons.remove),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.45,
                children: [
                  _buildStatCard(
                    title: 'Total Habitat Assessments',
                    value: _isLoadingStats ? '...' : '$_habitatCount',
                  ),
                  _buildStatCard(
                    title: 'Total Marine Protected Areas',
                    value: _isLoadingStats ? '...' : '$_marineCount',
                  ),
                  _buildStatCard(
                    title: 'Total Area Covered (ha)',
                    value: _isLoadingStats ? '...' : _totalAreaHa.toStringAsFixed(2),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({required String title, required String value}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF7F7F7F),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RingMarkerIcon extends StatelessWidget {
  final int seqId;
  final Color color;

  const _RingMarkerIcon({required this.seqId, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        seqId.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.clip,
      ),
    );
  }
}
