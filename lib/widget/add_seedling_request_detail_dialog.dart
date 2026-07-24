import 'package:flutter/material.dart';

import '../service/lookup_service.dart';

class SeedlingRequestDetail {
  final int seedId;
  final String speciesName;
  final int quantity;

  const SeedlingRequestDetail({
    required this.seedId,
    required this.speciesName,
    required this.quantity,
  });
}

class AddSeedlingRequestDetailDialog extends StatefulWidget {
  const AddSeedlingRequestDetailDialog({
    super.key,
    required this.seedlingOptions,
    required this.availableQuantityBySeedId,
    required this.onAdd,
  });

  final List<LookupOption> seedlingOptions;
  final Map<int, int> availableQuantityBySeedId;
  final ValueChanged<SeedlingRequestDetail> onAdd;

  @override
  State<AddSeedlingRequestDetailDialog> createState() =>
      _AddSeedlingRequestDetailDialogState();
}

class _AddSeedlingRequestDetailDialogState
    extends State<AddSeedlingRequestDetailDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _quantityController = TextEditingController();
  LookupOption? _selectedSeedling;

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  int get _availableForSelected {
    final seedling = _selectedSeedling;
    if (seedling == null) return 0;
    return widget.availableQuantityBySeedId[seedling.id] ?? 0;
  }

  InputDecoration _inputDecoration({required String hint, IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.green.shade50,
      prefixIcon:
          icon != null ? Icon(icon, color: Colors.green.shade600) : null,
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
    final seedling = _selectedSeedling;
    if (seedling == null) return;

    widget.onAdd(
      SeedlingRequestDetail(
        seedId: seedling.id,
        speciesName: seedling.name,
        quantity: int.parse(_quantityController.text.trim()),
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
                        'Add Seedling',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Set species and quantity',
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
                      Text(
                        'Seedling Species',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<LookupOption>(
                        initialValue: _selectedSeedling,
                        items: widget.seedlingOptions
                            .map((option) => DropdownMenuItem(
                                  value: option,
                                  child: Text(
                                      '${option.name} (${widget.availableQuantityBySeedId[option.id] ?? 0} available)'),
                                ))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedSeedling = value),
                        decoration: _inputDecoration(
                          hint: 'Choose seedling species',
                          icon: Icons.eco,
                        ),
                        validator: (value) =>
                            value == null ? 'Seedling species is required' : null,
                        isExpanded: true,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            'Quantity',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          if (_selectedSeedling != null) ...[
                            const Spacer(),
                            Text(
                              'Available: $_availableForSelected',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _quantityController,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration(
                          hint: 'Enter quantity',
                          icon: Icons.format_list_numbered,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Quantity is required';
                          }
                          final quantity = int.tryParse(value.trim());
                          if (quantity == null || quantity <= 0) {
                            return 'Enter a valid number';
                          }
                          if (quantity > _availableForSelected) {
                            return 'Cannot exceed available quantity ($_availableForSelected)';
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
                              child: const Text('Add Seedling'),
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
