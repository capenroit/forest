import 'package:flutter/material.dart';

import '../data_entry/flora_fauna_form.dart';
import '../service/api_service.dart';
import '../service/auth_session.dart';
import '../service/offline_sync_service.dart';
import '../widget/activity_photos_dialog.dart';
import '../widget/side_panel.dart';

class CapizFloraFaunaRecentActivityPage extends StatefulWidget {
  const CapizFloraFaunaRecentActivityPage({super.key});

  @override
  State<CapizFloraFaunaRecentActivityPage> createState() =>
      _CapizFloraFaunaRecentActivityPageState();
}

class _CapizFloraFaunaRecentActivityPageState
    extends State<CapizFloraFaunaRecentActivityPage> {
  final List<FloraFaunaEntry> _recentActivities = [];
  List<Map<String, dynamic>> _pendingItems = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll({bool showLoader = true}) async {
    await Future.wait([
      _loadRecentActivities(showLoader: showLoader),
      _loadPendingItems(),
    ]);
  }

  Future<void> _loadPendingItems() async {
    try {
      final items =
          await OfflineSyncService.getPendingItems(type: 'flora_fauna');
      if (!mounted) return;
      setState(() {
        _pendingItems = items;
      });
    } catch (_) {
      // Best effort — the pending list just stays as it was.
    }
  }

  Future<void> _loadRecentActivities({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final rows = await ApiService.getRecentFloraFaunaSurveys(limit: 100);
      final mapped = rows.map((row) {
        final activityName = (row['activity_name'] ?? '').toString().trim();
        final details = (row['details'] ?? '').toString().trim();
        final observer = (row['observer'] ?? '').toString().trim();
        final municipality = (row['municipality'] ?? '').toString().trim();
        final barangay = (row['barangay'] ?? '').toString().trim();
        final surveyDate = DateTime.tryParse(
            (row['survey_date'] ?? row['created_at'] ?? row['updated_at'] ?? '')
              .toString(),
          ) ??
          DateTime.now();

        const entryType = 'Survey';
        final speciesName =
            activityName.isNotEmpty ? activityName : 'Survey Record';

        return FloraFaunaEntry(
          id: (row['id'] as num?)?.toInt(),
          userId: (row['user_id'] ?? '').toString().isEmpty
              ? null
              : row['user_id'].toString(),
          activityName: activityName,
          entryType: entryType,
          speciesName: speciesName,
          scientificName: details,
          municipality: municipality,
          barangay: barangay,
          surveyDate: surveyDate,
          observer: observer,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _recentActivities
          ..clear()
          ..addAll(mapped);
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load recent activity: $e';
      });
    }
  }

  Future<void> _editActivity(FloraFaunaEntry activity, int index) async {
    final surveyId = activity.id;
    if (surveyId == null) {
      await _openAddDialog(initialEntry: activity, index: index);
      return;
    }

    try {
      final detailRows = await ApiService.getFloraFaunaSurveyDataRows(surveyId);
      final speciesDetails = detailRows
          .map((row) => FloraFaunaSpeciesDetail(
                speciesType: (row['species_type'] ?? '').toString(),
                name: (row['name'] ?? '').toString(),
                scientificName: (row['scientific_name'] ?? '').toString(),
                classification: (row['classification'] as String?)?.trim().isNotEmpty ==
                        true
                    ? (row['classification'] as String).trim()
                    : null,
              ))
          .toList();

      if (!mounted) return;
      await _openAddDialog(
        initialEntry: FloraFaunaEntry(
          id: activity.id,
          activityName: activity.activityName,
          entryType: activity.entryType,
          speciesName: activity.speciesName,
          scientificName: activity.scientificName,
          areaHectares: activity.areaHectares,
          municipality: activity.municipality,
          barangay: activity.barangay,
          surveyDate: activity.surveyDate,
          observer: activity.observer,
          speciesDetails: speciesDetails,
        ),
        index: index,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load species details: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _viewPhotos(FloraFaunaEntry activity) async {
    final surveyId = activity.id;
    if (surveyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No photos available for this activity.')),
      );
      return;
    }

    await showActivityPhotosDialog(
      context: context,
      title: 'Photos — ${(activity.activityName ?? '').trim().isEmpty ? 'Survey Record' : activity.activityName!.trim()}',
      loadPhotos: () => _loadPhotosForActivity(surveyId),
    );
  }

  Future<List<ActivityPhoto>> _loadPhotosForActivity(int surveyId) async {
    final photos = <ActivityPhoto>[];

    final photoRows = await ApiService.getPhotosForActivity(
      projectTypeId: 3,
      activityId: surveyId,
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

    return photos;
  }

  String _photoFileName(String url) {
    final base = url.split('/').last;
    return base.isNotEmpty ? base : 'photo.jpg';
  }

  Future<void> _openAddDialog({FloraFaunaEntry? initialEntry, int? index}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        insetPadding: const EdgeInsets.all(16),
        child: FloraFaunaForm(
          initialData: initialEntry,
          onSave: (entry) {
            Navigator.pop(dialogContext);
            if (!mounted) return;
            _loadAll(showLoader: false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(index == null
                    ? 'Survey entry added.'
                    : 'Survey entry updated.'),
              ),
            );
          },
          onCancel: () {
            Navigator.pop(dialogContext);
          },
        ),
      ),
    );
  }

  Future<void> _openPendingDialog(Map<String, dynamic> item) async {
    final localId = item['localId'] as String;
    final payload = Map<String, dynamic>.from(item['payload'] as Map? ?? {});

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        insetPadding: const EdgeInsets.all(16),
        child: FloraFaunaForm(
          pendingLocalId: localId,
          pendingPayload: payload,
          onSave: (entry) {
            Navigator.pop(dialogContext);
            if (!mounted) return;
            _loadAll(showLoader: false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Survey entry updated.')),
            );
          },
          onCancel: () {
            Navigator.pop(dialogContext);
          },
        ),
      ),
    );
  }

  Future<void> _deletePendingEntry(String localId) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Pending Entry?'),
            content: const Text(
              'This record has not been synced yet. It will be removed '
              'from the offline queue.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    await OfflineSyncService.deletePendingItem(localId);
    if (!mounted) return;
    await _loadPendingItems();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pending entry removed.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _confirmRemove(int index) {
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
            'This record will be removed from Recent Activity. You can not undo this action.',
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

                final surveyId = _recentActivities[index].id;
                if (surveyId == null) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Unable to remove record.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                try {
                  await ApiService.softDeleteFloraFaunaSurvey(surveyId);
                  if (!mounted) return;

                  await _loadRecentActivities(showLoader: false);

                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Survey entry removed.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Unable to remove record: $e'),
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

  Widget _buildPendingSectionHeader() {
    return Row(
      children: [
        const Icon(Icons.cloud_off_rounded, size: 16, color: Color(0xFFB25E00)),
        const SizedBox(width: 6),
        Text(
          'Pending sync (${_pendingItems.length})',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFFB25E00),
          ),
        ),
      ],
    );
  }

  Widget _buildSyncedSectionHeader() {
    return const Text(
      'Synced',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF636780),
      ),
    );
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
        title: const Text(
          'Capiz Flora and Fauna Survey',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Recent Activity',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF23253B),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
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
                                onPressed: _loadAll,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _loadAll(showLoader: false),
                        child: (_recentActivities.isEmpty &&
                                _pendingItems.isEmpty)
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(20),
                                children: const [
                                  SizedBox(height: 120),
                                  Center(
                                    child: Text(
                                      'No flora/fauna survey records yet.',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Color(0xFF636780),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                                children: [
                                  if (_pendingItems.isNotEmpty) ...[
                                    _buildPendingSectionHeader(),
                                    const SizedBox(height: 10),
                                    for (final item in _pendingItems)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: _PendingActivityCard(
                                          item: item,
                                          onTap: () =>
                                              _openPendingDialog(item),
                                          onDelete: () => _deletePendingEntry(
                                              item['localId'] as String),
                                        ),
                                      ),
                                    if (_recentActivities.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      _buildSyncedSectionHeader(),
                                      const SizedBox(height: 10),
                                    ],
                                  ],
                                  for (var index = 0;
                                      index < _recentActivities.length;
                                      index++)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: _RecentActivityCard(
                                        activity: _recentActivities[index],
                                        onPhotos: () => _viewPhotos(
                                            _recentActivities[index]),
                                        onEdit: () => _editActivity(
                                            _recentActivities[index], index),
                                        onRemove: () => _confirmRemove(index),
                                      ),
                                    ),
                                ],
                              ),
                      ),
          ),
        ],
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
          tooltip: 'Add new survey record',
        ),
      ),
    );
  }
}

