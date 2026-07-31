import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../service/auth_session.dart';
import '../service/lookup_service.dart';
import '../widget/side_panel.dart';

class _PropagatedDonation {
  final int id;
  final String donorName;
  final DateTime donatedDate;
  final int totalCount;

  const _PropagatedDonation({
    required this.id,
    required this.donorName,
    required this.donatedDate,
    required this.totalCount,
  });
}

class _SeedDetailRow {
  final int seedId;
  final String speciesName;
  final String speciesType;
  final int propagatedCount;
  final TextEditingController plantableController;

  _SeedDetailRow({
    required this.seedId,
    required this.speciesName,
    required this.speciesType,
    required this.propagatedCount,
  }) : plantableController =
           TextEditingController(text: propagatedCount.toString());
}

class _PropagatedRowState {
  final _PropagatedDonation donation;
  final List<_SeedDetailRow> seedDetails;
  String status = 'PROPAGATED';
  LookupOption? nursery;
  bool isConverting = false;

  _PropagatedRowState({required this.donation, required this.seedDetails});
}

class _NurseryQuantity {
  final int? nurseryId;
  final String nursery;
  final int quantity;

  const _NurseryQuantity({
    required this.nurseryId,
    required this.nursery,
    required this.quantity,
  });
}

class _AvailableSeedlingItem {
  final int? seedId;
  final String species;
  final int totalQuantity;
  final List<_NurseryQuantity> nurseryBreakdown;

  const _AvailableSeedlingItem({
    required this.seedId,
    required this.species,
    required this.totalQuantity,
    required this.nurseryBreakdown,
  });
}

class SeedlingInventoryPage extends StatefulWidget {
  const SeedlingInventoryPage({super.key});

  @override
  State<SeedlingInventoryPage> createState() => _SeedlingInventoryPageState();
}

class _SeedlingInventoryPageState extends State<SeedlingInventoryPage> {
  final List<_AvailableSeedlingItem> _items = [];
  final TextEditingController _searchController = TextEditingController();

  List<LookupOption> _nurseryFilterOptions = [];
  LookupOption? _selectedNurseryFilter;
  String _searchQuery = '';

  bool _isLoading = true;
  String? _errorMessage;
  int _propagatedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAvailableSeedlings();
    _loadNurseryFilterOptions();
    _loadPropagatedCount();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_AvailableSeedlingItem> get _filteredItems {
    final query = _searchQuery.trim().toLowerCase();
    final nurseryFilter = _selectedNurseryFilter;

    return _items.where((item) {
      if (query.isNotEmpty && !item.species.toLowerCase().contains(query)) {
        return false;
      }
      if (nurseryFilter != null) {
        final hasStockAtNursery = item.nurseryBreakdown.any(
          (n) => n.nurseryId == nurseryFilter.id && n.quantity > 0,
        );
        if (!hasStockAtNursery) return false;
      }
      return true;
    }).toList();
  }

  int _displayQuantity(_AvailableSeedlingItem item) {
    final nurseryFilter = _selectedNurseryFilter;
    if (nurseryFilter == null) return item.totalQuantity;
    for (final entry in item.nurseryBreakdown) {
      if (entry.nurseryId == nurseryFilter.id) return entry.quantity;
    }
    return 0;
  }

  Future<void> _loadNurseryFilterOptions() async {
    try {
      final rows = await Supabase.instance.client
          .from('seedling_nursery')
          .select('seq_id, name');

      final options = (rows as List<dynamic>)
          .map((row) => LookupOption(
                id: (row['seq_id'] as num).toInt(),
                name: (row['name'] as String).trim(),
              ))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (!mounted) return;
      setState(() => _nurseryFilterOptions = options);
    } catch (_) {
      // Nursery filter stays empty; filtering by nursery just won't be offered.
    }
  }

