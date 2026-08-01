import 'dart:async';

import 'package:flutter/material.dart';

import '../service/auth_session.dart';
import '../service/seedling_list_service.dart';

class SettingSeedlingPage extends StatefulWidget {
  const SettingSeedlingPage({super.key});

  @override
  State<SettingSeedlingPage> createState() => _SettingSeedlingPageState();
}

class _SettingSeedlingPageState extends State<SettingSeedlingPage> {
  final SeedlingListService _seedlingListService = SeedlingListService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _seedlingRows = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadSeedlings();
  }

  Future<void> _loadSeedlings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final rows = await _seedlingListService.getSeedlingRows();

      if (!mounted) return;
      setState(() {
        _seedlingRows = rows;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load seedlings: $e';
      });
    }
  }

  Future<void> _showAddSeedlingDialog() async {
    final nameController = TextEditingController();
    final detailsController = TextEditingController();

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
                      Icon(Icons.eco, color: Colors.white, size: 24),
                      SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add Seedling Type',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Add name and details',
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
                        'Seedling Name',
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
                          hintText: 'Enter seedling name',
                          filled: true,
                          fillColor: Colors.green.shade50,
                          prefixIcon:
                              Icon(Icons.forest, color: Colors.green.shade600),
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
                        'Details',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: detailsController,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          hintText: 'Example: Narra (Pterocarpus indicus)',
                          filled: true,
                          fillColor: Colors.blue.shade50,
                          prefixIcon: Icon(Icons.description_outlined,
                              color: Colors.blue.shade600),
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
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(dialogContext),
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
                              onPressed: _isSaving
                                  ? null
                                  : () async {
                                      await _addSeedling(
                                        rawName: nameController.text,
                                        rawDetails: detailsController.text,
                                        dialogContext: dialogContext,
                                      );
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1B8B5E),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
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
                                        valueColor: AlwaysStoppedAnimation<Color>(
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

    nameController.dispose();
    detailsController.dispose();
  }

  Future<void> _addSeedling({
    required String rawName,
    required String rawDetails,
    required BuildContext dialogContext,
  }) async {
    final name = rawName.trim();
    final details = rawDetails.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a seedling name.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final exists = _seedlingRows.any((row) =>
        (row['seedling_name'] ?? '').toString().toLowerCase() ==
        name.toLowerCase());
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seedling already exists.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    FocusManager.instance.primaryFocus?.unfocus();

    try {
      await _seedlingListService.addSeedlingName(
        seedlingName: name,
        details: details,
      ).timeout(const Duration(seconds: 12));

      if (!mounted) return;
      Navigator.pop(dialogContext);
      await _loadSeedlings();
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
          content: Text('Failed to add seedling: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _showEditSeedlingDialog(Map<String, dynamic> row) async {
    final seqId = (row['seq_id'] as num).toInt();
    final nameController =
        TextEditingController(text: (row['seedling_name'] ?? '').toString());
    final detailsController =
        TextEditingController(text: (row['details'] ?? '').toString());

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Edit Seedling'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Seedling Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: detailsController,
                decoration: const InputDecoration(labelText: 'Details'),
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
                      content: Text('Please enter a seedling name.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                try {
                  await _seedlingListService.updateSeedlingName(
                    seqId: seqId,
                    seedlingName: name,
                    details: detailsController.text,
                  );
                  if (!mounted) return;
                  Navigator.pop(dialogContext);
                  await _loadSeedlings();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to update seedling: $e'),
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

    nameController.dispose();
    detailsController.dispose();
  }

  Future<void> _confirmDeleteSeedling(Map<String, dynamic> row) async {
    final seqId = (row['seq_id'] as num).toInt();
    final name = (row['seedling_name'] ?? '').toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Remove Seedling?'),
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
      await _seedlingListService.deleteSeedlingName(seqId);
      if (!mounted) return;
      await _loadSeedlings();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name removed.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to remove seedling: $e'),
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
    final filteredSeedlings = _seedlingRows
        .where((row) => (row['seedling_name'] ?? '')
            .toString()
            .toLowerCase()
            .contains(_searchQuery.toLowerCase()))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seedling List Settings'),
        backgroundColor: const Color.fromARGB(255, 31, 103, 78),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _loadSeedlings,
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
                            'Seedling List',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _isSaving ? null : _showAddSeedlingDialog,
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
                        hintText: 'Search seedling name',
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
                        onPressed: _loadSeedlings,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_seedlingRows.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No seedlings in the list yet.'),
                ),
              )
            else if (filteredSeedlings.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No seedlings match your search.'),
                ),
              )
            else
              ...filteredSeedlings.map(
                (row) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.eco),
                    title: Text((row['seedling_name'] ?? '').toString()),
                    subtitle: (row['details'] ?? '').toString().isEmpty
                        ? null
                        : Text((row['details']).toString()),
                    trailing: AuthSession.isAdmin
                        ? PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') {
                                _showEditSeedlingDialog(row);
                              } else if (value == 'remove') {
                                _confirmDeleteSeedling(row);
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

