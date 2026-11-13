// lib/data/hymn_catalog.dart
//
// The built-in hymn library: about 300 public-domain hymns from the Open
// Hymnal Project, converted to MusicXML (.mxl) and shipped inside the app in
// assets/hymns/, with a small index (assets/hymns/index.json) for searching.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class HymnEntry {
  final String id; // file name without .mxl
  final String title;
  final String firstLine;
  final String tune;
  final String author;
  final String composer;
  final String category;
  final String meter; // metrical pattern, e.g. 8 7 8 7
  final String key; // written key, e.g. Eb
  final String time;
  final int voices;
  final int verses;

  HymnEntry({
    required this.id,
    required this.title,
    this.firstLine = '',
    this.tune = '',
    this.author = '',
    this.composer = '',
    this.category = '',
    this.meter = '',
    this.key = '',
    this.time = '',
    this.voices = 4,
    this.verses = 0,
  });

  factory HymnEntry.fromJson(Map<String, dynamic> j) => HymnEntry(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        firstLine: j['firstLine'] as String? ?? '',
        tune: j['tune'] as String? ?? '',
        author: j['author'] as String? ?? '',
        composer: j['composer'] as String? ?? '',
        category: j['category'] as String? ?? '',
        meter: j['meter'] as String? ?? '',
        key: j['key'] as String? ?? '',
        time: j['time'] as String? ?? '',
        voices: (j['voices'] as num?)?.toInt() ?? 4,
        verses: (j['verses'] as num?)?.toInt() ?? 0,
      );

  /// What a saved copy remembers it came from (see SavedScore.source).
  String get source => '${HymnCatalog.sourcePrefix}$id';

  /// Lower-case text matched by the search box.
  late final String searchText = [title, firstLine, tune, author, composer, category]
      .join(' ')
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9 ]"), '');

  bool matches(String query) {
    final words = query.toLowerCase().replaceAll(RegExp(r"[^a-z0-9 ]"), '').split(' ');
    return words.every((w) => w.isEmpty || searchText.contains(w));
  }
}

class HymnCatalog {
  static const sourcePrefix = 'openhymnal:';
  static const attribution = 'Hymns from the Open Hymnal Project (openhymnal.org), '
      'public domain. Converted to MusicXML for this app.';

  static Future<List<HymnEntry>>? _cache;

  /// All hymns, sorted by title. Loaded once.
  static Future<List<HymnEntry>> load() => _cache ??= _load();

  static Future<List<HymnEntry>> _load() async {
    final text = await rootBundle.loadString('assets/hymns/index.json');
    final list = (jsonDecode(text) as List).cast<Map<String, dynamic>>();
    return [for (final j in list) HymnEntry.fromJson(j)];
  }

  /// The hymn's .mxl file.
  static Future<Uint8List> bytes(String id) async =>
      (await rootBundle.load('assets/hymns/$id.mxl')).buffer.asUint8List();

  /// Categories, biggest first.
  static List<String> categories(List<HymnEntry> hymns) {
    final counts = <String, int>{};
    for (final h in hymns) {
      if (h.category.isNotEmpty) counts[h.category] = (counts[h.category] ?? 0) + 1;
    }
    return counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }
}
