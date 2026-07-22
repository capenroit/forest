import 'package:flutter/material.dart';

import '../data_entry/seed_for_forest_models.dart';
import '../service/lookup_service.dart';

class AddSeedListDialog extends StatefulWidget {
  const AddSeedListDialog({
    super.key,
    required this.seedInventory,
    required this.onAdd,
  });

  final List<LookupOption> seedInventory;
  final ValueChanged<SeedDetail> onAdd;

  @override
  State<AddSeedListDialog> createState() => _AddSeedListDialogState();
}

class _AddSeedListDialogState extends State<AddSeedListDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _speciesCountController = TextEditingController();
  LookupOption? _selectedSeed;

  @override
  void dispose() {
    _speciesCountController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration({required String hint, IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.green.shade50,
      prefixIcon: icon != null ? Icon(icon, color: Colors.green.shade600) : null,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
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
        borderSide: BorderSide(color: Color(0xFF1B8B5E), width: 2),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final selectedSeed = _selectedSeed;
    if (selectedSeed == null) return;

    widget.onAdd(
      SeedDetail(
        seedId: selectedSeed.id,
        speciesType: '',
        speciesName: selectedSeed.name,
        speciesCount: int.parse(_speciesCountController.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        constraints: BoxConstraints(
          maxWidth: 450,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
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
              child: const Row(
                children: [
                  Icon(Icons.playlist_add, color: Colors.white, size: 24),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add Seed List',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Set species name and count',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        'Species Name',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<LookupOption>(
                        initialValue: _selectedSeed,
                        items: widget.seedInventory
                            .map(
                              (option) => DropdownMenuItem<LookupOption>(
                                value: option,
                                child: Text(option.name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() => _selectedSeed = value);
                        },
                        decoration: _inputDecoration(
                          hint: 'Choose species name',
                          icon: Icons.eco_outlined,
                        ),
                        validator: (value) {
                          if (value == null) {
                            return 'Species name is required';
                          }
                          return null;
                        },
                        isExpanded: true,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Species Count',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _speciesCountController,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration(
                          hint: 'Enter species count',
                          icon: Icons.confirmation_number_outlined,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Species count is required';
                          }
                          final count = int.tryParse(value.trim());
                          if (count == null || count <= 0) {
                            return 'Enter a valid number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
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
                              onPressed: _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1B8B5E),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text('Add Seed'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
