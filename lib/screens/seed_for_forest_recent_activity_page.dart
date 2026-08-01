import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data_entry/seed_for_forest_models.dart';
import '../data_entry/seed_for_forest_form.dart';
import '../service/auth_session.dart';
import '../service/offline_sync_service.dart';
import '../service/seedling_list_service.dart';
import '../widget/side_panel.dart';

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

  /// Synced records and queued-but-not-yet-synced ("pending sync") records,
  /// loaded together so both refresh in lockstep on initState, pull-to-
  /// refresh, and after returning from the form. The third element carries a
  /// friendly message when the synced-records fetch failed (e.g. offline) —
  /// pending items still load from disk in that case, so they aren't lost.
  late Future<(List<SeedForForestEntry>, List<Map<String, dynamic>>, String?)>
      _pageDataFuture;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _pageDataFuture = _loadPageData();
  }

  Future<(List<SeedForForestEntry>, List<Map<String, dynamic>>, String?)>
      _loadPageData() async {
    List<SeedForForestEntry> activities = const [];
    String? errorMessage;
    try {
      activities = await _loadRecentActivities();
    } catch (e) {
      errorMessage = OfflineSyncService.friendlyErrorMessage(e);
    }

    final pendingItems =
        await OfflineSyncService.getPendingItems(type: 'seed_for_forest');
    return (activities, pendingItems, errorMessage);
  }

  void _refresh() {
    setState(() {
      _pageDataFuture = _loadPageData();
    });
  }

  Future<void> _syncNow() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    final synced = await OfflineSyncService.syncAll();

    if (!mounted) return;
    final nextFuture = _loadPageData();
    setState(() {
      _pageDataFuture = nextFuture;
      _isSyncing = false;
    });
    await nextFuture;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          synced > 0
              ? 'Synced $synced record${synced == 1 ? '' : 's'}.'
              : 'Unable to sync — check your internet connection.',
        ),
        backgroundColor: synced > 0 ? Colors.green : Colors.red,
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
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF23253B),
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                _refresh();
                await _pageDataFuture;
              },
              child: FutureBuilder<
                  (List<SeedForForestEntry>, List<Map<String, dynamic>>, String?)>(
                future: _pageDataFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          OfflineSyncService.friendlyErrorMessage(
                              snapshot.error!),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  final activities =
                      snapshot.data?.$1 ?? const <SeedForForestEntry>[];
                  final pendingItems =
                      snapshot.data?.$2 ?? const <Map<String, dynamic>>[];
                  final loadError = snapshot.data?.$3;

                  if (activities.isEmpty &&
                      pendingItems.isEmpty &&
                      loadError == null) {
                    return const Center(
                      child: Text('No seed donations found.'),
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    children: [
                      if (loadError != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            loadError,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFFB07C1F)),
                          ),
                        ),
                      ],
                      if (pendingItems.isNotEmpty) ...[
                        Row(
                          children: [
                            Expanded(
                              child: _SectionLabel(
                                text: 'Pending Sync (${pendingItems.length})',
                                color: const Color(0xFFB07C1F),
                                icon: Icons.cloud_off_rounded,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _isSyncing ? null : _syncNow,
                              icon: _isSyncing
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFB07C1F),
                                      ),
                                    )
                                  : const Icon(Icons.sync_rounded,
                                      size: 16, color: Color(0xFFB07C1F)),
                              label: Text(
                                _isSyncing ? 'Syncing…' : 'Sync Now',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFB07C1F),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        for (final item in pendingItems)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _PendingActivityCard(
                              item: item,
                              onTap: () => _editPendingActivity(item),
                              onDelete: () => _deletePendingActivity(item),
                            ),
                          ),
                        if (activities.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          const _SectionLabel(
                            text: 'Synced',
                            color: Color(0xFF23253B),
                            icon: Icons.cloud_done_rounded,
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                      for (final activity in activities)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _RecentActivityCard(
                            activity: activity,
                            onEdit: () => _editActivity(activity),
                            onRemove: () => _removeDonation(activity),
                            onStatusTap: () => _changeStatus(activity),
                          ),
                        ),
                    ],
                  );
                },
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
          tooltip: 'Add new seed record',
        ),
      ),
    );
  }

  Future<void> _openAddDialog({
    SeedForForestEntry? initialEntry,
    String? pendingLocalId,
    Map<String, dynamic>? pendingPayload,
  }) async {
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
          pendingLocalId: pendingLocalId,
          pendingPayload: pendingPayload,
          onSave: (entry) {
            Navigator.pop(dialogContext);
            if (!mounted) return;
            _refresh();
            // Offline/pending saves (entry.id == null) already show their
            // own "Data was saved." snackbar from inside the form — only
            // show this one for a save that actually reached the server.
            if (entry.id != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    initialEntry == null
                        ? 'Seed for a Forest record added.'
                        : 'Seed for a Forest record updated.',
                  ),
                ),
              );
            }
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

  Future<void> _editPendingActivity(Map<String, dynamic> item) async {
    final localId = (item['localId'] ?? '').toString();
    if (localId.isEmpty) return;
    final payload = Map<String, dynamic>.from(item['payload'] as Map? ?? {});
    await _openAddDialog(pendingLocalId: localId, pendingPayload: payload);
  }

  Future<void> _deletePendingActivity(Map<String, dynamic> item) async {
    final localId = (item['localId'] ?? '').toString();
    if (localId.isEmpty) return;

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
                'Delete Pending Record?',
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
          'This record has not synced yet. Deleting it now discards it permanently and it will not be uploaded.',
          style: TextStyle(
            fontSize: 14,
            height: 1.35,
            color: Color(0xFF5E6175),
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
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
              'Delete',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await OfflineSyncService.deletePendingItem(localId);
    if (!mounted) return;
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pending record removed.')),
    );
  }

  Future<SeedForForestEntry?> _loadEntryForEdit(int? donationId) async {
    if (donationId == null) return null;

    final headerRow = await _supabase
        .from('seed_donation')
        .select(
          'id, donor_name, donated_date, total_count, details, status, is_converted, survive',
        )
        .eq('id', donationId)
        .maybeSingle();

    if (headerRow == null) return null;

    final detailRows = await _supabase
        .from('seed_donation_data')
        .select('seed_id, seed_count, species_type, is_mangrove')
        .eq('seed_donation_id', donationId);

    final seedDetails = await _resolveSeedDetails(
      (detailRows as List<dynamic>).cast<Map<String, dynamic>>(),
    );

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
      status: (headerRow['status'] ?? 'DONATED').toString(),
      isConverted: (headerRow['is_converted'] as bool?) ?? false,
      survive: (headerRow['survive'] as num?)?.toInt(),
    );
  }

  Future<List<SeedDetail>> _loadSeedDetailsForDonation(int? donationId) async {
    if (donationId == null) return const [];

    try {
      final detailRows = await _supabase
          .from('seed_donation_data')
          .select('seed_id, seed_count, species_type, is_mangrove')
          .eq('seed_donation_id', donationId);

      return await _resolveSeedDetails(
        (detailRows as List<dynamic>).cast<Map<String, dynamic>>(),
      );
    } catch (_) {
      return const [];
    }
  }

  /// Resolves seed_donation_data rows to display-ready SeedDetail objects.
  /// seed_id points into seedling_list normally, but into mangrove_list for
  /// rows flagged is_mangrove (saved by the mangrove propagation form) —
  /// the two id spaces aren't related, so each group is looked up against
  /// its own table.
  Future<List<SeedDetail>> _resolveSeedDetails(
    List<Map<String, dynamic>> rows,
  ) async {
    final regularSeedIds = <int>{};
    final mangroveSeedIds = <int>{};
    for (final row in rows) {
      final seedId = (row['seed_id'] as num?)?.toInt();
      if (seedId == null) continue;
      if (row['is_mangrove'] == true) {
        mangroveSeedIds.add(seedId);
      } else {
        regularSeedIds.add(seedId);
      }
    }

    final Map<int, String> seedNameById = {};
    if (regularSeedIds.isNotEmpty) {
      final seedOptions = await _seedlingListService.getSeedlingOptions();
      for (final option in seedOptions) {
        seedNameById[option.id] = option.name;
      }
    }

    final Map<int, String> mangroveNameById = {};
    if (mangroveSeedIds.isNotEmpty) {
      final mangroveRows = await _supabase
          .from('mangrove_list')
          .select('id, name')
          .inFilter('id', mangroveSeedIds.toList());

      for (final row
          in (mangroveRows as List<dynamic>).cast<Map<String, dynamic>>()) {
        final id = (row['id'] as num?)?.toInt();
        final name = (row['name'] ?? '').toString();
        if (id != null) {
          mangroveNameById[id] = name;
        }
      }
    }

    return rows.map((row) {
      final seedId = (row['seed_id'] as num?)?.toInt() ?? 0;
      final isMangrove = row['is_mangrove'] == true;
      final resolvedName =
          isMangrove ? mangroveNameById[seedId] : seedNameById[seedId];
      return SeedDetail(
        seedId: seedId,
        speciesType: (row['species_type'] ?? '').toString(),
        speciesName: resolvedName ?? 'Seed $seedId',
        speciesCount: (row['seed_count'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  Future<void> _changeStatus(SeedForForestEntry activity) async {
    const statusOptions = [
      ('DONATED', Icons.volunteer_activism_rounded),
      ('PROPAGATED', Icons.eco_rounded),
    ];

    var selectedStatus = statusOptions.any((o) => o.$1 == activity.status)
        ? activity.status
        : 'DONATED';

    final seedDetails = await _loadSeedDetailsForDonation(activity.id);

    if (!mounted) return;

    final updatedStatus = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              insetPadding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white,
                ),
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF1F674E),
                            Color(0xFF1B8B5E),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.sync_alt_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Update Status',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Move this donation to its next stage',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (seedDetails.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Seedlings in this donation',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (var i = 0; i < seedDetails.length; i++) ...[
                                    if (i > 0) const Divider(height: 1),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8),
                                      child: Row(
                                        children: [
                                          Icon(Icons.eco,
                                              size: 16,
                                              color: Colors.green.shade600),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              seedDetails[i]
                                                      .speciesName
                                                      .trim()
                                                      .isEmpty
                                                  ? 'Unspecified'
                                                  : seedDetails[i].speciesName,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF25273B),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text(
                                            '${seedDetails[i].speciesCount}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF1B8B5E),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Status',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...statusOptions.map((option) {
                            final (value, icon) = option;
                            final isSelected = selectedStatus == value;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () =>
                                      setDialogState(() => selectedStatus = value),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: isSelected
                                          ? const Color(0xFF1B8B5E)
                                              .withValues(alpha: 0.1)
                                          : Colors.grey.shade50,
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF1B8B5E)
                                            : Colors.grey.shade200,
                                        width: isSelected ? 1.5 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          icon,
                                          size: 20,
                                          color: isSelected
                                              ? const Color(0xFF1B8B5E)
                                              : Colors.grey.shade500,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            value,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: isSelected
                                                  ? const Color(0xFF1B8B5E)
                                                  : const Color(0xFF3A3D4D),
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          isSelected
                                              ? Icons.radio_button_checked_rounded
                                              : Icons.radio_button_unchecked_rounded,
                                          size: 20,
                                          color: isSelected
                                              ? const Color(0xFF1B8B5E)
                                              : Colors.grey.shade400,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(dialogContext).pop(),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                side: BorderSide(color: Colors.grey.shade300),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF4E526A),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(selectedStatus),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1B8B5E),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'Update',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (updatedStatus == null ||
        updatedStatus == activity.status ||
        activity.id == null) {
      return;
    }

    try {
      await _supabase
          .from('seed_donation')
          .update({'status': updatedStatus}).eq('id', activity.id!);

      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status updated to $updatedStatus.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    }
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
      _refresh();
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
        .select(
          'id, user_id, donor_name, donated_date, total_count, details, created_at, status, is_converted, survive',
        )
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
            userId: (data['user_id'] ?? '').toString().isEmpty
                ? null
                : data['user_id'].toString(),
            donorName: (data['donor_name'] ?? '').toString(),
            seedDetails: const [],
            date: donatedDate,
            totalCount: totalCount,
            remarks: (data['details'] ?? '').toString(),
            status: (data['status'] ?? 'DONATED').toString(),
            isConverted: (data['is_converted'] as bool?) ?? false,
            survive: (data['survive'] as num?)?.toInt(),
          );
        })
        .toList();
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.text,
    required this.color,
    required this.icon,
  });

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Lightweight card for a record queued via OfflineSyncService that has not
/// synced to the server yet. Reads straight from the queue item's payload
/// map rather than a model class — donor name / date / total count come
/// from payload['headerPayload'], falling back to summing
/// payload['seedDetails'] for the count if total_count wasn't stored.
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
    final header =
        Map<String, dynamic>.from(payload['headerPayload'] as Map? ?? {});
    final seedDetails = (payload['seedDetails'] as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    final donorName = (header['donor_name'] ?? '').toString();
    final donatedDate =
        DateTime.tryParse((header['donated_date'] ?? '').toString());
    final totalCount = (header['total_count'] as num?)?.toInt() ??
        seedDetails.fold<int>(
          0,
          (sum, row) => sum + ((row['seed_count'] as num?)?.toInt() ?? 0),
        );

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6EA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0C88A)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFB07C1F).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_rounded,
                              size: 12, color: Color(0xFFB07C1F)),
                          SizedBox(width: 4),
                          Text(
                            'PENDING SYNC',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              color: Color(0xFFB07C1F),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline,
                          color: Color(0xFFB07C1F)),
                      tooltip: 'Delete pending record',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _RowColumn(
                        label: 'Donor Name',
                        value: donorName.isEmpty ? 'Unspecified' : donorName,
                        valueMaxLines: 2,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _RowColumn(
                        label: 'Date',
                        value: donatedDate != null
                            ? _formatDate(donatedDate)
                            : '-',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _RowColumn(
                        label: 'Total Seed Donated',
                        value: totalCount.toString(),
                        valueColor: const Color(0xFFB07C1F),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
    required this.onEdit,
    required this.onRemove,
    required this.onStatusTap,
  });

  final SeedForForestEntry activity;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final VoidCallback onStatusTap;

  @override
  Widget build(BuildContext context) {
    final isPlantable = activity.status.toUpperCase() == 'PLANTABLE';
    final statusColor = switch (activity.status.toUpperCase()) {
      'PLANTABLE' => const Color(0xFF1B8B5E),
      'PROPAGATED' => const Color(0xFFB07C1F),
      _ => const Color(0xFF6B7280),
    };

    return Container(
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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isPlantable ? null : onStatusTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                    if (isPlantable) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: _RowColumn(
                          label: 'Survive',
                          value: (activity.survive ?? 0).toString(),
                          valueColor: const Color(0xFF1976D2),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      tooltip: 'Actions',
                      enabled: !isPlantable,
                      onSelected: (value) {
                        if (value == 'edit') {
                          onEdit();
                        } else if (value == 'remove') {
                          onRemove();
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        // Only the record's creator or an admin can delete it.
                        if (AuthSession.canDelete(activity.userId))
                          const PopupMenuItem(
                              value: 'remove', child: Text('Remove')),
                      ],
                      icon: Icon(
                        Icons.more_vert,
                        color: isPlantable ? Colors.grey.shade300 : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        activity.status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: statusColor,
                        ),
                      ),
                    ),
                    if (activity.isConverted) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7DD7).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_rounded,
                                size: 12, color: Color(0xFF2E7DD7)),
                            SizedBox(width: 4),
                            Text(
                              'IN INVENTORY',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                color: Color(0xFF2E7DD7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
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

