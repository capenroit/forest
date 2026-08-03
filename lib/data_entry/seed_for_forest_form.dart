import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'seed_for_forest_models.dart';
import '../widget/add_seed_list_dialog.dart';
import '../service/auth_session.dart';
import '../service/lookup_service.dart';
import '../service/offline_sync_service.dart';
import '../service/seedling_list_service.dart';

class SeedForForestForm extends StatefulWidget {
  const SeedForForestForm({
    super.key,
    required this.onSave,
    required this.onCancel,
    this.initialData,
    this.donorFieldLabel = 'Donor Name',
    this.showNurseryField = false,
    this.formTitle = 'Seed for a Forest Data Entry',
    this.formSubtitle = 'Record donor and seed list details',
    this.useMangroveSpeciesList = false,
    this.pendingLocalId,
    this.pendingPayload,
  });

  final ValueChanged<SeedForForestEntry> onSave;
  final VoidCallback onCancel;
  final SeedForForestEntry? initialData;

  /// When set, this form is editing a record that was saved offline and is
  /// still sitting in the local sync queue (not yet on the server). [_save]
  /// rewrites the queued payload in place instead of talking to Supabase,
  /// and [initState] populates fields from [pendingPayload] instead of
  /// [initialData].
  final String? pendingLocalId;

  /// The queued payload for [pendingLocalId], in the exact shape
  /// OfflineSyncService stores/expects for type 'seed_for_forest':
  /// `{'headerPayload': {...}, 'seedDetails': [...]}`.
  final Map<String, dynamic>? pendingPayload;

  /// Label for the donor/propagator name field — lets callers repurpose this
  /// form (e.g. "Propagated By" for a direct propagation quick-add) without
  /// changing what's recorded for the existing "Seed for a Forest" flow.
  final String donorFieldLabel;

  /// When true, shows a required nursery dropdown and saves the selection
  /// to seed_donation.nursery_id.
  final bool showNurseryField;

  /// Header title/subtitle — overridable so callers can repurpose this form
  /// (e.g. "Mangrove Data Entry") without changing the default used by the
  /// "Seed for a Forest" flow.
  final String formTitle;
  final String formSubtitle;

  /// When true, "Add Seed List" pulls species from mangrove_list instead of
  /// seedling_list.
  final bool useMangroveSpeciesList;

  @override
  State<SeedForForestForm> createState() => _SeedForForestFormState();
}

