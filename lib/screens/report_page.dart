import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../service/api_service.dart';
import '../widget/export_options_dialog.dart';
import '../widget/side_panel.dart';
import '../widget/web_helper.dart' as web_helper;

class ReportPage extends StatelessWidget {
  const ReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ReportsScreen(
      isCollapsed: false,
      onToggle: () {},
    );
  }
}

class ReportsScreen extends StatefulWidget {
  final bool isCollapsed;
  final VoidCallback onToggle;

  const ReportsScreen({
    super.key,
    required this.isCollapsed,
    required this.onToggle,
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _selectedProjectTypeName = 'Tree Growing';
  int? _selectedProjectTypeId;
  bool _isLoading = false;
  List<Map<String, dynamic>> _reportData = [];
  List<Map<String, dynamic>> _projectTypes = [];
  String _selectedPeriod = 'all';
  DateTimeRange? _selectedDateRange;
  late ScrollController _horizontalScrollController;
  bool _isLoadingReport = false;
  List<String> _seedlingNurseryColumns = [];

  static const int _rowsPerPage = 50;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _horizontalScrollController = ScrollController();
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadProjectTypes();
          _loadReport();
        }
      });
    } catch (e) {
      debugPrint('❌ Error initializing reports: $e');
    }
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadProjectTypes() async {
    try {
      final response = await Supabase.instance.client
          .from('project_type')
          .select('id, projectname')
          .order('id', ascending: true)
          .timeout(const Duration(seconds: 5));

      final typed =
          response.map((row) => Map<String, dynamic>.from(row as Map)).toList();

      if (!mounted) return;
      setState(() {
        _projectTypes = typed;
        if (_selectedProjectTypeId == null && typed.isNotEmpty) {
          final defaultMatch = typed.firstWhere(
            (projectType) =>
                (projectType['projectname'] ?? '').toString().toLowerCase() ==
                'tree growing',
            orElse: () => typed.first,
          );
          _selectedProjectTypeId = _toInt(defaultMatch['id']);
          _selectedProjectTypeName =
              (defaultMatch['projectname'] ?? 'all').toString();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _projectTypes = []);
    }
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String? get _dropdownProjectTypeValue {
    final exists = _projectTypes.any((projectType) =>
        (projectType['projectname'] ?? '').toString() ==
        _selectedProjectTypeName);
    return exists ? _selectedProjectTypeName : null;
  }

  Future<void> _loadReport() async {
    if (!mounted) return;
    if (_isLoadingReport) {
      return;
    }

    _isLoadingReport = true;
    _currentPage = 0;

    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      List<dynamic> data = [];
      final tableName =
          _resolveTableNameForSelection(_selectedProjectTypeName);

      final query = Supabase.instance.client.from(tableName).select('*');
      var filteredQuery = query;
      if (tableName == 'tree_growing' && _selectedProjectTypeId != null) {
        filteredQuery = filteredQuery.eq('project_type_id', _selectedProjectTypeId!);
      } else if (tableName == 'seedling_transaction' && _isSeedlingRequestSelected) {
        filteredQuery = filteredQuery.eq('transaction_type_id', 2);
      } else if (tableName == 'crm_habitat_assssment' ||
          tableName == 'crm_marine_protected') {
        filteredQuery = filteredQuery.eq('is_deleted', 0);
      }

      final completer = Completer<List<dynamic>>();

      filteredQuery.limit(500).then((result) {
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      }).catchError((e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      });

      data = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Query timed out');
        },
      );

      if (data.isEmpty) {
        if (mounted) {
          setState(() {
            _reportData = [];
            _isLoading = false;
          });
        }
        return;
      }

      var mapData = List<Map<String, dynamic>>.from(data);

      if (tableName == 'tree_growing') {
        mapData = await _attachTreeGrowingSpeciesRows(mapData);
      } else if (tableName == 'flora_fauna_survey') {
        mapData = await _attachFloraFaunaSpeciesRows(mapData);
      } else if (tableName == 'tree_survival_monitoring') {
        mapData = await _attachTreeSurvivalSpeciesRows(mapData);
      } else if (tableName == 'seed_donation') {
        mapData = await _attachSeedDonationSpeciesRows(mapData);
      } else if (tableName == 'crm_habitat_assssment') {
        mapData = await _attachHabitatAssessmentSummaryRows(mapData);
      }

      final filteredData = await compute(
        _filterDataInBackground,
        {
          'data': mapData,
          'period': _selectedPeriod,
          'dateFieldName': _getDateFieldName(),
          'startDate': _selectedDateRange?.start.toIso8601String(),
          'endDate': _selectedDateRange?.end.toIso8601String(),
        },
      );

      var finalData = filteredData;
      if (tableName == 'seedling_transaction') {
        finalData = _isSeedlingRequestSelected
            ? await _buildSeedlingRequestRows(filteredData)
            : await _buildSeedlingInventoryRows(filteredData);
      }

      if (mounted) {
        setState(() {
          _reportData = finalData;
          _isLoading = false;
        });
      }

      if (finalData.length <= 5000) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'report_${_selectedProjectTypeId ?? 'all'}_cache',
            jsonEncode(finalData),
          );
        } catch (e) {
          debugPrint('⚠️ Error caching data: $e');
        }
      }
    } catch (e) {
      debugPrint('❌ Unexpected error in _loadReport: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      _loadReportFromCache();
    } finally {
      _isLoadingReport = false;
    }
  }

  /// Expands each tree_growing activity row into one row per species/count
  /// captured in tree_growing_data, joined via
  /// tree_growing.seq_id == tree_growing_data.tree_growing_id.
  ///
  /// Mangrove Planting's report doesn't show species/tree-count columns at
  /// all (see _getColumnsToDisplay), so it's passed through as one row per
  /// activity instead — otherwise an activity with no seedlings recorded yet
  /// would be silently omitted from the report entirely.
  Future<List<Map<String, dynamic>>> _attachTreeGrowingSpeciesRows(
    List<Map<String, dynamic>> rows,
  ) async {
    if (_isMangrovePlantingSelected) return rows;

    final seqIds = rows
        .map((row) => (row['seq_id'] as num?)?.toInt())
        .whereType<int>()
        .toList();

    if (seqIds.isEmpty) return rows;

    Map<int, List<Map<String, dynamic>>> seedRowsByActivity;
    try {
      seedRowsByActivity =
          await ApiService.getTreeGrowingDataByTreeGrowingIds(seqIds);
    } catch (e) {
      debugPrint('⚠️ Error fetching tree_growing_data rows: $e');
      return rows;
    }

    final flattened = <Map<String, dynamic>>[];
    for (final row in rows) {
      final seqId = (row['seq_id'] as num?)?.toInt();
      final seedRows = seqId != null ? seedRowsByActivity[seqId] : null;

      if (seedRows == null || seedRows.isEmpty) {
        // No matching tree_growing_data rows for this activity — omit it.
        continue;
      }

      for (final seedRow in seedRows) {
        flattened.add({
          ...row,
          'tree_species': seedRow['seed_name'],
          'number_of_trees': seedRow['seedling_count'],
        });
      }
    }

    return flattened;
  }

  /// Summarizes each habitat assessment row with its species names and total
  /// count from crm_habitat_assssment_data — matching what the activity list
  /// card shows (species joined by ", ", counts summed). Unlike
  /// _attachTreeGrowingSpeciesRows this keeps one row per assessment rather
  /// than expanding to one row per species, and never omits an assessment
  /// for having no species rows yet.
  Future<List<Map<String, dynamic>>> _attachHabitatAssessmentSummaryRows(
    List<Map<String, dynamic>> rows,
  ) async {
    final ids = rows
        .map((row) => (row['id'] as num?)?.toInt())
        .whereType<int>()
        .toList();

    var speciesRowsByAssessment = <int, List<Map<String, dynamic>>>{};
    if (ids.isNotEmpty) {
      try {
        speciesRowsByAssessment =
            await ApiService.getHabitatAssessmentDataByAssessmentIds(ids);
      } catch (e) {
        debugPrint('⚠️ Error fetching crm_habitat_assssment_data rows: $e');
      }
    }

    return rows.map((row) {
      final id = (row['id'] as num?)?.toInt();
      final speciesRows =
          id != null ? speciesRowsByAssessment[id] ?? const [] : const [];

      final speciesNames = speciesRows
          .map((r) => (r['species_name'] ?? '').toString().trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .join(', ');

      final totalCount = speciesRows.fold<int>(
        0,
        (sum, r) => sum + ((r['count'] as num?)?.toInt() ?? 0),
      );

      return {
        ...row,
        'species': speciesNames.isEmpty ? 'Unspecified' : speciesNames,
        'total_count': totalCount,
      };
    }).toList();
  }

  /// Expands each flora_fauna_survey row into one row per species captured
  /// in flora_fauna_survey_data, joined via
  /// flora_fauna_survey.id == flora_fauna_survey_data.flora_fauna_id.
  Future<List<Map<String, dynamic>>> _attachFloraFaunaSpeciesRows(
    List<Map<String, dynamic>> rows,
  ) async {
    final surveyIds = rows
        .map((row) => _parseNullableInt(row['id']))
        .whereType<int>()
        .toList();

    if (surveyIds.isEmpty) return rows;

    Map<int, List<Map<String, dynamic>>> speciesRowsBySurvey;
    try {
      speciesRowsBySurvey =
          await ApiService.getFloraFaunaSurveyDataByFloraFaunaIds(surveyIds);
    } catch (e) {
      debugPrint('⚠️ Error fetching flora_fauna_survey_data rows: $e');
      return rows;
    }

    final flattened = <Map<String, dynamic>>[];
    for (final row in rows) {
      final surveyId = _parseNullableInt(row['id']);
      final speciesRows =
          surveyId != null ? speciesRowsBySurvey[surveyId] : null;

      if (speciesRows == null || speciesRows.isEmpty) {
        // No matching flora_fauna_survey_data rows for this survey — omit it.
        continue;
      }

      for (final speciesRow in speciesRows) {
        flattened.add({
          ...row,
          'species_type': speciesRow['species_type'],
          'classification': speciesRow['classification'],
          'species_name': speciesRow['name'],
        });
      }
    }

    return flattened;
  }

  /// Each tree_survival_monitoring row already represents exactly one
  /// species (seed_id == tree_growing_data.id), so this just attaches the
  /// species name/count and the tree_growing activity's name/location —
  /// no fan-out needed.
  ///
  /// tree_survival_monitoring rows aren't tagged with a project type of
  /// their own — activity_id just points into tree_growing, which is shared
  /// by Tree Growing (project_type_id 1) and Mangrove Planting (6). Only
  /// keep rows whose activity matches whichever of those two is selected —
  /// same disambiguation the recent-activity list pages already do.
  Future<List<Map<String, dynamic>>> _attachTreeSurvivalSpeciesRows(
    List<Map<String, dynamic>> rows,
  ) async {
    final activityIds = rows
        .map((row) => _parseNullableInt(row['activity_id']))
        .whereType<int>()
        .toSet()
        .toList();

    if (activityIds.isEmpty) return [];

    final expectedProjectTypeId = _isMangroveSurvivalSelected ? 6 : 1;

    Map<int, Map<String, dynamic>> treeGrowingBySeqId;
    Map<int, Map<String, dynamic>> seedRowById;
    try {
      final treeGrowingRows = await Supabase.instance.client
          .from('tree_growing')
          .select(
              'seq_id, activity_name, municipality, barangay, area_cover, project_type_id')
          .inFilter('seq_id', activityIds);

      treeGrowingBySeqId = {
        for (final item in (treeGrowingRows as List))
          if (_parseNullableInt((item as Map)['seq_id']) != null)
            _parseNullableInt(item['seq_id'])!: Map<String, dynamic>.from(item),
      };

      final seedRowsByActivity =
          await ApiService.getTreeGrowingDataByTreeGrowingIds(activityIds);
      seedRowById = {
        for (final seedRows in seedRowsByActivity.values)
          for (final seedRow in seedRows)
            if (_parseNullableInt(seedRow['id']) != null)
              _parseNullableInt(seedRow['id'])!: seedRow,
      };
    } catch (e) {
      debugPrint('⚠️ Error fetching tree survival join data: $e');
      return [];
    }

    final flattened = <Map<String, dynamic>>[];
    for (final row in rows) {
      final activityId = _parseNullableInt(row['activity_id']);
      final seedId = _parseNullableInt(row['seed_id']);
      final seedRow = seedId != null ? seedRowById[seedId] : null;

      if (activityId == null || seedRow == null) {
        // No matching tree_growing_data row for this seed_id — omit it.
        continue;
      }

      final treeGrowingRow = treeGrowingBySeqId[activityId];
      if (_parseNullableInt(treeGrowingRow?['project_type_id']) !=
          expectedProjectTypeId) {
        // Belongs to the other project type sharing this table — omit it.
        continue;
      }

      final quarter = row['quarter'];
      final quarterLabel = quarter == null ? '' : 'Q$quarter';

      flattened.add({
        ...row,
        'activity_name': treeGrowingRow?['activity_name'] ?? '',
        'municipality': treeGrowingRow?['municipality'] ?? '',
        'barangay': treeGrowingRow?['barangay'] ?? '',
        'area_cover': treeGrowingRow?['area_cover'],
        'tree_species': seedRow['seed_name'],
        'number_of_trees': seedRow['seedling_count'],
        'quarter_label': quarterLabel,
      });
    }

    return flattened;
  }

  /// Expands each seed_donation row into one row per species captured in
  /// seed_donation_data, joined via
  /// seed_donation.id == seed_donation_data.seed_donation_id, with the
  /// species name resolved via seedling_list.seq_id == seed_id.
  Future<List<Map<String, dynamic>>> _attachSeedDonationSpeciesRows(
    List<Map<String, dynamic>> rows,
  ) async {
    final donationIds = rows
        .map((row) => _parseNullableInt(row['id']))
        .whereType<int>()
        .toList();

    if (donationIds.isEmpty) return rows;

    final Map<int, List<Map<String, dynamic>>> dataRowsByDonationId = {};
    final Map<int, String> seedNameById = {};

    try {
      final dataRows = await Supabase.instance.client
          .from('seed_donation_data')
          .select('seed_donation_id, seed_id, seed_count')
          .inFilter('seed_donation_id', donationIds);

      final parsedDataRows = (dataRows as List).cast<Map<String, dynamic>>();
      for (final row in parsedDataRows) {
        final donationId = _parseNullableInt(row['seed_donation_id']);
        if (donationId == null) continue;
        dataRowsByDonationId.putIfAbsent(donationId, () => []).add(row);
      }

      final seedIds = parsedDataRows
          .map((row) => _parseNullableInt(row['seed_id']))
          .whereType<int>()
          .toSet()
          .toList();

      if (seedIds.isNotEmpty) {
        final seedRows = await Supabase.instance.client
            .from('seedling_list')
            .select('seq_id, seedling_name')
            .inFilter('seq_id', seedIds);
        for (final row in (seedRows as List).cast<Map<String, dynamic>>()) {
          final id = _parseNullableInt(row['seq_id']);
          if (id != null) {
            seedNameById[id] = (row['seedling_name'] ?? '').toString();
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching seed_donation_data rows: $e');
      return rows;
    }

    final flattened = <Map<String, dynamic>>[];
    for (final row in rows) {
      final donationId = _parseNullableInt(row['id']);
      final dataRows =
          donationId != null ? dataRowsByDonationId[donationId] : null;

      if (dataRows == null || dataRows.isEmpty) {
        // No matching seed_donation_data rows for this donation — omit it.
        continue;
      }

      for (final dataRow in dataRows) {
        final seedId = _parseNullableInt(dataRow['seed_id']);
        flattened.add({
          ...row,
          'seed_species_name':
              seedId != null ? (seedNameById[seedId] ?? 'Unspecified') : 'Unspecified',
          'seed_count': dataRow['seed_count'],
        });
      }
    }

    return flattened;
  }

  /// Builds the Seedling Request view: one row per seedling_transaction
  /// record (already filtered to transaction_type_id == 2 == release),
  /// joined against seedling_list and seedling_nursery for display names.
  Future<List<Map<String, dynamic>>> _buildSeedlingRequestRows(
    List<Map<String, dynamic>> rows,
  ) async {
    final seedIds = rows
        .map((row) => _parseNullableInt(row['seed_id']))
        .whereType<int>()
        .toSet()
        .toList();
    final nurseryIds = rows
        .map((row) => _parseNullableInt(row['nursery_id']))
        .whereType<int>()
        .toSet()
        .toList();

    final Map<int, String> seedNameById = {};
    final Map<int, String> nurseryNameById = {};

    try {
      if (seedIds.isNotEmpty) {
        final seedRows = await Supabase.instance.client
            .from('seedling_list')
            .select('seq_id, seedling_name')
            .inFilter('seq_id', seedIds);
        for (final row in (seedRows as List).cast<Map<String, dynamic>>()) {
          final id = _parseNullableInt(row['seq_id']);
          if (id != null) {
            seedNameById[id] = (row['seedling_name'] ?? '').toString();
          }
        }
      }

      if (nurseryIds.isNotEmpty) {
        final nurseryRows = await Supabase.instance.client
            .from('seedling_nursery')
            .select('seq_id, name')
            .inFilter('seq_id', nurseryIds);
        for (final row
            in (nurseryRows as List).cast<Map<String, dynamic>>()) {
          final id = _parseNullableInt(row['seq_id']);
          if (id != null) {
            nurseryNameById[id] = (row['name'] ?? '').toString();
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching seedling request join data: $e');
    }

    return rows.map((row) {
      final seedId = _parseNullableInt(row['seed_id']);
      final nurseryId = _parseNullableInt(row['nursery_id']);
      final createdAt = (row['created_at'] ?? '').toString();

      return <String, dynamic>{
        'no': _parseNullableInt(row['transaction_id']),
        'release_by': (row['release_by'] ?? '').toString(),
        'release_to': (row['release_to'] ?? '').toString(),
        'species': seedId != null
            ? (seedNameById[seedId] ?? 'Unspecified')
            : 'Unspecified',
        'quantity': row['seedling_count'],
        'nursery': nurseryId != null
            ? (nurseryNameById[nurseryId] ?? 'Unspecified')
            : 'Unspecified',
        'date': createdAt.isEmpty ? '' : createdAt.split('T').first,
      };
    }).toList();
  }

  /// Builds the Seedling Inventory pivot: one row per species/nursery
  /// showing the quantity received (transaction_type_id == 1) at that
  /// nursery, plus a final "Available" row per species equal to
  /// (sum of transaction_type_id == 1) - (sum of transaction_type_id == 2)
  /// across all nurseries.
  Future<List<Map<String, dynamic>>> _buildSeedlingInventoryRows(
    List<Map<String, dynamic>> rows,
  ) async {
    final seedIds = rows
        .map((row) => _parseNullableInt(row['seed_id']))
        .whereType<int>()
        .toSet()
        .toList();
    final nurseryIds = rows
        .map((row) => _parseNullableInt(row['nursery_id']))
        .whereType<int>()
        .toSet()
        .toList();

    final Map<int, String> seedNameById = {};
    final Map<int, String> nurseryNameById = {};

    try {
      if (seedIds.isNotEmpty) {
        final seedRows = await Supabase.instance.client
            .from('seedling_list')
            .select('seq_id, seedling_name')
            .inFilter('seq_id', seedIds);
        for (final row in (seedRows as List).cast<Map<String, dynamic>>()) {
          final id = _parseNullableInt(row['seq_id']);
          if (id != null) {
            seedNameById[id] = (row['seedling_name'] ?? '').toString();
          }
        }
      }

      if (nurseryIds.isNotEmpty) {
        final nurseryRows = await Supabase.instance.client
            .from('seedling_nursery')
            .select('seq_id, name')
            .inFilter('seq_id', nurseryIds);
        for (final row
            in (nurseryRows as List).cast<Map<String, dynamic>>()) {
          final id = _parseNullableInt(row['seq_id']);
          if (id != null) {
            nurseryNameById[id] = (row['name'] ?? '').toString();
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching seedling inventory lookups: $e');
    }

    // Per seed: net (type 1 - type 2) quantity per nursery, plus the
    // overall net available across all rows, including rows with no
    // nursery assigned.
    final Map<int, Map<int, int>> netBySeedAndNursery = {};
    final Map<int, int> availableBySeed = {};

    for (final row in rows) {
      final seedId = _parseNullableInt(row['seed_id']);
      if (seedId == null) continue;

      final nurseryId = _parseNullableInt(row['nursery_id']);
      final typeId = _parseNullableInt(row['transaction_type_id']);
      final quantity = _parseNullableInt(row['seedling_count']) ?? 0;

      if (typeId != 1 && typeId != 2) continue;
      final signedQuantity = typeId == 1 ? quantity : -quantity;

      availableBySeed[seedId] =
          (availableBySeed[seedId] ?? 0) + signedQuantity;
      if (nurseryId != null) {
        final nurseryMap = netBySeedAndNursery.putIfAbsent(seedId, () => {});
        nurseryMap[nurseryId] = (nurseryMap[nurseryId] ?? 0) + signedQuantity;
      }
    }

    final nurseryColumnIds = netBySeedAndNursery.values
        .expand((nurseryMap) => nurseryMap.keys)
        .toSet()
        .toList()
      ..sort();
    final nurseryColumns = nurseryColumnIds
        .map((id) => nurseryNameById[id] ?? 'Unspecified')
        .toList();

    _seedlingNurseryColumns = nurseryColumns;

    final sortedSeedIds = seedIds.toList()
      ..sort((a, b) => (seedNameById[a] ?? '')
          .toLowerCase()
          .compareTo((seedNameById[b] ?? '').toLowerCase()));

    final pivoted = <Map<String, dynamic>>[];
    var sortOrder = 0;
    for (var i = 0; i < sortedSeedIds.length; i++) {
      final seedId = sortedSeedIds[i];
      final speciesName = seedNameById[seedId] ?? 'Unspecified';
      final no = i + 1;
      final nurseryMap = netBySeedAndNursery[seedId] ?? {};

      for (final nurseryId in nurseryColumnIds) {
        final quantity = nurseryMap[nurseryId];
        if (quantity == null) continue;

        final rowMap = <String, dynamic>{
          'sort_order': sortOrder++,
          'no': no,
          'species': speciesName,
          'available': '',
        };
        for (final column in nurseryColumns) {
          rowMap[column] = '';
        }
        rowMap[nurseryNameById[nurseryId] ?? 'Unspecified'] =
            quantity.toString();
        pivoted.add(rowMap);
      }

      final rowMap = <String, dynamic>{
        'sort_order': sortOrder++,
        'no': no,
        'species': speciesName,
        'available': (availableBySeed[seedId] ?? 0).toString(),
      };
      for (final column in nurseryColumns) {
        rowMap[column] = '';
      }
      pivoted.add(rowMap);
    }

    return pivoted;
  }

  static Future<List<Map<String, dynamic>>> _filterDataInBackground(
    Map<String, dynamic> params,
  ) async {
    final data = params['data'] as List<Map<String, dynamic>>;
    final period = params['period'] as String;
    final dateFieldName = params['dateFieldName'] as String;

    if (period != 'date_range') {
      return data;
    }

    final startDateString = params['startDate'] as String?;
    final endDateString = params['endDate'] as String?;
    if (startDateString == null || endDateString == null) {
      return data;
    }

    final startDate = DateTime.parse(startDateString);
    final endDate = DateTime.parse(endDateString);
    final endOfDay =
        DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    return data.where((item) {
      try {
        final dateString = item[dateFieldName]?.toString();
        if (dateString == null || dateString.isEmpty) return false;

        final date = DateTime.parse(dateString);
        return !date.isBefore(startDate) && !date.isAfter(endOfDay);
      } catch (e) {
        return false;
      }
    }).toList();
  }

  String get _currentTableName =>
      _resolveTableNameForSelection(_selectedProjectTypeName);

  /// Both "Seedling Inventory" and "Seedling Request" read from the same
  /// seedling_transaction table but render completely different views, so
  /// this disambiguates which one is selected wherever _currentTableName
  /// alone (== 'seedling_transaction') can't tell them apart.
  bool get _isSeedlingRequestSelected =>
      _selectedProjectTypeName.trim().toLowerCase() == 'seedling request';

  /// Mangrove Planting shares the tree_growing table with Tree Growing
  /// (rows are told apart by project_type_id), so _currentTableName alone
  /// can't distinguish them either — same pattern as _isSeedlingRequestSelected
  /// above.
  bool get _isMangrovePlantingSelected =>
      _selectedProjectTypeName.trim().toLowerCase() == 'mangrove planting';

  /// Monitoring of Mangrove Survival shares the tree_survival_monitoring
  /// table with Monitoring Tree Survival — same pattern as
  /// _isMangrovePlantingSelected above, one level further removed (rows are
  /// told apart via their linked tree_growing activity's project_type_id,
  /// not a column on tree_survival_monitoring itself).
  bool get _isMangroveSurvivalSelected =>
      _selectedProjectTypeName.trim().toLowerCase() ==
      'monitoring of mangrove survival';

  String _getDateFieldName() {
    switch (_currentTableName) {
      case 'flora_fauna_survey':
        return 'survey_date';
      case 'tree_survival_monitoring':
        return 'date';
      case 'seedling_transaction':
        return 'created_at';
      case 'seed_donation':
        return 'donated_date';
      case 'crm_habitat_assssment':
      case 'crm_marine_protected':
        return 'date';
      default:
        return 'planting_date';
    }
  }

  String _resolveTableNameForSelection(String? projectName) {
    final normalized = (projectName ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'tree growing':
      case 'tree_growing':
        return 'tree_growing';
      case 'monitoring tree survival':
      case 'monitoring':
      case 'monitoring of mangrove survival':
        return 'tree_survival_monitoring';
      case 'flora and fauna survey':
      case 'flora_fauna_survey':
        return 'flora_fauna_survey';
      case 'seedling inventory':
      case 'seedling_transaction':
      case 'seedling request':
        return 'seedling_transaction';
      case 'seed for a forest':
      case 'seed_donation':
        return 'seed_donation';
      case 'habitat assessment':
      case 'crm_habitat_assssment':
        return 'crm_habitat_assssment';
      case 'marine protected area':
      case 'crm_marine_protected':
        return 'crm_marine_protected';
      default:
        return 'tree_growing';
    }
  }

  Future<void> _loadReportFromCache() async {
    if (!mounted) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData =
          prefs.getString('report_${_selectedProjectTypeId ?? 'all'}_cache');

      if (cachedData != null) {
        try {
          final decoded = await compute(
            _parseJsonInBackground,
            cachedData,
          );
          if (mounted) {
            setState(() {
              _reportData = decoded;
              _isLoading = false;
            });
          }
        } catch (e) {
          debugPrint('❌ Error decoding cache: $e');
          if (mounted) {
            setState(() {
              _isLoading = false;
              _reportData = [];
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _reportData = [];
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading from cache: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  static Future<List<Map<String, dynamic>>> _parseJsonInBackground(
    String jsonString,
  ) async {
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(jsonString));
    } catch (e) {
      debugPrint('Error parsing JSON: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      drawer: const SidePanel(),
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Builder(
                            builder: (context) => IconButton(
                              icon: const Icon(Icons.menu),
                              onPressed: () =>
                                  Scaffold.of(context).openDrawer(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Reports',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        margin: const EdgeInsets.only(right: 80),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.cloud_done, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('Online'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Card(
                          elevation: 2,
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Project Type',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(height: 4),
                                      DropdownButton<String>(
                                        value: _dropdownProjectTypeValue,
                                        isExpanded: true,
                                        items: [
                                          ..._projectTypes.map((projectType) {
                                            final name = (projectType[
                                                        'projectname'] ??
                                                    '')
                                                .toString();
                                            return DropdownMenuItem(
                                              value: name,
                                              child: Text(name),
                                            );
                                          }),
                                        ],
                                        onChanged: (value) {
                                          if (value == null) return;
                                          setState(() {
                                            _selectedProjectTypeName = value;
                                            _selectedProjectTypeId = _toInt(
                                                _projectTypes.firstWhere(
                                              (projectType) =>
                                                  (projectType[
                                                              'projectname'] ??
                                                          '')
                                                      .toString() ==
                                                  value,
                                              orElse: () => {},
                                            )['id']);
                                          });
                                          _loadReport();
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Period',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(height: 4),
                                      DropdownButton<String>(
                                        value: _selectedPeriod,
                                        isExpanded: true,
                                        items: const [
                                          DropdownMenuItem(
                                            value: 'all',
                                            child: Text('All Time'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'date_range',
                                            child: Text('Date Range'),
                                          ),
                                        ],
                                        onChanged: (value) async {
                                          if (value == null) return;

                                          if (value == 'date_range') {
                                            final picked =
                                                await _pickDateRange();
                                            if (picked == null) return;

                                            setState(() {
                                              _selectedPeriod = 'date_range';
                                              _selectedDateRange = picked;
                                            });
                                            _loadReport();
                                            return;
                                          }

                                          setState(() {
                                            _selectedPeriod = value;
                                            _selectedDateRange = null;
                                          });
                                          _loadReport();
                                        },
                                      ),
                                      if (_selectedPeriod == 'date_range' &&
                                          _selectedDateRange != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              top: 4),
                                          child: GestureDetector(
                                            onTap: () async {
                                              final picked =
                                                  await _pickDateRange();
                                              if (picked == null) return;

                                              setState(() {
                                                _selectedDateRange = picked;
                                              });
                                              _loadReport();
                                            },
                                            child: Text(
                                              '${_formatDate(_selectedDateRange!.start)} - ${_formatDate(_selectedDateRange!.end)}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.blue.shade700,
                                                decoration:
                                                    TextDecoration.underline,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_reportData.isNotEmpty)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _exportToExcel,
                                icon: const Icon(Icons.download),
                                label: const Text('Export to Excel'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: _isLoading
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const CircularProgressIndicator(),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Loading REPORT data...',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'This may take a few moments',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : _reportData.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.assessment_outlined,
                                            size: 64,
                                            color: Colors.grey.shade400,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'No data available',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          ElevatedButton.icon(
                                            onPressed: _loadReport,
                                            icon: const Icon(Icons.refresh),
                                            label: const Text('Retry'),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Card(
                                      elevation: 2,
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: Scrollbar(
                                              controller:
                                                  _horizontalScrollController,
                                              scrollbarOrientation:
                                                  ScrollbarOrientation.bottom,
                                              child: SingleChildScrollView(
                                                controller:
                                                    _horizontalScrollController,
                                                scrollDirection:
                                                    Axis.horizontal,
                                                child: SingleChildScrollView(
                                                  scrollDirection:
                                                      Axis.vertical,
                                                  child: _buildCustomTable(),
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (_reportData.isNotEmpty &&
                                              _totalPages > 1)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.all(8.0),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(
                                                        Icons.arrow_back),
                                                    onPressed: _currentPage > 0
                                                        ? () {
                                                            setState(() =>
                                                                _currentPage--);
                                                          }
                                                        : null,
                                                  ),
                                                  Text(
                                                    'Page ${_currentPage + 1} of $_totalPages (${_reportData.length} total)',
                                                    style: const TextStyle(
                                                        fontSize: 12),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                        Icons.arrow_forward),
                                                    onPressed: _currentPage <
                                                            _totalPages - 1
                                                        ? () {
                                                            setState(() =>
                                                                _currentPage++);
                                                          }
                                                        : null,
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                        ),
                        const SizedBox(height: 12),
                        if (_reportData.isNotEmpty)
                          Card(
                            elevation: 3,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _buildStatCard(
                                    'Total Records',
                                    _reportData.length.toString(),
                                    Icons.assessment,
                                  ),
                                  _buildStatCard(
                                    'Total Trees',
                                    _calculateTotalTrees().toString(),
                                    Icons.park,
                                  ),
                                  _buildStatCard(
                                    'Last Updated',
                                    _formatDate(DateTime.now()),
                                    Icons.calendar_today,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Picks a start then end date via two single-date pickers, each of which
  /// lets the user tap the header to jump straight to a year/month grid
  /// instead of scrolling the calendar month-by-month.
  Future<DateTimeRange?> _pickDateRange() async {
    final start = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDate: _selectedDateRange?.start ?? DateTime.now(),
      helpText: 'Select Start Date',
    );
    if (start == null || !mounted) return null;

    final initialEnd = _selectedDateRange?.end;
    final end = await showDatePicker(
      context: context,
      firstDate: start,
      lastDate: DateTime.now(),
      initialDate: initialEnd != null && !initialEnd.isBefore(start)
          ? initialEnd
          : start,
      helpText: 'Select End Date',
    );
    if (end == null) return null;

    return DateTimeRange(start: start, end: end);
  }

  String _getReportTitle() {
    switch (_currentTableName) {
      case 'flora_fauna_survey':
        return 'Flora and Fauna Survey Report';
      case 'tree_survival_monitoring':
        if (_isMangroveSurvivalSelected) {
          return 'Monitoring of Mangrove Survival Report';
        }
        return 'Monitoring Tree Survival Report';
      case 'seedling_transaction':
        return _isSeedlingRequestSelected
            ? 'Seedling Request Report'
            : 'Seedling Inventory Report';
      case 'seed_donation':
        return 'Seed for a Forest Report';
      case 'tree_growing':
        if (_isMangrovePlantingSelected) return 'Mangrove Planting Report';
        return 'Tree Growing Report';
      case 'crm_habitat_assssment':
        return 'Habitat Assessment Report';
      case 'crm_marine_protected':
        return 'Marine Protected Area Report';
      default:
        return 'Tree Growing Report';
    }
  }

  /// The column holding each row's display number ("No.") — the primary
  /// key column differs per source table.
  String _getNoColumnKey() {
    switch (_currentTableName) {
      case 'flora_fauna_survey':
        return 'id';
      case 'tree_survival_monitoring':
        return 'activity_id';
      case 'seedling_transaction':
        return _isSeedlingRequestSelected ? 'no' : 'sort_order';
      case 'seed_donation':
        return 'id';
      case 'crm_habitat_assssment':
      case 'crm_marine_protected':
        return 'id';
      default:
        return 'seq_id';
    }
  }

  List<String> _getColumnsToDisplay() {
    switch (_currentTableName) {
      case 'flora_fauna_survey':
        return [
          'id',
          'activity_name',
          'species_type',
          'classification',
          'species_name',
          'area',
          'municipality',
          'barangay',
          'observer',
          'survey_date',
        ];
      case 'tree_survival_monitoring':
        return [
          'activity_id',
          'activity_name',
          'tree_species',
          'number_of_trees',
          'number_tree_survived',
          'quarter_label',
          'area_cover',
          'municipality',
          'barangay',
          'date',
        ];
      case 'seedling_transaction':
        return _isSeedlingRequestSelected
            ? [
                'no',
                'release_by',
                'release_to',
                'species',
                'quantity',
                'nursery',
                'date',
              ]
            : ['no', 'species', ..._seedlingNurseryColumns, 'available'];
      case 'seed_donation':
        return [
          'id',
          'donor_name',
          'seed_species_name',
          'seed_count',
          'survive',
          'status',
          'donated_date',
        ];
      case 'tree_growing':
        if (_isMangrovePlantingSelected) {
          return [
            'seq_id',
            'activity_name',
            'area_cover',
            'municipality',
            'barangay',
            'planting_date',
          ];
        }
        return [
          'seq_id',
          'activity_name',
          'tree_species',
          'number_of_trees',
          'area_cover',
          'municipality',
          'barangay',
          'planting_date',
        ];
      case 'crm_habitat_assssment':
        return [
          'id',
          'type_assessment',
          'municipality',
          'barangay',
          'species',
          'total_count',
          'date',
        ];
      case 'crm_marine_protected':
        return [
          'id',
          'name',
          'municipality',
          'barangay',
          'ordinance',
          'area',
          'date',
        ];
      default:
        return [
          'seq_id',
          'activity_name',
          'tree_species',
          'number_of_trees',
          'area_cover',
          'municipality',
          'barangay',
          'planting_date',
        ];
    }
  }

  List<int> _getColumnFlexValues() {
    return [2, 5, 6, 3, 3, 4, 4, 3];
  }

  String _getColumnDisplayName(String columnName) {
    if (_seedlingNurseryColumns.contains(columnName)) return columnName;

    final nameMap = {
      'seq_id': 'No.',
      'id': 'No.',
      'activity_id': 'No.',
      'no': 'No.',
      'activity_name': 'Activity Name',
      'tree_species': 'Species',
      'species_type': 'Type',
      'classification': 'Classification',
      'species_name': 'Species',
      'species': 'Species',
      'number_of_trees': 'Number of Trees',
      'number_tree_survived': 'Survived',
      'quarter_label': 'Quarter',
      'area_cover': 'Area Cover',
      'area': 'Area Cover',
      'municipality': 'Municipality',
      'barangay': 'Barangay',
      'observer': 'Observer',
      'planting_date': 'Date',
      'survey_date': 'Date',
      'date': 'Date',
      'quantity': 'Quantity',
      'available': 'Available',
      'release_by': 'Release By',
      'release_to': 'Release To',
      'nursery': 'Nursery',
      'donor_name': 'Donor Name',
      'seed_species_name': 'Species Name',
      'seed_count': 'Quantity',
      'survive': 'Survive',
      'status': 'Status',
      'donated_date': 'Date',
      'type_assessment': 'Type of Assessment',
      'total_count': 'Total Count',
      'name': 'Name',
      'ordinance': 'Ordinance',
      'created_at': 'Date',
    };
    return nameMap[columnName] ?? columnName.replaceAll('_', ' ').toUpperCase();
  }

  double _getColumnRatio(String columnName) {
    if (_seedlingNurseryColumns.contains(columnName)) return 0.12;

    switch (columnName) {
      case 'seq_id':
      case 'id':
      case 'activity_id':
      case 'no':
        return 0.06;
      case 'activity_name':
        return 0.16;
      case 'tree_species':
      case 'species_type':
      case 'classification':
      case 'species_name':
      case 'species':
      case 'seed_species_name':
        return 0.14;
      case 'donor_name':
        return 0.16;
      case 'status':
        return 0.12;
      case 'available':
        return 0.12;
      case 'release_by':
      case 'release_to':
      case 'nursery':
        return 0.14;
      case 'number_of_trees':
      case 'number_tree_survived':
      case 'survive':
        return 0.12;
      case 'quarter_label':
        return 0.08;
      case 'area_cover':
      case 'area':
        return 0.12;
      case 'municipality':
        return 0.14;
      case 'barangay':
        return 0.14;
      case 'observer':
        return 0.12;
      case 'date':
      case 'planting_date':
      case 'survey_date':
      case 'donated_date':
      case 'created_at':
        return 0.14;
      case 'type_assessment':
        return 0.16;
      case 'total_count':
        return 0.12;
      case 'name':
        return 0.16;
      case 'ordinance':
        return 0.14;
      default:
        return 0.10;
    }
  }

  int? _parseNullableInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  int _toComparableInt(dynamic value) => _parseNullableInt(value) ?? 0;

  List<Map<String, dynamic>> _sortBySeqId(List<Map<String, dynamic>> data) {
    final noColumnKey = _getNoColumnKey();
    final sorted = List<Map<String, dynamic>>.from(data);
    sorted.sort((a, b) {
      final seqA = _toComparableInt(a[noColumnKey]);
      final seqB = _toComparableInt(b[noColumnKey]);
      return seqA.compareTo(seqB);
    });
    return sorted;
  }

  Widget _buildCustomTable() {
    final columnsToShow = _getColumnsToDisplay();

    final sortedData = _sortBySeqId(_reportData);

    final startIndex = _currentPage * _rowsPerPage;
    final endIndex = min(startIndex + _rowsPerPage, sortedData.length);
    final paginatedData = sortedData.sublist(startIndex, endIndex);

    // This widget already sits inside a horizontally-scrolling ancestor
    // (see the Scrollbar/SingleChildScrollView pair around its call site),
    // so incoming layout constraints are unbounded here — MediaQuery is
    // used instead of LayoutBuilder to get the real available width.
    final screenWidth = MediaQuery.of(context).size.width;
    final tableWidth =
        kIsWeb && screenWidth > 1200 ? screenWidth : 1200.0;

    return SizedBox(
      width: tableWidth,
      child: Table(
        columnWidths: Map.fromIterable(
          List.generate(columnsToShow.length, (i) => i),
          value: (index) {
            final ratio = _getColumnRatio(columnsToShow[index]);
            return FixedColumnWidth(ratio * tableWidth);
          },
        ),
        border: TableBorder.all(color: Colors.grey.shade300, width: 1),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey.shade200),
            children: columnsToShow.map((columnName) {
              return Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  _getColumnDisplayName(columnName),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12),
                  softWrap: true,
                ),
              );
            }).toList(),
          ),
          ...paginatedData.map((row) {
            final isEvenRow = paginatedData.indexOf(row).isEven;
            final backgroundColor =
                isEvenRow ? Colors.white : Colors.blue.shade50;

            return TableRow(
              decoration: BoxDecoration(color: backgroundColor),
              children: columnsToShow.map((columnName) {
                return Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    row[columnName]?.toString() ?? 'N/A',
                    softWrap: true,
                    style: const TextStyle(color: Colors.black87, fontSize: 13),
                  ),
                );
              }).toList(),
            );
          }),
        ],
      ),
    );
  }

  int get _totalPages => (_reportData.length / _rowsPerPage).ceil();

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.green, size: 30),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  int _calculateTotalTrees() {
    int total = 0;
    for (var record in _reportData) {
      final numberOfTrees = record['number_of_trees'];
      if (numberOfTrees != null) {
        total += (numberOfTrees is int
            ? numberOfTrees
            : int.tryParse(numberOfTrees.toString()) ?? 0);
      }
    }
    return total;
  }

  Future<void> _exportToExcel() async {
    try {
      if (_reportData.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No data to export')),
          );
        }
        return;
      }

      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Sheet1'];
      final columnsToShow = _getColumnsToDisplay();

      for (int colIndex = 0; colIndex < columnsToShow.length; colIndex++) {
        var cell = sheetObject.cell(CellIndex.indexByColumnRow(
          columnIndex: colIndex,
          rowIndex: 0,
        ));
        cell.value =
            TextCellValue(_getColumnDisplayName(columnsToShow[colIndex]));
        cell.cellStyle = CellStyle(bold: true);
      }

      final exportData = _sortBySeqId(_reportData);
      for (int rowIndex = 0; rowIndex < exportData.length; rowIndex++) {
        var row = exportData[rowIndex];
        for (int colIndex = 0; colIndex < columnsToShow.length; colIndex++) {
          var cell = sheetObject.cell(CellIndex.indexByColumnRow(
            columnIndex: colIndex,
            rowIndex: rowIndex + 1,
          ));
          cell.value =
              TextCellValue(row[columnsToShow[colIndex]]?.toString() ?? '');
        }
      }

      for (int colIndex = 0; colIndex < columnsToShow.length; colIndex++) {
        final columnName = columnsToShow[colIndex];
        final width = columnName == 'tree_species' ? 30.0 : 20.0;
        sheetObject.setColumnWidth(colIndex, width);
      }

      List<int>? fileBytes = excel.encode();
      if (fileBytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error encoding Excel file')),
          );
        }
        return;
      }

      final fileName =
          '${_getReportTitle()}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final exportBytes = Uint8List.fromList(fileBytes);

      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) => const ExportOptionsDialog(),
      );

      if (action == 'save') {
        await _saveExcelFile(fileName, exportBytes);
      } else if (action == 'share') {
        await _shareExcelFile(fileName, exportBytes);
      }
    } catch (e) {
      debugPrint('Error exporting report: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting report: $e')),
        );
      }
    }
  }

  Future<void> _saveExcelFile(String fileName, Uint8List bytes) async {
    try {
      if (kIsWeb) {
        // FileSaver's web implementation has been unreliable; trigger the
        // browser download directly via an anchor + Blob instead.
        web_helper.downloadBytes(
          bytes,
          fileName,
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Downloaded $fileName')),
          );
        }
        return;
      }

      // FileSaver appends `ext` to `name` itself, so the base name must not
      // already carry the extension or the saved file ends up double-suffixed
      // (e.g. "report.xlsx.xlsx").
      final baseName = fileName.endsWith('.xlsx')
          ? fileName.substring(0, fileName.length - '.xlsx'.length)
          : fileName;

      // saveAs() opens the native "Save As" picker so the user chooses (and
      // therefore knows) exactly where the file goes, instead of it landing
      // in an app-specific default folder that's hard to locate afterward.
      final savedPath = await FileSaver.instance.saveAs(
        name: baseName,
        bytes: bytes,
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              savedPath != null
                  ? 'Saved to $savedPath'
                  : 'Excel file saved',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving excel file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving file: $e')),
        );
      }
    }
  }

  Future<void> _shareExcelFile(String fileName, Uint8List bytes) async {
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
      debugPrint('Error sharing excel file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing file: $e')),
        );
      }
    }
  }
}

int resolveCoordinateCount({
  required String? plantingId,
  required int? seqId,
  required Map<String, int> coordinateCounts,
}) {
  if (seqId != null) {
    final seqKey = seqId.toString();
    if (coordinateCounts.containsKey(seqKey)) {
      return coordinateCounts[seqKey] ?? 0;
    }
  }

  final plantingKey = plantingId?.toString() ?? '';
  if (plantingKey.isEmpty) {
    return 0;
  }
  return coordinateCounts[plantingKey] ?? 0;
}
