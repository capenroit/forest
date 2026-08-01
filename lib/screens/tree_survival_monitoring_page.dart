import 'package:flutter/material.dart';

import '../data_entry/monitoring_tree_survival_form.dart';
import '../service/activity_model.dart';
import '../service/api_service.dart';
import '../service/auth_session.dart';
import '../service/offline_sync_service.dart';
import '../widget/side_panel.dart';

class TreeSurvivalMonitoringPage extends StatefulWidget {
  const TreeSurvivalMonitoringPage({super.key});

  @override
  State<TreeSurvivalMonitoringPage> createState() =>
      _TreeSurvivalMonitoringPageState();
}

class _TreeSurvivalMonitoringPageState extends State<TreeSurvivalMonitoringPage> {
  static const int _treeGrowingProjectTypeId = 1;

  final List<Map<String, dynamic>> _items = [];
  final List<Map<String, dynamic>> _pendingItems = [];
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
              'Monitoring of Tree Survival',
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
                      fontSize: 22,
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

    if (_items.isEmpty && _pendingItems.isEmpty) {
      return const Center(
        child: Text(
          'No tree survival records yet.',
          style: TextStyle(fontSize: 16, color: Color(0xFF636780)),
        ),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 88),
      children: [
        if (_pendingItems.isNotEmpty) ...[
          _buildPendingSectionHeader(),
          const SizedBox(height: 10),
          for (final item in _pendingItems)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildPendingCard(item),
            ),
          const SizedBox(height: 6),
        ],
        for (final row in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildActivityCard(row),
          ),
      ],
    );
  }

  Widget _buildPendingSectionHeader() {
    return Row(
      children: [
        Icon(Icons.cloud_off_rounded, size: 16, color: Colors.orange.shade700),
        const SizedBox(width: 6),
        Text(
          'Pending Sync',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Colors.orange.shade800,
          ),
        ),
      ],
    );
  }

  Widget _buildPendingCard(Map<String, dynamic> item) {
    final localId = item['localId'] as String;
    final payload = Map<String, dynamic>.from(item['payload'] as Map);
    final activityName = (item['activityName'] ?? '').toString().trim();
    final municipality = (item['municipality'] ?? '').toString().trim();
    final barangay = (item['barangay'] ?? '').toString().trim();
    final activityId = (payload['activityId'] as num?)?.toInt();
    final quarter = (payload['quarter'] as num?)?.toInt();
    final dateRaw = payload['date']?.toString() ?? '';
    final parsedDate = DateTime.tryParse(dateRaw) ?? DateTime.now();

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openPendingEditDialog(localId, payload),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded,
                          size: 14, color: Colors.orange.shade700),
                      const SizedBox(width: 6),
                      Text(
                        'Not yet synced',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    activityName.isNotEmpty
                        ? activityName
                        : (activityId != null
                            ? 'Activity #$activityId'
                            : 'Unknown activity'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF25273B),
                    ),
                  ),
                  if (municipality.isNotEmpty || barangay.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      [municipality, barangay]
                          .where((s) => s.isNotEmpty)
                          .join(' | '),
                      style:
                          const TextStyle(fontSize: 12, color: Color(0xFF777A90)),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        _formatDate(parsedDate),
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF666A80)),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        quarter != null ? 'Q$quarter' : 'N/A',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF666A80)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
              tooltip: 'Delete pending record',
              onPressed: () => _confirmAndDeletePending(localId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> row) {
    final activityName = (row['activity_name'] ?? '').toString().trim();
    final municipality = (row['municipality'] ?? '').toString().trim();
    final barangay = (row['barangay'] ?? '').toString().trim();
    final quarter = (row['quarter'] as num?)?.toInt();
    final treesSurvived =
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
                        valueStyle: const TextStyle(
                          fontSize: 13,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF25273B),
                        ),
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
                    _buildTreesSurvived(treesSurvived),
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
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Edit'),
                    ],
                  ),
                ),
                // Only the record's creator or an admin can delete it.
                if (AuthSession.canDelete((row['user_id'] ?? '').toString()))
                  const PopupMenuItem(
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
            fontSize: 11,
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
                fontSize: 13,
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
            fontSize: 11,
            color: Color(0xFF777A90),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            const Icon(
              Icons.calendar_today_rounded,
              size: 13,
              color: Color(0xFF9B9DAE),
            ),
            const SizedBox(width: 6),
            Text(
              _formatDate(date),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF666A80),
                height: 1,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTreesSurvived(int treesSurvived) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text(
          'Trees Survived',
          style: TextStyle(
            fontSize: 11,
            color: Color(0xFF777A90),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$treesSurvived',
          style: const TextStyle(
            fontSize: 16,
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

    // Best-effort local read alongside the server load — never throws, so
    // a failure of the server-backed list below is reported on its own.
    final pendingFuture = _loadPendingItems();

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
      // shared with Mangrove Planting (project_type_id 6). Only keep rows
      // whose activity actually is a Tree Growing one (project_type_id 1).
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
          .where((row) => row['_project_type_id'] == 1)
          .toList();

      final mergedItems = _mergeRecordsByActivity(enrichedItems);

      await pendingFuture;

      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(mergedItems);
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      await pendingFuture;
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load records: $e';
      });
    }
  }

  /// Loads still-queued offline drafts and keeps only the ones belonging to
  /// this page (i.e. whose `activityId` points at a Tree Growing activity,
  /// project_type_id 1 — both survival-monitoring forms share the same
  /// queue `type` string, so this is how the two pages tell their pending
  /// items apart). Only activities that have actually synced at some point
  /// (and are therefore in the local cache) are considered valid targets.
  Future<void> _loadPendingItems() async {
    try {
      final pending = await OfflineSyncService.getPendingItems(
        type: 'tree_survival_monitoring',
      );
      final cachedActivities =
          await OfflineSyncService.getCachedActivities(_treeGrowingProjectTypeId);
      final activitiesBySeqId = <int, TreePlanting>{
        for (final activity in cachedActivities)
          if (activity.seqId != null) activity.seqId!: activity,
      };

      final relevant = <Map<String, dynamic>>[];
      for (final item in pending) {
        final rawPayload = item['payload'];
        if (rawPayload is! Map) continue;
        final payload = Map<String, dynamic>.from(rawPayload);
        final activityId = (payload['activityId'] as num?)?.toInt();
        final activity =
            activityId != null ? activitiesBySeqId[activityId] : null;
        if (activity == null) continue;

        relevant.add({
          'localId': item['localId'],
          'payload': payload,
          'activityName': activity.activityName,
          'municipality': activity.municipality,
          'barangay': activity.barangay,
        });
      }

      if (!mounted) return;
      setState(() {
        _pendingItems
          ..clear()
          ..addAll(relevant);
      });
    } catch (_) {
      // Best effort — leave whatever pending list we already had.
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
        child: MonitoringTreeSurvivalForm(
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
        child: MonitoringTreeSurvivalForm(
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

  Future<void> _openPendingEditDialog(
      String localId, Map<String, dynamic> payload) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        insetPadding: const EdgeInsets.all(16),
        child: MonitoringTreeSurvivalForm(
          municipalities: const [],
          barangays: const [],
          pendingLocalId: localId,
          pendingPayload: payload,
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

  Future<void> _confirmAndDeletePending(String localId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove pending record'),
        content: const Text(
          'This will delete this offline draft before it syncs. This cannot be undone.',
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

    await OfflineSyncService.deletePendingItem(localId);
    if (!mounted) return;
    await _loadRecentActivities(showLoader: false);
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

