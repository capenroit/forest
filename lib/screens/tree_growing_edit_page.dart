import 'package:flutter/material.dart';

import '../data_entry/tree_growing_form.dart';
import '../service/activity_model.dart';

class TreeGrowingEditPage extends StatelessWidget {
  final TreePlanting initialData;

  const TreeGrowingEditPage({
    super.key,
    required this.initialData,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.28),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Material(
              color: Colors.transparent,
              elevation: 14,
              borderRadius: BorderRadius.circular(12),
              child: TreeGrowingForm(
                municipalities: const [],
                barangays: const [],
                initialData: initialData,
                onSave: (updatedTreePlanting) {
                  Navigator.of(context).pop(updatedTreePlanting);
                },
                onCancel: () {
                  Navigator.of(context).pop();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
