import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data_entry/seedling_request_form.dart';

class _SeedlingRequestItem {
  final String transactionId;
  final int? seedId;
  final String species;
  final int quantity;
  final DateTime createdAt;
  final int? nurseryId;
  final String nursery;
  final int? speciesTypeId;
  final String? releaseBy;
  final String? releaseTo;

  const _SeedlingRequestItem({
    required this.transactionId,
    required this.seedId,
    required this.species,
    required this.quantity,
    required this.createdAt,
    required this.nurseryId,
    required this.nursery,
    required this.speciesTypeId,
    required this.releaseBy,
    required this.releaseTo,
  });
}

class _SeedlingRequestGroup {
  final String groupKey;
  final DateTime createdAt;
  final String releaseTo;
  final String? releaseBy;
  final List<_SeedlingRequestItem> items;

  const _SeedlingRequestGroup({
    required this.groupKey,
    required this.createdAt,
    required this.releaseTo,
    required this.releaseBy,
    required this.items,
  });

  int get totalQuantity =>
      items.fold<int>(0, (sum, item) => sum + item.quantity);
}

class SeedlingRequestPage extends StatefulWidget {
  const SeedlingRequestPage({super.key});

  @override
  State<SeedlingRequestPage> createState() => _SeedlingRequestPageState();
}

