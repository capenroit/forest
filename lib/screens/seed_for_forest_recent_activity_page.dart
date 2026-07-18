import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data_entry/seed_for_forest_models.dart';
import '../data_entry/seed_for_forest_form.dart';
import '../service/seedling_list_service.dart';

class SeedForForestRecentActivityPage extends StatefulWidget {
  const SeedForForestRecentActivityPage({super.key});

  @override
  State<SeedForForestRecentActivityPage> createState() =>
      _SeedForForestRecentActivityPageState();
}

class _SeedForForestRecentActivityPageState
    extends State<SeedForForestRecentActivityPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SeedlingListService _seedlingListService = SeedlingListService();
  late Future<List<SeedForForestEntry>> _recentActivitiesFuture;

  @override
  void initState() {
    super.initState();
    _recentActivitiesFuture = _loadRecentActivities();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 31, 103, 78),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Seed for a Forest',
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
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF23253B),
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<SeedForForestEntry>>(
              future: _recentActivitiesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Failed to load recent activity: ${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final activities = snapshot.data ?? const <SeedForForestEntry>[];
                if (activities.isEmpty) {
                  return const Center(
                    child: Text('No seed donations found.'),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  itemCount: activities.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final activity = activities[index];
                    return _RecentActivityCard(
                      activity: activity,
                      onEdit: () => _editActivity(activity),
                      onRemove: () => _removeDonation(activity),
                    );
                  },
                );
              },
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
          tooltip: 'Add new seed record',
        ),
      ),
    );
  }

  Future<void> _openAddDialog({SeedForForestEntry? initialEntry}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        insetPadding: const EdgeInsets.all(16),
        child: SeedForForestForm(
          initialData: initialEntry,
          onSave: (entry) {
            Navigator.pop(dialogContext);
            if (!mounted) return;
            setState(() {
              _recentActivitiesFuture = _loadRecentActivities();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  initialEntry == null
                      ? 'Seed for a Forest record added.'
                      : 'Seed for a Forest record updated.',
                ),
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

  Future<void> _editActivity(SeedForForestEntry activity) async {
    final initialData = await _loadEntryForEdit(activity.id);
    if (!mounted || initialData == null) return;
    await _openAddDialog(initialEntry: initialData);
  }

  Future<SeedForForestEntry?> _loadEntryForEdit(int? donationId) async {
    if (donationId == null) return null;

    final headerRow = await _supabase
        .from('seed_donation')
        .select('id, donor_name, donated_date, total_count, details')
        .eq('id', donationId)
        .maybeSingle();

    if (headerRow == null) return null;

    final detailRows = await _supabase
        .from('seed_donation_data')
        .select('seed_id, seed_count, species_type')
        .eq('seed_donation_id', donationId);

    final seedOptions = await _seedlingListService.getSeedlingOptions();
    final seedNameById = {
      for (final option in seedOptions) option.id: option.name,
    };

    final seedDetails = (detailRows as List<dynamic>).map((row) {
      final data = Map<String, dynamic>.from(row as Map);
      final seedId = (data['seed_id'] as num?)?.toInt() ?? 0;
      return SeedDetail(
        seedId: seedId,
        speciesType: (data['species_type'] ?? '').toString(),
        speciesName: seedNameById[seedId] ?? 'Seed $seedId',
        speciesCount: (data['seed_count'] as num?)?.toInt() ?? 0,
      );
    }).toList();

    final donatedDateRaw = (headerRow['donated_date'] ?? '').toString();
    final donatedDate = DateTime.tryParse(donatedDateRaw) ?? DateTime.now();
    final totalCount = (headerRow['total_count'] as num?)?.toInt() ??
        seedDetails.fold<int>(0, (sum, detail) => sum + detail.speciesCount);

    return SeedForForestEntry(
      id: (headerRow['id'] as num?)?.toInt(),
      donorName: (headerRow['donor_name'] ?? '').toString(),
      seedDetails: seedDetails,
      date: donatedDate,
      totalCount: totalCount,
      remarks: (headerRow['details'] ?? '').toString(),
    );
  }

  Future<void> _removeDonation(SeedForForestEntry activity) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
        content: Text(
          'This record will be removed from Recent Activity and hidden from the dashboard. You can not undo this action.',
          style: const TextStyle(
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
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text(
              'Remove',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || activity.id == null) return;

    try {
      await _supabase
          .from('seed_donation_data')
          .delete()
          .eq('seed_donation_id', activity.id!);
      await _supabase.from('seed_donation').delete().eq('id', activity.id!);

      if (!mounted) return;
      setState(() {
        _recentActivitiesFuture = _loadRecentActivities();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seed donation removed.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove donation: $e')),
      );
    }
  }

  Future<List<SeedForForestEntry>> _loadRecentActivities() async {
    final response = await _supabase
        .from('seed_donation')
        .select('id, donor_name, donated_date, total_count, details, created_at')
        .order('donated_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(100);

    return (response as List<dynamic>)
        .map((row) {
          final data = Map<String, dynamic>.from(row as Map);
          final donatedDateRaw = (data['donated_date'] ?? '').toString();
          final donatedDate = DateTime.tryParse(donatedDateRaw) ?? DateTime.now();
          final totalCount = (data['total_count'] as num?)?.toInt() ?? 0;

          return SeedForForestEntry(
            id: (data['id'] as num?)?.toInt(),
            donorName: (data['donor_name'] ?? '').toString(),
            seedDetails: const [],
            date: donatedDate,
            totalCount: totalCount,
            remarks: (data['details'] ?? '').toString(),
          );
        })
        .toList();
  }
}

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({
    required this.activity,
    required this.onEdit,
    required this.onRemove,
  });

  final SeedForForestEntry activity;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: _RowColumn(
                  label: 'Donor Name',
                  value: activity.donorName,
                  valueMaxLines: 2,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _RowColumn(
                  label: 'Date',
                  value: _formatDate(activity.date),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _RowColumn(
                  label: 'Total Seed Donated',
                  value: activity.totalCount.toString(),
                  valueColor: const Color(0xFF1B8B5E),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'Actions',
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit();
                  } else if (value == 'remove') {
                    onRemove();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'remove', child: Text('Remove')),
                ],
                icon: const Icon(Icons.more_vert),
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

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor = const Color(0xFF111827),
  });

  final String label;
  final String value;
  final IconData icon;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF6B7280)),
        const SizedBox(width: 8),
        Expanded(
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
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RowColumn extends StatelessWidget {
  const _RowColumn({
    required this.label,
    required this.value,
    this.valueColor = const Color(0xFF111827),
    this.valueMaxLines = 1,
  });

  final String label;
  final String value;
  final Color valueColor;
  final int valueMaxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: valueMaxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

