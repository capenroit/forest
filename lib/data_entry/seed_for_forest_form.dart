import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'seed_for_forest_models.dart';
import '../widget/add_seed_list_dialog.dart';
import '../service/auth_session.dart';
import '../service/lookup_service.dart';
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
  });

  final ValueChanged<SeedForForestEntry> onSave;
  final VoidCallback onCancel;
  final SeedForForestEntry? initialData;

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

  @override
  void initState() {
    super.initState();
    final initial = widget.initialData;

    _donorNameController = TextEditingController(
      text: initial?.donorName ?? '',
    );
    _remarksController = TextEditingController(text: initial?.remarks ?? '');
    if (initial != null) {
      _seedDetails.addAll(initial.seedDetails);
    }
    _date = initial?.date ?? DateTime.now();

    if (widget.showNurseryField) {
      _loadNurseryOptions();
    }
  }

  Future<void> _loadNurseryOptions() async {
    setState(() => _isLoadingNurseries = true);
    try {
      // This dropdown only applies to the division-2 (CRM) propagation
      // quick-add flow, so only that division's nurseries are offered.
      final rows = await _supabase
          .from('seedling_nursery')
          .select('seq_id, name')
          .eq('div_type', 2);

      final options = (rows as List<dynamic>)
          .map((row) => LookupOption(
                id: (row['seq_id'] as num).toInt(),
                name: (row['name'] as String).trim(),
              ))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (!mounted) return;
      setState(() => _nurseryOptions = options);
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

      final initial = widget.initialData;
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

      final dataRows = _seedDetails.map((detail) {
        return {
          'seed_id': detail.seedId,
          'seed_count': detail.speciesCount,
          'seed_donation_id': seedDonationId,
          'species_type': detail.speciesType,
          // seed_id here points into mangrove_list, not seedling_list, when
          // this form was opened in mangrove mode — flag it so downstream
          // readers know which lookup table to resolve the name against.
          'is_mangrove': widget.useMangroveSpeciesList,
        };
      }).toList();

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
