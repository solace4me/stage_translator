// lib/ui/play_button.dart
//
// The "Play do" button: tap plays Doh, long-press shows more sounds.

import 'package:flutter/material.dart';

class PlayDohButton extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String label; // "do" or "1"

  const PlayDohButton({super.key, required this.onTap, this.onLongPress, this.label = 'do'});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: onLongPress == null ? 'Play $label' : 'Play $label (hold for more)',
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.volume_up, size: 22),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
        ),
      ),
    );
  }
}
