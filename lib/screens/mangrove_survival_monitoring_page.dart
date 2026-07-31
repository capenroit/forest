import 'package:flutter/material.dart';

import '../data_entry/monitoring_mangrove_survival_form.dart';
import '../service/api_service.dart';
import '../widget/side_panel.dart';

class MangroveSurvivalMonitoringPage extends StatefulWidget {
  const MangroveSurvivalMonitoringPage({super.key});

  @override
  State<MangroveSurvivalMonitoringPage> createState() =>
      _MangroveSurvivalMonitoringPageState();
}

class _MangroveSurvivalMonitoringPageState
    extends State<MangroveSurvivalMonitoringPage> {
  final List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRecentActivities();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      drawer: const SidePanel(),
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 31, 103, 78),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Row(
          children: const [
            Icon(Icons.monitor_heart_rounded, color: Colors.white, size: 32),
            SizedBox(width: 12),
            Text(
              'Monitoring of Mangrove Survival',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadRecentActivities(showLoader: false),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Row(
                children: [
                  Text(
                    'Recent Activity',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF23253B),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Container(
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 200, 230, 220),
          borderRadius: BorderRadius.circular(50),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: IconButton(
          onPressed: _openAddDialog,
          icon: const Icon(
            Icons.add,
            color: Color.fromARGB(255, 31, 103, 78),
          ),
          iconSize: 35,
          tooltip: 'Add new record',
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _loadRecentActivities,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Text(
          'No mangrove survival records yet.',
          style: TextStyle(fontSize: 16, color: Color(0xFF636780)),
        ),
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 88),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _buildActivityCard(_items[index]);
      },
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> row) {
    final activityName = (row['activity_name'] ?? '').toString().trim();
    final municipality = (row['municipality'] ?? '').toString().trim();
    final barangay = (row['barangay'] ?? '').toString().trim();
    final quarter = (row['quarter'] as num?)?.toInt();
    final mangrovesSurvived =
        (row['number_tree_survived'] as num?)?.toInt() ??
            (row['number_tree_sur'] as num?)?.toInt() ??
            0;

    final dateRaw = row['date']?.toString() ?? '';
    final parsedDate = DateTime.tryParse(dateRaw) ?? DateTime.now();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildLabelValue(
                        label: 'Activity Name',
                        value: activityName.isNotEmpty ? activityName : 'N/A',
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _buildLabelValue(
                        label: 'Municipality',
                        value: municipality.isEmpty ? 'N/A' : municipality,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _buildLabelValue(
                        label: 'Barangay',
                        value: barangay.isEmpty ? 'N/A' : barangay,
                      ),
                    ),
                    const SizedBox(width: 18),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildDate(parsedDate)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _buildLabelValue(
                        label: 'Quarter',
                        value: quarter != null ? 'Q$quarter' : 'N/A',
                      ),
                    ),
                    const SizedBox(width: 14),
                    _buildMangrovesSurvived(mangrovesSurvived),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: -4,
            right: -10,
            child: PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert_rounded,
                color: Color(0xFF8A8DA3),
              ),
              tooltip: 'More',
              onSelected: (action) {
                if (action == 'edit') {
                  _openEditDialog(row);
                } else if (action == 'remove') {
                  _confirmAndRemove(row);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Edit'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      SizedBox(width: 10),
                      Text('Remove', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabelValue({
    required String label,
    required String value,
    TextStyle? valueStyle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF777A90),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: valueStyle ??
              const TextStyle(
                fontSize: 14,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: Color(0xFF25273B),
              ),
        ),
      ],
    );
  }

  Widget _buildDate(DateTime date) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Date',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF777A90),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            const Icon(
              Icons.calendar_today_rounded,
              size: 14,
              color: Color(0xFF9B9DAE),
            ),
            const SizedBox(width: 6),
            Text(
              _formatDate(date),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF666A80),
                height: 1,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMangrovesSurvived(int mangrovesSurvived) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text(
          'Mangroves Survived',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF777A90),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$mangrovesSurvived',
          style: const TextStyle(
            fontSize: 18,
            height: 1,
            fontWeight: FontWeight.w700,
            color: Color(0xFF22232F),
          ),
        ),
      ],
    );
  }

  Future<void> _loadRecentActivities({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final items = await ApiService.getTreeSurvivalMonitoringRecords(
        limit: 200,
      );

      final activityIds = items
          .map((row) => (row['activity_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet()
          .toList();

      final infoBySeqId = await ApiService.getTreeGrowingActivityInfoBySeqIds(
        activityIds,
      );

      // tree_survival_monitoring rows aren't tagged with a project type of
      // their own — activity_id just points into tree_growing, which is
      // shared with Tree Growing (project_type_id 1). Only keep rows whose
      // activity actually is a Mangrove Planting one (project_type_id 6).
      final enrichedItems = items
          .map((row) {
            final activityId = (row['activity_id'] as num?)?.toInt();
            final info = activityId != null ? infoBySeqId[activityId] : null;
            return {
              ...row,
              'activity_name': info?['activity_name'],
              'municipality': info?['municipality'],
              'barangay': info?['barangay'],
              '_project_type_id': info?['project_type_id'],
            };
          })
          .where((row) => row['_project_type_id'] == 6)
          .toList();

      final mergedItems = _mergeRecordsByActivity(enrichedItems);

      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(mergedItems);
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load records: $e';
      });
    }
  }

  /// Each row is one species now (seed_id links to tree_growing_data), so a
  /// single monitoring submission produces several rows sharing the same
  /// activity, quarter, date, and updated_at. Merge those back into one
  /// card, summing the per-species survived counts.
  List<Map<String, dynamic>> _mergeRecordsByActivity(
    List<Map<String, dynamic>> rows,
  ) {
    final merged = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      final activityId = row['activity_id']?.toString() ?? '';
      final quarter = row['quarter']?.toString() ?? '';
      final date = row['date']?.toString() ?? '';
      final updatedAt = row['updated_at']?.toString() ?? '';
      final key = '$activityId|$quarter|$date|$updatedAt';

      final survived = (row['number_tree_survived'] as num?)?.toInt() ??
          (row['number_tree_sur'] as num?)?.toInt() ??
          0;

      final existing = merged[key];
      if (existing == null) {
        merged[key] = {
          ...row,
          'number_tree_survived': survived,
          '_group_rows': [row],
        };
      } else {
        final existingSurvived =
            (existing['number_tree_survived'] as num?)?.toInt() ?? 0;
        existing['number_tree_survived'] = existingSurvived + survived;
        (existing['_group_rows'] as List<Map<String, dynamic>>).add(row);
      }
    }

    return merged.values.toList();
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<void> _openAddDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        insetPadding: const EdgeInsets.all(16),
        child: MonitoringMangroveSurvivalForm(
          municipalities: const [],
          barangays: const [],
          onSave: () {
            Navigator.pop(dialogContext);
            _loadRecentActivities(showLoader: false);
          },
          onCancel: () {
            Navigator.pop(dialogContext);
          },
        ),
      ),
    );
  }

  Future<void> _openEditDialog(Map<String, dynamic> mergedRow) async {
    final groupRows =
        (mergedRow['_group_rows'] as List<Map<String, dynamic>>?) ??
            [mergedRow];

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        insetPadding: const EdgeInsets.all(16),
        child: MonitoringMangroveSurvivalForm(
          municipalities: const [],
          barangays: const [],
          initialRows: groupRows,
          onSave: () {
            Navigator.pop(dialogContext);
            _loadRecentActivities(showLoader: false);
          },
          onCancel: () {
            Navigator.pop(dialogContext);
          },
        ),
      ),
    );
  }

  Future<void> _confirmAndRemove(Map<String, dynamic> mergedRow) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove record'),
        content: const Text(
          'This will delete this monitoring record and all its species entries. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final groupRows =
        (mergedRow['_group_rows'] as List<Map<String, dynamic>>?) ??
            [mergedRow];
    final ids = groupRows
        .map((row) =>
            (row['seq_id'] as num?)?.toInt() ?? (row['id'] as num?)?.toInt())
        .whereType<int>()
        .toList();

    try {
      await ApiService.deleteTreeSurvivalMonitoringRows(ids);
      if (!mounted) return;
      await _loadRecentActivities(showLoader: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove record: $e')),
      );
    }
  }
}
