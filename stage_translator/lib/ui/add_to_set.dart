// lib/ui/add_to_set.dart
//
// "Add to set list" from a song's menu: pick one of your sets, or make a new
// one with this song in it.

import 'package:flutter/material.dart';

import '../data/set_list.dart';

Future<void> addToSetList(BuildContext context, SetItem item) async {
  final repo = SetListRepository();
  final messenger = ScaffoldMessenger.of(context);
  final sets = await repo.list();
  if (!context.mounted) return;

  // Returns a set's id, or 'new'.
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.6),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Add "${item.title}" to', style: Theme.of(c).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New set list'),
              onTap: () => Navigator.pop(c, 'new'),
            ),
            for (final s in sets)
              ListTile(
                leading: CircleAvatar(child: Text('${s.items.length}')),
                title: Text(s.name),
                subtitle: s.items.contains(item) ? const Text('Already in this set') : null,
                enabled: !s.items.contains(item),
                onTap: () => Navigator.pop(c, s.id),
              ),
          ],
        ),
      ),
    ),
  );
  if (choice == null) return;

  final SetList target;
  if (choice == 'new') {
    final now = DateTime.now();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    target = SetList(
      id: SetListRepository.newId(),
      name: 'Set ${now.day} ${months[now.month - 1]}',
      items: [item],
      updatedAt: now,
    );
  } else {
    final s = sets.firstWhere((s) => s.id == choice);
    target = s.copyWith(items: [...s.items, item]);
  }
  await repo.save(target);
  messenger.showSnackBar(SnackBar(content: Text('Added to "${target.name}"')));
}
