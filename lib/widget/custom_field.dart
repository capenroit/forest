import 'package:flutter/material.dart';

/// ✅ Reusable entry field widget
class CustomEntryField extends StatelessWidget {
  final String label;
  final IconData icon;
  final TextInputType keyboardType;

  const CustomEntryField({
    super.key,
    required this.label,
    required this.icon,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.black),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon, color: const Color.fromARGB(255, 31, 103, 78)),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.grey), // default border
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(
            color: Color.fromARGB(255, 31, 103, 78),
            width: 2,
          ), // highlight border
        ),
      ),
    );
  }
}

