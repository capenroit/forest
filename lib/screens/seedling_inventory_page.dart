import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data_entry/seedling_transaction_form.dart';

class _SeedlingInventoryActivityItem {
  final String transactionId;
  final int? seedId;
  final String species;
  final int quantity;
  final DateTime createdAt;
  final int? transactionTypeId;
  final String transactionType;
  final int? nurseryId;
  final String nursery;
  final int? speciesTypeId;
  final String? releaseBy;
  final String? releaseTo;

  const _SeedlingInventoryActivityItem({
    required this.transactionId,
    required this.seedId,
    required this.species,
    required this.quantity,
    required this.createdAt,
    required this.transactionTypeId,
    required this.transactionType,
    required this.nurseryId,
    required this.nursery,
    required this.speciesTypeId,
    required this.releaseBy,
    required this.releaseTo,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': transactionId,
      'seed_id': seedId,
      'species': species,
      'quantity': quantity,
      'created_at': createdAt.toIso8601String(),
      'transaction_type_id': transactionTypeId,
      'transaction_type': transactionType,
      'nursery_id': nurseryId,
      'nursery': nursery,
      'species_type_id': speciesTypeId,
      'release_by': releaseBy,
      'release_to': releaseTo,
    };
  }

  static _SeedlingInventoryActivityItem fromJson(Map<String, dynamic> json) {
    final rawDate = (json['created_at'] ?? '').toString();
    final parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();

    return _SeedlingInventoryActivityItem(
      transactionId: (json['id'] ?? '').toString(),
      seedId: (json['seed_id'] as num?)?.toInt(),
      species: (json['species'] ?? '').toString(),
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      createdAt: parsedDate,
      transactionTypeId: (json['transaction_type_id'] as num?)?.toInt(),
      transactionType: (json['transaction_type'] ?? '').toString(),
      nurseryId: (json['nursery_id'] as num?)?.toInt(),
      nursery: (json['nursery'] ?? '').toString(),
      speciesTypeId: (json['species_type_id'] as num?)?.toInt(),
      releaseBy: (json['release_by'] ?? '').toString(),
      releaseTo: (json['release_to'] ?? '').toString(),
    );
  }
}

class SeedlingInventoryPage extends StatefulWidget {
  const SeedlingInventoryPage({super.key});

  @override
  State<SeedlingInventoryPage> createState() => _SeedlingInventoryPageState();
}

