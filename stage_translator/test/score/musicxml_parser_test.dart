// test/score/musicxml_parser_test.dart
// Run with:  flutter test test/score

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage_translator/core/solfege_engine.dart';
import 'package:stage_translator/score/musicxml_parser.dart';
import 'package:stage_translator/score/score.dart';
import 'package:stage_translator/score/solfa.dart';

import 'fixtures.dart';

List<String?> syllables(SolfaLine l) => l.notes.map((n) => n.syllable).toList();
List<String> pitches(SolfaLine l) => l.notes.where((n) => !n.isRest).map((n) => '${n.pitch}').toList();

void main() {
  final score = MusicXmlParser.parseString(kHymn);
  final voices = score.voices();
  VoiceTrack role(VoiceRole r) => voices.firstWhere((v) => v.role == r);

  group('reading the file', () {
    test('title, composer, key and time', () {
      expect(score.title, 'Test Hymn');
      expect(score.composer, 'Anon');
      expect(score.initialKey.fifths, -1);
      expect(score.initialKey.displayName, 'F major');
      expect(score.initialTime.toString(), '4/4');
      expect(score.keyAt(1).fifths, 0);
      expect(score.parts.single.staves, 2);
    });

    test('backup puts every voice at the start of the bar', () {
      expect(role(VoiceRole.soprano).notes.map((n) => n.onset), [0, 1, 2, 3, 4, 6, 7]);
      expect(role(VoiceRole.alto).notes.map((n) => n.onset), [0, 1, 2, 3, 4]);
      expect(role(VoiceRole.bass).notes.map((n) => n.onset), [0, 2, 4]);
      expect(role(VoiceRole.bass).notes[1].duration, 2);
    });

    test('pitch spelling is kept', () {
      final t = role(VoiceRole.tenor).notes;
      expect(t[1].pitch.toString(), 'Bb3');
      expect(role(VoiceRole.soprano).notes[3].pitch.toString(), 'B4');
    });

    test('lyrics for each verse, with hyphenation', () {
      final s = role(VoiceRole.soprano).notes;
      expect(role(VoiceRole.soprano).verses, [1, 2]);
      expect(s[2].lyrics[1]!.displayText, 'ho-');
      expect(s[3].lyrics[1]!.displayText, 'ly');
      expect(s[2].lyrics[2]!.text, 'Lord');
    });

    test('bad input gives a clear error', () {
      expect(() => MusicXmlParser.parseString('<html></html>'),
          throwsA(isA<MusicXmlFormatException>()));
      expect(() => MusicXmlParser.parseString('not xml'), throwsA(isA<MusicXmlFormatException>()));
    });
  });

  group('voices', () {
    test('a grand staff with two voices each is S A T B', () {
      expect(voices.map((v) => v.label), ['Soprano', 'Alto', 'Tenor', 'Bass']);
    });

    test('chords in one voice are split into upper and lower lines', () {
      final s = MusicXmlParser.parseString(kChordHymn);
      final v = s.voices();
      expect(v.map((t) => t.label), ['Soprano', 'Alto', 'Tenor', 'Bass']);
      expect(v[0].notes.map((n) => '${n.pitch}'), ['G4', 'F#4']);
      expect(v[1].notes.map((n) => '${n.pitch}'), ['B3', 'D4']);
      expect(v[2].notes.map((n) => '${n.pitch}'), ['D3', 'A3']);
      expect(v[3].notes.map((n) => '${n.pitch}'), ['G2', 'D3']);
      // The lyric was on the lower chord note; the soprano line still gets it.
      expect(v[0].notes.first.lyrics[1]!.displayText, 'Hal-');
      // G major: G = do, F# = ti.
      expect(syllables(SolfaBuilder.build(s, v[0])), ['do', 'ti']);
    });
  });

  group('solfège', () {
    test('syllables follow the written key; B natural in F is fa#', () {
      final line = SolfaBuilder.build(score, role(VoiceRole.soprano));
      expect(syllables(line), ['do', 're', 'mi', 'fa#', 'do', 'do', null]);
      expect(line.notes[5].isTieContinuation, isTrue);
    });

    test('keeping the first do through the key change', () {
      final line = SolfaBuilder.build(score, role(VoiceRole.soprano),
          options: const SolfaOptions(followKeyChanges: false));
      expect(syllables(line).sublist(4, 6), ['so', 'so']);
    });

    test('lower voices', () {
      expect(syllables(SolfaBuilder.build(score, role(VoiceRole.bass))), ['do', 'fa', 'do']);
      expect(syllables(SolfaBuilder.build(score, role(VoiceRole.tenor))).take(4), ['mi', 'fa', 'so', 'la']);
    });

    test('transposing moves the letters, not the syllables', () {
      final inD = SolfaBuilder.build(score, role(VoiceRole.soprano), performanceDoh: NoteName.parse('D'));
      expect(syllables(inD), ['do', 're', 'mi', 'fa#', 'do', 'do', null]);
      expect(pitches(inD), ['D4', 'E4', 'F#4', 'G#4', 'A4', 'A4']);
      final inAb = SolfaBuilder.build(score, role(VoiceRole.soprano), performanceDoh: NoteName.parse('Ab'));
      expect(pitches(inAb).take(4), ['Ab4', 'Bb4', 'C5', 'D5']);
    });

    test('minor keys: la-based by default, do-based on request', () {
      const dMinor = KeySignature(-1, KeyMode.minor);
      expect(dMinor.displayName, 'D minor');
      expect(dMinor.doh().toString(), 'F');
      expect(dMinor.doh(laBasedMinor: false).toString(), 'D');
    });

    test('tonic sol-fa text view', () {
      final text = SolfaBuilder.toText(SolfaBuilder.build(score, role(VoiceRole.soprano)));
      expect(text, 'do    re  mi   fa#  do  -\nSing  a   ho-  ly');
      final v2 = SolfaBuilder.toText(SolfaBuilder.build(score, role(VoiceRole.soprano)), verse: 2);
      expect(v2.split('\n')[1], 'Praise  the  Lord  now');
    });
  });

  test('.mxl (zipped MusicXML) is read through META-INF/container.xml', () {
    final xmlBytes = utf8.encode(kHymn);
    const container = '<?xml version="1.0"?><container><rootfiles>'
        '<rootfile full-path="score/hymn.musicxml"/></rootfiles></container>';
    final containerBytes = utf8.encode(container);
    final archive = Archive()
      ..addFile(ArchiveFile('META-INF/container.xml', containerBytes.length, containerBytes))
      ..addFile(ArchiveFile('score/hymn.musicxml', xmlBytes.length, xmlBytes));
    final zipped = Uint8List.fromList(ZipEncoder().encode(archive) as List<int>);
    final s = MusicXmlParser.parseBytes(zipped);
    expect(s.title, 'Test Hymn');
    expect(s.voices().length, 4);
  });
}
