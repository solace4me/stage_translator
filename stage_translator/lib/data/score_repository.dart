// lib/data/score_repository.dart
//
// Saved scores: the original MusicXML/.mxl file is kept as-is, next to a
// small JSON file with the title and your view settings. Folder:
// <app documents>/scores/<id>.score (the file) and <id>.json (settings).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class SavedScore {
  final String id;
  final String title;
  final String? performanceKey; // null = the written key
  final int voiceIndex;
  final int verse;
  final DateTime updatedAt;

  const SavedScore({
    required this.id,
    required this.title,
    this.performanceKey,
    this.voiceIndex = 0,
    this.verse = 1,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'version': 1,
        'id': id,
        'title': title,
        'performanceKey': performanceKey,
        'voiceIndex': voiceIndex,
        'verse': verse,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory SavedScore.fromJson(Map<String, dynamic> j) => SavedScore(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Untitled',
        performanceKey: j['performanceKey'] as String?,
        voiceIndex: (j['voiceIndex'] as num?)?.toInt() ?? 0,
        verse: (j['verse'] as num?)?.toInt() ?? 1,
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

class ScoreRepository {
  Directory? _dir;

  Future<Directory> _scoresDir() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/scores');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  Future<List<SavedScore>> list() async {
    final dir = await _scoresDir();
    final out = <SavedScore>[];
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        out.add(SavedScore.fromJson(jsonDecode(await e.readAsString()) as Map<String, dynamic>));
      } catch (_) {
        // skip unreadable entries
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<Uint8List> readFile(String id) async =>
      File('${(await _scoresDir()).path}/$id.score').readAsBytes();

  /// Saves the settings, and the score file itself when [bytes] is given.
  Future<void> save(SavedScore meta, {Uint8List? bytes}) async {
    final dir = await _scoresDir();
    if (bytes != null) {
      final tmp = File('${dir.path}/${meta.id}.score.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename('${dir.path}/${meta.id}.score');
    }
    final tmp = File('${dir.path}/${meta.id}.json.tmp');
    await tmp.writeAsString(jsonEncode(meta.toJson()), flush: true);
    await tmp.rename('${dir.path}/${meta.id}.json');
  }

  Future<void> delete(String id) async {
    final dir = await _scoresDir();
    for (final ext in ['score', 'json']) {
      final f = File('${dir.path}/$id.$ext');
      if (await f.exists()) await f.delete();
    }
  }

  static String newId() => 's${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}
