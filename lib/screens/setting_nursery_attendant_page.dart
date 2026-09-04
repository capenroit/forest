import 'package:flutter/material.dart';

import '../service/api_service.dart';
import '../service/auth_session.dart';
import '../service/nursery_attendant_service.dart';

/// Manages the nursery attendant roster that feeds the "Propagated By"
/// dropdown on the propagation form.
///
/// Nurseries are scoped by division (access_level 1 sees every division,
/// everyone else only their own), and editing is limited to admins —
/// mirroring SettingNurseryPage, which this sits alongside.
class SettingNurseryAttendantPage extends StatefulWidget {
  const SettingNurseryAttendantPage({super.key});

  @override
  State<SettingNurseryAttendantPage> createState() =>
      _SettingNurseryAttendantPageState();
}

class _SettingNurseryAttendantPageState
    extends State<SettingNurseryAttendantPage> {
  static const List<String> _statusOptions = ['Active', 'Inactive'];

  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String _searchQuery = '';

  /// Nurseries this user may assign attendants to, by seq_id.
  Map<int, String> _nurseryNames = {};
  List<Map<String, dynamic>> _attendants = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

      final attendants = await NurseryAttendantService.getAttendants(
        nurseryIds: visible.keys.toList(),
      );

      if (!mounted) return;
      setState(() {
        _nurseryNames = visible;
        _attendants = attendants;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load attendants: $e';
      });
    }
  }

  Future<void> _showAttendantDialog({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final nameController = TextEditingController(
      text: (existing?['name'] ?? '').toString(),
    );

    int? selectedNurseryId = (existing?['nursery_id'] as num?)?.toInt();
    if (selectedNurseryId != null &&
        !_nurseryNames.containsKey(selectedNurseryId)) {
      selectedNurseryId = null;
    }
    selectedNurseryId ??=
        _nurseryNames.isEmpty ? null : _nurseryNames.keys.first;

    var selectedStatus = (existing?['status'] ?? 'Active').toString();
    if (!_statusOptions.contains(selectedStatus)) {
      selectedStatus = _statusOptions.first;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(isEdit ? 'Edit Attendant' : 'Add Attendant'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Attendant name',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  initialValue: selectedNurseryId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Nursery',
                    prefixIcon: Icon(Icons.park_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: _nurseryNames.entries
                      .map((entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => selectedNurseryId = value),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: selectedStatus,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    prefixIcon: Icon(Icons.toggle_on_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: _statusOptions
                      .map((status) => DropdownMenuItem(
                            value: status,
                            child: Text(status),
                          ))
                      .toList(),
                  onChanged: (value) => setDialogState(
                    () => selectedStatus = value ?? 'Active',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Only Active attendants appear in the "Propagated By" '
                  'dropdown. Set someone Inactive instead of removing them '
                  'so their recorded work is kept.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final nurseryId = selectedNurseryId;

                if (name.isEmpty || nurseryId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Enter a name and choose a nursery.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                Navigator.pop(dialogContext);
                await _save(
                  existing: existing,
                  name: name,
                  nurseryId: nurseryId,
                  status: selectedStatus,
                );
              },
              child: Text(isEdit ? 'Save' : 'Add'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
  }

  Future<void> _save({
    Map<String, dynamic>? existing,
    required String name,
    required int nurseryId,
    required String status,
  }) async {
    setState(() => _isSaving = true);
    try {
      if (existing == null) {
        await NurseryAttendantService.addAttendant(
          name: name,
          nurseryId: nurseryId,
          status: status,
        );
      } else {
        await NurseryAttendantService.updateAttendant(
          seqId: (existing['seq_id'] as num).toInt(),
          name: name,
          nurseryId: nurseryId,
          status: status,
        );
      }

      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    final name = (row['name'] ?? '').toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Remove Attendant?'),
        content: Text(
          'Remove "$name"? Propagation records already linked to them will '
          'lose that link. Setting them Inactive keeps the history instead.',
        ),
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
      await NurseryAttendantService.deleteAttendant(
        (row['seq_id'] as num).toInt(),
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name removed.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.toLowerCase();
    final filtered = _attendants.where((row) {
      final name = (row['name'] ?? '').toString().toLowerCase();
      final nursery =
          (_nurseryNames[(row['nursery_id'] as num?)?.toInt()] ?? '')
              .toLowerCase();
      return name.contains(query) || nursery.contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nursery Attendants'),
        backgroundColor: const Color.fromARGB(255, 31, 103, 78),
        foregroundColor: Colors.white,
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
                        const Expanded(
                          child: Text(
                            'Attendant Roster',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (AuthSession.isAdmin)
                          ElevatedButton.icon(
                            onPressed: (_isSaving || _nurseryNames.isEmpty)
                                ? null
                                : () => _showAttendantDialog(),
                            icon: const Icon(Icons.add),
                            label: const Text('Add'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'These names fill the "Propagated By" dropdown when '
                      'recording propagation from Seedling Inventory.',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchController,
                      onChanged: (value) =>
                          setState(() => _searchQuery = value.trim()),
                      decoration: InputDecoration(
                        hintText: 'Search attendant or nursery',
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
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_nurseryNames.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No nurseries are available for your division yet. Add a '
                    'nursery first, then its attendants.',
                  ),
                ),
              )
            else if (_attendants.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No attendants added yet.'),
                ),
              )
            else if (filtered.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No attendants match your search.'),
                ),
              )
            else
              ...filtered.map(_buildAttendantCard),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendantCard(Map<String, dynamic> row) {
    final nurseryId = (row['nursery_id'] as num?)?.toInt();
    final nurseryName = _nurseryNames[nurseryId] ?? 'Unknown nursery';
    final status = (row['status'] ?? '').toString();
    final isActive = status == 'Active';

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              isActive ? const Color(0xFF1B8B5E) : Colors.grey.shade400,
          child: const Icon(Icons.person, color: Colors.white, size: 20),
        ),
        title: Text((row['name'] ?? '').toString()),
        subtitle: Text('$nurseryName • $status'),
        trailing: AuthSession.isAdmin
            ? PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    _showAttendantDialog(existing: row);
                  } else if (value == 'remove') {
                    _confirmDelete(row);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'remove', child: Text('Remove')),
                ],
              )
            : null,
      ),
    );
  }
}