class _PendingActivityCard extends StatelessWidget {
  const _PendingActivityCard({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final payload = Map<String, dynamic>.from(item['payload'] as Map? ?? {});
    final survey = Map<String, dynamic>.from(payload['survey'] as Map? ?? {});
    final activityName = (survey['activityName'] as String?)?.trim();
    final municipality = (survey['municipality'] as String?)?.trim() ?? '';
    final barangay = (survey['barangay'] as String?)?.trim() ?? '';
    final surveyDate =
        DateTime.tryParse((survey['surveyDate'] as String?) ?? '');

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF6E5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFCC80)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    (activityName != null && activityName.isNotEmpty)
                        ? activityName
                        : 'Survey Record',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF7A4F01),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Pending sync',
                    style: TextStyle(
                      color: Color(0xFFB25E00),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 20),
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _LabelValue(
                  label: 'Municipality',
                  value: municipality.isEmpty ? '—' : municipality,
                ),
                _LabelValue(
                  label: 'Barangay',
                  value: barangay.isEmpty ? '—' : barangay,
                ),
                _LabelValue(
                  label: 'Survey Date',
                  value: surveyDate != null ? _formatDate(surveyDate) : '—',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({
    required this.activity,
    required this.onPhotos,
    required this.onEdit,
    required this.onRemove,
  });

  final FloraFaunaEntry activity;
  final VoidCallback onPhotos;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  static const _menuPhotos = 'photos';
  static const _menuEdit = 'edit';
  static const _menuRemove = 'remove';

  @override
  Widget build(BuildContext context) {
    final chipColor = activity.entryType == 'Fauna'
        ? const Color(0xFF1565C0)
        : const Color(0xFF2E7D32);

    return Container(
      padding: const EdgeInsets.all(14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.speciesName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      activity.scientificName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF4B5563),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.more_vert,
                      color: Color(0xFF6B7280),
                    ),
                    onSelected: (value) {
                      if (value == _menuPhotos) {
                        onPhotos();
                      } else if (value == _menuEdit) {
                        onEdit();
                      } else if (value == _menuRemove) {
                        onRemove();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem<String>(
                        value: _menuPhotos,
                        child: Row(
                          children: [
                            Icon(Icons.photo_library_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('Photos'),
                          ],
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: _menuEdit,
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      // Only the record's creator or an admin can delete it.
                      if (AuthSession.canDelete(activity.userId))
                        const PopupMenuItem<String>(
                          value: _menuRemove,
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline,
                                  size: 18, color: Colors.red),
                              SizedBox(width: 10),
                              Text('Remove',
                                  style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: chipColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      activity.entryType,
                      style: TextStyle(
                        color: chipColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _LabelValue(
                label: 'Municipality',
                value: activity.municipality,
              ),
              _LabelValue(
                label: 'Barangay',
                value: activity.barangay,
              ),
              _LabelValue(
                label: 'Observer',
                value: activity.observer,
              ),
              _LabelValue(
                label: 'Survey Date',
                value: _formatDate(activity.surveyDate),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

class _LabelValue extends StatelessWidget {
  const _LabelValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}


