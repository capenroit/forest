import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../service/auth_session.dart';
import '../service/lookup_service.dart';
import '../widget/add_seedling_request_detail_dialog.dart';

class SeedlingRequestForm extends StatefulWidget {
  final VoidCallback? onSave;
  final int? initialRequestId;
  final int? initialNurseryId;
  final List<SeedlingRequestDetail>? initialDetails;
  final DateTime? initialDate;
  final String? initialReleaseBy;
  final String? initialReleaseTo;

  const SeedlingRequestForm({
    super.key,
    this.onSave,
    this.initialRequestId,
    this.initialNurseryId,
    this.initialDetails,
    this.initialDate,
    this.initialReleaseBy,
    this.initialReleaseTo,
  });

  @override
  State<SeedlingRequestForm> createState() => _SeedlingRequestFormState();
}

class _SeedlingRequestFormState extends State<SeedlingRequestForm> {
  late TextEditingController _dateController;
  late TextEditingController _releaseByController;
  late TextEditingController _releaseToController;

  // Lookup Options
  List<_SeedlingOption> _seedlingOptions = [];
  List<LookupOption> _transactionTypeOptions = [];
  List<LookupOption> _nurseryOptions = [];
  Map<int, Map<int, int>> _availabilityBySeedAndNursery = {};

  // Selected values
  LookupOption? _selectedNursery;
  final List<SeedlingRequestDetail> _details = [];

  // State flags
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _dateController = TextEditingController(
      text: (widget.initialDate ?? DateTime.now()).toIso8601String().split('T').first,
    );
    _releaseByController = TextEditingController(
      text: widget.initialReleaseBy ?? '',
    );
    _releaseToController = TextEditingController(
      text: widget.initialReleaseTo ?? '',
    );

