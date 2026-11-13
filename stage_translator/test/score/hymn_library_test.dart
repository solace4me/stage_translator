// Opens every hymn in the built-in library with the real parser and checks
// it has voices, notes and (where expected) words for each verse.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stage_translator/score/curwen.dart';
import 'package:stage_translator/score/musicxml_parser.dart';

void main() {
  final index = (jsonDecode(File('assets/hymns/index.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  test('index lists about 300 hymns, each with a file', () {
    expect(index.length, greaterThan(290));
    for (final h in index) {
      expect(File('assets/hymns/${h['id']}.mxl').existsSync(), isTrue, reason: h['id'] as String);
    }
  });

  test('every library hymn opens, with its voices and verses', () {
    final failures = <String>[];
    for (final h in index) {
      final id = h['id'] as String;
      try {
        final score = MusicXmlParser.parseBytes(File('assets/hymns/$id.mxl').readAsBytesSync());
        final voices = score.withRepeatsFollowed().voices();
        if (voices.isEmpty) failures.add('$id: no voices');
        final verses = <int>{for (final v in voices) ...v.verses};
        final expected = h['verses'] as int;
        if (expected > 0 && !verses.containsAll([for (var i = 1; i <= expected; i++) i])) {
          failures.add('$id: verses $verses, expected 1..$expected');
        }
        CurwenBuilder.build(score, voices, verse: 1).systems(60); // lays out without throwing
      } catch (e) {
        failures.add('$id: $e');
      }
    }
    expect(failures, isEmpty, reason: failures.take(20).join('\n'));
  });
}