class _SeedForForestFormState extends State<SeedForForestForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final SeedlingListService _seedlingListService = SeedlingListService();
  final SupabaseClient _supabase = Supabase.instance.client;

  late TextEditingController _donorNameController;
  late TextEditingController _remarksController;
  final List<SeedDetail> _seedDetails = [];
  DateTime _date = DateTime.now();
  bool _isSaving = false;

  List<LookupOption> _nurseryOptions = [];
  LookupOption? _selectedNursery;
  bool _isLoadingNurseries = false;

  /// nursery_id read from a pending draft's header payload, applied to
  /// _selectedNursery once _nurseryOptions finishes loading.
  int? _pendingNurseryId;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialData;
    final pending = widget.pendingPayload;

    if (widget.pendingLocalId != null && pending != null) {
      final header =
          Map<String, dynamic>.from(pending['headerPayload'] as Map? ?? {});
      final seedDetailRows = (pending['seedDetails'] as List? ?? [])
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      _donorNameController = TextEditingController(
        text: (header['donor_name'] ?? '').toString(),
      );
      _remarksController = TextEditingController(
        text: (header['details'] ?? '').toString(),
      );
      _date = DateTime.tryParse((header['donated_date'] ?? '').toString()) ??
          DateTime.now();

      _seedDetails.addAll(seedDetailRows.map((row) {
        final seedId = (row['seed_id'] as num?)?.toInt() ?? 0;
        return SeedDetail(
          seedId: seedId,
          speciesType: (row['species_type'] ?? '').toString(),
          // Resolved asynchronously below once the seed/mangrove lookup
          // tables have been queried — the queued payload only stores the
          // id, not the display name.
          speciesName: 'Seed $seedId',
          speciesCount: (row['seed_count'] as num?)?.toInt() ?? 0,
        );
      }));

      if (widget.showNurseryField) {
        _pendingNurseryId = (header['nursery_id'] as num?)?.toInt();
      }

      _resolvePendingSeedNames(seedDetailRows);
    } else {
      _donorNameController = TextEditingController(
        text: initial?.donorName ?? '',
      );
      _remarksController = TextEditingController(text: initial?.remarks ?? '');
      if (initial != null) {
        _seedDetails.addAll(initial.seedDetails);
      }
      _date = initial?.date ?? DateTime.now();
    }

    if (widget.showNurseryField) {
      _loadNurseryOptions();
    }
  }

  /// Resolves the display names for seed details restored from a pending
  /// (not-yet-synced) draft. Mirrors the lookup logic
  /// SeedForForestRecentActivityPage uses for synced records: seed_id
  /// points into seedling_list normally, or into mangrove_list for rows
  /// flagged is_mangrove.
  Future<void> _resolvePendingSeedNames(
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

    final Map<int, String> nameById = {};
    try {
      if (regularSeedIds.isNotEmpty) {
        final options = await _seedlingListService.getSeedlingOptions();
        for (final option in options) {
          nameById[option.id] = option.name;
        }
      }
    } catch (_) {
      // Keep the placeholder names if the lookup fails.
    }

    final Map<int, String> mangroveNameById = {};
    try {
      if (mangroveSeedIds.isNotEmpty) {
        final mangroveRows = await _supabase
            .from('mangrove_list')
            .select('id, name')
            .inFilter('id', mangroveSeedIds.toList());
        for (final row in (mangroveRows as List<dynamic>)
            .cast<Map<String, dynamic>>()) {
          final id = (row['id'] as num?)?.toInt();
          final name = (row['name'] ?? '').toString();
          if (id != null) mangroveNameById[id] = name;
        }
      }
    } catch (_) {
      // Keep the placeholder names if the lookup fails.
    }

    if (!mounted) return;
    setState(() {
      for (var i = 0; i < _seedDetails.length && i < rows.length; i++) {
        final row = rows[i];
        final seedId = (row['seed_id'] as num?)?.toInt() ?? _seedDetails[i].seedId;
        final isMangrove = row['is_mangrove'] == true;
        final resolvedName =
            isMangrove ? mangroveNameById[seedId] : nameById[seedId];
        if (resolvedName != null && resolvedName.isNotEmpty) {
          _seedDetails[i] = SeedDetail(
            seedId: seedId,
            speciesType: _seedDetails[i].speciesType,
            speciesName: resolvedName,
            speciesCount: _seedDetails[i].speciesCount,
          );
        }
      }
    });
  }

  Future<void> _loadNurseryOptions() async {
    setState(() => _isLoadingNurseries = true);
    try {
      // Offer only the nurseries belonging to this dialog's own division —
      // mangrove (CRM, div_type 2) vs. forest (FMS, div_type 1) — matching
      // useMangroveSpeciesList, which the caller already sets based on the
      // current user's division.
      final rows = await _supabase
          .from('seedling_nursery')
          .select('seq_id, name')
          .eq('div_type', widget.useMangroveSpeciesList ? 2 : 1);

      final options = (rows as List<dynamic>)
          .map((row) => LookupOption(
                id: (row['seq_id'] as num).toInt(),
                name: (row['name'] as String).trim(),
              ))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _nurseryOptions = options;
        if (_pendingNurseryId != null) {
          for (final option in options) {
            if (option.id == _pendingNurseryId) {
              _selectedNursery = option;
              break;
            }
          }
        }
      });
    } catch (_) {
      // Dropdown just stays empty; save-time validation catches it.
    } finally {
      if (mounted) {
        setState(() => _isLoadingNurseries = false);
      }
    }
  }

  Future<List<LookupOption>> _getMangroveSpeciesOptions() async {
    try {
      final rows =
          await _supabase.from('mangrove_list').select('id, name').order('name');

      return (rows as List<dynamic>)
          .map((row) => LookupOption(
                id: (row['id'] as num).toInt(),
                name: (row['name'] as String).trim(),
              ))
          .where((option) => option.name.isNotEmpty)
          .toList();
    } catch (_) {
      return const <LookupOption>[];
    }
  }

  @override
  void dispose() {
    _donorNameController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  InputDecoration _modernInputDecoration({
    required String label,
    String? hint,
    IconData? icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, color: Colors.grey.shade600) : null,
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
      labelStyle: TextStyle(color: Colors.grey.shade700, fontSize: 13),
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.green.shade700, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.green.shade900,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
      ),
      constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: Color(0xFF1B8B5E),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.forest, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.formTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          widget.formSubtitle,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: 'Close',
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
                    _buildSectionHeader(
                      widget.showNurseryField
                          ? 'Propagation Details'
                          : 'Donor Details',
                      Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7FAF8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFD7E6DE)),
                      ),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _donorNameController,
                            decoration: _modernInputDecoration(
                              label: widget.donorFieldLabel,
                              hint: 'Enter ${widget.donorFieldLabel.toLowerCase()}',
                              icon: Icons.badge_outlined,
                            ),
                            validator: (v) =>
                                v == null || v.trim().isEmpty ? 'Required' : null,
                          ),
                          if (widget.showNurseryField) ...[
                            const SizedBox(height: 10),
                            DropdownButtonFormField<LookupOption>(
                              initialValue: _selectedNursery,
                              decoration: _modernInputDecoration(
                                label: 'Nursery',
                                hint: _isLoadingNurseries
                                    ? 'Loading nurseries...'
                                    : 'Select nursery',
                                icon: Icons.park_outlined,
                              ),
                              items: _nurseryOptions
                                  .map((option) => DropdownMenuItem(
                                        value: option,
                                        child: Text(option.name),
                                      ))
                                  .toList(),
                              onChanged: _isLoadingNurseries
                                  ? null
                                  : (value) =>
                                      setState(() => _selectedNursery = value),
                              validator: (v) =>
                                  v == null ? 'Required' : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildSectionHeader('Seed Details', Icons.grass_rounded),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7FAF8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFD7E6DE)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add one or more seed details using the dialog below.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_seedDetails.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Text(
                                'No seed details added yet.',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 13,
                                ),
                              ),
                            )
                          else
                            Column(
                              children: List.generate(_seedDetails.length, (index) {
                                final detail = _seedDetails[index];
                                return Padding(
                                  padding: EdgeInsets.only(
                                    bottom: index == _seedDetails.length - 1 ? 0 : 10,
                                  ),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFFD7E6DE),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                detail.speciesName,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Count: ${detail.speciesCount}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () {
                                            setState(() {
                                              _seedDetails.removeAt(index);
                                            });
                                          },
                                          icon: const Icon(Icons.delete_outline),
                                          tooltip: 'Remove seed detail',
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _openAddSeedListDialog,
                              icon: const Icon(Icons.playlist_add),
                              label: const Text('Add Seed List'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 44),
                                side: const BorderSide(color: Color(0xFF1B8B5E)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildSectionHeader('Schedule and Remarks', Icons.event_note_rounded),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7FAF8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFD7E6DE)),
                      ),
                      child: Column(
                        children: [
                          InkWell(
                            onTap: _pickDate,
                            borderRadius: BorderRadius.circular(8),
                            child: InputDecorator(
                              decoration: _modernInputDecoration(
                                label: 'Date',
                                icon: Icons.calendar_month_outlined,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDate(_date),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                  const Icon(Icons.calendar_today, size: 18),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _remarksController,
                            maxLines: 3,
                            decoration: _modernInputDecoration(
                              label: 'Remarks',
                              hint: 'Enter remarks (optional)',
                              icon: Icons.notes_outlined,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAF8),
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onCancel,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        side: const BorderSide(
                          color: Color(0xFF1B8B5E),
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Color(0xFF1B5E20),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        backgroundColor: const Color(0xFF1B8B5E),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Save',
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
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null) {
      setState(() => _date = selected);
    }
  }

  Future<void> _openAddSeedListDialog() async {
    final seedInventory = widget.useMangroveSpeciesList
        ? await _getMangroveSpeciesOptions()
        : await _seedlingListService.getSeedlingOptions();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AddSeedListDialog(
        seedInventory: seedInventory,
        onAdd: (detail) {
          Navigator.pop(dialogContext);
          if (!mounted) return;
          setState(() {
            _seedDetails.add(detail);
          });
        },
      ),
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;
    if (_seedDetails.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one seed detail.')),
      );
      return;
    }

    final authUserId = _supabase.auth.currentUser?.id;
    if (authUserId == null || authUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to save.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final totalCount = _seedDetails.fold<int>(
        0,
        (sum, detail) => sum + detail.speciesCount,
      );
      final headerPayload = <String, dynamic>{
        'user_id': authUserId,
        'userid': AuthSession.currentUser?.seqId,
        'donor_name': _donorNameController.text.trim(),
        'donated_date': _formatDateOnly(_date),
        'total_count': totalCount,
        'details': _remarksController.text.trim(),
        if (widget.showNurseryField) ...{
          'nursery_id': _selectedNursery!.id,
          'status': 'PROPAGATED',
        },
      };

      // Same shape _supabase.from('seed_donation_data') rows have always
      // been built with, minus seed_donation_id — that's only known once
      // the header row exists (added below for the online path, added by
      // OfflineSyncService._syncSeedForForest once it syncs for the
      // offline/pending paths).
      final seedDetailRows = _seedDetails.map((detail) {
        return {
          'seed_id': detail.seedId,
          'seed_count': detail.speciesCount,
          'species_type': detail.speciesType,
          // seed_id here points into mangrove_list, not seedling_list, when
          // this form was opened in mangrove mode — flag it so downstream
          // readers know which lookup table to resolve the name against.
          'is_mangrove': widget.useMangroveSpeciesList,
        };
      }).toList();

      // ── Editing a pending (not-yet-synced) draft ────────────────────────
      // Purely local: rewrite the queued payload in place, no connectivity
      // check and no Supabase calls.
      if (widget.pendingLocalId != null) {
        await OfflineSyncService.updatePendingItem(
          widget.pendingLocalId!,
          {
            'headerPayload': headerPayload,
            'seedDetails': seedDetailRows,
          },
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data was saved.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        widget.onSave(
          SeedForForestEntry(
            id: widget.initialData?.id,
            donorName: _donorNameController.text.trim(),
            seedDetails: List<SeedDetail>.unmodifiable(_seedDetails),
            date: _date,
            totalCount: totalCount,
            remarks: _remarksController.text.trim(),
          ),
        );
        return;
      }

      final initial = widget.initialData;

      // ── Offline path ─────────────────────────────────────────────────────
      final isOnline = await OfflineSyncService.hasInternetConnection();
      if (!mounted) return;

      if (!isOnline) {
        if (initial?.id != null) {
          // Editing an already-synced record offline is out of scope —
          // there is nothing queued locally to rewrite, and attempting the
          // online update/delete calls below would just hang/fail against
          // a dead connection.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Editing requires an internet connection.'),
            ),
          );
          return;
        }

        await OfflineSyncService.queueGenericRecord(
          type: 'seed_for_forest',
          payload: {
            'headerPayload': headerPayload,
            'seedDetails': seedDetailRows,
          },
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data was saved.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        widget.onSave(
          SeedForForestEntry(
            donorName: _donorNameController.text.trim(),
            seedDetails: List<SeedDetail>.unmodifiable(_seedDetails),
            date: _date,
            totalCount: totalCount,
            remarks: _remarksController.text.trim(),
          ),
        );
        return;
      }
      // ── End offline path ────────────────────────────────────────────────

      int seedDonationId;

      if (initial?.id == null) {
        final headerRow = await _supabase
            .from('seed_donation')
            .insert(headerPayload)
            .select('id')
            .single();
        seedDonationId = (headerRow['id'] as num).toInt();
      } else {
        seedDonationId = initial!.id!;
        await _supabase
            .from('seed_donation')
            .update(headerPayload)
            .eq('id', seedDonationId);
        await _supabase
            .from('seed_donation_data')
            .delete()
            .eq('seed_donation_id', seedDonationId);
      }

      final dataRows = seedDetailRows
          .map((row) => {
                ...row,
                'seed_donation_id': seedDonationId,
              })
          .toList();

      await _supabase.from('seed_donation_data').insert(dataRows);

      if (!mounted) return;

      widget.onSave(
        SeedForForestEntry(
          id: seedDonationId,
          donorName: _donorNameController.text.trim(),
          seedDetails: List<SeedDetail>.unmodifiable(_seedDetails),
          date: _date,
          totalCount: totalCount,
          remarks: _remarksController.text.trim(),
        ),
      );

      // Flush any other pending offline records now that we know we're
      // online and this save has already completed.
      OfflineSyncService.syncAll().ignore();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save seed donation: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _formatDateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
