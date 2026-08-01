import 'dart:async';

import 'package:flutter/material.dart';

import '../service/api_service.dart';
import '../service/auth_session.dart';

class SettingNurseryPage extends StatefulWidget {
  const SettingNurseryPage({super.key});

  @override
  State<SettingNurseryPage> createState() => _SettingNurseryPageState();
}

class _SettingNurseryPageState extends State<SettingNurseryPage> {
  // Mirrors the division picker in signup_screen.dart. SWM (3) belongs to a
  // separate app this one doesn't manage nurseries for.
  static const Map<String, int> _divisionOptions = {
    'FMS': 1,
    'CRM': 2,
  };
  static const Map<int, String> _divisionNames = {
    1: 'FMS',
    2: 'CRM',
  };

  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _nurseryRows = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadNurseries();
  }

  Future<void> _loadNurseries() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final rows = await ApiService.getSeedlingNurseryRows();

      if (!mounted) return;
      setState(() {
        _nurseryRows = rows;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load nurseries: $e';
      });
    }
  }

  Future<void> _showAddNurseryDialog() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    String? selectedDivision = _divisionOptions.keys.first;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              insetPadding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white,
                ),
                constraints: const BoxConstraints(maxWidth: 450),
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
                          Icon(Icons.park, color: Colors.white, size: 24),
                          SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Add Nursery',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Add name, division, and details',
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
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Nursery Name',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: nameController,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              hintText: 'Enter nursery name',
                              filled: true,
                              fillColor: Colors.green.shade50,
                              prefixIcon:
                                  Icon(Icons.park, color: Colors.green.shade600),
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade200),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Division',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: selectedDivision,
                            items: _divisionOptions.keys
                                .map((division) => DropdownMenuItem(
                                      value: division,
                                      child: Text(division),
                                    ))
                                .toList(),
                            onChanged: (value) =>
                                setDialogState(() => selectedDivision = value),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.green.shade50,
                              prefixIcon: Icon(Icons.apartment,
                                  color: Colors.green.shade600),
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade200),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Description',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: descriptionController,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              hintText: 'Optional details',
                              filled: true,
                              fillColor: Colors.blue.shade50,
                              prefixIcon: Icon(Icons.description_outlined,
                                  color: Colors.blue.shade600),
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade200),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  style: OutlinedButton.styleFrom(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 12),
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
                                  onPressed: _isSaving
                                      ? null
                                      : () async {
                                          await _addNursery(
                                            rawName: nameController.text,
                                            rawDescription:
                                                descriptionController.text,
                                            division: selectedDivision,
                                            dialogContext: dialogContext,
                                          );
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1B8B5E),
                                    foregroundColor: Colors.white,
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: _isSaving
                                      ? const SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                          ),
                                        )
                                      : const Text('Save'),
                                ),
                              ),
                            ],
                          ),
                        ],
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

    nameController.dispose();
    descriptionController.dispose();
  }

  Future<void> _addNursery({
    required String rawName,
    required String rawDescription,
    required String? division,
    required BuildContext dialogContext,
  }) async {
    final name = rawName.trim();
    final description = rawDescription.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a nursery name.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (division == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a division.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final exists = _nurseryRows.any((row) =>
        (row['name'] ?? '').toString().toLowerCase() == name.toLowerCase());
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nursery already exists.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    FocusManager.instance.primaryFocus?.unfocus();

    try {
      await ApiService.addSeedlingNursery(
        name: name,
        description: description,
        divType: _divisionOptions[division]!,
      ).timeout(const Duration(seconds: 12));

      if (!mounted) return;
      Navigator.pop(dialogContext);
      await _loadNurseries();
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Save timed out. Please check internet and try again.'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add nursery: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _showEditNurseryDialog(Map<String, dynamic> row) async {
    final seqId = (row['seq_id'] as num).toInt();
    final nameController =
        TextEditingController(text: (row['name'] ?? '').toString());
    final descriptionController =
        TextEditingController(text: (row['description'] ?? '').toString());
    String? selectedDivision =
        _divisionNames[(row['div_type'] as num?)?.toInt()] ??
            _divisionOptions.keys.first;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: const Text('Edit Nursery'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Nursery Name'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedDivision,
                    items: _divisionOptions.keys
                        .map((division) => DropdownMenuItem(
                              value: division,
                              child: Text(division),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => selectedDivision = value),
                    decoration: const InputDecoration(labelText: 'Division'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a nursery name.'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    if (selectedDivision == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select a division.'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }

                    try {
                      await ApiService.updateSeedlingNursery(
                        seqId: seqId,
                        name: name,
                        description: descriptionController.text,
                        divType: _divisionOptions[selectedDivision]!,
                      );
                      if (!mounted) return;
                      Navigator.pop(dialogContext);
                      await _loadNurseries();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to update nursery: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    descriptionController.dispose();
  }

  Future<void> _confirmDeleteNursery(Map<String, dynamic> row) async {
    final seqId = (row['seq_id'] as num).toInt();
    final name = (row['name'] ?? '').toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Remove Nursery?'),
        content: Text('Are you sure you want to remove "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiService.deleteSeedlingNursery(seqId);
      if (!mounted) return;
      await _loadNurseries();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name removed.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to remove nursery: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredNurseries = _nurseryRows
        .where((row) => (row['name'] ?? '')
            .toString()
            .toLowerCase()
            .contains(_searchQuery.toLowerCase()))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nursery List Settings'),
        backgroundColor: const Color.fromARGB(255, 31, 103, 78),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _loadNurseries,
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
                        const Expanded(
                          child: Text(
                            'Nursery List',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _isSaving ? null : _showAddNurseryDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Add'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        setState(() => _searchQuery = value.trim());
                      },
                      decoration: InputDecoration(
                        hintText: 'Search nursery name',
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
                        fillColor: Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
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
                        onPressed: _loadNurseries,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_nurseryRows.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No nurseries in the list yet.'),
                ),
              )
            else if (filteredNurseries.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No nurseries match your search.'),
                ),
              )
            else
              ...filteredNurseries.map(
                (row) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.park),
                    title: Text((row['name'] ?? '').toString()),
                    subtitle: Text(
                      [
                        _divisionNames[(row['div_type'] as num?)?.toInt()] ??
                            'N/A',
                        if ((row['description'] ?? '').toString().isNotEmpty)
                          (row['description']).toString(),
                      ].join(' • '),
                    ),
                    trailing: AuthSession.isAdmin
                        ? PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') {
                                _showEditNurseryDialog(row);
                              } else if (value == 'remove') {
                                _confirmDeleteNursery(row);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                  value: 'edit', child: Text('Edit')),
                              PopupMenuItem(
                                  value: 'remove', child: Text('Remove')),
                            ],
                          )
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
