import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widget/polygon_calculator.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  int _treeGrowingCount = 0;
  int _totalSeedlingAvailable = 0;
  int _totalSeedlingRelease = 0;
  bool _isLoadingCount = true;
  bool _isCachedData = false;
  bool _isLoadingSeedlingStats = true;
  bool _isCachedSeedlingStats = false;
  bool _isRefreshing = false;

  List<Marker> _markers = [];
  List<Polygon> _polygons = [];
  bool _isLoadingMarkers = true;
  bool _isCachedMarkers = false;

  List<Map<String, dynamic>> _allPhotoUrlRows = [];
  List<Map<String, dynamic>> _allTreeGrowingRows = [];

  List<Map<String, dynamic>> _projectTypes = [];
  int? _selectedProjectTypeId;
  bool _isLoadingProjectTypes = true;

  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    WidgetsBinding.instance.addObserver(this);
    _refreshDashboard();
    _loadProjectTypes();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshDashboard();
    }
  }

  Future<void> _refreshDashboard() async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    try {
      await Future.wait([
        _loadTreeGrowingCount(),
        _loadSeedlingStats(),
        _loadTreeGrowingMarkers(),
      ]);
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _loadTreeGrowingCount() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (result.contains(ConnectivityResult.none)) {
        await _loadTreeGrowingCountFromCache();
        return;
      }

      final response = await Supabase.instance.client
          .from('tree_growing')
          .select('id')
          .eq('is_deleted', 0)
          .timeout(const Duration(seconds: 5));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('tree_growing_count', response.length);
      await prefs.setString(
        'tree_growing_count_date',
        DateTime.now().toIso8601String(),
      );

      if (!mounted) return;
      setState(() {
        _treeGrowingCount = response.length;
        _isLoadingCount = false;
        _isCachedData = false;
      });
    } catch (_) {
      await _loadTreeGrowingCountFromCache();
    }
  }

  Future<void> _loadTreeGrowingCountFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedCount = prefs.getInt('tree_growing_count');

      if (!mounted) return;
      setState(() {
        _treeGrowingCount = cachedCount ?? 0;
        _isLoadingCount = false;
        _isCachedData = cachedCount != null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingCount = false;
      });
    }
  }

  Future<void> _loadSeedlingStats() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (result.contains(ConnectivityResult.none)) {
        await _loadSeedlingStatsFromCache();
        return;
      }

      final receiveRows = await Supabase.instance.client
          .from('seedling_transaction')
          .select('seedling_count')
          .eq('transaction_type_id', 1)
          .timeout(const Duration(seconds: 5));

      final releaseRows = await Supabase.instance.client
          .from('seedling_transaction')
          .select('seedling_count')
          .eq('transaction_type_id', 2)
          .timeout(const Duration(seconds: 5));

      int receiveTotal = 0;
      for (final row in receiveRows) {
        receiveTotal += ((row['seedling_count'] as num?)?.toInt() ?? 0);
      }

      int releaseTotal = 0;
      for (final row in releaseRows) {
        releaseTotal += ((row['seedling_count'] as num?)?.toInt() ?? 0);
      }

      final availableTotal = receiveTotal - releaseTotal;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('seedling_total_available', availableTotal);
      await prefs.setInt('seedling_total_release', releaseTotal);
      await prefs.setString(
        'seedling_stats_date',
        DateTime.now().toIso8601String(),
      );

      if (!mounted) return;
      setState(() {
        _totalSeedlingAvailable = availableTotal;
        _totalSeedlingRelease = releaseTotal;
        _isLoadingSeedlingStats = false;
        _isCachedSeedlingStats = false;
      });
    } catch (_) {
      await _loadSeedlingStatsFromCache();
    }
  }

  Future<void> _loadSeedlingStatsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedAvailable = prefs.getInt('seedling_total_available');
      final cachedRelease = prefs.getInt('seedling_total_release');

      if (!mounted) return;
      setState(() {
        _totalSeedlingAvailable = cachedAvailable ?? 0;
        _totalSeedlingRelease = cachedRelease ?? 0;
        _isLoadingSeedlingStats = false;
        _isCachedSeedlingStats =
            cachedAvailable != null || cachedRelease != null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingSeedlingStats = false;
      });
    }
  }

  Future<void> _loadTreeGrowingMarkers() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (result.contains(ConnectivityResult.none)) {
        await _loadTreeGrowingMarkersFromCache();
        return;
      }

      final photoUrlResponse = await Supabase.instance.client
          .from('photourl_area')
          .select('id, activity_id, latitude, longitude')
          .eq('isDeleted', 0)
          .timeout(const Duration(seconds: 5));

      final treeGrowingResponse = await Supabase.instance.client
          .from('tree_growing')
          .select('*')
          .eq('is_deleted', 0)
          .timeout(const Duration(seconds: 5));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('photourl_areas_json', jsonEncode(photoUrlResponse));
      await prefs.setString('tree_growing_json', jsonEncode(treeGrowingResponse));
      await prefs.setString('markers_cache_date', DateTime.now().toIso8601String());

      final typedPhotoRows = photoUrlResponse
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final typedTreeRows = treeGrowingResponse
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

      final markers = _buildMarkersFromData(typedPhotoRows, typedTreeRows);
      final polygons = _buildPolygonsFromData(typedPhotoRows, typedTreeRows);

      if (!mounted) return;
      setState(() {
        _allPhotoUrlRows = typedPhotoRows;
        _allTreeGrowingRows = typedTreeRows;
        _markers = markers;
        _polygons = polygons;
        _isLoadingMarkers = false;
        _isCachedMarkers = false;
      });
    } catch (_) {
      await _loadTreeGrowingMarkersFromCache();
    }
  }

  Future<void> _loadTreeGrowingMarkersFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final photoUrlJson = prefs.getString('photourl_areas_json');
      final treeGrowingJson = prefs.getString('tree_growing_json');

      if (photoUrlJson == null || treeGrowingJson == null) {
        if (!mounted) return;
        setState(() => _isLoadingMarkers = false);
        return;
      }

      final photoUrlResponse =
          List<Map<String, dynamic>>.from(jsonDecode(photoUrlJson) as List);
      final treeGrowingResponse =
          List<Map<String, dynamic>>.from(jsonDecode(treeGrowingJson) as List);

      final markers = _buildMarkersFromData(photoUrlResponse, treeGrowingResponse);
      final polygons = _buildPolygonsFromData(photoUrlResponse, treeGrowingResponse);

      if (!mounted) return;
      setState(() {
        _allPhotoUrlRows = photoUrlResponse;
        _allTreeGrowingRows = treeGrowingResponse;
        _markers = markers;
        _polygons = polygons;
        _isLoadingMarkers = false;
        _isCachedMarkers = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMarkers = false);
    }
  }

  Future<void> _loadProjectTypes() async {
    try {
      final response = await Supabase.instance.client
          .from('project_type')
          .select('id, projectname')
          .eq('dashboard_filter', true)
          .order('id')
          .timeout(const Duration(seconds: 5));

      final typed = response
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

      int? defaultProjectTypeId;
      for (final row in typed) {
        final name = (row['projectname'] ?? '').toString().trim().toLowerCase();
        if (name == 'tree growing') {
          defaultProjectTypeId = _toInt(row['id']);
          break;
        }
      }

      defaultProjectTypeId ??=
          typed.isNotEmpty ? _toInt(typed.first['id']) : null;

      if (!mounted) return;
      setState(() {
        _projectTypes = typed;
        _selectedProjectTypeId = defaultProjectTypeId;
        _isLoadingProjectTypes = false;
      });

      _applyProjectTypeFilter();
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

  int? _extractProjectTypeId(Map<String, dynamic> row) {
    const possibleKeys = [
      'project_type_id',
      'projectTypeId',
      'project_type',
      'projectType',
      'projectid',
      'project_id',
    ];

    for (final key in possibleKeys) {
      final parsed = _toInt(row[key]);
      if (parsed != null) return parsed;
    }

    return null;
  }

  bool _matchesSelectedProjectType(Map<String, dynamic>? activityRow) {
    if (_selectedProjectTypeId == null) return true;
    if (activityRow == null) return false;
    final explicitId = _extractProjectTypeId(activityRow);
    return explicitId == _selectedProjectTypeId;
  }

  void _applyProjectTypeFilter() {
    final markers = _buildMarkersFromData(_allPhotoUrlRows, _allTreeGrowingRows);
    final polygons = _buildPolygonsFromData(_allPhotoUrlRows, _allTreeGrowingRows);

    setState(() {
      _markers = markers;
      _polygons = polygons;
    });
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  List<Marker> _buildMarkersFromData(
    List<dynamic> photoUrlResponse,
    List<dynamic> treeGrowingResponse,
  ) {
    final activityMap = <dynamic, Map<String, dynamic>>{};
    for (final item in treeGrowingResponse) {
      final row = Map<String, dynamic>.from(item as Map);
      activityMap[row['seq_id']] = row;
    }

    final markers = <Marker>[];
    for (final item in photoUrlResponse) {
      final row = Map<String, dynamic>.from(item as Map);
      final lat = _toDouble(row['latitude']);
      final lng = _toDouble(row['longitude']);
      final activityId = row['activity_id'];

      if (lat == null || lng == null) continue;

      final activityData = activityId != null ? activityMap[activityId] : null;
      if (!_matchesSelectedProjectType(activityData)) continue;

      markers.add(
        Marker(
          point: ll.LatLng(lat, lng),
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _showMarkerInfo(activityData, activityId, row['id'], lat, lng),
            child: Container(
              width: 35,
              height: 35,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade400, Colors.green.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.shade400.withValues(alpha: 0.6),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.park, color: Colors.white, size: 20),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  List<Polygon> _buildPolygonsFromData(
    List<dynamic> photoUrlResponse,
    List<dynamic> treeGrowingResponse,
  ) {
    final coordinatesByActivity = <dynamic, List<ll.LatLng>>{};
    final activityMap = <dynamic, Map<String, dynamic>>{};

    for (final item in treeGrowingResponse) {
      final row = Map<String, dynamic>.from(item as Map);
      activityMap[row['seq_id']] = row;
    }

    for (final item in photoUrlResponse) {
      final row = Map<String, dynamic>.from(item as Map);
      final activityId = row['activity_id'];
      final lat = _toDouble(row['latitude']);
      final lng = _toDouble(row['longitude']);

      if (activityId == null || lat == null || lng == null) continue;

      final activityRow = activityMap[activityId];
      if (!_matchesSelectedProjectType(activityRow)) {
        continue;
      }

      coordinatesByActivity.putIfAbsent(activityId, () => []);
      coordinatesByActivity[activityId]!.add(ll.LatLng(lat, lng));
    }

    final polygons = <Polygon>[];
    for (final entry in coordinatesByActivity.entries) {
      final points = entry.value;
      if (points.length < 4) continue;

      final areaHectares =
          PolygonCalculator.calculatePolygonAreaInHectares(points);
      var polygonColor = Colors.green.shade300;
      if (areaHectares > 10) {
        polygonColor = Colors.blue.shade300;
      } else if (areaHectares > 5) {
        polygonColor = Colors.teal.shade300;
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

    return polygons;
  }

  void _showMarkerInfo(
    Map<String, dynamic>? activityData,
    dynamic activityId,
    dynamic photoAreaId,
    dynamic lat,
    dynamic lng,
  ) {
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
                  child: const Row(
                    children: [
                      Icon(Icons.location_on_rounded, color: Colors.white),
                      SizedBox(width: 10),
                      Text(
                        'Activity Details',
                        style: TextStyle(
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
                  child: FutureBuilder<Map<String, String>>(
                    future: _loadDialogDetails(
                      activityId: activityId,
                      activityData: activityData,
                      lat: lat,
                      lng: lng,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final details = snapshot.data ??
                          {
                            'Activity': 'N/A',
                            'Municipality': 'N/A',
                            'Barangay': 'N/A',
                            'Lat & Long': 'N/A',
                            'Seedling Name': 'N/A',
                            'Seedling Count': '0',
                            'Area': 'N/A',
                            'Planting Date': 'N/A',
                          };

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildDetailRow('Activity', details['Activity'] ?? 'N/A'),
                          _buildDetailRow('Municipality', details['Municipality'] ?? 'N/A'),
                          _buildDetailRow('Barangay', details['Barangay'] ?? 'N/A'),
                          _buildDetailRow('Lat & Long', details['Lat & Long'] ?? 'N/A'),
                          _buildDetailRow('Seedling Name', details['Seedling Name'] ?? 'N/A'),
                          _buildDetailRow('Seedling Count', details['Seedling Count'] ?? '0'),
                          _buildDetailRow('Area', details['Area'] ?? 'N/A'),
                          _buildDetailRow('Planting Date', details['Planting Date'] ?? 'N/A'),
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
              width: 110,
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

  Future<Map<String, String>> _loadDialogDetails({
    required dynamic activityId,
    required Map<String, dynamic>? activityData,
    required dynamic lat,
    required dynamic lng,
  }) async {
    final safeData = activityData ?? <String, dynamic>{};
    final activityName = (safeData['activity_name'] ?? safeData['activityName'] ?? 'N/A')
        .toString();
    final municipality = (safeData['municipality'] ?? 'N/A').toString();
    final barangay = (safeData['barangay'] ?? 'N/A').toString();
    String latLong = '${lat ?? 'N/A'}, ${lng ?? 'N/A'}';

    String seedlingName = 'N/A';
    String seedlingCount = '0';
    String area = 'N/A';
    final plantingDate = _formatPlantingDate(
      safeData['planting_date'] ?? safeData['created_at'],
    );

    try {
      if (activityId != null) {
        final seedRows = await Supabase.instance.client
            .from('tree_growing_data')
            .select('seed_name, seedling_count')
            .eq('tree_growing_id', activityId);

        final rows = List<Map<String, dynamic>>.from(seedRows as List);
        if (rows.isNotEmpty) {
          final names = rows
              .map((row) => (row['seed_name'] ?? '').toString().trim())
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList();
          seedlingName = names.isEmpty ? 'N/A' : names.join(', ');

          final total = rows.fold<int>(0, (sum, row) {
            final qty = (row['seedling_count'] as num?)?.toInt() ?? 0;
            return sum + qty;
          });
          seedlingCount = total.toString();
        }

        final coordinateRows = await Supabase.instance.client
            .from('photourl_area')
            .select('latitude, longitude')
            .eq('activity_id', activityId)
            .eq('isDeleted', 0);

        final coords = List<Map<String, dynamic>>.from(coordinateRows as List)
            .map((row) {
              final latitude = _toDouble(row['latitude']);
              final longitude = _toDouble(row['longitude']);
              if (latitude == null || longitude == null) return null;
              return ll.LatLng(latitude, longitude);
            })
            .whereType<ll.LatLng>()
            .toList();

        if (coords.isNotEmpty) {
          final formatted = coords.asMap().entries.map((entry) {
            final index = entry.key + 1;
            final point = entry.value;
            return '$index. ${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
          }).join('\n');

          latLong = formatted;
        }

        if (coords.length >= 3) {
          final ha = PolygonCalculator.calculatePolygonAreaInHectares(coords);
          area = '${ha.toStringAsFixed(2)} ha';
        } else {
          final areaCover = _toDouble(safeData['area_cover']);
          if (areaCover != null && areaCover > 0) {
            area = '${areaCover.toStringAsFixed(2)} ha';
          }
        }
      }
    } catch (_) {
      // Keep graceful fallback values.
    }

    return {
      'Activity': activityName,
      'Municipality': municipality,
      'Barangay': barangay,
      'Lat & Long': latLong,
      'Seedling Name': seedlingName,
      'Seedling Count': seedlingCount,
      'Area': area,
      'Planting Date': plantingDate,
    };
  }

  String _formatPlantingDate(dynamic value) {
    if (value == null) return 'N/A';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    final year = parsed.year.toString().padLeft(4, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refreshDashboard,
      color: const Color.fromARGB(255, 31, 103, 78),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Forest Management Dashboard',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.teal.shade700,
              ),
            ),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.45,
              children: [
                _buildStatCard(
                  title: 'Total Tree Growing Activity',
                  value: _isLoadingCount ? '...' : '$_treeGrowingCount',
                  trend: _isCachedData ? 'Cached' : 'Live',
                ),
                _buildStatCard(
                  title: 'Total Seedling Available',
                  value: _isLoadingSeedlingStats
                      ? '...'
                      : '$_totalSeedlingAvailable',
                  trend: _isCachedSeedlingStats ? 'Cached' : 'Live',
                ),
                _buildStatCard(
                  title: 'Total Seedling Release',
                  value: _isLoadingSeedlingStats
                      ? '...'
                      : '$_totalSeedlingRelease',
                  trend: _isCachedSeedlingStats ? 'Cached' : 'Live',
                ),
              ],
            ),
            const SizedBox(height: 24),
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
                  hint: const Text('Select project type'),
                  items: _projectTypes.map((projectType) {
                    final id = _toInt(projectType['id']);
                    final name = (projectType['projectname'] ?? '').toString();
                    return DropdownMenuItem<int?>(
                      value: id,
                      child: Text(name.isEmpty ? 'Unnamed Project' : name),
                    );
                  }).toList(),
                  onChanged: _isLoadingProjectTypes
                      ? null
                      : (selected) {
                          _selectedProjectTypeId = selected;
                          _applyProjectTypeFilter();
                        },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 420,
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _isLoadingMarkers
                        ? const Center(child: CircularProgressIndicator())
                        : FlutterMap(
                            mapController: _mapController,
                            options: const MapOptions(
                              initialCenter: ll.LatLng(11.39815374730887, 122.73605826343467),
                              initialZoom: 9.8,
                              interactionOptions: InteractionOptions(
                                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                              ),
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
                              MarkerLayer(markers: _markers),
                            ],
                          ),
                  ),
                  // Zoom controls
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Column(
                      children: [
                        // Zoom In Button
                        FloatingActionButton(
                          heroTag: 'zoom_in',
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
                        // Zoom Out Button
                        FloatingActionButton(
                          heroTag: 'zoom_out',
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
            const SizedBox(height: 12),
            if (_isCachedMarkers)
              Text(
                'Showing cached marker data',
                style: TextStyle(color: Colors.amber.shade800),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String trend,
  }) {
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
          const SizedBox(height: 6),
          Text(
            trend,
            style: TextStyle(
              fontSize: 10,
              color: trend == 'Live' ? Colors.green : Colors.orange,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

