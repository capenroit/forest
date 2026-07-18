import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../service/activity_model.dart';
import '../service/api_service.dart';
import '../service/auth_session.dart';

class MonitoringTreeSurvivalForm extends StatefulWidget {
  final List<String> municipalities;
  final List<String> barangays;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const MonitoringTreeSurvivalForm({
    super.key,
    required this.municipalities,
    required this.barangays,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<MonitoringTreeSurvivalForm> createState() =>
      _MonitoringTreeSurvivalFormState();
}

class _MonitoringTreeSurvivalFormState extends State<MonitoringTreeSurvivalForm> {
  static const int _treeGrowingProjectTypeId = 1;
  static const List<int> _quarterOptions = [1, 2, 3, 4];

  late TextEditingController _detailsController;
  late TextEditingController _dateController;
  int? _selectedQuarter;

  List<TreePlanting> _treeGrowingOptions = [];
  TreePlanting? _selectedTreeGrowing;
  List<_SurvivalSeedRow> _survivalRows = [];

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isLoadingSeedRows = false;

  @override
  void initState() {
    super.initState();
    _detailsController = TextEditingController();
    _dateController = TextEditingController(
      text: DateTime.now().toIso8601String().split('T').first,
    );
    _loadTreeGrowingOptions();
  }

  @override
  void dispose() {
    _detailsController.dispose();
    _dateController.dispose();
    for (final row in _survivalRows) {
      row.surviveController.dispose();
    }
    super.dispose();
  }

  Future<void> _loadTreeGrowingOptions() async {
    setState(() => _isLoading = true);
    try {
      final options = await ApiService.getTreePlantingsByProjectTypeId(
        _treeGrowingProjectTypeId,
        limit: 500,
      );
      if (!mounted) return;
      setState(() {
        _treeGrowingOptions = options;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );

    if (picked != null) {
      setState(() {
        _dateController.text = picked.toIso8601String().split('T').first;
      });
    }
  }

  Future<void> _loadSeedRowsForSelectedActivity(TreePlanting activity) async {
    final seqId = activity.seqId;

    if (seqId == null || seqId <= 0) {
      setState(() {
        for (final row in _survivalRows) {
          row.surviveController.dispose();
        }
        _survivalRows = [];
      });
      return;
    }

    setState(() => _isLoadingSeedRows = true);

    try {
      final grouped = await ApiService.getTreeGrowingDataByTreeGrowingIds([
        seqId,
      ]);
      final rows = grouped[seqId] ?? const [];

      final nextRows = rows.map((row) {
        final seedName = (row['seed_name'] ?? '').toString().trim();
        final planted = (row['seedling_count'] as num?)?.toInt() ?? 0;
        return _SurvivalSeedRow(
          species: seedName.isEmpty ? 'N/A' : seedName,
          plantedCount: planted,
          surviveController: TextEditingController(),
        );
      }).toList();

      if (!mounted) {
        for (final row in nextRows) {
          row.surviveController.dispose();
        }
        return;
      }

      setState(() {
        for (final row in _survivalRows) {
          row.surviveController.dispose();
        }
        _survivalRows = nextRows;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingSeedRows = false);
      }
    }
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;

    final selectedTreeGrowing = _selectedTreeGrowing;
    final activitySeqId = selectedTreeGrowing?.seqId;
    final activityName = selectedTreeGrowing?.activityName?.trim() ?? '';
    final details = _detailsController.text.trim();
    final municipality = selectedTreeGrowing?.municipality.trim() ?? '';
    final barangay = selectedTreeGrowing?.barangay.trim() ?? '';
    final quarter = _selectedQuarter;

    if (_survivalRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data is incomplete.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    bool hasInvalidSurviveValue = false;
    bool hasSurviveGreaterThanPlanted = false;
    int totalSurvive = 0;

    for (final row in _survivalRows) {
      final raw = row.surviveController.text.trim();
      final survive = int.tryParse(raw);
      if (raw.isEmpty || survive == null || survive < 0) {
        hasInvalidSurviveValue = true;
        break;
      }
      if (survive > row.plantedCount) {
        hasSurviveGreaterThanPlanted = true;
        break;
      }
      totalSurvive += survive;
    }

    if (hasSurviveGreaterThanPlanted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Survive cannot be greater than Planted.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (selectedTreeGrowing == null ||
      activitySeqId == null ||
      activitySeqId <= 0 ||
      quarter == null ||
        activityName.isEmpty ||
        municipality.isEmpty ||
        barangay.isEmpty ||
        hasInvalidSurviveValue) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data is incomplete.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final authUserId = AuthSession.currentUser?.id ??
        Supabase.instance.client.auth.currentUser?.id;

    if (authUserId == null || authUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save data.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final parsedDate =
        DateTime.tryParse(_dateController.text.trim()) ?? DateTime.now();

    setState(() => _isSaving = true);

    try {
      await ApiService.saveTreeSurvivalMonitoring(
        userId: authUserId,
        activityId: activitySeqId,
        numberTreeSurvived: totalSurvive,
        quarter: quarter,
        details: details.isEmpty ? null : details,
        date: parsedDate,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data was saved.'),
          backgroundColor: Colors.green,
        ),
      );

      widget.onSave();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save data.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.grey.shade600),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF1B8B5E), width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade700,
      ),
    );
  }

  String _buildTreeGrowingLabel(TreePlanting planting) {
    final activityName = (planting.activityName ?? '').trim();
    final municipality = planting.municipality.trim();
    final barangay = planting.barangay.trim();
    final date = _formatDate(planting.date);

    final safeActivity = activityName.isEmpty ? 'N/A' : activityName;
    final safeMunicipality = municipality.isEmpty ? 'N/A' : municipality;
    final safeBarangay = barangay.isEmpty ? 'N/A' : barangay;

    return '$safeActivity | $safeMunicipality | $safeBarangay | $date';
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  int _totalPlanted() {
    return _survivalRows.fold<int>(
      0,
      (sum, row) => sum + row.plantedCount,
    );
  }

  int _totalSurvive() {
    return _survivalRows.fold<int>(0, (sum, row) {
      final survive = int.tryParse(row.surviveController.text.trim()) ?? 0;
      return sum + survive;
    });
  }

  Widget _buildSurvivalTable() {
    if (_isLoadingSeedRows) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Loading species...'),
          ],
        ),
      );
    }

    if (_selectedTreeGrowing == null) {
      return Text(
        'Select an activity to load species.',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
      );
    }

    if (_survivalRows.isEmpty) {
      return Text(
        'No species found for this activity.',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F7F4)),
        columns: const [
          DataColumn(label: Text('Species')),
          DataColumn(label: Text('Planted')),
          DataColumn(label: Text('Survive')),
        ],
        rows: _survivalRows.map((row) {
          return DataRow(
            cells: [
              DataCell(SizedBox(width: 190, child: Text(row.species))),
              DataCell(Text('${row.plantedCount}')),
              DataCell(
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: row.surviveController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (value) {
                      setState(() {});
                      if (value.isEmpty) return;
                      final parsed = int.tryParse(value);
                      if (parsed == null) return;
                      if (parsed > row.plantedCount) {
                        final capped = '${row.plantedCount}';
                        row.surviveController.value = TextEditingValue(
                          text: capped,
                          selection:
                              TextSelection.collapsed(offset: capped.length),
                        );
                      }
                    },
                    decoration: const InputDecoration(
                      hintText: '0',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
      ),
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
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
              children: const [
                Icon(Icons.monitor_heart_rounded,
                    color: Colors.white, size: 24),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monitoring of Tree Survival',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Add monitoring record',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fieldLabel('Activity Name *'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<TreePlanting>(
                    value: _selectedTreeGrowing,
                    onChanged: _isLoading || _treeGrowingOptions.isEmpty
                        ? null
                        : (TreePlanting? newValue) async {
                            setState(() => _selectedTreeGrowing = newValue);
                            if (newValue != null) {
                              await _loadSeedRowsForSelectedActivity(newValue);
                            } else {
                              setState(() {
                                for (final row in _survivalRows) {
                                  row.surviveController.dispose();
                                }
                                _survivalRows = [];
                              });
                            }
                          },
                    decoration: _inputDecoration(
                      hint: 'Select tree growing activity',
                      icon: Icons.edit_rounded,
                    ),
                    isExpanded: true,
                    dropdownColor: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    items: _isLoading
                        ? [
                            const DropdownMenuItem<TreePlanting>(
                              value: null,
                              child: Text('Loading...'),
                            ),
                          ]
                        : _treeGrowingOptions.isEmpty
                            ? [
                                const DropdownMenuItem<TreePlanting>(
                                  value: null,
                                  child: Text('No tree growing activities found'),
                                ),
                              ]
                            : _treeGrowingOptions.map((option) {
                                return DropdownMenuItem<TreePlanting>(
                                  value: option,
                                  child: Text(
                                    _buildTreeGrowingLabel(option),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                  ),
                  const SizedBox(height: 14),
                  _fieldLabel('Survival Data'),
                  const SizedBox(height: 6),
                  _buildSurvivalTable(),
                  if (_survivalRows.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: const Color(0xFFF1F7F4),
                        border: Border.all(color: const Color(0xFFD5E9DD)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Planted: ${_totalPlanted()}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          Text(
                            'Total Survive: ${_totalSurvive()}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1B8B5E),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _fieldLabel('Quarter *'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    value: _selectedQuarter,
                    onChanged: _isLoading
                        ? null
                        : (int? value) {
                            setState(() => _selectedQuarter = value);
                          },
                    decoration: _inputDecoration(
                      hint: 'Select quarter',
                      icon: Icons.filter_4_rounded,
                    ),
                    dropdownColor: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    items: _quarterOptions
                        .map(
                          (quarter) => DropdownMenuItem<int>(
                            value: quarter,
                            child: Text('Quarter $quarter'),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 14),
                  _fieldLabel('Date *'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _dateController,
                    enabled: !_isLoading,
                    readOnly: true,
                    onTap: _isLoading ? null : () => _selectDate(context),
                    decoration: _inputDecoration(
                      hint: 'Select date',
                      icon: Icons.calendar_today_rounded,
                      suffixIcon: Icon(
                        Icons.arrow_drop_down_rounded,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _fieldLabel('Notes'),
                  const SizedBox(height: 6),
                  TextField(
                    enabled: !_isLoading,
                    controller: _detailsController,
                    maxLines: 3,
                    decoration: _inputDecoration(
                      hint: 'Optional details',
                      icon: Icons.notes_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: (_isLoading || _isSaving) ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B8B5E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.save_rounded, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Save Record',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SurvivalSeedRow {
  final String species;
  final int plantedCount;
  final TextEditingController surviveController;

  _SurvivalSeedRow({
    required this.species,
    required this.plantedCount,
    required this.surviveController,
  });
}