class _SeedlingRequestPageState extends State<SeedlingRequestPage> {
  final List<_SeedlingRequestGroup> _groups = [];

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 31, 103, 78),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: const [
            Icon(Icons.assignment_outlined, color: Colors.white, size: 32),
            SizedBox(width: 12),
            Text(
              'Seedling Request',
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
        onRefresh: () => _loadRequests(showLoader: false),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Row(
                children: [
                  Text(
                    'Recent Requests',
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
          onPressed: _openDataEntryDialog,
          icon: const Icon(
            Icons.add,
            color: Color.fromARGB(255, 31, 103, 78),
          ),
          iconSize: 35,
          tooltip: 'Add seedling request',
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
                onPressed: _loadRequests,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_groups.isEmpty) {
      return const Center(
        child: Text(
          'No seedling requests yet.',
          style: TextStyle(fontSize: 16, color: Color(0xFF636780)),
        ),
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 88),
      itemCount: _groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _buildRequestCard(_groups[index]);
      },
    );
  }

  Widget _buildRequestCard(_SeedlingRequestGroup group) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _showGroupDetailsDialog(group),
      child: Container(
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
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: _buildInlineField(
                label: 'Release To',
                value: group.releaseTo.trim().isEmpty
                    ? 'Unspecified'
                    : group.releaseTo,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _buildInlineField(
                label: 'Date',
                value: _formatDate(group.createdAt),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${group.items.length} species',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF777A90),
            ),
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert_rounded,
                color: Color(0xFF777A90),
              ),
              onSelected: (value) => _onActivityMenuSelected(group, value),
              itemBuilder: (context) => [
                if (group.items.length == 1)
                  const PopupMenuItem<String>(
                    value: 'edit',
                    child: Text('Edit'),
                  ),
                const PopupMenuItem<String>(
                  value: 'remove',
                  child: Text('Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineField({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF777A90),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF25273B),
            height: 1.1,
          ),
        ),
      ],
    );
  }

  Future<void> _showGroupDetailsDialog(_SeedlingRequestGroup group) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white,
            ),
            constraints: const BoxConstraints(maxWidth: 450, maxHeight: 550),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1F674E), Color(0xFF1B8B5E)],
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
                          Icons.assignment_outlined,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.releaseTo.trim().isEmpty
                                  ? 'Unspecified'
                                  : group.releaseTo,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '${_formatDate(group.createdAt)} • Total: ${group.totalQuantity}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        'Species',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Quantity',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    itemCount: group.items.length,
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemBuilder: (context, index) {
                      final item = group.items[index];
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  item.species.trim().isEmpty
                                      ? 'Unspecified'
                                      : item.species,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF25273B),
                                  ),
                                ),
                                Text(
                                  item.nursery.trim().isEmpty
                                      ? 'Unspecified nursery'
                                      : item.nursery,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            item.quantity.toString(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1B8B5E),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _onActivityMenuSelected(
    _SeedlingRequestGroup group,
    String action,
  ) async {
    if (action == 'edit' && group.items.length == 1) {
      await _openDataEntryDialog(item: group.items.first);
      return;
    }

    if (action == 'remove') {
      await _removeRequest(group);
    }
  }

  Future<void> _removeRequest(_SeedlingRequestGroup group) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Request'),
        content: Text(
          group.items.length > 1
              ? 'Are you sure you want to remove this request? All ${group.items.length} species in this request will be removed.'
              : 'Are you sure you want to remove this request?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    final ids = group.items
        .map((item) => item.transactionId)
        .where((id) => id.isNotEmpty)
        .toList();

    if (ids.isEmpty) return;

    try {
      await Supabase.instance.client
          .from('seedling_transaction')
          .delete()
          .inFilter('id', ids);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request removed.'),
          backgroundColor: Color(0xFF1B8B5E),
        ),
      );
      await _loadRequests(showLoader: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to remove request: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _loadRequests({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final supabase = Supabase.instance.client;

      final releaseTypeRow = await supabase
          .from('seedling_transaction_type')
          .select('id')
          .ilike('transaction_type', 'release')
          .maybeSingle();

      final releaseTypeId = (releaseTypeRow?['id'] as num?)?.toInt();

      var query = supabase
          .from('seedling_transaction')
          .select(
              'id, seed_id, nursery_id, seedling_count, species_type_id, release_by, release_to, created_at, transaction_type_id');

      if (releaseTypeId != null) {
        query = query.eq('transaction_type_id', releaseTypeId);
      }

      final transactionRows =
          await query.order('created_at', ascending: false).limit(200);

      final parsedTransactions =
          (transactionRows as List<dynamic>).cast<Map<String, dynamic>>();

      final seedIds = parsedTransactions
          .map((row) => (row['seed_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet()
          .toList();
      final nurseryIds = parsedTransactions
          .map((row) => (row['nursery_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet()
          .toList();

      final Map<int, String> seedNameById = {};
      final Map<int, String> nurseryNameById = {};

      if (seedIds.isNotEmpty) {
        final seedRows = await supabase
            .from('seedling_list')
            .select('seq_id, seedling_name')
            .inFilter('seq_id', seedIds);

        for (final row
            in (seedRows as List<dynamic>).cast<Map<String, dynamic>>()) {
          final id = (row['seq_id'] as num?)?.toInt();
          final name = (row['seedling_name'] ?? '').toString();
          if (id != null) {
            seedNameById[id] = name;
          }
        }
      }

      if (nurseryIds.isNotEmpty) {
        final nurseryRows = await supabase
            .from('seedling_nursery')
            .select('seq_id, name')
            .inFilter('seq_id', nurseryIds);

        for (final row
            in (nurseryRows as List<dynamic>).cast<Map<String, dynamic>>()) {
          final id = (row['seq_id'] as num?)?.toInt();
          final nurseryName = (row['name'] ?? '').toString();
          if (id != null) {
            nurseryNameById[id] = nurseryName;
          }
        }
      }

      final loadedItems = parsedTransactions.map((row) {
        final seedId = (row['seed_id'] as num?)?.toInt();
        final nurseryId = (row['nursery_id'] as num?)?.toInt();
        final createdAtRaw = (row['created_at'] ?? '').toString();
        final createdAt = DateTime.tryParse(createdAtRaw) ?? DateTime.now();

        return _SeedlingRequestItem(
          transactionId: (row['id'] ?? '').toString(),
          seedId: seedId,
          species: seedNameById[seedId] ?? 'Unspecified',
          quantity: (row['seedling_count'] as num?)?.toInt() ?? 0,
          createdAt: createdAt,
          nurseryId: nurseryId,
          nursery: nurseryNameById[nurseryId] ?? 'Unspecified',
          speciesTypeId: (row['species_type_id'] as num?)?.toInt(),
          releaseBy: (row['release_by'] ?? '').toString(),
          releaseTo: (row['release_to'] ?? '').toString(),
        );
      }).toList();

      final Map<String, List<_SeedlingRequestItem>> grouped = {};
      for (final item in loadedItems) {
        final key =
            '${item.createdAt.toIso8601String()}|${item.releaseTo}|${item.releaseBy}|${item.nurseryId}';
        grouped.putIfAbsent(key, () => []).add(item);
      }

      final loadedGroups = grouped.entries.map((entry) {
        final items = entry.value;
        final first = items.first;
        return _SeedlingRequestGroup(
          groupKey: entry.key,
          createdAt: first.createdAt,
          releaseTo: first.releaseTo ?? '',
          releaseBy: first.releaseBy,
          items: items,
        );
      }).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (!mounted) return;
      setState(() {
        _groups
          ..clear()
          ..addAll(loadedGroups);
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load requests: $e';
      });
    }
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<void> _openDataEntryDialog({_SeedlingRequestItem? item}) async {
    try {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => SeedlingRequestForm(
          initialTransactionId:
              item == null ? null : int.tryParse(item.transactionId),
          initialSeedId: item?.seedId,
          initialNurseryId: item?.nurseryId,
          initialSpeciesTypeId: item?.speciesTypeId,
          initialSeedlingCount: item?.quantity,
          initialDate: item?.createdAt,
          initialReleaseBy: item?.releaseBy,
          initialReleaseTo: item?.releaseTo,
          onSave: () {
            _loadRequests();
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open data entry form: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}
