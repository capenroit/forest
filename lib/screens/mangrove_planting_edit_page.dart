import 'package:flutter/material.dart';

import '../data_entry/mangrove_planting_form.dart';
import '../service/activity_model.dart';

class MangrovePlantingEditPage extends StatelessWidget {
  final TreePlanting initialData;

  const MangrovePlantingEditPage({
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
              child: MangrovePlantingForm(
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
