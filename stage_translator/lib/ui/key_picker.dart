// lib/ui/key_picker.dart

import 'package:flutter/material.dart';

import '../core/solfege_engine.dart';

/// Dropdown of the 14 key spellings. [label] is shown before the value,
/// e.g. "Doh =" or "Written in".
class KeyPicker extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const KeyPicker({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: kKeyChoices.contains(value) ? value : 'C',
          underline: const SizedBox.shrink(),
          items: [
            for (final k in kKeyChoices)
              DropdownMenuItem(
                value: k,
                child: Text(k, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}
