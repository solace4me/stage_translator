// lib/data/set_list.dart
//
// Set lists: an ordered list of songs for a service or a gig. Each item points
// at a saved chord sheet or a saved hymn, so the key and voice you chose for
// it come along. One JSON file per set in <app documents>/setlists/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum SetItemKind { sheet, score }

class SetItem {
  final SetItemKind kind;
  final String refId; // Sheet.id or SavedScore.id
  final String title; // remembered, in case the song is later deleted

  const SetItem({required this.kind, required this.refId, required this.title});

  Map<String, dynamic> toJson() => {'kind': kind.name, 'refId': refId, 'title': title};

  factory SetItem.fromJson(Map<String, dynamic> j) => SetItem(
        kind: j['kind'] == 'score' ? SetItemKind.score : SetItemKind.sheet,
        refId: j['refId'] as String,
        title: j['title'] as String? ?? 'Untitled',
      );

  SetItem withTitle(String t) => SetItem(kind: kind, refId: refId, title: t);

  @override
  bool operator ==(Object other) => other is SetItem && other.kind == kind && other.refId == refId;

  @override
  int get hashCode => Object.hash(kind, refId);
}

class SetList {
  final String id;
  final String name;
  final List<SetItem> items;
  final DateTime updatedAt;

  const SetList({required this.id, required this.name, this.items = const [], required this.updatedAt});

  SetList copyWith({String? name, List<SetItem>? items}) =>
      SetList(id: id, name: name ?? this.name, items: items ?? this.items, updatedAt: DateTime.now());

  Map<String, dynamic> toJson() => {
        'version': 1,
        'id': id,
        'name': name,
        'items': [for (final i in items) i.toJson()],
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory SetList.fromJson(Map<String, dynamic> j) => SetList(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Set list',
        items: [
          for (final i in (j['items'] as List? ?? const []))
            SetItem.fromJson((i as Map).cast<String, dynamic>()),
        ],
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

class SetListRepository {
  static final ValueNotifier<int> changes = ValueNotifier(0);

  Directory? _dir;
  Future<void> _writing = Future.value();

  Future<Directory> _setsDir() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/setlists');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  Future<List<SetList>> list() async {
    final dir = await _setsDir();
    final out = <SetList>[];
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        out.add(SetList.fromJson(jsonDecode(await e.readAsString()) as Map<String, dynamic>));
      } catch (_) {
        // skip unreadable files
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  /// Saves are queued one after another, so quick edits never collide.
  Future<void> save(SetList set) {
    return _writing = _writing.then((_) async {
      final dir = await _setsDir();
      final tmp = File('${dir.path}/${set.id}.json.tmp');
      await tmp.writeAsString(jsonEncode(set.toJson()), flush: true);
      await tmp.rename('${dir.path}/${set.id}.json');
      changes.value++;
    });
  }

  /// Queued after any pending save, so a late save can't bring it back.
  Future<void> delete(String id) {
    return _writing = _writing.then((_) async {
      final f = File('${(await _setsDir()).path}/$id.json');
      if (await f.exists()) await f.delete();
      changes.value++;
    });
  }

  static String newId() => 'set${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}