  Future<void> _loadPropagatedCount() async {
    try {
      final rows = await Supabase.instance.client
          .from('seed_donation')
          .select('id')
          .eq('status', 'PROPAGATED');

      if (!mounted) return;
      setState(() => _propagatedCount = (rows as List<dynamic>).length);
    } catch (_) {
      // Badge just won't show if this fails.
    }
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
            Icon(Icons.inventory_2_rounded, color: Colors.white, size: 32),
            SizedBox(width: 12),
            Text(
              'Available Seedling Inventory',
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
        onRefresh: () async {
          await _loadAvailableSeedlings(showLoader: false);
          await _loadPropagatedCount();
        },
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Row(
                children: [
                  Text(
                    'Available Plantable Seedling',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF23253B),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    decoration: InputDecoration(
                      hintText: 'Search species',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(color: Color(0xFF1B8B5E), width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<LookupOption?>(
                    initialValue: _selectedNurseryFilter,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<LookupOption?>(
                        value: null,
                        child: Text('All Nurseries'),
                      ),
                      ..._nurseryFilterOptions.map(
                        (option) => DropdownMenuItem<LookupOption?>(
                          value: option,
                          child: Text(option.name),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedNurseryFilter = value),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.filter_alt_outlined,
                          color: Colors.grey.shade600),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(color: Color(0xFF1B8B5E), width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
            if (!_isLoading && _errorMessage == null) _buildTotalFooter(),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
          bottom: !_isLoading && _errorMessage == null ? 64 : 0,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
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
                  Icons.list_alt_rounded,
                  color: Color.fromARGB(255, 31, 103, 78),
                ),
                iconSize: 35,
                tooltip: 'View propagated seeds',
              ),
            ),
            if (_propagatedCount > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _propagatedCount > 99 ? '99+' : '$_propagatedCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalFooter() {
    final total = _filteredItems.fold<int>(
        0, (sum, item) => sum + _displayQuantity(item));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Total Available Plantable Seedling',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const Spacer(),
          Text(
            total.toString(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1B8B5E),
            ),
          ),
        ],
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
                onPressed: _loadAvailableSeedlings,
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
          'No seedling inventory yet.',
          style: TextStyle(fontSize: 16, color: Color(0xFF636780)),
        ),
      );
    }

    final filtered = _filteredItems;

    if (filtered.isEmpty) {
      return const Center(
        child: Text(
          'No seedlings match your search or filter.',
          style: TextStyle(fontSize: 16, color: Color(0xFF636780)),
        ),
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 88),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _buildAvailableSeedlingCard(filtered[index]);
      },
    );
  }

  Widget _buildAvailableSeedlingCard(_AvailableSeedlingItem item) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _showNurseryQuantityPopup(item),
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
                label: 'Species',
                value:
                    item.species.trim().isEmpty ? 'Unspecified' : item.species,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _buildInlineField(
                label: 'Available',
                value: _displayQuantity(item).toString(),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF777A90),
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

  Future<void> _showNurseryQuantityPopup(_AvailableSeedlingItem item) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
            ),
            constraints: const BoxConstraints(maxWidth: 450, maxHeight: 550),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF1B8B5E),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      const Icon(Icons.eco, color: Colors.white, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.species.trim().isEmpty
                                  ? 'Unspecified'
                                  : item.species,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Total available: ${item.totalQuantity}',
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
                        'Nursery',
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
                  child: item.nurseryBreakdown.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'No nursery data available.',
                            style: TextStyle(color: Color(0xFF636780)),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          itemCount: item.nurseryBreakdown.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 16),
                          itemBuilder: (context, index) {
                            final row = item.nurseryBreakdown[index];
                            return Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    row.nursery.trim().isEmpty
                                        ? 'Unspecified'
                                        : row.nursery,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF25273B),
                                    ),
                                  ),
                                ),
                                Text(
                                  row.quantity.toString(),
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

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<void> _loadAvailableSeedlings({bool showLoader = true}) async {
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
          .select('seed_id, transaction_type_id, nursery_id, seedling_count')
          .limit(5000);

      final parsedTransactions =
          (transactionRows as List<dynamic>).cast<Map<String, dynamic>>();

      final typeRows =
          await supabase.from('seedling_transaction_type').select('id, transaction_type');
      final Map<int, String> transactionTypeById = {};
      for (final row in (typeRows as List<dynamic>).cast<Map<String, dynamic>>()) {
        final id = (row['id'] as num?)?.toInt();
        final typeName = (row['transaction_type'] ?? '').toString();
        if (id != null) {
          transactionTypeById[id] = typeName.trim().toLowerCase();
        }
      }

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

      final Map<int, String> nurseryNameById = {};
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

      // netBySeed[seedId] = net quantity across all nurseries.
      final Map<int, int> netBySeed = {};
      // netBySeedAndNursery[seedId][nurseryId] = net quantity for that nursery.
      final Map<int, Map<int, int>> netBySeedAndNursery = {};

      for (final row in parsedTransactions) {
        final seedId = (row['seed_id'] as num?)?.toInt();
        final nurseryId = (row['nursery_id'] as num?)?.toInt();
        final transactionTypeId = (row['transaction_type_id'] as num?)?.toInt();
        final quantity = (row['seedling_count'] as num?)?.toInt() ?? 0;

        if (seedId == null) continue;

        final type = transactionTypeById[transactionTypeId] ?? '';
        final signedQuantity = type == 'release' ? -quantity : quantity;

        netBySeed[seedId] = (netBySeed[seedId] ?? 0) + signedQuantity;

        if (nurseryId != null) {
          final nurseryMap = netBySeedAndNursery.putIfAbsent(seedId, () => {});
          nurseryMap[nurseryId] = (nurseryMap[nurseryId] ?? 0) + signedQuantity;
        }
      }

      final loadedItems = netBySeed.entries.map((entry) {
        final seedId = entry.key;
        final nurseryMap = netBySeedAndNursery[seedId] ?? {};
        final breakdown = nurseryMap.entries
            .map((nurseryEntry) => _NurseryQuantity(
                  nurseryId: nurseryEntry.key,
                  nursery: nurseryNameById[nurseryEntry.key] ?? 'Unspecified',
                  quantity: nurseryEntry.value,
                ))
            .toList()
          ..sort((a, b) => a.nursery.toLowerCase().compareTo(b.nursery.toLowerCase()));

        return _AvailableSeedlingItem(
          seedId: seedId,
          species: seedNameById[seedId] ?? 'Unspecified',
          totalQuantity: entry.value,
          nurseryBreakdown: breakdown,
        );
      }).toList()
        ..sort((a, b) => a.species.toLowerCase().compareTo(b.species.toLowerCase()));

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

  Future<int?> _resolveCurrentUserSeqId() async {
    final sessionSeqId = AuthSession.currentUser?.seqId;
    if (sessionSeqId != null) {
      return sessionSeqId;
    }

    final parsedFromSessionId = int.tryParse(AuthSession.currentUser?.id ?? '');
    if (parsedFromSessionId != null) {
      return parsedFromSessionId;
    }

    final authUuid = Supabase.instance.client.auth.currentUser?.id;
    if (authUuid == null || authUuid.isEmpty) {
      return null;
    }

    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('seq_id')
          .eq('id', authUuid)
          .maybeSingle();
      return (row?['seq_id'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  Future<void> _openDataEntryDialog() async {
    try {
      if (!mounted) return;

      final supabase = Supabase.instance.client;

      final response = await supabase
          .from('seed_donation')
          .select('id, donor_name, donated_date, total_count, status')
          .eq('status', 'PROPAGATED')
          .order('donated_date', ascending: false);

      final donations = (response as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((row) {
            final donatedDateRaw = (row['donated_date'] ?? '').toString();
            return _PropagatedDonation(
              id: (row['id'] as num).toInt(),
              donorName: (row['donor_name'] ?? '').toString(),
              donatedDate: DateTime.tryParse(donatedDateRaw) ?? DateTime.now(),
              totalCount: (row['total_count'] as num?)?.toInt() ?? 0,
            );
          })
          .toList();

      final donationIds = donations.map((d) => d.id).toList();
      final Map<int, List<_SeedDetailRow>> seedDetailsByDonationId = {};
      if (donationIds.isNotEmpty) {
        final detailRows = await supabase
            .from('seed_donation_data')
            .select('seed_donation_id, seed_id, seed_count, species_type')
            .inFilter('seed_donation_id', donationIds);

        final parsedDetails =
            (detailRows as List<dynamic>).cast<Map<String, dynamic>>();

        final detailSeedIds = parsedDetails
            .map((row) => (row['seed_id'] as num?)?.toInt())
            .whereType<int>()
            .toSet()
            .toList();

        final Map<int, String> seedNameById = {};
        if (detailSeedIds.isNotEmpty) {
          final seedRows = await supabase
              .from('seedling_list')
              .select('seq_id, seedling_name')
              .inFilter('seq_id', detailSeedIds);

          for (final row
              in (seedRows as List<dynamic>).cast<Map<String, dynamic>>()) {
            final id = (row['seq_id'] as num?)?.toInt();
            final name = (row['seedling_name'] ?? '').toString();
            if (id != null) {
              seedNameById[id] = name;
            }
          }
        }

        for (final row in parsedDetails) {
          final donationId = (row['seed_donation_id'] as num?)?.toInt();
          if (donationId == null) continue;
          final seedId = (row['seed_id'] as num?)?.toInt() ?? 0;

          seedDetailsByDonationId.putIfAbsent(donationId, () => []).add(
                _SeedDetailRow(
                  seedId: seedId,
                  speciesName: seedNameById[seedId] ?? 'Seed $seedId',
                  speciesType: (row['species_type'] ?? '').toString(),
                  propagatedCount: (row['seed_count'] as num?)?.toInt() ?? 0,
                ),
              );
        }
      }

      final nurseryRows =
          await supabase.from('seedling_nursery').select('seq_id, name');
      final nurseryOptions = (nurseryRows as List<dynamic>)
          .map((row) => LookupOption(
                id: (row['seq_id'] as num).toInt(),
                name: (row['name'] as String).trim(),
              ))
          .toList();

      final transactionTypeRows = await supabase
          .from('seedling_transaction_type')
          .select('id, transaction_type');
      int? receiveTypeId;
      for (final row in (transactionTypeRows as List<dynamic>)
          .cast<Map<String, dynamic>>()) {
        final typeName =
            (row['transaction_type'] ?? '').toString().trim().toLowerCase();
        if (typeName == 'receive') {
          receiveTypeId = (row['id'] as num).toInt();
          break;
        }
      }

      final rows = donations
          .map((d) => _PropagatedRowState(
                donation: d,
                seedDetails: seedDetailsByDonationId[d.id] ?? [],
              ))
          .toList();

      if (!mounted) return;
      await _showPropagatedDonationsDialog(
        rows: rows,
        nurseryOptions: nurseryOptions,
        receiveTypeId: receiveTypeId,
      );
      _loadPropagatedCount();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load propagated seeds: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  bool _isPlantableValid(_SeedDetailRow detail) {
    final text = detail.plantableController.text.trim();
    if (text.isEmpty) return true;
    final value = int.tryParse(text);
    if (value == null) return false;
    return value >= 0 && value <= detail.propagatedCount;
  }

  int _plantableValue(_SeedDetailRow detail) {
    return int.tryParse(detail.plantableController.text.trim()) ?? 0;
  }

  Future<void> _convertDonationToInventory(
    _PropagatedRowState row,
    int? receiveTypeId,
  ) async {
    final nursery = row.nursery;
    if (nursery == null) {
      throw Exception('Please choose a nursery.');
    }
    if (receiveTypeId == null) {
      throw Exception('Receive transaction type mapping is missing.');
    }

    final supabase = Supabase.instance.client;

    final userSeqId = await _resolveCurrentUserSeqId();
    if (userSeqId == null) {
      throw Exception('Unable to save data. Logged-in user id is missing.');
    }

    final rows = row.seedDetails
        .map((detail) {
          final plantableCount = _plantableValue(detail);
          if (plantableCount <= 0) return null;

          return {
            'seed_id': detail.seedId,
            'user_id': userSeqId,
            'transaction_type_id': receiveTypeId,
            'seedling_count': plantableCount,
            'details':
                'Converted from Seed for a Forest donation #${row.donation.id}',
            'created_at': DateTime.now().toIso8601String(),
            'nursery_id': nursery.id,
            'release_by': null,
            'release_to': null,
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    if (rows.isEmpty) {
      throw Exception('Enter a Plantable quantity for at least one seedling.');
    }

    final totalSurvive = row.seedDetails
        .fold<int>(0, (sum, detail) => sum + _plantableValue(detail));

    await supabase.from('seedling_transaction').insert(rows);

    await supabase.from('seed_donation').update({
      'status': 'PLANTABLE',
      'is_converted': true,
      'survive': totalSurvive,
    }).eq('id', row.donation.id);
  }

  Future<void> _showPropagatedDonationsDialog({
    required List<_PropagatedRowState> rows,
    required List<LookupOption> nurseryOptions,
    required int? receiveTypeId,
  }) async {
    final pageContext = context;
    final allRows = List<_PropagatedRowState>.from(rows);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white,
            ),
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
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
                          Icons.eco_rounded,
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
                              'Propagated Seeds',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Ready to plant, from Seed for a Forest',
                              style: TextStyle(fontSize: 12, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: rows.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No propagated seed donations yet.',
                            style: TextStyle(color: Color(0xFF636780)),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(20),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final row = rows[index];
                            final donation = row.donation;
                            final needsNursery = row.status == 'PLANTABLE';
                            final plantableValid = row.seedDetails
                                .every((detail) => _isPlantableValid(detail));
                            final hasPlantableQuantity = row.seedDetails.any(
                                (detail) => _plantableValue(detail) > 0);
                            final canConvert = needsNursery &&
                                row.nursery != null &&
                                !row.isConverting &&
                                plantableValid &&
                                hasPlantableQuantity;

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              donation.donorName.trim().isEmpty
                                                  ? 'Unspecified'
                                                  : donation.donorName,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF25273B),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _formatDate(donation.donatedDate),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        '${donation.totalCount}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF1B8B5E),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (row.seedDetails.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: Colors.grey.shade200),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          for (var i = 0;
                                              i < row.seedDetails.length;
                                              i++) ...[
                                            if (i > 0)
                                              const Divider(height: 1),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 6),
                                              child: Row(
                                                children: [
                                                  Icon(Icons.eco,
                                                      size: 15,
                                                      color: Colors
                                                          .green.shade600),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          row.seedDetails[i]
                                                              .speciesName,
                                                          style: const TextStyle(
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: Color(
                                                                0xFF25273B),
                                                          ),
                                                          maxLines: 1,
                                                          overflow:
                                                              TextOverflow
                                                                  .ellipsis,
                                                        ),
                                                        Text(
                                                          'Propagated: ${row.seedDetails[i].propagatedCount}',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color: Colors
                                                                .grey.shade600,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  if (needsNursery) ...[
                                                    const SizedBox(width: 8),
                                                    SizedBox(
                                                      width: 80,
                                                      child: TextField(
                                                        controller: row
                                                            .seedDetails[i]
                                                            .plantableController,
                                                        enabled:
                                                            !row.isConverting,
                                                        keyboardType:
                                                            TextInputType
                                                                .number,
                                                        textAlign:
                                                            TextAlign.center,
                                                        onChanged: (_) =>
                                                            setDialogState(
                                                                () {}),
                                                        decoration:
                                                            InputDecoration(
                                                          isDense: true,
                                                          labelText:
                                                              'Plantable',
                                                          errorText:
                                                              _isPlantableValid(
                                                                      row.seedDetails[
                                                                          i])
                                                                  ? null
                                                                  : '≤ ${row.seedDetails[i].propagatedCount}',
                                                          contentPadding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 8),
                                                          border:
                                                              OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        8),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          initialValue: row.status,
                                          isDense: true,
                                          items: const [
                                            DropdownMenuItem(
                                              value: 'PROPAGATED',
                                              child: Text('PROPAGATED'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'PLANTABLE',
                                              child: Text('PLANTABLE'),
                                            ),
                                          ],
                                          onChanged: row.isConverting
                                              ? null
                                              : (value) {
                                                  if (value == null) return;
                                                  setDialogState(
                                                      () => row.status = value);
                                                },
                                          decoration: InputDecoration(
                                            isDense: true,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8),
                                            filled: true,
                                            fillColor: Colors.white,
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: BorderSide(
                                                  color: Colors.grey.shade300),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (needsNursery) ...[
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: DropdownButtonFormField<
                                              LookupOption>(
                                            initialValue: row.nursery,
                                            isDense: true,
                                            items: nurseryOptions
                                                .map((option) => DropdownMenuItem(
                                                      value: option,
                                                      child: Text(option.name),
                                                    ))
                                                .toList(),
                                            onChanged: row.isConverting
                                                ? null
                                                : (value) => setDialogState(
                                                    () => row.nursery = value),
                                            decoration: InputDecoration(
                                              isDense: true,
                                              hintText: 'Nursery',
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 8),
                                              filled: true,
                                              fillColor: Colors.white,
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: BorderSide(
                                                    color:
                                                        Colors.grey.shade300),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          height: 40,
                                          child: row.isConverting
                                              ? const Padding(
                                                  padding: EdgeInsets.symmetric(
                                                      horizontal: 8),
                                                  child: SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Color(0xFF1B8B5E),
                                                    ),
                                                  ),
                                                )
                                              : ElevatedButton.icon(
                                                  onPressed: canConvert
                                                      ? () async {
                                                          setDialogState(() =>
                                                              row.isConverting =
                                                                  true);
                                                          try {
                                                            await _convertDonationToInventory(
                                                              row,
                                                              receiveTypeId,
                                                            );
                                                            setDialogState(() =>
                                                                rows.remove(
                                                                    row));
                                                            _loadAvailableSeedlings();
                                                            _loadPropagatedCount();
                                                            if (!pageContext.mounted) return;
                                                            ScaffoldMessenger.of(
                                                                    pageContext)
                                                                .showSnackBar(
                                                              const SnackBar(
                                                                content: Text(
                                                                    'Marked Plantable and added to Available Seedling.'),
                                                                backgroundColor:
                                                                    Color(
                                                                        0xFF1B8B5E),
                                                              ),
                                                            );
                                                            if (rows.isEmpty) {
                                                              Navigator.of(
                                                                      dialogContext)
                                                                  .pop();
                                                            }
                                                          } catch (e) {
                                                            setDialogState(() =>
                                                                row.isConverting =
                                                                    false);
                                                            if (!pageContext.mounted) return;
                                                            ScaffoldMessenger.of(
                                                                    pageContext)
                                                                .showSnackBar(
                                                              SnackBar(
                                                                content: Text(
                                                                    'Failed to convert: $e'),
                                                                backgroundColor:
                                                                    Colors
                                                                        .redAccent,
                                                              ),
                                                            );
                                                          }
                                                        }
                                                      : null,
                                                  icon: const Icon(
                                                      Icons.save_rounded,
                                                      size: 16),
                                                  label: const Text('Save'),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        const Color(0xFF1B8B5E),
                                                    foregroundColor: Colors.white,
                                                    disabledBackgroundColor:
                                                        Colors.grey.shade300,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                            horizontal: 12),
                                                    textStyle: const TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600),
                                                  ),
                                                ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF4E526A),
                        ),
                      ),
                    ),
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

    for (final row in allRows) {
      for (final detail in row.seedDetails) {
        detail.plantableController.dispose();
      }
    }
  }
}
