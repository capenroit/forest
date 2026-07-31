import 'package:flutter/material.dart';

import '../data_entry/habitat_assessment_form.dart';
import '../service/activity_model.dart';
import '../service/api_service.dart';
import '../widget/side_panel.dart';

class HabitatAssessmentPage extends StatefulWidget {
  const HabitatAssessmentPage({super.key});

  @override
  State<HabitatAssessmentPage> createState() => _HabitatAssessmentPageState();
}

class _HabitatActivityItem {
  final HabitatAssessment assessment;
  final String species;
  final int totalCount;

  const _HabitatActivityItem({
    required this.assessment,
    required this.species,
    required this.totalCount,
  });
}

enum _ActivityCardMenuAction { edit, delete }

class _HabitatAssessmentPageState extends State<HabitatAssessmentPage> {
  final List<_HabitatActivityItem> _items = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRecentActivities();
  }

  Future<void> _loadRecentActivities({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final assessments = await ApiService.getAllHabitatAssessments(limit: 200);
      final ids = assessments
          .map((assessment) => assessment.id)
          .whereType<int>()
          .toList();

      final dataByAssessmentId =
          await ApiService.getHabitatAssessmentDataByAssessmentIds(ids);

      final mapped = assessments.map((assessment) {
        final rows = dataByAssessmentId[assessment.id ?? -1] ?? const [];

        final speciesFromRows = rows
            .map((row) => (row['species_name'] ?? '').toString().trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .join(', ');

        final totalCount = rows.fold<int>(0, (sum, row) {
          final count = (row['count'] as num?)?.toInt() ?? 0;
          return sum + count;
        });

        return _HabitatActivityItem(
          assessment: assessment,
          species: speciesFromRows.isNotEmpty ? speciesFromRows : 'Unspecified',
          totalCount: totalCount,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(mapped);
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

  Future<void> _openAddDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.all(16),
        child: HabitatAssessmentForm(
          onSave: () {
            Navigator.pop(dialogContext);
            _loadRecentActivities(showLoader: false);
          },
          onCancel: () => Navigator.pop(dialogContext),
        ),
      ),
    );
  }

  Future<void> _editActivity(HabitatAssessment assessment) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.all(16),
        child: HabitatAssessmentForm(
          initialData: assessment,
          onSave: () {
            Navigator.pop(dialogContext);
            _loadRecentActivities(showLoader: false);
          },
          onCancel: () => Navigator.pop(dialogContext),
        ),
      ),
    );
  }

  void _deleteActivity(HabitatAssessment assessment) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: Color(0xFFC62828),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Delete Activity?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF22232F),
                  ),
                ),
              ),
            ],
          ),
          content: const Text(
            'This record will be permanently removed. You can not undo this action.',
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: Color(0xFF5E6175),
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: const BorderSide(color: Color(0xFFD4D7E5)),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF4E526A), fontWeight: FontWeight.w600),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              icon: const Icon(Icons.delete_rounded, size: 18),
              label: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: () async {
                Navigator.of(dialogContext).pop();

                try {
                  final id = assessment.id;
                  if (id == null) {
                    throw Exception('Missing activity id.');
                  }

                  await ApiService.deleteHabitatAssessment(id);

                  if (!mounted) return;
                  setState(() {
                    _items.removeWhere((item) => item.assessment.id == assessment.id);
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Activity deleted successfully.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Unable to delete activity: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
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
            Icon(Icons.waves, color: Colors.white, size: 28),
            SizedBox(width: 12),
            Text(
              'Habitat Assessment',
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
          'No habitat assessments yet.',
          style: TextStyle(fontSize: 16, color: Color(0xFF636780)),
        ),
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 88),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildActivityCard(_items[index]),
    );
  }

  Widget _buildActivityCard(_HabitatActivityItem item) {
    final assessment = item.assessment;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildLabelValue(
                  label: 'Type of Assessment',
                  value: assessment.typeAssessment.trim().isEmpty
                      ? 'N/A'
                      : assessment.typeAssessment.trim(),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildLabelValue(
                  label: 'Municipality',
                  value: assessment.municipality.trim().isEmpty
                      ? 'N/A'
                      : assessment.municipality,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildLabelValue(
                  label: 'Barangay',
                  value: assessment.barangay.trim().isEmpty
                      ? 'N/A'
                      : assessment.barangay,
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<_ActivityCardMenuAction>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  size: 22,
                  color: Color(0xFF8B8EA3),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onSelected: (action) {
                  if (action == _ActivityCardMenuAction.edit) {
                    _editActivity(assessment);
                  }
                  if (action == _ActivityCardMenuAction.delete) {
                    _deleteActivity(assessment);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<_ActivityCardMenuAction>(
                    value: _ActivityCardMenuAction.edit,
                    child: Text('Edit'),
                  ),
                  PopupMenuItem<_ActivityCardMenuAction>(
                    value: _ActivityCardMenuAction.delete,
                    child: Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildDate(assessment.date)),
              const SizedBox(width: 14),
              Expanded(
                child: _buildLabelValue(
                  label: 'Species',
                  value: item.species,
                ),
              ),
              const SizedBox(width: 14),
              _buildCount(item.totalCount),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLabelValue({required String label, required String value}) {
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
          style: const TextStyle(
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
            const Icon(Icons.calendar_today_rounded,
                size: 14, color: Color(0xFF9B9DAE)),
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

  Widget _buildCount(int count) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text(
          'Total Count',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF777A90),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$count',
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
}
