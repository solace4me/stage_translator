// lib/data/library_repository.dart
//
// Offline library: one JSON file per sheet in <app documents>/library/.
// Writes go to a temp file first and are then renamed, so a crash mid-save
// never leaves a half-written sheet.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'sheet.dart';

class LibraryRepository {
  /// Goes up by one after every save or delete, so screens showing the
  /// library (the home screen) can refresh straight away.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  Directory? _dir;

  Future<Directory> _libraryDir() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/library');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  Future<File> _file(String id) async => File('${(await _libraryDir()).path}/$id.json');

  /// All saved sheets, most recently edited first. Corrupt files are skipped.
  Future<List<Sheet>> list() async {
    final dir = await _libraryDir();
    final sheets = <Sheet>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        sheets.add(Sheet.fromJson(json));
      } catch (_) {
        // Skip unreadable files rather than breaking the whole library.
      }
    }
    sheets.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sheets;
  }

  Future<void> save(Sheet sheet) async {
    final file = await _file(sheet.id);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(sheet.toJson()), flush: true);
    await tmp.rename(file.path);
    changes.value++;
  }

  Future<void> delete(String id) async {
    final file = await _file(id);
    if (await file.exists()) await file.delete();
    changes.value++;
  }

  static String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}
