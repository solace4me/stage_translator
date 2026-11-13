// lib/ui/set_nav.dart
//
// Previous / next bar shown at the bottom of a song while playing a set list.

import 'package:flutter/material.dart';

class SetNav {
  final String setName;
  final int index; // 0-based
  final int count;
  final String? nextTitle;
  final VoidCallback? onPrevious; // null on the first song
  final VoidCallback? onNext; // null on the last song

  const SetNav({
    required this.setName,
    required this.index,
    required this.count,
    this.nextTitle,
    this.onPrevious,
    this.onNext,
  });
}

class SetNavBar extends StatelessWidget {
  final SetNav nav;
  final VoidCallback? onPrevious; // the screen's wrapped versions (they save first)
  final VoidCallback? onNext;

  const SetNavBar({super.key, required this.nav, this.onPrevious, this.onNext});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              IconButton(
                iconSize: 32,
                tooltip: 'Previous song',
                onPressed: nav.onPrevious == null ? null : (onPrevious ?? nav.onPrevious),
                icon: const Icon(Icons.skip_previous),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${nav.setName} · ${nav.index + 1} of ${nav.count}',
                        style: text.labelMedium, overflow: TextOverflow.ellipsis),
                    Text(
                      nav.nextTitle == null ? 'Last song' : 'Next: ${nav.nextTitle}',
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                iconSize: 32,
                tooltip: 'Next song',
                onPressed: nav.onNext == null ? null : (onNext ?? nav.onNext),
                icon: const Icon(Icons.skip_next),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
