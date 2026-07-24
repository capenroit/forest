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
  String _selectedProjectTypeName = 'all';
  int? _selectedProjectTypeId;
  bool _isLoading = false;
  List<Map<String, dynamic>> _reportData = [];
  List<Map<String, dynamic>> _projectTypes = [];
  String _selectedPeriod = 'all';
  DateTimeRange? _selectedDateRange;
  late ScrollController _horizontalScrollController;
  bool _isLoadingReport = false;

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
          .eq('dashboard_filter', true)
          .order('id')
          .timeout(const Duration(seconds: 5));

      final typed =
          response.map((row) => Map<String, dynamic>.from(row as Map)).toList();

      if (!mounted) return;
      setState(() {
        _projectTypes = typed;
        if (_selectedProjectTypeId == null && typed.isNotEmpty) {
          _selectedProjectTypeId = _toInt(typed.first['id']);
          _selectedProjectTypeName =
              (typed.first['projectname'] ?? 'all').toString();
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
      final tableName = _resolveTableNameForSelection(
          _selectedProjectTypeName == 'all' ? null : _selectedProjectTypeName);

      final query = Supabase.instance.client.from(tableName).select('*');
      final filteredQuery =
          tableName == 'tree_growing' && _selectedProjectTypeId != null
              ? query.eq('project_type_id', _selectedProjectTypeId!)
              : query;

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

      if (mounted) {
        setState(() {
          _reportData = filteredData;
          _isLoading = false;
        });
      }

      if (filteredData.length <= 5000) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'report_${_selectedProjectTypeId ?? 'all'}_cache',
            jsonEncode(filteredData),
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
  Future<List<Map<String, dynamic>>> _attachTreeGrowingSpeciesRows(
    List<Map<String, dynamic>> rows,
  ) async {
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

  String _getDateFieldName() {
    return 'planting_date';
  }

  String _resolveTableNameForSelection(String? projectName) {
    final normalized = (projectName ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'tree growing':
      case 'tree_growing':
        return 'tree_growing';
      case 'monitoring tree survival':
      case 'monitoring':
        return 'tree_survival_monitoring';
      case 'flora and fauna survey':
      case 'flora_fauna_survey':
        return 'flora_fauna_survey';
      case 'seedling inventory':
      case 'seedling_transaction':
        return 'seedling_transaction';
      case 'seed for a forest':
      case 'seed_donation':
        return 'seed_donation';
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
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => Navigator.of(context).maybePop(),
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
                                        value: _selectedProjectTypeName,
                                        isExpanded: true,
                                        items: [
                                          const DropdownMenuItem(
                                            value: 'all',
                                            child: Text('All'),
                                          ),
                                          const DropdownMenuItem(
                                            value: 'Tree Growing',
                                            child: Text('Tree Growing'),
                                          ),
                                          const DropdownMenuItem(
                                            value: 'Monitoring Tree Survival',
                                            child: Text(
                                                'Monitoring Tree Survival'),
                                          ),
                                          const DropdownMenuItem(
                                            value: 'Flora and Fauna Survey',
                                            child:
                                                Text('Flora and Fauna Survey'),
                                          ),
                                          const DropdownMenuItem(
                                            value: 'Seedling Inventory',
                                            child: Text('Seedling Inventory'),
                                          ),
                                          const DropdownMenuItem(
                                            value: 'Seed for a Forest',
                                            child: Text('Seed for a Forest'),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          if (value == null) return;
                                          setState(() {
                                            _selectedProjectTypeName = value;
                                            _selectedProjectTypeId = value ==
                                                    'all'
                                                ? null
                                                : _toInt(
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _getReportTitle(),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_reportData.isNotEmpty)
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
    return 'Tree Growing Report';
  }

  List<String> _getColumnsToDisplay() {
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

  List<int> _getColumnFlexValues() {
    return [2, 5, 6, 3, 3, 4, 4, 3];
  }

  String _getColumnDisplayName(String columnName) {
    final nameMap = {
      'seq_id': 'No.',
      'activity_name': 'Activity Name',
      'tree_species': 'Species',
      'number_of_trees': 'Number of Trees',
      'area_cover': 'Area Cover',
      'municipality': 'Municipality',
      'barangay': 'Barangay',
      'planting_date': 'Date',
      'date': 'Date',
      'quantity': 'Quantity',
    };
    return nameMap[columnName] ?? columnName.replaceAll('_', ' ').toUpperCase();
  }

  double _getColumnRatio(String columnName) {
    switch (columnName) {
      case 'seq_id':
        return 0.06;
      case 'activity_name':
        return 0.16;
      case 'tree_species':
        return 0.16;
      case 'number_of_trees':
        return 0.12;
      case 'area_cover':
        return 0.12;
      case 'municipality':
        return 0.14;
      case 'barangay':
        return 0.14;
      case 'date':
      case 'planting_date':
        return 0.14;
      default:
        return 0.10;
    }
  }

  List<Map<String, dynamic>> _sortBySeqId(List<Map<String, dynamic>> data) {
    final sorted = List<Map<String, dynamic>>.from(data);
    sorted.sort((a, b) {
      final seqA = (a['seq_id'] as num?)?.toInt() ?? 0;
      final seqB = (b['seq_id'] as num?)?.toInt() ?? 0;
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

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        columnWidths: Map.fromIterable(
          List.generate(columnsToShow.length, (i) => i),
          value: (index) {
            final ratio = _getColumnRatio(columnsToShow[index]);
            return FixedColumnWidth(ratio * 1200);
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
          }).toList(),
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
