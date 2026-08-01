import 'package:flutter/material.dart';

import '../data_entry/tree_growing_form.dart';
import '../service/activity_model.dart';
import '../service/api_service.dart';
import '../service/auth_session.dart';
import '../widget/activity_photos_dialog.dart';
import '../widget/side_panel.dart';
import 'tree_growing_edit_page.dart';

class TreeGrowingPage extends StatefulWidget {
  const TreeGrowingPage({super.key});

  @override
  State<TreeGrowingPage> createState() => _TreeGrowingPageState();
}

class _TreeGrowingActivityItem {
  final TreePlanting planting;
  final String species;
  final int treesCount;

  const _TreeGrowingActivityItem({
    required this.planting,
    required this.species,
    required this.treesCount,
  });
}

enum _ActivityCardMenuAction { photos, edit, delete }

class _TreeGrowingPageState extends State<TreeGrowingPage> {
  final List<_TreeGrowingActivityItem> _items = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRecentActivities();
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = _items;

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
            Icon(Icons.park_rounded, color: Colors.white, size: 32),
            SizedBox(width: 12),
            Text(
              'Tree Planting Activity',
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: const Row(
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
            Expanded(
              child: _buildBody(visibleItems),
            ),
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

  Widget _buildBody(List<_TreeGrowingActivityItem> visibleItems) {
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

    if (visibleItems.isEmpty) {
      return const Center(
        child: Text(
          'No tree planting activities yet.',
          style: TextStyle(fontSize: 16, color: Color(0xFF636780)),
        ),
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 88),
      itemCount: visibleItems.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = visibleItems[index];
        return _buildActivityCard(item);
      },
    );
  }

  Widget _buildActivityCard(_TreeGrowingActivityItem item) {
    final planting = item.planting;

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
                  label: 'Activity Name',
                  value: (planting.activityName ?? '').trim().isEmpty
                      ? 'N/A'
                      : planting.activityName!.trim(),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildLabelValue(
                  label: 'Municipality',
                  value: planting.municipality.trim().isEmpty
                      ? 'N/A'
                      : planting.municipality,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildLabelValue(
                  label: 'Barangay',
                  value: planting.barangay.trim().isEmpty
                      ? 'N/A'
                      : planting.barangay,
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
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                onSelected: (action) {
                  if (action == _ActivityCardMenuAction.photos) {
                    _viewPhotos(item.planting);
                  }
                  if (action == _ActivityCardMenuAction.edit) {
                    _editActivity(item.planting);
                  }
                  if (action == _ActivityCardMenuAction.delete) {
                    _deleteActivity(item.planting);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem<_ActivityCardMenuAction>(
                    value: _ActivityCardMenuAction.photos,
                    child: Text('Photos'),
                  ),
                  const PopupMenuItem<_ActivityCardMenuAction>(
                    value: _ActivityCardMenuAction.edit,
                    child: Text('Edit'),
                  ),
                  // Only the record's creator or an admin can delete it.
                  if (AuthSession.canDelete(item.planting.userid))
                    const PopupMenuItem<_ActivityCardMenuAction>(
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
              Expanded(
                child: _buildDate(planting.date),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildLabelValue(
                  label: 'Species',
                  value: item.species,
                ),
              ),
              const SizedBox(width: 14),
              _buildTreesCount(item.treesCount),
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

  Widget _buildTreesCount(int treesCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text(
          'Trees Count',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF777A90),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$treesCount',
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
      final plantings = await ApiService.getTreePlantingsByProjectTypeId(1, limit: 200);
      final seqIds = plantings
          .map((planting) => planting.seqId)
          .whereType<int>()
          .where((id) => id > 0)
          .toList();

      final dataByTreeGrowingId =
          await ApiService.getTreeGrowingDataByTreeGrowingIds(seqIds);

      final mapped = plantings.map((planting) {
        final rows = dataByTreeGrowingId[planting.seqId ?? -1] ?? const [];

        final speciesFromRows = rows
            .map((row) => (row['seed_name'] ?? '').toString().trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .join(', ');

        final treesFromRows = rows.fold<int>(0, (sum, row) {
          final qty = (row['seedling_count'] as num?)?.toInt() ?? 0;
          return sum + qty;
        });

        final species = speciesFromRows.isNotEmpty ? speciesFromRows : 'Unspecified';

        final treesCount = treesFromRows > 0 ? treesFromRows : planting.numberOfTrees;

        return _TreeGrowingActivityItem(
          planting: planting,
          species: species,
          treesCount: treesCount,
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
        child: TreeGrowingForm(
          municipalities: const [],
          barangays: const [],
          onSave: (_) {
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

  Future<void> _viewPhotos(TreePlanting activity) async {
    final seqId = activity.seqId;
    if (seqId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No photos available for this activity.')),
      );
      return;
    }

    await showActivityPhotosDialog(
      context: context,
      title: 'Photos — ${(activity.activityName ?? '').trim().isEmpty ? 'Tree Planting Activity' : activity.activityName!.trim()}',
      loadPhotos: () => _loadPhotosForActivity(seqId),
    );
  }

  Future<List<ActivityPhoto>> _loadPhotosForActivity(int seqId) async {
    final photos = <ActivityPhoto>[];

    final photoRows = await ApiService.getPhotosForActivity(
      projectTypeId: 1,
      activityId: seqId,
    );
    for (final row in photoRows) {
      final url = (row['photo_url'] ?? '').toString();
      if (url.isEmpty) continue;
      final name = (row['name'] as String?)?.trim();
      photos.add(ActivityPhoto(
        url: url,
        name: (name != null && name.isNotEmpty) ? name : _photoFileName(url),
      ));
    }

    // Legacy points captured before the migration to the location/photo
    // tables still keep their photo inline on photourl_area.
    final legacyRows = await ApiService.getPhotourlAreasByActivityId(seqId);
    for (final row in legacyRows) {
      final url = (row['photo_url'] ?? '').toString();
      if (url.isEmpty) continue;
      photos.add(ActivityPhoto(url: url, name: _photoFileName(url)));
    }

    return photos;
  }

  String _photoFileName(String url) {
    final base = url.split('/').last;
    return base.isNotEmpty ? base : 'photo.jpg';
  }

  Future<void> _editActivity(TreePlanting activity) async {
    final updatedTreePlanting = await Navigator.of(context).push<TreePlanting>(
      PageRouteBuilder<TreePlanting>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 140),
        pageBuilder: (_, __, ___) => TreeGrowingEditPage(initialData: activity),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            ),
            child: child,
          );
        },
      ),
    );

    if (!mounted || updatedTreePlanting == null) return;

    setState(() {
      final index = _items.indexWhere(
        (a) => a.planting.id == activity.id,
      );

      if (index != -1) {
        final existing = _items[index];
        _items[index] = _TreeGrowingActivityItem(
          planting: updatedTreePlanting,
          species: existing.species,
          treesCount: updatedTreePlanting.numberOfTrees > 0
              ? updatedTreePlanting.numberOfTrees
              : existing.treesCount,
        );
      }
    });

    _loadRecentActivities(showLoader: false);
  }

  void _deleteActivity(TreePlanting activity) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
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
            'This record will be removed from Recent Activity and hidden from the dashboard map. You can not undo this action.',
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                side: const BorderSide(color: Color(0xFFD4D7E5)),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Color(0xFF4E526A),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.delete_rounded, size: 18),
              label: const Text(
                'Delete',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              onPressed: () async {
                Navigator.of(dialogContext).pop();

                try {
                  final id = activity.id;
                  if (id == null || id.isEmpty) {
                    throw Exception('Missing activity id.');
                  }

                  await ApiService.deleteTreePlanting(id);

                  if (!mounted) return;
                  setState(() {
                    _items.removeWhere((a) => a.planting.id == activity.id);
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
}

