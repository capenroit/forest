import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../service/auth_session.dart';
import '../service/lookup_service.dart';

class SeedlingTransactionForm extends StatefulWidget {
  final VoidCallback? onSave;
  final int? initialTransactionId;
  final int? initialSeedId;
  final int? initialNurseryId;
  final int? initialSpeciesTypeId;
  final int? initialTransactionTypeId;
  final int? initialSeedlingCount;
  final DateTime? initialDate;
  final String? initialReleaseBy;
  final String? initialReleaseTo;
  final int initialTabIndex;

  const SeedlingTransactionForm({
    Key? key,
    this.onSave,
    this.initialTransactionId,
    this.initialSeedId,
    this.initialNurseryId,
    this.initialSpeciesTypeId,
    this.initialTransactionTypeId,
    this.initialSeedlingCount,
    this.initialDate,
    this.initialReleaseBy,
    this.initialReleaseTo,
    this.initialTabIndex = 0,
  }) : super(key: key);

  @override
  State<SeedlingTransactionForm> createState() =>
      _SeedlingTransactionFormState();
}

class _SeedlingTransactionFormState extends State<SeedlingTransactionForm> {
  late TextEditingController _seedlingCountController;
  late TextEditingController _dateController;
  late TextEditingController _releaseByController;
  late TextEditingController _releaseToController;

  // Lookup Options
  List<_SeedlingOption> _seedlingOptions = [];
  List<LookupOption> _transactionTypeOptions = [];
  List<LookupOption> _nurseryOptions = [];
  List<LookupOption> _speciesTypeOptions = [];

  // Selected Values
  _SeedlingOption? _selectedSeedling;
  LookupOption? _selectedNursery;
  LookupOption? _selectedSpeciesType;
  int _selectedTabIndex = 0;

  // State flags
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _seedlingCountController = TextEditingController(
      text: widget.initialSeedlingCount?.toString() ?? '',
    );
    _dateController = TextEditingController(
      text: (widget.initialDate ?? DateTime.now()).toIso8601String().split('T').first,
    );
    _releaseByController = TextEditingController(
      text: widget.initialReleaseBy ?? '',
    );
    _releaseToController = TextEditingController(
      text: widget.initialReleaseTo ?? '',
    );
    _selectedTabIndex = widget.initialTabIndex;

