import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widget/export_options_dialog.dart';
import '../widget/map_basemap.dart';
import '../widget/polygon_calculator.dart';
import '../widget/web_helper.dart' as web_helper;

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  MapBasemap _basemap = MapBasemap.light;
  int _treeGrowingCount = 0;
  int _totalSeedlingAvailable = 0;
  int _totalSeedlingRelease = 0;
  int _totalSeedlingSurvive = 0;
  bool _isLoadingCount = true;
  bool _isCachedData = false;
  bool _isLoadingSeedlingStats = true;
  bool _isCachedSeedlingStats = false;
  bool _isLoadingSurviveStats = true;
  bool _isCachedSurviveStats = false;
  bool _isRefreshing = false;

  List<Marker> _markers = [];
  List<Polygon> _polygons = [];
  bool _isLoadingMarkers = true;
  bool _isCachedMarkers = false;
  int _mapTapVersion = 0;
  bool _hasExpandedCluster = false;
  final GlobalKey _mapCaptureKey = GlobalKey();
  bool _isCapturingMap = false;

  List<Map<String, dynamic>> _allTreeGrowingRows = [];
  Set<int> _treeGrowingIdsWithSpeciesData = {};

  List<Map<String, dynamic>> _allLocationRows = [];
  List<Map<String, dynamic>> _allFloraFaunaRows = [];
  Set<int> _floraFaunaIdsWithSpeciesData = {};

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
        _loadSurviveStats(),
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
          .eq('project_type_id', 1)
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

  /// Sums number_tree_survived from tree_survival_monitoring, restricted to
  /// activities whose tree_growing row is project_type_id 1 (Tree Growing)
  /// — that table is shared with Mangrove Survival (project_type_id 6),
  /// same disambiguation used by the Report page and the recent-activity
  /// list pages.
  Future<void> _loadSurviveStats() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (result.contains(ConnectivityResult.none)) {
        await _loadSurviveStatsFromCache();
        return;
      }

      final survivalRows = await Supabase.instance.client
          .from('tree_survival_monitoring')
          .select()
          .eq('is_deleted', 0)
          .timeout(const Duration(seconds: 5));

      final rows = List<Map<String, dynamic>>.from(survivalRows);
      final activityIds = rows
          .map((row) => (row['activity_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet()
          .toList();

      var treeGrowingActivityIds = <int>{};
      if (activityIds.isNotEmpty) {
        final treeGrowingRows = await Supabase.instance.client
            .from('tree_growing')
            .select('seq_id, project_type_id')
            .inFilter('seq_id', activityIds)
            .timeout(const Duration(seconds: 5));

        treeGrowingActivityIds = List<Map<String, dynamic>>.from(treeGrowingRows)
            .where((row) => (row['project_type_id'] as num?)?.toInt() == 1)
            .map((row) => (row['seq_id'] as num).toInt())
            .toSet();
      }

      int surviveTotal = 0;
      for (final row in rows) {
        final activityId = (row['activity_id'] as num?)?.toInt();
        if (activityId == null || !treeGrowingActivityIds.contains(activityId)) {
          continue;
        }
        surviveTotal += (row['number_tree_survived'] as num?)?.toInt() ??
            (row['number_tree_sur'] as num?)?.toInt() ??
            0;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('total_seedling_survive', surviveTotal);

      if (!mounted) return;
      setState(() {
        _totalSeedlingSurvive = surviveTotal;
        _isLoadingSurviveStats = false;
        _isCachedSurviveStats = false;
      });
    } catch (_) {
      await _loadSurviveStatsFromCache();
    }
  }

  Future<void> _loadSurviveStatsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedSurvive = prefs.getInt('total_seedling_survive');

      if (!mounted) return;
      setState(() {
        _totalSeedlingSurvive = cachedSurvive ?? 0;
        _isLoadingSurviveStats = false;
        _isCachedSurviveStats = cachedSurvive != null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingSurviveStats = false;
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

      final treeGrowingResponse = await Supabase.instance.client
          .from('tree_growing')
          .select('*')
          .eq('is_deleted', 0)
          .timeout(const Duration(seconds: 5));

      final treeGrowingDataResponse = await Supabase.instance.client
          .from('tree_growing_data')
          .select('tree_growing_id')
          .timeout(const Duration(seconds: 5));

      final idsWithSpeciesData = treeGrowingDataResponse
          .map((row) => _toInt((row as Map)['tree_growing_id']))
          .whereType<int>()
          .toSet();

      final locationResponse = await Supabase.instance.client
          .from('location')
          .select('id, activity_id, activity_type_id, latitude, longitude')
          .eq('isDeleted', 0)
          .timeout(const Duration(seconds: 5));

      final floraFaunaResponse = await Supabase.instance.client
          .from('flora_fauna_survey')
          .select('*')
          .eq('is_deleted', 0)
          .timeout(const Duration(seconds: 5));

      final floraFaunaDataResponse = await Supabase.instance.client
          .from('flora_fauna_survey_data')
          .select('flora_fauna_id')
          .timeout(const Duration(seconds: 5));

      final floraFaunaIdsWithSpeciesData = floraFaunaDataResponse
          .map((row) => _toInt((row as Map)['flora_fauna_id']))
          .whereType<int>()
          .toSet();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tree_growing_json', jsonEncode(treeGrowingResponse));
      await prefs.setString(
        'tree_growing_data_ids_json',
        jsonEncode(idsWithSpeciesData.toList()),
      );
      await prefs.setString('location_json', jsonEncode(locationResponse));
      await prefs.setString(
          'flora_fauna_survey_json', jsonEncode(floraFaunaResponse));
      await prefs.setString(
        'flora_fauna_survey_data_ids_json',
        jsonEncode(floraFaunaIdsWithSpeciesData.toList()),
      );
      await prefs.setString('markers_cache_date', DateTime.now().toIso8601String());

      final typedTreeRows = treeGrowingResponse
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final typedLocationRows = locationResponse
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final typedFloraFaunaRows = floraFaunaResponse
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

      _treeGrowingIdsWithSpeciesData = idsWithSpeciesData;
      _floraFaunaIdsWithSpeciesData = floraFaunaIdsWithSpeciesData;

      final markers = [
        ..._buildMarkersFromData(typedTreeRows,
            locationResponse: typedLocationRows),
        ..._buildFloraFaunaMarkersFromData(
            typedLocationRows, typedFloraFaunaRows),
      ];
      final polygons = [
        ..._buildPolygonsFromData(typedTreeRows,
            locationResponse: typedLocationRows),
        ..._buildFloraFaunaPolygonsFromData(
            typedLocationRows, typedFloraFaunaRows),
      ];

      if (!mounted) return;
      setState(() {
        _allTreeGrowingRows = typedTreeRows;
        _allLocationRows = typedLocationRows;
        _allFloraFaunaRows = typedFloraFaunaRows;
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
      final treeGrowingJson = prefs.getString('tree_growing_json');

      if (treeGrowingJson == null) {
        if (!mounted) return;
        setState(() => _isLoadingMarkers = false);
        return;
      }

      final treeGrowingResponse =
          List<Map<String, dynamic>>.from(jsonDecode(treeGrowingJson) as List);

      final treeGrowingDataIdsJson =
          prefs.getString('tree_growing_data_ids_json');
      _treeGrowingIdsWithSpeciesData = treeGrowingDataIdsJson != null
          ? (jsonDecode(treeGrowingDataIdsJson) as List)
              .map((id) => (id as num).toInt())
              .toSet()
          : {};

      final locationJson = prefs.getString('location_json');
      final floraFaunaJson = prefs.getString('flora_fauna_survey_json');
      final locationResponse = locationJson != null
          ? List<Map<String, dynamic>>.from(jsonDecode(locationJson) as List)
          : <Map<String, dynamic>>[];
      final floraFaunaResponse = floraFaunaJson != null
          ? List<Map<String, dynamic>>.from(
              jsonDecode(floraFaunaJson) as List)
          : <Map<String, dynamic>>[];

      final floraFaunaDataIdsJson =
          prefs.getString('flora_fauna_survey_data_ids_json');
      _floraFaunaIdsWithSpeciesData = floraFaunaDataIdsJson != null
          ? (jsonDecode(floraFaunaDataIdsJson) as List)
              .map((id) => (id as num).toInt())
              .toSet()
          : {};

      final markers = [
        ..._buildMarkersFromData(treeGrowingResponse,
            locationResponse: locationResponse),
        ..._buildFloraFaunaMarkersFromData(locationResponse, floraFaunaResponse),
      ];
      final polygons = [
        ..._buildPolygonsFromData(treeGrowingResponse,
            locationResponse: locationResponse),
        ..._buildFloraFaunaPolygonsFromData(
            locationResponse, floraFaunaResponse),
      ];

      if (!mounted) return;
      setState(() {
        _allTreeGrowingRows = treeGrowingResponse;
        _allLocationRows = locationResponse;
        _allFloraFaunaRows = floraFaunaResponse;
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

  // Habitat Assessment and Marine Protected Area have their own dashboard
  // (see CoastalDashboardPage) and aren't handled by this page's marker
  // loading logic, so they're excluded from this filter regardless of their
  // dashboard_filter flag.
  static const List<int> _excludedProjectTypeIds = [8, 9];

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
          .where((row) => !_excludedProjectTypeIds.contains(_toInt(row['id'])))
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
    final markers = [
      ..._buildMarkersFromData(_allTreeGrowingRows,
          locationResponse: _allLocationRows),
      ..._buildFloraFaunaMarkersFromData(_allLocationRows, _allFloraFaunaRows),
    ];
    final polygons = [
      ..._buildPolygonsFromData(_allTreeGrowingRows,
          locationResponse: _allLocationRows),
      ..._buildFloraFaunaPolygonsFromData(
          _allLocationRows, _allFloraFaunaRows),
    ];

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

  /// Rows from `location` that belong to the Tree Growing flow
  /// (activity_type_id == 1). Filtered explicitly so a numeric activity_id
  /// collision with another activity type (e.g. a Flora & Fauna survey id)
  /// can never be mistaken for a tree growing point.
  List<dynamic> _treeGrowingLocationRows(List<dynamic> locationResponse) {
    return locationResponse.where((item) {
      final row = Map<String, dynamic>.from(item as Map);
      return _toInt(row['activity_type_id']) == 1;
    }).toList();
  }

  List<Marker> _buildMarkersFromData(
    List<dynamic> treeGrowingResponse, {
    List<dynamic> locationResponse = const [],
  }) {
    final activityMap = <int, Map<String, dynamic>>{};
    for (final item in treeGrowingResponse) {
      final row = Map<String, dynamic>.from(item as Map);
      final rowSeqId = (row['seq_id'] as num?)?.toInt();
      if (rowSeqId != null) {
        activityMap[rowSeqId] = row;
      }
    }

    final combinedRows = _treeGrowingLocationRows(locationResponse);

    final markers = <Marker>[];
    final seenSeqIds = <int>{};
    for (final item in combinedRows) {
      final row = Map<String, dynamic>.from(item as Map);
      final lat = _toDouble(row['latitude']);
      final lng = _toDouble(row['longitude']);
      final seqId = (row['activity_id'] as num?)?.toInt();

      if (lat == null || lng == null || seqId == null) continue;

      // Only show a marker when its activity_id resolves to an actual
      // tree_growing row (tree_growing.seq_id) AND that row has matching
      // species data (tree_growing_data.tree_growing_id == seq_id).
      final activityData = activityMap[seqId];
      if (activityData == null) continue;
      if (!_matchesSelectedProjectType(activityData)) continue;
      if (!_treeGrowingIdsWithSpeciesData.contains(seqId)) continue;

      // An activity can have several location points — collapse them to a
      // single marker per seq_id.
      if (!seenSeqIds.add(seqId)) continue;

      markers.add(
        Marker(
          point: ll.LatLng(lat, lng),
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _showMarkerInfo(activityData, seqId, row['id'], lat, lng),
            child: _RingMarkerIcon(seqId: seqId),
          ),
        ),
      );
    }
    return markers;
  }

  List<Polygon> _buildPolygonsFromData(
    List<dynamic> treeGrowingResponse, {
    List<dynamic> locationResponse = const [],
  }) {
    final coordinatesByActivity = <dynamic, List<ll.LatLng>>{};
    final activityMap = <dynamic, Map<String, dynamic>>{};

    for (final item in treeGrowingResponse) {
      final row = Map<String, dynamic>.from(item as Map);
      activityMap[row['seq_id']] = row;
    }

    final combinedRows = _treeGrowingLocationRows(locationResponse);

    for (final item in combinedRows) {
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

  /// Mirrors _buildMarkersFromData but for the Flora and Fauna Survey flow,
  /// where coordinates live in location (activity_type_id == project_type_id)
  /// joined via location.activity_id == flora_fauna_survey.id, and species
  /// data lives in flora_fauna_survey_data.flora_fauna_id.
  List<Marker> _buildFloraFaunaMarkersFromData(
    List<dynamic> locationResponse,
    List<dynamic> floraFaunaResponse,
  ) {
    final surveyMap = <int, Map<String, dynamic>>{};
    for (final item in floraFaunaResponse) {
      final row = Map<String, dynamic>.from(item as Map);
      final rowId = _toInt(row['id']);
      if (rowId != null) {
        surveyMap[rowId] = row;
      }
    }

    final markers = <Marker>[];
    final seenSurveyIds = <int>{};
    for (final item in locationResponse) {
      final row = Map<String, dynamic>.from(item as Map);
      // location is shared by several activity types now (Tree Growing,
      // Mangrove, Habitat Assessment, Marine Protected Area). Without this
      // filter, a numeric activity_id collision with another type's row
      // could be mistaken for a flora & fauna survey.
      if (_toInt(row['activity_type_id']) != 3) continue;
      final lat = _toDouble(row['latitude']);
      final lng = _toDouble(row['longitude']);
      final surveyId = _toInt(row['activity_id']);

      if (lat == null || lng == null || surveyId == null) continue;

      final surveyData = surveyMap[surveyId];
      if (surveyData == null) continue;
      if (!_matchesSelectedProjectType(surveyData)) continue;
      if (!_floraFaunaIdsWithSpeciesData.contains(surveyId)) continue;

      // A survey can have several location points — collapse to one marker.
      if (!seenSurveyIds.add(surveyId)) continue;

      markers.add(
        Marker(
          point: ll.LatLng(lat, lng),
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () =>
                _showMarkerInfo(surveyData, surveyId, row['id'], lat, lng),
            child: _RingMarkerIcon(seqId: surveyId),
          ),
        ),
      );
    }
    return markers;
  }

  List<Polygon> _buildFloraFaunaPolygonsFromData(
    List<dynamic> locationResponse,
    List<dynamic> floraFaunaResponse,
  ) {
    final coordinatesBySurvey = <int, List<ll.LatLng>>{};
    final surveyMap = <int, Map<String, dynamic>>{};

    for (final item in floraFaunaResponse) {
      final row = Map<String, dynamic>.from(item as Map);
      final rowId = _toInt(row['id']);
      if (rowId != null) {
        surveyMap[rowId] = row;
      }
    }

    for (final item in locationResponse) {
      final row = Map<String, dynamic>.from(item as Map);
      if (_toInt(row['activity_type_id']) != 3) continue;
      final surveyId = _toInt(row['activity_id']);
      final lat = _toDouble(row['latitude']);
      final lng = _toDouble(row['longitude']);

      if (surveyId == null || lat == null || lng == null) continue;

      final surveyData = surveyMap[surveyId];
      if (!_matchesSelectedProjectType(surveyData)) continue;

      coordinatesBySurvey.putIfAbsent(surveyId, () => []);
      coordinatesBySurvey[surveyId]!.add(ll.LatLng(lat, lng));
    }

    final polygons = <Polygon>[];
    for (final entry in coordinatesBySurvey.entries) {
      final points = entry.value;
      if (points.length < 4) continue;

      final areaHectares =
          PolygonCalculator.calculatePolygonAreaInHectares(points);
      var polygonColor = Colors.orange.shade300;
      if (areaHectares > 10) {
        polygonColor = Colors.purple.shade300;
      } else if (areaHectares > 5) {
        polygonColor = Colors.amber.shade300;
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

  /// Stacks spiderfied cluster markers in a vertical line above/below the
  /// cluster's screen position instead of the package's default circle/spiral.
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
      final fileName = 'Map_${DateTime.now().millisecondsSinceEpoch}.png';

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
      debugPrint('Error capturing map: $e');
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
      debugPrint('Error saving map image: $e');
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

      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempFile.path)],
          subject: fileName,
          text: 'Sharing $fileName',
        ),
      );

      if (result.status == ShareResultStatus.dismissed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Share cancelled')),
        );
      }
    } catch (e) {
      debugPrint('Error sharing map image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing map image: $e')),
        );
      }
    }
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
                  child: FutureBuilder<List<MapEntry<String, String>>>(
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
                          const [
                            MapEntry('Activity', 'N/A'),
                            MapEntry('Municipality', 'N/A'),
                            MapEntry('Barangay', 'N/A'),
                            MapEntry('Lat & Long', 'N/A'),
                            MapEntry('Area', 'N/A'),
                            MapEntry('Planting Date', 'N/A'),
                          ];

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

  Future<List<MapEntry<String, String>>> _loadDialogDetails({
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

    // flora_fauna_survey rows carry a survey_date column that tree_growing
    // rows don't — use it to tell the two activity flows apart.
    final isFloraFauna = safeData.containsKey('survey_date');
    final plantingDate = _formatPlantingDate(
      safeData['survey_date'] ?? safeData['planting_date'] ?? safeData['created_at'],
    );

    String area = 'N/A';
    // Tree Growing shows two fixed rows; Flora and Fauna instead shows one
    // row per species_type present (e.g. "Flora", "Fauna"), each listing the
    // names captured for that type.
    final speciesGroupRows = <MapEntry<String, String>>[];

    try {
      if (activityId != null) {
        final coords = <ll.LatLng>[];

        if (isFloraFauna) {
          final speciesRows = await Supabase.instance.client
              .from('flora_fauna_survey_data')
              .select('name, species_type')
              .eq('flora_fauna_id', activityId);

          final rows = List<Map<String, dynamic>>.from(speciesRows as List);
          final namesByType = <String, List<String>>{};
          for (final row in rows) {
            final type = (row['species_type'] ?? '').toString().trim();
            final name = (row['name'] ?? '').toString().trim();
            if (type.isEmpty || name.isEmpty) continue;
            namesByType.putIfAbsent(type, () => []).add(name);
          }
          for (final entry in namesByType.entries) {
            speciesGroupRows.add(MapEntry(entry.key, entry.value.join(', ')));
          }

          final locationRows = await Supabase.instance.client
              .from('location')
              .select('latitude, longitude')
              .eq('activity_id', activityId)
              .eq('isDeleted', 0);

          coords.addAll(
            List<Map<String, dynamic>>.from(locationRows as List)
                .map((row) {
                  final latitude = _toDouble(row['latitude']);
                  final longitude = _toDouble(row['longitude']);
                  if (latitude == null || longitude == null) return null;
                  return ll.LatLng(latitude, longitude);
                })
                .whereType<ll.LatLng>(),
          );
        } else {
          final seedRows = await Supabase.instance.client
              .from('tree_growing_data')
              .select('seed_name, seedling_count')
              .eq('tree_growing_id', activityId);

          final rows = List<Map<String, dynamic>>.from(seedRows as List);
          String seedlingName = 'N/A';
          String seedlingCount = '0';
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
          speciesGroupRows.add(MapEntry('Seedling Name', seedlingName));
          speciesGroupRows.add(MapEntry('Seedling Count', seedlingCount));

          final locationCoordinateRows = await Supabase.instance.client
              .from('location')
              .select('latitude, longitude')
              .eq('activity_id', activityId)
              .eq('activity_type_id', 1)
              .eq('isDeleted', 0);

          coords.addAll(
            List<Map<String, dynamic>>.from(locationCoordinateRows as List)
                .map((row) {
                  final latitude = _toDouble(row['latitude']);
                  final longitude = _toDouble(row['longitude']);
                  if (latitude == null || longitude == null) return null;
                  return ll.LatLng(latitude, longitude);
                })
                .whereType<ll.LatLng>(),
          );
        }

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
          final areaCover =
              _toDouble(safeData[isFloraFauna ? 'area' : 'area_cover']);
          if (areaCover != null && areaCover > 0) {
            area = '${areaCover.toStringAsFixed(2)} ha';
          }
        }
      }
    } catch (_) {
      // Keep graceful fallback values.
    }

    return [
      MapEntry('Activity', activityName),
      MapEntry('Municipality', municipality),
      MapEntry('Barangay', barangay),
      MapEntry('Lat & Long', latLong),
      ...speciesGroupRows,
      MapEntry('Area', area),
      MapEntry('Planting Date', plantingDate),
    ];
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
                              initialCenter: const ll.LatLng(11.39815374730887, 122.73605826343467),
                              initialZoom: 9.8,
                              interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                              ),
                              onTap: (_, __) {
                                // Only force the (expensive) cluster layer
                                // remount when a cluster was actually
                                // expanded — avoids rebuilding the whole
                                // marker tree on every stray tap, which was
                                // freezing the map during rapid dragging.
                                if (_hasExpandedCluster) {
                                  _hasExpandedCluster = false;
                                  setState(() => _mapTapVersion++);
                                }
                              },
                            ),
                            children: [
                              ...basemapTileLayers(_basemap),
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
                                  onClusterTap: (_) =>
                                      _hasExpandedCluster = true,
                                  spiderfyShapePositions:
                                      _verticalSpiderfyPositions,
                                  builder: (context, markers) {
                                    return Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.green.shade600,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.25),
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
                              BasemapAttribution(basemap: _basemap),
                            ],
                          ),
                    ),
                  ),
                  // Basemap style picker
                  Positioned(
                    left: 12,
                    top: 12,
                    child: BasemapSwitcher(
                      selected: _basemap,
                      accentColor: Colors.teal.shade700,
                      onChanged: (basemap) =>
                          setState(() => _basemap = basemap),
                    ),
                  ),
                  // Capture map button
                  Positioned(
                    right: 12,
                    top: 12,
                    child: FloatingActionButton(
                      heroTag: 'capture_map',
                      onPressed:
                          _isCapturingMap ? null : _captureAndExportMap,
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
            const SizedBox(height: 24),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.9,
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
                _buildStatCard(
                  title: 'Total Seedling Survive',
                  value: _isLoadingSurviveStats
                      ? '...'
                      : '$_totalSeedlingSurvive',
                  trend: _isCachedSurviveStats ? 'Cached' : 'Live',
                ),
              ],
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

class _RingMarkerIcon extends StatelessWidget {
  final int seqId;

  const _RingMarkerIcon({required this.seqId});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.green.shade600,
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

