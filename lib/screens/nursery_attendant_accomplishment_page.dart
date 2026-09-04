import 'package:flutter/material.dart';

import '../service/api_service.dart';
import '../service/nursery_attendant_service.dart';
import '../widget/side_panel.dart';

/// Per-attendant propagation totals, read from the
/// nursery_attendant_accomplishment view.
///
/// The view does the aggregation and keeps attendants with nothing recorded
/// at zero rather than dropping them — an accomplishment list needs to show
/// who has done nothing as much as who has done the most.
class NurseryAttendantAccomplishmentPage extends StatefulWidget {
  const NurseryAttendantAccomplishmentPage({super.key});

  @override
  State<NurseryAttendantAccomplishmentPage> createState() =>
      _NurseryAttendantAccomplishmentPageState();
}

class _NurseryAttendantAccomplishmentPageState
    extends State<NurseryAttendantAccomplishmentPage> {
  bool _isLoading = true;
  String? _errorMessage;

  List<Map<String, dynamic>> _rows = [];
  Map<int, String> _nurseryNames = {};

  /// null = every nursery the user can see.
  int? _nurseryFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final nurseryRows = await ApiService.getSeedlingNurseryRows();
      final divisionTypeId = NurseryAttendantService.scopedDivisionTypeId();

      final visible = <int, String>{};
      for (final row in nurseryRows) {
        final seqId = (row['seq_id'] as num?)?.toInt();
        final divType = (row['div_type'] as num?)?.toInt();
        if (seqId == null) continue;
        if (divisionTypeId != null && divType != divisionTypeId) continue;
        visible[seqId] = (row['name'] ?? '').toString();
      }

      final rows = await NurseryAttendantService.getAccomplishments(
        nurseryIds: visible.keys.toList(),
      );

      if (!mounted) return;
      setState(() {
        _nurseryNames = visible;
        _rows = rows;
        if (_nurseryFilter != null && !visible.containsKey(_nurseryFilter)) {
          _nurseryFilter = null;
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load accomplishments: $e';
      });
    }
  }

  int _toInt(dynamic value) => (value as num?)?.toInt() ?? 0;

  String _formatDate(dynamic value) {
    if (value == null) return 'None yet';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    return '${parsed.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _nurseryFilter == null
        ? _rows
        : _rows
            .where((row) => _toInt(row['nursery_id']) == _nurseryFilter)
            .toList();

    final totalSeeds = filtered.fold<int>(
      0,
      (sum, row) => sum + _toInt(row['total_seeds']),
    );
    final totalRecords = filtered.fold<int>(
      0,
      (sum, row) => sum + _toInt(row['propagation_count']),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      drawer: const SidePanel(),
      appBar: AppBar(
        title: const Text('Attendant Accomplishments'),
        backgroundColor: const Color.fromARGB(255, 31, 103, 78),
        foregroundColor: Colors.white,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildTotal(
                            label: 'Seeds propagated',
                            value: '$totalSeeds',
                          ),
                        ),
                        Expanded(
                          child: _buildTotal(
                            label: 'Records',
                            value: '$totalRecords',
                          ),
                        ),
                        Expanded(
                          child: _buildTotal(
                            label: 'Attendants',
                            value: '${filtered.length}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int?>(
                      initialValue: _nurseryFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Nursery',
                        prefixIcon: Icon(Icons.filter_alt_outlined),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('All nurseries'),
                        ),
                        ..._nurseryNames.entries.map(
                          (entry) => DropdownMenuItem<int?>(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _nurseryFilter = value),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 30),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorMessage != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (filtered.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No attendants yet. Add them under Settings → Nursery '
                    'Attendants, then record propagation from Seedling '
                    'Inventory.',
                  ),
                ),
              )
            else
              ...filtered.asMap().entries.map(
                    (entry) => _buildRow(entry.key + 1, entry.value, totalSeeds),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotal({required String label, required String value}) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Color.fromARGB(255, 31, 103, 78),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
      ],
    );
  }

  Widget _buildRow(int rank, Map<String, dynamic> row, int totalSeeds) {
    final seeds = _toInt(row['total_seeds']);
    final records = _toInt(row['propagation_count']);
    final status = (row['status'] ?? '').toString();
    final isActive = status == 'Active';

    // Share of the filtered total, so the bar stays meaningful when the
    // nursery filter changes. Guarded against a zero total.
    final share = totalSeeds == 0 ? 0.0 : seeds / totalSeeds;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (row['attendant_name'] ?? '').toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        (row['nursery_name'] ?? 'Unknown nursery').toString(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$seeds',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color.fromARGB(255, 31, 103, 78),
                      ),
                    ),
                    Text(
                      'seeds',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF1B8B5E),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _buildChip('$records record${records == 1 ? '' : 's'}'),
                _buildChip('Last: ${_formatDate(row['last_propagated_date'])}'),
                if (!isActive) _buildChip(status, warning: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String text, {bool warning = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFDECEA) : const Color(0xFFEDF2F0),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: warning ? const Color(0xFFB3261E) : const Color(0xFF3A4A44),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