class _SeedlingInventoryPageState extends State<SeedlingInventoryPage> {
  final List<_SeedlingInventoryActivityItem> _items = [];

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
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 31, 103, 78),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: const [
            Icon(Icons.inventory_2_rounded, color: Colors.white, size: 32),
            SizedBox(width: 12),
            Text(
              'Seedling Inventory',
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
          onPressed: _openDataEntryDialog,
          icon: const Icon(
            Icons.add,
            color: Color.fromARGB(255, 31, 103, 78),
          ),
          iconSize: 35,
          tooltip: 'Add inventory entry',
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
          'No seedling inventory activity yet.',
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

  Widget _buildActivityCard(_SeedlingInventoryActivityItem item) {
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
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: _buildInlineField(
              label: 'Species',
              value: item.species.trim().isEmpty ? 'Unspecified' : item.species,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _buildInlineField(
              label: 'Count',
              value: item.quantity.toString(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _buildInlineField(
              label: 'Nursery',
              value: item.nursery.trim().isEmpty ? 'Unspecified' : item.nursery,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _buildInlineField(
              label: 'Type',
              value: item.transactionType.trim().isEmpty
                  ? 'Unspecified'
                  : item.transactionType,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _buildInlineField(
              label: 'Date',
              value: _formatDate(item.createdAt),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert_rounded,
              color: Color(0xFF777A90),
            ),
            onSelected: (value) => _onActivityMenuSelected(item, value),
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'edit',
                child: Text('Edit'),
              ),
              PopupMenuItem<String>(
                value: 'remove',
                child: Text('Remove'),
              ),
            ],
          ),
        ],
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

  Future<void> _onActivityMenuSelected(
    _SeedlingInventoryActivityItem item,
    String action,
  ) async {
    if (action == 'edit') {
      await _openDataEntryDialog(item: item);
      return;
    }

    if (action == 'remove') {
      await _removeActivity(item);
    }
  }

  Future<void> _removeActivity(_SeedlingInventoryActivityItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Activity'),
        content: const Text('Are you sure you want to remove this record?'),
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

    if (confirm != true || item.transactionId.isEmpty) {
      return;
    }

    try {
      await Supabase.instance.client
          .from('seedling_transaction')
          .delete()
          .eq('id', item.transactionId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Activity removed.'),
          backgroundColor: Color(0xFF1B8B5E),
        ),
      );
      await _loadRecentActivities(showLoader: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to remove activity: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
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
      final supabase = Supabase.instance.client;
      final transactionRows = await supabase
          .from('seedling_transaction')
          .select('id, seed_id, transaction_type_id, nursery_id, seedling_count, species_type_id, release_by, release_to, created_at')
          .order('created_at', ascending: false)
          .limit(200);

      final parsedTransactions =
          (transactionRows as List<dynamic>).cast<Map<String, dynamic>>();

      final seedIds = parsedTransactions
          .map((row) => (row['seed_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet()
          .toList();
        final transactionTypeIds = parsedTransactions
          .map((row) => (row['transaction_type_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet()
          .toList();
        final nurseryIds = parsedTransactions
          .map((row) => (row['nursery_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet()
          .toList();

      final Map<int, String> seedNameById = {};
        final Map<int, String> transactionTypeById = {};
        final Map<int, String> nurseryNameById = {};
      if (seedIds.isNotEmpty) {
        final seedRows = await supabase
            .from('seedling_list')
            .select('seq_id, seedling_name')
            .inFilter('seq_id', seedIds);

        for (final row in (seedRows as List<dynamic>).cast<Map<String, dynamic>>()) {
          final id = (row['seq_id'] as num?)?.toInt();
          final name = (row['seedling_name'] ?? '').toString();
          if (id != null) {
            seedNameById[id] = name;
          }
        }
      }

      if (transactionTypeIds.isNotEmpty) {
        final typeRows = await supabase
            .from('seedling_transaction_type')
            .select('id, transaction_type')
            .inFilter('id', transactionTypeIds);

        for (final row in (typeRows as List<dynamic>).cast<Map<String, dynamic>>()) {
          final id = (row['id'] as num?)?.toInt();
          final typeName = (row['transaction_type'] ?? '').toString();
          if (id != null) {
            transactionTypeById[id] = typeName;
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
        final transactionId = (row['id'] ?? '').toString();
        final transactionTypeId = (row['transaction_type_id'] as num?)?.toInt();
        final nurseryId = (row['nursery_id'] as num?)?.toInt();
        final quantity = (row['seedling_count'] as num?)?.toInt() ?? 0;
        final createdAtRaw = (row['created_at'] ?? '').toString();
        final createdAt = DateTime.tryParse(createdAtRaw) ?? DateTime.now();

        return _SeedlingInventoryActivityItem(
          transactionId: transactionId,
          seedId: seedId,
          species: seedNameById[seedId] ?? 'Unspecified',
          quantity: quantity,
          createdAt: createdAt,
          transactionTypeId: transactionTypeId,
          transactionType:
              transactionTypeById[transactionTypeId] ?? 'Unspecified',
          nurseryId: nurseryId,
          nursery: nurseryNameById[nurseryId] ?? 'Unspecified',
          speciesTypeId: (row['species_type_id'] as num?)?.toInt(),
          releaseBy: (row['release_by'] ?? '').toString(),
          releaseTo: (row['release_to'] ?? '').toString(),
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(loadedItems);
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

  Future<void> _openDataEntryDialog({_SeedlingInventoryActivityItem? item}) async {
    try {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => SeedlingTransactionForm(
          initialTransactionId: item == null ? null : int.tryParse(item.transactionId),
          initialSeedId: item?.seedId,
          initialNurseryId: item?.nurseryId,
          initialSpeciesTypeId: item?.speciesTypeId,
          initialTransactionTypeId: item?.transactionTypeId,
          initialSeedlingCount: item?.quantity,
          initialDate: item == null ? null : DateTime.tryParse(item.createdAt.toIso8601String()),
          initialReleaseBy: item?.releaseBy,
          initialReleaseTo: item?.releaseTo,
          initialTabIndex:
              (item?.transactionType.trim().toLowerCase() ?? '') == 'release'
                  ? 1
                  : 0,
          onSave: () {
            _loadRecentActivities();
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