    _loadAllData();
  }

  @override
  void dispose() {
    _seedlingCountController.dispose();
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
        _loadSpeciesTypes(),
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
    if (widget.initialSeedId != null) {
      for (final option in _seedlingOptions) {
        if (option.id == widget.initialSeedId) {
          _selectedSeedling = option;
          break;
        }
      }
    }

    if (widget.initialNurseryId != null) {
      for (final option in _nurseryOptions) {
        if (option.id == widget.initialNurseryId) {
          _selectedNursery = option;
          break;
        }
      }
    }

    if (widget.initialSpeciesTypeId != null) {
      for (final option in _speciesTypeOptions) {
        if (option.id == widget.initialSpeciesTypeId) {
          _selectedSpeciesType = option;
          break;
        }
      }
    }

    if (widget.initialTransactionTypeId != null) {
      for (final option in _transactionTypeOptions) {
        if (option.id == widget.initialTransactionTypeId) {
          final normalized = option.name.trim().toLowerCase();
          _selectedTabIndex = normalized == 'release' ? 1 : 0;
          break;
        }
      }
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

  Future<void> _loadSpeciesTypes() async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('species_type')
          .select('seq_id, name');

      final options = (response as List<dynamic>)
          .map((row) => LookupOption(
            id: (row['seq_id'] as num).toInt(),
            name: (row['name'] as String).trim(),
          ))
          .toList();

      if (!mounted) return;
      setState(() {
        _speciesTypeOptions = options;
      });
    } catch (e) {
      // Error handled silently
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

  Future<void> _handleSave() async {
    if (_isSaving) return;

    final selectedSeedling = _selectedSeedling;
    final selectedNursery = _selectedNursery;
    final selectedSpeciesType = _selectedSpeciesType;
    final seedlingCount = _seedlingCountController.text.trim();
    final releaseBy = _releaseByController.text.trim();
    final releaseTo = _releaseToController.text.trim();
    final transactionTypeId = _resolveTransactionTypeIdForTab();

    // Validation
    if (selectedSeedling == null) {
      _showErrorSnackBar('Please select a seedling species.');
      return;
    }

    if (transactionTypeId == null) {
      _showErrorSnackBar('Transaction type mapping is missing.');
      return;
    }

    if (selectedNursery == null) {
      _showErrorSnackBar('Please select a nursery.');
      return;
    }

    if (selectedSpeciesType == null) {
      _showErrorSnackBar('Please select a species type.');
      return;
    }

    if (seedlingCount.isEmpty) {
      _showErrorSnackBar('Please enter seedling count.');
      return;
    }

    final count = int.tryParse(seedlingCount);
    if (count == null || count <= 0) {
      _showErrorSnackBar('Seedling count must be a positive number.');
      return;
    }

    if (_selectedTabIndex == 1 && releaseBy.isEmpty) {
      _showErrorSnackBar('Please enter Release By.');
      return;
    }

    if (_selectedTabIndex == 1 && releaseTo.isEmpty) {
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
      final details = _selectedTabIndex == 1
          ? 'Release transaction'
          : 'Receive transaction';
      final payload = {
        'seed_id': selectedSeedling.id,
        'user_id': authUserId,
        'transaction_type_id': transactionTypeId,
        'seedling_count': count,
        'details': details,
        'created_at': parsedDate.toIso8601String(),
        'nursery_id': selectedNursery.id,
        'species_type_id': selectedSpeciesType.id,
        'release_by': _selectedTabIndex == 1 ? releaseBy : null,
        'release_to': _selectedTabIndex == 1 ? releaseTo : null,
      };

      // Save to database
      final supabase = Supabase.instance.client;

      if (widget.initialTransactionId == null) {
        await supabase.from('seedling_transaction').insert(payload);
      } else {
        await supabase
            .from('seedling_transaction')
            .update(payload)
            .eq('id', widget.initialTransactionId!);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaction saved successfully.'),
          backgroundColor: Colors.green,
        ),
      );

      widget.onSave?.call();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('Failed to save transaction: ${e.toString()}');
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

  int? _resolveTransactionTypeIdForTab() {
    final expectedType = _selectedTabIndex == 0 ? 'receive' : 'release';
    for (final option in _transactionTypeOptions) {
      if (option.name.trim().toLowerCase() == expectedType) {
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

  Widget _buildTransactionTypeTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabItem(
              title: 'Receive',
              icon: Icons.south_west_rounded,
              isActive: _selectedTabIndex == 0,
              onTap: () => setState(() => _selectedTabIndex = 0),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildTabItem(
              title: 'Release',
              icon: Icons.north_east_rounded,
              isActive: _selectedTabIndex == 1,
              onTap: () => setState(() => _selectedTabIndex = 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem({
    required String title,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: isActive ? const Color(0xFF1B8B5E) : Colors.transparent,
            boxShadow: isActive
                ? const [
                    BoxShadow(
                      color: Color(0x331B8B5E),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive ? Colors.white : const Color(0xFF4A5A55),
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isActive ? Colors.white : const Color(0xFF4A5A55),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
            child: CircularProgressIndicator(
              color: Color(0xFF1B8B5E),
            ),
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
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 650),
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
                  Icon(Icons.local_shipping_rounded, color: Colors.white, size: 24),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Seedling Transaction',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Record seedling movement',
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
                    // Transaction Type Tabs
                    Text(
                      'Transaction Type *',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildTransactionTypeTabs(),
                    const SizedBox(height: 16),

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
                      value: _selectedNursery,
                      items: _nurseryOptions
                          .map((option) => DropdownMenuItem(
                                value: option,
                                child: Text(option.name),
                              ))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _selectedNursery = value),
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

                    // Species Type
                    Text(
                      'Species Type *',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<LookupOption>(
                      value: _selectedSpeciesType,
                      items: _speciesTypeOptions
                          .map((option) => DropdownMenuItem(
                                value: option,
                                child: Text(option.name),
                              ))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _selectedSpeciesType = value),
                      decoration: InputDecoration(
                        hintText: 'Choose species type',
                        filled: true,
                        fillColor: Colors.teal.shade50,
                        prefixIcon:
                            Icon(Icons.category_outlined, color: Colors.teal.shade600),
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

                    // Seedling Species
                    Text(
                      'Seedling Species *',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<_SeedlingOption>(
                      value: _selectedSeedling,
                      items: _seedlingOptions
                          .map((option) => DropdownMenuItem(
                                value: option,
                                child: Text(option.name),
                              ))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _selectedSeedling = value),
                      decoration: InputDecoration(
                        hintText: 'Choose seedling species',
                        filled: true,
                        fillColor: Colors.green.shade50,
                        prefixIcon:
                            Icon(Icons.eco, color: Colors.green.shade600),
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

                    // Seedling Count
                    Text(
                      'Seedling Count *',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _seedlingCountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'Enter seedling count',
                        filled: true,
                        fillColor: Colors.purple.shade50,
                        prefixIcon: Icon(Icons.format_list_numbered,
                            color: Colors.purple.shade600),
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

                    if (_selectedTabIndex == 1) ...[
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
                    ],

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

