import 'package:flutter/material.dart';
// You’ll need to import your SeedlingEntry model and seedlingInventory list
// import '../models/seedling_entry.dart';
// import '../data/seedling_inventory.dart';

/// Sentinel dropdown value that represents the trailing "+ Add New Seedling"
/// entry — never a real seedling name, so it can't collide with one.
const String _addNewSentinel = '__add_new_seedling__';

class AddSeedlingDialog extends StatefulWidget {
  final List<String> seedlingInventory;
  final void Function(String type, int quantity) onAdd;

  /// Called when the user types a name that isn't already in
  /// [seedlingInventory] and confirms it via the "+ Add New Seedling" row.
  /// Lets the caller persist the new name to whichever master list backs
  /// this form (e.g. the shared seedling_list table, or the mangrove
  /// species list) so it shows up next time. Optional — when omitted (or
  /// when it throws), the typed name is still used for this entry only.
  final Future<void> Function(String newTypeName)? onCreateType;

  const AddSeedlingDialog({
    super.key,
    required this.seedlingInventory,
    required this.onAdd,
    this.onCreateType,
  });

  @override
  State<AddSeedlingDialog> createState() => _AddSeedlingDialogState();
}

class _AddSeedlingDialogState extends State<AddSeedlingDialog> {
  String? selectedType;
  bool _isAddingNew = false;
  bool _isSavingNewType = false;
  String? _newTypeError;
  final TextEditingController quantityController = TextEditingController();
  final TextEditingController _newTypeController = TextEditingController();

  //final SeedlingListService seedlingListService = SeedlingListService();
  //List<String> seedlingNames = [];

  @override
  void dispose() {
    quantityController.dispose();
    _newTypeController.dispose();
    super.dispose();
  }

  /// Case-insensitive match against the existing inventory, so a name typed
  /// with different casing (or the "new" name turning out to already exist)
  /// reuses the exact stored spelling instead of creating a near-duplicate.
  String? _matchExisting(String name) {
    final lower = name.trim().toLowerCase();
    for (final existing in widget.seedlingInventory) {
      if (existing.trim().toLowerCase() == lower) return existing;
    }
    return null;
  }

  Future<void> _handleAddPressed() async {
    final quantity = int.tryParse(quantityController.text.trim());
    if (quantity == null || quantity <= 0) {
      return;
    }

    String? type;

    if (_isAddingNew) {
      final entered = _newTypeController.text.trim();
      if (entered.isEmpty) {
        setState(() => _newTypeError = 'Please enter a seedling name.');
        return;
      }

      final existing = _matchExisting(entered);
      if (existing != null) {
        type = existing;
      } else if (widget.onCreateType != null) {
        setState(() {
          _isSavingNewType = true;
          _newTypeError = null;
        });
        try {
          await widget.onCreateType!(entered);
          type = entered;
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _isSavingNewType = false;
            _newTypeError = 'Unable to save new seedling. Try again.';
          });
          return;
        }
        if (!mounted) return;
        setState(() => _isSavingNewType = false);
      } else {
        type = entered;
      }
    } else {
      type = selectedType;
    }

    if (type == null || type.isEmpty) return;

    widget.onAdd(type, quantity);
    Navigator.pop(context);
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
        constraints: const BoxConstraints(maxWidth: 450, maxHeight: 550),
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
                  Icon(Icons.eco, color: Colors.white, size: 24),
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
                        'Select type and quantity',
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
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Seedling Type
                  Text(
                    'Seedling Type',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _isAddingNew ? _addNewSentinel : selectedType,
                    items: [
                      ...widget.seedlingInventory.map((type) => DropdownMenuItem(
                            value: type,
                            child: Text(type),
                          )),
                      DropdownMenuItem(
                        value: _addNewSentinel,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_circle,
                                size: 18, color: Colors.green.shade700),
                            const SizedBox(width: 6),
                            Text(
                              'Add New Seedling',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        if (value == _addNewSentinel) {
                          _isAddingNew = true;
                          selectedType = null;
                          _newTypeError = null;
                        } else {
                          _isAddingNew = false;
                          selectedType = value;
                        }
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Choose seedling type',
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

                  if (_isAddingNew) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _newTypeController,
                      autofocus: true,
                      enabled: !_isSavingNewType,
                      onChanged: (_) {
                        if (_newTypeError != null) {
                          setState(() => _newTypeError = null);
                        }
                      },
                      decoration: InputDecoration(
                        hintText: 'Enter new seedling name',
                        errorText: _newTypeError,
                        filled: true,
                        fillColor: Colors.green.shade50,
                        prefixIcon:
                            Icon(Icons.eco_outlined, color: Colors.green.shade600),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Cancel',
                          onPressed: _isSavingNewType
                              ? null
                              : () {
                                  setState(() {
                                    _isAddingNew = false;
                                    _newTypeError = null;
                                    _newTypeController.clear();
                                  });
                                },
                        ),
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
                  const SizedBox(height: 18),

                  // Quantity
                  Text(
                    'Quantity',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: quantityController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Enter quantity',
                      filled: true,
                      fillColor: Colors.blue.shade50,
                      prefixIcon: Icon(Icons.format_list_numbered,
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

                  // Buttons
                  Row(
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
                          onPressed: _isSavingNewType ? null : _handleAddPressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1B8B5E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isSavingNewType
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text('Add Seedling'),
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
  }
}