    _loadAllData();
  }

  @override
  void dispose() {
    _dateController.dispose();
    _releaseByController.dispose();
    _releaseToController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadSeedlings(),
        _loadTransactionTypes(),
        _loadNurseries(),
        _loadAvailability(),
      ]);
      if (mounted) {
        _applyInitialSelections();
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyInitialSelections() {
    if (widget.initialNurseryId != null) {
      for (final option in _nurseryOptions) {
        if (option.id == widget.initialNurseryId) {
          _selectedNursery = option;
          break;
        }
      }
    }

    if (widget.initialDetails != null) {
      _details
        ..clear()
        ..addAll(widget.initialDetails!);
    }

    setState(() {});
  }

  Future<void> _loadSeedlings() async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('seedling_list')
          .select('seq_id, seedling_name');

      final options = (response as List<dynamic>)
          .map((row) => _SeedlingOption(
            id: (row['seq_id'] as num).toInt(),
            name: (row['seedling_name'] as String).trim(),
          ))
          .toList();

      if (!mounted) return;
      setState(() {
        _seedlingOptions = options;
      });
    } catch (e) {
      // Error handled silently
    }
  }

  Future<void> _loadTransactionTypes() async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('seedling_transaction_type')
          .select('id, transaction_type');

      final options = (response as List<dynamic>)
          .map((row) => LookupOption(
            id: (row['id'] as num).toInt(),
            name: (row['transaction_type'] as String).trim(),
          ))
          .toList();

      if (!mounted) return;
      setState(() {
        _transactionTypeOptions = options;
      });
    } catch (e) {
      // Error handled silently
    }
  }

  Future<void> _loadNurseries() async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('seedling_nursery')
          .select('seq_id, name');

      final options = (response as List<dynamic>)
          .map((row) => LookupOption(
            id: (row['seq_id'] as num).toInt(),
            name: (row['name'] as String).trim(),
          ))
          .toList();

      if (!mounted) return;
      setState(() {
        _nurseryOptions = options;
      });
    } catch (e) {
      // Error handled silently
    }
  }

  Future<void> _loadAvailability() async {
    try {
      final supabase = Supabase.instance.client;
      final transactionRows = await supabase
          .from('seedling_transaction')
          .select(
              'seed_id, transaction_type_id, nursery_id, seedling_count, transaction_id')
          .limit(5000);

      final typeRows = await supabase
          .from('seedling_transaction_type')
          .select('id, transaction_type');
      final Map<int, String> typeById = {
        for (final row
            in (typeRows as List<dynamic>).cast<Map<String, dynamic>>())
          (row['id'] as num).toInt():
              (row['transaction_type'] ?? '').toString().trim().toLowerCase(),
      };

      final Map<int, Map<int, int>> availability = {};
      for (final row
          in (transactionRows as List<dynamic>).cast<Map<String, dynamic>>()) {
        final seedId = (row['seed_id'] as num?)?.toInt();
        final nurseryId = (row['nursery_id'] as num?)?.toInt();
        final typeId = (row['transaction_type_id'] as num?)?.toInt();
        final quantity = (row['seedling_count'] as num?)?.toInt() ?? 0;
        final rowRequestId = (row['transaction_id'] as num?)?.toInt();

        if (seedId == null || nurseryId == null) continue;
        // Exclude this request's own existing rows so re-saving the same
        // (or adjusted) quantities isn't blocked by its own prior release.
        if (widget.initialRequestId != null &&
            rowRequestId == widget.initialRequestId) {
          continue;
        }

        final type = typeById[typeId] ?? '';
        final signedQuantity = type == 'release' ? -quantity : quantity;

        final nurseryMap = availability.putIfAbsent(seedId, () => {});
        nurseryMap[nurseryId] = (nurseryMap[nurseryId] ?? 0) + signedQuantity;
      }

      if (!mounted) return;
      setState(() => _availabilityBySeedAndNursery = availability);
    } catch (e) {
      // Error handled silently; availability checks will just show 0.
    }
  }

  int _availableQuantity(int? seedId, int? nurseryId) {
    if (seedId == null || nurseryId == null) return 0;
    return _availabilityBySeedAndNursery[seedId]?[nurseryId] ?? 0;
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

  Future<void> _openAddDetailDialog() async {
    final nurseryId = _selectedNursery?.id;
    if (nurseryId == null) {
      _showErrorSnackBar('Please select a nursery first.');
      return;
    }

    final usedSeedIds = _details.map((d) => d.seedId).toSet();
    final availableQuantityBySeedId = <int, int>{};
    for (final option in _seedlingOptions) {
      final available = _availableQuantity(option.id, nurseryId);
      if (available > 0) {
        availableQuantityBySeedId[option.id] = available;
      }
    }

    final options = _seedlingOptions
        .where((option) =>
            availableQuantityBySeedId.containsKey(option.id) &&
            !usedSeedIds.contains(option.id))
        .map((option) => LookupOption(id: option.id, name: option.name))
        .toList();

    if (options.isEmpty) {
      _showErrorSnackBar('No more available seedlings to add at this nursery.');
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AddSeedlingRequestDetailDialog(
        seedlingOptions: options,
        availableQuantityBySeedId: availableQuantityBySeedId,
        onAdd: (detail) {
          Navigator.pop(dialogContext);
          if (!mounted) return;
          setState(() => _details.add(detail));
        },
      ),
    );
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;

    final selectedNursery = _selectedNursery;
    final releaseBy = _releaseByController.text.trim();
    final releaseTo = _releaseToController.text.trim();
    final transactionTypeId = _resolveReleaseTransactionTypeId();

    // Validation
    if (selectedNursery == null) {
      _showErrorSnackBar('Please select a nursery.');
      return;
    }

    if (transactionTypeId == null) {
      _showErrorSnackBar('Transaction type mapping is missing.');
      return;
    }

    if (_details.isEmpty) {
      _showErrorSnackBar('Please add at least one seedling detail.');
      return;
    }

    for (final detail in _details) {
      final available = _availableQuantity(detail.seedId, selectedNursery.id);
      if (detail.quantity > available) {
        _showErrorSnackBar(
            '${detail.speciesName} cannot exceed available quantity ($available).');
        return;
      }
    }

    if (releaseBy.isEmpty) {
      _showErrorSnackBar('Please enter Release By.');
      return;
    }

    if (releaseTo.isEmpty) {
      _showErrorSnackBar('Please enter Release To.');
      return;
    }

    final authUserId = await _resolveCurrentUserSeqId();

    if (authUserId == null) {
      _showErrorSnackBar('Unable to save data. Logged-in user id is missing.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final parsedDate =
          DateTime.tryParse(_dateController.text.trim()) ?? DateTime.now();
      final supabase = Supabase.instance.client;

      final requestId = widget.initialRequestId ??
          await _resolveNextTransactionId(supabase);

      final rows = _details
          .map((detail) => {
                'seed_id': detail.seedId,
                'user_id': authUserId,
                'transaction_type_id': transactionTypeId,
                'seedling_count': detail.quantity,
                'details': 'Release transaction',
                'created_at': parsedDate.toIso8601String(),
                'nursery_id': selectedNursery.id,
                'release_by': releaseBy,
                'release_to': releaseTo,
                'transaction_id': requestId,
              })
          .toList();

      if (widget.initialRequestId != null) {
        // Editing: replace every row that belonged to this request rather
        // than updating by row id, since species/quantities may have been
        // added, removed, or changed — same pattern used for other
        // multi-row records (e.g. Flora and Fauna Survey).
        await supabase
            .from('seedling_transaction')
            .delete()
            .eq('transaction_id', requestId);
      }

      await supabase.from('seedling_transaction').insert(rows);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seedling request saved successfully.'),
          backgroundColor: Colors.green,
        ),
      );

      widget.onSave?.call();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('Failed to save request: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  /// One transaction_id is shared by every detail row saved in this request
  /// so the Seedling Request page can merge them back into a single card.
  Future<int> _resolveNextTransactionId(SupabaseClient supabase) async {
    final row = await supabase
        .from('seedling_transaction')
        .select('transaction_id')
        .order('transaction_id', ascending: false)
        .limit(1)
        .maybeSingle();

    final currentMax = (row?['transaction_id'] as num?)?.toInt() ?? 0;
    return currentMax + 1;
  }

  int? _resolveReleaseTransactionTypeId() {
    for (final option in _transactionTypeOptions) {
      if (option.name.trim().toLowerCase() == 'release') {
        return option.id;
      }
    }
    return null;
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

      final seqId = (row?['seq_id'] as num?)?.toInt();
      if (seqId != null && AuthSession.currentUser != null) {
        final current = AuthSession.currentUser!;
        AuthSession.currentUser = AppUser(
          id: current.id,
          seqId: seqId,
          email: current.email,
          name: current.name,
          accessLevel: current.accessLevel,
          status: current.status,
          divisionTypeId: current.divisionTypeId,
        );
      }
      return seqId;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
          ),
          padding: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxWidth: 500),
          child: const Center(
            child: CircularProgressIndicator(color: Color(0xFF1B8B5E)),
          ),
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
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
                  Icon(Icons.assignment_outlined, color: Colors.white, size: 24),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Seedling Request',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Release one or more seedlings in a single request',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Nursery
                    Text(
                      'Nursery *',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<LookupOption>(
                      initialValue: _selectedNursery,
                      items: _nurseryOptions
                          .map((option) => DropdownMenuItem(
                                value: option,
                                child: Text(option.name),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() {
                        _selectedNursery = value;
                        _details.clear();
                      }),
                      decoration: InputDecoration(
                        hintText: 'Choose nursery',
                        filled: true,
                        fillColor: Colors.orange.shade50,
                        prefixIcon:
                            Icon(Icons.location_on, color: Colors.orange.shade600),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          borderSide: BorderSide(
                            color: Color(0xFF1B8B5E),
                            width: 2,
                          ),
                        ),
                      ),
                      isExpanded: true,
                    ),
                    const SizedBox(height: 16),

                    // Seedling Details
                    Text(
                      'Seedling Details *',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
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
                          if (_details.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Text(
                                'No seedlings added yet.',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 13,
                                ),
                              ),
                            )
                          else
                            Column(
                              children: List.generate(_details.length, (index) {
                                final detail = _details[index];
                                return Padding(
                                  padding: EdgeInsets.only(
                                    bottom: index == _details.length - 1 ? 0 : 10,
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
                                                'Quantity: ${detail.quantity}',
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
                                              _details.removeAt(index);
                                            });
                                          },
                                          icon: const Icon(Icons.delete_outline),
                                          tooltip: 'Remove seedling',
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
                              onPressed: _selectedNursery == null
                                  ? null
                                  : _openAddDetailDialog,
                              icon: const Icon(Icons.playlist_add),
                              label: const Text('Add Seedling'),
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
                    const SizedBox(height: 16),

                    Text(
                      'Release By *',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _releaseByController,
                      decoration: InputDecoration(
                        hintText: 'Enter person releasing seedlings',
                        filled: true,
                        fillColor: Colors.blueGrey.shade50,
                        prefixIcon: Icon(Icons.person_outline,
                            color: Colors.blueGrey.shade600),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          borderSide: BorderSide(
                            color: Color(0xFF1B8B5E),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Release To *',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _releaseToController,
                      decoration: InputDecoration(
                        hintText: 'Enter recipient',
                        filled: true,
                        fillColor: Colors.blueGrey.shade50,
                        prefixIcon: Icon(Icons.person,
                            color: Colors.blueGrey.shade600),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          borderSide: BorderSide(
                            color: Color(0xFF1B8B5E),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Date
                    Text(
                      'Date *',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _dateController,
                      readOnly: true,
                      onTap: () => _selectDate(context),
                      decoration: InputDecoration(
                        hintText: 'Select date',
                        filled: true,
                        fillColor: Colors.red.shade50,
                        prefixIcon: Icon(Icons.calendar_today,
                            color: Colors.red.shade600),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          borderSide: BorderSide(
                            color: Color(0xFF1B8B5E),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Buttons
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1B8B5E),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Save',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
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
}

class _SeedlingOption {
  final int id;
  final String name;

  _SeedlingOption({required this.id, required this.name});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SeedlingOption &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name;

  @override
  int get hashCode => id.hashCode ^ name.hashCode;
}
