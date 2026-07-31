import 'package:flutter/material.dart';

import '../data_entry/marine_protected_area_form.dart';
import '../service/activity_model.dart';
import '../service/api_service.dart';
import '../widget/side_panel.dart';

class MarineProtectedAreaPage extends StatefulWidget {
  const MarineProtectedAreaPage({super.key});

  @override
  State<MarineProtectedAreaPage> createState() => _MarineProtectedAreaPageState();
}

enum _ActivityCardMenuAction { edit, delete }

class _MarineProtectedAreaPageState extends State<MarineProtectedAreaPage> {
  final List<MarineProtectedArea> _items = [];
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
      final areas = await ApiService.getAllMarineProtectedAreas(limit: 200);

      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(areas);
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
        child: MarineProtectedAreaForm(
          onSave: () {
            Navigator.pop(dialogContext);
            _loadRecentActivities(showLoader: false);
          },
          onCancel: () => Navigator.pop(dialogContext),
        ),
      ),
    );
  }

  Future<void> _editActivity(MarineProtectedArea area) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.all(16),
        child: MarineProtectedAreaForm(
          initialData: area,
          onSave: () {
            Navigator.pop(dialogContext);
            _loadRecentActivities(showLoader: false);
          },
          onCancel: () => Navigator.pop(dialogContext),
        ),
      ),
    );
  }

  void _deleteActivity(MarineProtectedArea area) {
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
                  final id = area.id;
                  if (id == null) {
                    throw Exception('Missing activity id.');
                  }

                  await ApiService.deleteMarineProtectedArea(id);

                  if (!mounted) return;
                  setState(() {
                    _items.removeWhere((item) => item.id == area.id);
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
            Icon(Icons.sailing, color: Colors.white, size: 28),
            SizedBox(width: 12),
            Text(
              'Marine Protected Area',
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
          'No marine protected areas yet.',
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

  Widget _buildActivityCard(MarineProtectedArea area) {
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
                  label: 'Name',
                  value: area.name.trim().isEmpty ? 'N/A' : area.name.trim(),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildLabelValue(
                  label: 'Municipality',
                  value: area.municipality.trim().isEmpty
                      ? 'N/A'
                      : area.municipality,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildLabelValue(
                  label: 'Barangay',
                  value: area.barangay.trim().isEmpty ? 'N/A' : area.barangay,
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
                    _editActivity(area);
                  }
                  if (action == _ActivityCardMenuAction.delete) {
                    _deleteActivity(area);
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
              Expanded(child: _buildDate(area.date)),
              const SizedBox(width: 14),
              Expanded(
                child: _buildLabelValue(
                  label: 'Ordinance',
                  value: (area.ordinance ?? '').trim().isEmpty
                      ? 'N/A'
                      : area.ordinance!.trim(),
                ),
              ),
              const SizedBox(width: 14),
              _buildArea(area.area),
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

  Widget _buildArea(double? area) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text(
          'Area (ha)',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF777A90),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          area != null ? area.toStringAsFixed(2) : 'N/A',
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
