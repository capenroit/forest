import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../service/activity_model.dart';
import '../service/api_service.dart';
import '../service/auth_session.dart';
import '../service/offline_sync_service.dart';

class MonitoringMangroveSurvivalForm extends StatefulWidget {
  final List<String> municipalities;
  final List<String> barangays;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  /// The raw tree_survival_monitoring rows (one per species) belonging to
  /// the record being edited. Null/empty means "create a new record".
  final List<Map<String, dynamic>>? initialRows;

  /// When set (together with [pendingPayload]), this form edits a still-
  /// queued offline draft instead of a server record or a brand-new entry.
  final String? pendingLocalId;

  /// The offline queue payload for the draft being edited (see
  /// [pendingLocalId]). Shape matches what `_handleSave` queues below.
  final Map<String, dynamic>? pendingPayload;

  const MonitoringMangroveSurvivalForm({
    super.key,
    required this.municipalities,
    required this.barangays,
    required this.onSave,
    required this.onCancel,
    this.initialRows,
    this.pendingLocalId,
    this.pendingPayload,
  });

  @override
  State<MonitoringMangroveSurvivalForm> createState() =>
      _MonitoringMangroveSurvivalFormState();
}

class _MonitoringMangroveSurvivalFormState
    extends State<MonitoringMangroveSurvivalForm> {
  static const int _mangrovePlantingProjectTypeId = 6;
  static const List<int> _quarterOptions = [1, 2, 3, 4];

  late TextEditingController _detailsController;
  late TextEditingController _dateController;
  int? _selectedQuarter;
  Set<int> _usedQuarters = {};

  List<TreePlanting> _mangrovePlantingOptions = [];
  TreePlanting? _selectedMangrovePlanting;
  List<_SurvivalSeedRow> _survivalRows = [];

  // The activity actually used for saving/species lookup. In edit mode this
  // is captured from the record being edited (activity_name + seq_id) up
  // front, independent of whether a matching TreePlanting is ever found in
  // _mangrovePlantingOptions — so the Activity Name field shows correctly
  // right away instead of waiting on that list to load and match.
  int? _activitySeqId;
  String _activityName = '';
  String _municipality = '';
  String _barangay = '';

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isLoadingSeedRows = false;
  bool _speciesLoadFailed = false;

  bool get _isEditing =>
      widget.initialRows != null && widget.initialRows!.isNotEmpty;

  /// True when this form is editing an offline draft that has not yet
  /// synced to the server (see
  /// [MonitoringMangroveSurvivalForm.pendingLocalId]).
  bool get _isEditingPending => widget.pendingLocalId != null;

  @override
  void initState() {
    super.initState();

    if (_isEditingPending) {
      final payload = widget.pendingPayload ?? const <String, dynamic>{};
      final parsedDate =
          DateTime.tryParse(payload['date']?.toString() ?? '');

      _detailsController =
          TextEditingController(text: (payload['details'] ?? '').toString());
      _dateController = TextEditingController(
        text: (parsedDate ?? DateTime.now()).toIso8601String().split('T').first,
      );
      _selectedQuarter = (payload['quarter'] as num?)?.toInt();
      _activitySeqId = (payload['activityId'] as num?)?.toInt();

      final speciesSurvival =
          (payload['speciesSurvival'] as List?) ?? const [];
      _survivalRows = speciesSurvival
          .map((raw) {
            final row = Map<String, dynamic>.from(raw as Map);
            final seedId = (row['seedId'] as num?)?.toInt();
            if (seedId == null) return null;
            return _SurvivalSeedRow(
              seedId: seedId,
              species: (row['seedName'] ?? '').toString(),
              plantedCount: (row['plantedCount'] as num?)?.toInt() ?? 0,
              surviveController: TextEditingController(
                text: (row['numberTreeSurvived'] ?? '').toString(),
              ),
            );
          })
          .whereType<_SurvivalSeedRow>()
          .toList();
    } else {
      final editingRows = widget.initialRows;
      _detailsController = TextEditingController(
        text: _isEditing ? (editingRows!.first['details'] ?? '').toString() : '',
      );
      _dateController = TextEditingController(
        text: _isEditing
            ? (editingRows!.first['date']?.toString() ??
                DateTime.now().toIso8601String().split('T').first)
            : DateTime.now().toIso8601String().split('T').first,
      );
      _selectedQuarter =
          _isEditing ? (editingRows!.first['quarter'] as num?)?.toInt() : null;

      if (_isEditing) {
        _activitySeqId = (editingRows!.first['activity_id'] as num?)?.toInt();
        _activityName = (editingRows.first['activity_name'] ?? '').toString();
        _municipality = (editingRows.first['municipality'] ?? '').toString();
        _barangay = (editingRows.first['barangay'] ?? '').toString();
        if (_activitySeqId != null) {
          _loadSeedRowsForSelectedActivity(_activitySeqId!);
        }
      }
    }

    _loadMangrovePlantingOptions();
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

  Future<void> _loadMangrovePlantingOptions() async {
    setState(() => _isLoading = true);
    try {
      List<TreePlanting> options;
      try {
        options = await ApiService.getTreePlantingsByProjectTypeId(
          _mangrovePlantingProjectTypeId,
          limit: 500,
        );
        // Write-through cache so the picker still has activities to offer
        // next time this device is offline.
        await OfflineSyncService.cacheActivities(
            _mangrovePlantingProjectTypeId, options);
      } catch (_) {
        // Offline or the request otherwise failed — fall back to the last
        // successfully synced activity list.
        options = await OfflineSyncService.getCachedActivities(
            _mangrovePlantingProjectTypeId);
      }

      if (!mounted) return;
      setState(() {
        _mangrovePlantingOptions = options;
      });

      if ((_isEditing || _isEditingPending) && _activitySeqId != null) {
        // Only used to enrich the (locked) display — species/date/quarter
        // were already loaded from the edited record in initState.
        TreePlanting? matched;
        for (final option in options) {
          if (option.seqId == _activitySeqId) {
            matched = option;
            break;
          }
        }
        if (matched != null) {
          setState(() {
            _selectedMangrovePlanting = matched;
            if (_isEditingPending) {
              _activityName = matched!.activityName?.trim() ?? '';
              _municipality = matched.municipality.trim();
              _barangay = matched.barangay.trim();
            }
          });
        } else if (_isEditingPending && _activityName.isEmpty) {
          setState(() => _activityName = 'Activity #$_activitySeqId');
        }
      }
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

  Future<void> _loadSeedRowsForSelectedActivity(int? seqId) async {
    if (seqId == null || seqId <= 0) {
      setState(() {
        for (final row in _survivalRows) {
          row.surviveController.dispose();
        }
        _survivalRows = [];
        _usedQuarters = {};
        _speciesLoadFailed = false;
      });
      return;
    }

    setState(() {
      _isLoadingSeedRows = true;
      _speciesLoadFailed = false;
    });

    // Existing per-species survived counts, keyed by seed_id, when editing.
    final existingSurvivedBySeedId = <int, int>{};
    if (_isEditing) {
      for (final row in widget.initialRows!) {
        final seedId = (row['seed_id'] as num?)?.toInt();
        final survived = (row['number_tree_survived'] as num?)?.toInt() ??
            (row['number_tree_sur'] as num?)?.toInt();
        if (seedId != null && survived != null) {
          existingSurvivedBySeedId[seedId] = survived;
        }
      }
    }

    try {
      final grouped = await ApiService.getTreeGrowingDataByTreeGrowingIds([
        seqId,
      ]);
      final rows = grouped[seqId] ?? const [];

      final nextRows = rows
          .map((row) {
            final seedId = (row['id'] as num?)?.toInt();
            if (seedId == null) return null;
            final seedName = (row['seed_name'] ?? '').toString().trim();
            final planted = (row['seedling_count'] as num?)?.toInt() ?? 0;
            final controller = TextEditingController(
              text: existingSurvivedBySeedId[seedId]?.toString() ?? '',
            );
            return _SurvivalSeedRow(
              seedId: seedId,
              species: seedName.isEmpty ? 'N/A' : seedName,
              plantedCount: planted,
              surviveController: controller,
            );
          })
          .whereType<_SurvivalSeedRow>()
          .toList();

      Set<int> usedQuarters = {};
      try {
        usedQuarters = await ApiService.getUsedQuartersForActivity(seqId);
      } catch (_) {
        // Non-fatal; leave quarters unlocked if this lookup fails.
      }
      if (_isEditing) {
        final ownQuarter =
            (widget.initialRows!.first['quarter'] as num?)?.toInt();
        if (ownQuarter != null) usedQuarters.remove(ownQuarter);
      }

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
        _usedQuarters = usedQuarters;
      });
    } catch (_) {
      // No live connection (or the request otherwise failed). Species rows
      // for an offline-selected activity are only available if this device
      // has loaded them before — since they weren't, surface a clear inline
      // message instead of crashing.
      if (!mounted) return;
      setState(() {
        for (final row in _survivalRows) {
          row.surviveController.dispose();
        }
        _survivalRows = [];
        _usedQuarters = {};
        _speciesLoadFailed = true;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingSeedRows = false);
      }
    }
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;

    final activitySeqId = _activitySeqId;
    final activityName = _activityName.trim();
    final details = _detailsController.text.trim();
    final municipality = _municipality.trim();
    final barangay = _barangay.trim();
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
    final speciesSurvival = <({
      int seedId,
      int numberTreeSurvived,
      String seedName,
      int plantedCount,
    })>[];

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
      speciesSurvival.add((
        seedId: row.seedId,
        numberTreeSurvived: survive,
        seedName: row.species,
        plantedCount: row.plantedCount,
      ));
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

    if (activitySeqId == null ||
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

    final offlinePayload = {
      'userId': authUserId,
      'userSeqId': AuthSession.currentUser?.seqId,
      'activityId': activitySeqId,
      'quarter': quarter,
      'details': details.isEmpty ? null : details,
      'date': parsedDate.toIso8601String(),
      'speciesSurvival': speciesSurvival
          .map((s) => {
                'seedId': s.seedId,
                'numberTreeSurvived': s.numberTreeSurvived,
                'seedName': s.seedName,
                'plantedCount': s.plantedCount,
              })
          .toList(),
    };

    try {
      if (_isEditingPending) {
        // Still-queued offline draft — just rewrite the local payload, no
        // connectivity or ApiService calls involved.
        await OfflineSyncService.updatePendingItem(
            widget.pendingLocalId!, offlinePayload);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data was saved.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        widget.onSave();
        return;
      }

      final isOnline = await OfflineSyncService.hasInternetConnection();
      if (!mounted) return;

      if (!isOnline) {
        if (_isEditing) {
          // Editing an already-synced record requires re-fetching/replacing
          // server rows, which needs connectivity.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Editing requires an internet connection.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        await OfflineSyncService.queueGenericRecord(
          type: 'tree_survival_monitoring',
          payload: offlinePayload,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data was saved.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        widget.onSave();
        return;
      }

      // Neither call below has a built-in timeout — without this guard a
      // dropped/slow connection mid-save leaves the (non-dismissible)
      // dialog spinning forever, which looks like the app "freezing".
      await (() async {
        if (_isEditing) {
          final oldIds = widget.initialRows!
              .map((row) =>
                  (row['seq_id'] as num?)?.toInt() ??
                  (row['id'] as num?)?.toInt())
              .whereType<int>()
              .toList();
          await ApiService.deleteTreeSurvivalMonitoringRows(oldIds);
        }

        await ApiService.saveTreeSurvivalMonitoringRows(
          userId: authUserId,
          userSeqId: AuthSession.currentUser?.seqId,
          activityId: activitySeqId,
          speciesSurvival: speciesSurvival,
          quarter: quarter,
          details: details.isEmpty ? null : details,
          date: parsedDate,
        );
      })()
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException(
          'Saving is taking too long. Check your connection and try again.',
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data was saved.'),
          backgroundColor: Colors.green,
        ),
      );

      widget.onSave();

      // Flush any other pending offline records now that we know we're
      // online and this save has already completed.
      OfflineSyncService.syncAll().ignore();
    } catch (e, st) {
      debugPrint('SAVE FAILED: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is TimeoutException
                ? (e.message ?? 'Unable to save data.')
                : 'Unable to save data.',
          ),
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

  String _buildMangrovePlantingLabel(TreePlanting planting) {
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

    if (_activitySeqId == null) {
      return Text(
        'Select an activity to load species.',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
      );
    }

    if (_speciesLoadFailed) {
      return Text(
        'Species list unavailable offline for this activity.',
        style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
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
              children: [
                const Icon(Icons.monitor_heart_rounded,
                    color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Monitoring of Mangrove Survival',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      _isEditing
                          ? 'Edit monitoring record'
                          : _isEditingPending
                              ? 'Edit pending (offline) record'
                              : 'Add monitoring record',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white70),
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
                  if (_isEditing || _isEditingPending)
                    TextFormField(
                      // Rekeyed on the displayed text so that when the
                      // pending-draft activity name resolves asynchronously
                      // (from the cached activity list), Flutter recreates
                      // this field's internal state and picks up the new
                      // initialValue instead of showing a stale placeholder.
                      key: ValueKey(
                        'activity-$_activityName|$_municipality|$_barangay',
                      ),
                      readOnly: true,
                      enabled: false,
                      initialValue: _activityName.isEmpty
                          ? 'N/A'
                          : '$_activityName | ${_municipality.isEmpty ? 'N/A' : _municipality} | ${_barangay.isEmpty ? 'N/A' : _barangay}',
                      style: const TextStyle(color: Color(0xFF25273B)),
                      decoration: _inputDecoration(
                        hint: 'Select mangrove planting activity',
                        icon: Icons.edit_rounded,
                        suffixIcon: Icon(Icons.lock_outline,
                            color: Colors.grey.shade500, size: 18),
                      ).copyWith(
                        fillColor: Colors.grey.shade100,
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: Colors.grey.shade300, width: 2),
                        ),
                      ),
                    )
                  else
                    DropdownButtonFormField<TreePlanting>(
                      value: _selectedMangrovePlanting,
                      onChanged: _isLoading || _mangrovePlantingOptions.isEmpty
                          ? null
                          : (TreePlanting? newValue) async {
                              setState(() {
                                _selectedMangrovePlanting = newValue;
                                _activitySeqId = newValue?.seqId;
                                _activityName =
                                    newValue?.activityName?.trim() ?? '';
                                _municipality =
                                    newValue?.municipality.trim() ?? '';
                                _barangay = newValue?.barangay.trim() ?? '';
                                _selectedQuarter = null;
                                _usedQuarters = {};
                              });
                              if (newValue != null) {
                                await _loadSeedRowsForSelectedActivity(
                                    newValue.seqId);
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
                        hint: 'Select mangrove planting activity',
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
                          : _mangrovePlantingOptions.isEmpty
                              ? [
                                  const DropdownMenuItem<TreePlanting>(
                                    value: null,
                                    child: Text(
                                        'No mangrove planting activities found'),
                                  ),
                                ]
                              : _mangrovePlantingOptions.map((option) {
                                  return DropdownMenuItem<TreePlanting>(
                                    value: option,
                                    child: Text(
                                      _buildMangrovePlantingLabel(option),
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
                    items: _quarterOptions.map(
                      (quarter) {
                        final isUsed = _usedQuarters.contains(quarter);
                        return DropdownMenuItem<int>(
                          value: quarter,
                          enabled: !isUsed,
                          child: Text(
                            isUsed
                                ? 'Quarter $quarter (already recorded)'
                                : 'Quarter $quarter',
                            style: isUsed
                                ? TextStyle(color: Colors.grey.shade400)
                                : null,
                          ),
                        );
                      },
                    ).toList(),
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
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.save_rounded, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                (_isEditing || _isEditingPending)
                                    ? 'Update Record'
                                    : 'Save Record',
                                style: const TextStyle(
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
  final int seedId;
  final String species;
  final int plantedCount;
  final TextEditingController surviveController;

  _SurvivalSeedRow({
    required this.seedId,
    required this.species,
    required this.plantedCount,
    required this.surviveController,
  });
}
