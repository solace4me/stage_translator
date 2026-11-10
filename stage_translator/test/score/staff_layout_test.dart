// test/score/staff_layout_test.dart
// Run with:  flutter test test/score

import 'package:flutter_test/flutter_test.dart';
import 'package:stage_translator/core/solfege_engine.dart';
import 'package:stage_translator/score/musicxml_parser.dart';
import 'package:stage_translator/score/score.dart';
import 'package:stage_translator/score/solfa.dart';
import 'package:stage_translator/score/staff_layout.dart';

import 'fixtures.dart';

Pitch p(String name, int octave) => Pitch(NoteName.parse(name), octave);

void main() {
  group('staff positions', () {
    test('treble and bass clef steps', () {
      expect(StaffLayout.stepOf(p('E', 4), Clef.treble), 0);
      expect(StaffLayout.stepOf(p('C', 4), Clef.treble), -2);
      expect(StaffLayout.stepOf(p('F', 5), Clef.treble), 8);
      expect(StaffLayout.stepOf(p('G', 2), Clef.bass), 0);
      expect(StaffLayout.stepOf(p('C', 4), Clef.bass), 10);
    });

    test('ledger lines', () {
      expect(StaffLayout.ledgerStepsFor(-2), [-2]);
      expect(StaffLayout.ledgerStepsFor(-5), [-2, -4]);
      expect(StaffLayout.ledgerStepsFor(10), [10]);
      expect(StaffLayout.ledgerStepsFor(3), isEmpty);
    });

    test('note values and dots', () {
      expect(StaffLayout.valueOf(4), NoteValue.whole);
      expect(StaffLayout.valueOf(3), NoteValue.half);
      expect(StaffLayout.isDotted(3), isTrue);
      expect(StaffLayout.valueOf(1), NoteValue.quarter);
      expect(StaffLayout.valueOf(0.5), NoteValue.eighth);
      expect(StaffLayout.isDotted(2), isFalse);
    });
  });

  group('key signatures', () {
    test('sharps and flats from Doh', () {
      expect(StaffLayout.fifthsOf(NoteName.parse('F')), -1);
      expect(StaffLayout.fifthsOf(NoteName.parse('D')), 2);
      expect(StaffLayout.fifthsOf(NoteName.parse('F#')), 6);
      expect(StaffLayout.fifthsOf(NoteName.parse('D#')), -3); // shown as Eb
    });

    test('printed positions', () {
      expect(StaffLayout.keySignatureSteps(-1, Clef.treble), [4]);
      expect(StaffLayout.keySignatureSteps(2, Clef.treble), [8, 5]);
      expect(StaffLayout.keySignatureSteps(2, Clef.bass), [6, 3]);
      expect(StaffLayout.keyAlterations(-1), [0, 0, 0, 0, 0, 0, -1]);
      expect(StaffLayout.keyAlterations(2), [1, 0, 0, 1, 0, 0, 0]);
    });
  });

  group('laying out a line', () {
    final score = MusicXmlParser.parseString(kHymn);
    final soprano = score.voices().first;
    final bass = score.voices().last;

    test('soprano in F: treble clef, one flat, B natural shows ♮', () {
      final layout = StaffLayout.build(SolfaBuilder.build(score, soprano), width: 2000);
      expect(layout.clef, Clef.treble);
      expect(layout.fifths, -1);
      expect(layout.rows.length, 1);
      expect(layout.rows.single.barlines.length, 2);
      final accidentals = layout.rows.single.glyphs.map((g) => g.accidental).toList();
      expect(accidentals, [null, null, null, '♮', null, null, null]);
    });

    test('transposed to D: two sharps, the raised 4th shows #', () {
      final line = SolfaBuilder.build(score, soprano, performanceDoh: NoteName.parse('D'));
      final layout = StaffLayout.build(line, width: 2000);
      expect(layout.fifths, 2);
      final g = layout.rows.single.glyphs;
      expect(g[2].accidental, isNull); // F# is in the key signature
      expect(g[3].accidental, '#'); // G#
    });

    test('bass line gets the bass clef', () {
      expect(StaffLayout.build(SolfaBuilder.build(score, bass), width: 2000).clef, Clef.bass);
    });

    test('a narrow screen wraps into more rows, notes stay in order', () {
      final layout = StaffLayout.build(SolfaBuilder.build(score, soprano), width: 220);
      expect(layout.rows.length, greaterThan(1));
      final all = layout.rows.expand((r) => r.glyphs).toList();
      expect(all.length, 7);
      for (final r in layout.rows) {
        for (var i = 1; i < r.glyphs.length; i++) {
          expect(r.glyphs[i].x, greaterThan(r.glyphs[i - 1].x));
        }
      }
    });

    test('a long syllable gets room', () {
      final layout = StaffLayout.build(SolfaBuilder.build(score, soprano), width: 2000, charWidth: 30);
      final g = layout.rows.single.glyphs;
      // Note 1 ("Praise", 6 chars) is 6 * 30 + 12 + 6 = 198 px wide, note 2
      // ("the", 3 chars) 3 * 30 + 12 + 6 = 108 px: centres are 99 + 54 apart.
      expect(g[1].x - g[0].x, closeTo(153, 0.01));
    });
  });

  group('key changes', () {
    final score = MusicXmlParser.parseString(kHymn);
    final soprano = score.voices().first;

    test('a key change inside a row: double bar, natural for the old flat', () {
      final row = StaffLayout.build(SolfaBuilder.build(score, soprano), width: 2000).rows.single;
      expect(row.startFifths, -1);
      expect(row.keyChanges.length, 1);
      expect(row.keyChanges.single.fifths, 0);
      expect(row.keyChanges.single.cancelSteps, [4]); // the B-flat is cancelled
    });

    test('a key change at a row break moves into the new row\'s header', () {
      final layout = StaffLayout.build(SolfaBuilder.build(score, soprano), width: 400);
      expect(layout.rows.length, 2);
      expect(layout.rows[0].startFifths, -1);
      expect(layout.rows[1].startFifths, 0);
      expect(layout.rows.every((r) => r.keyChanges.isEmpty), isTrue);
    });

    test('the new key is transposed with the notes', () {
      final line = SolfaBuilder.build(score, soprano, performanceDoh: NoteName.parse('D'));
      final row = StaffLayout.build(line, width: 2000).rows.single;
      expect(row.startFifths, 2); // D major
      expect(row.keyChanges.single.fifths, 3); // C major moved up to A major
    });

    test('the time signature is shown on the first row only', () {
      final layout = StaffLayout.build(SolfaBuilder.build(score, soprano), width: 400);
      expect(layout.time.toString(), '4/4');
      expect(layout.rows.map((r) => r.showTime), [true, false]);
    });
  });

  group('beams, ties and slurs', () {
    final tune = MusicXmlParser.parseString(kBeamTune);
    final line = SolfaBuilder.build(tune, tune.voices().single);
    final row = StaffLayout.build(line, width: 3000).rows.single;

    test('6/8 beams in groups of three eighths', () {
      expect(line.beatLength, 1.5);
      expect(row.beams.length, 3);
      expect(row.beams[0].glyphs, [0, 1, 2]);
      expect(row.beams[1].glyphs, [3, 4, 5]);
    });

    test('stems follow the group: low notes up, high notes down', () {
      expect(row.beams[0].stemUp, isTrue);
      expect(row.beams[1].stemUp, isFalse);
      expect(row.glyphs[1].stemUp, isTrue);
    });

    test('sixteenths get a second beam; the rest ends the group', () {
      final b = row.beams[2];
      expect(b.glyphs, [7, 8, 9]);
      expect(b.levels, [2, 2, 1]);
    });

    test('the dotted quarter is not beamed', () {
      expect(row.beams.any((b) => b.glyphs.contains(6)), isFalse);
      expect(row.glyphs[6].dotted, isTrue);
    });

    test('a slur from the first note to the third', () {
      final slurs = row.arcs.where((a) => !a.isTie).toList();
      expect(slurs.length, 1);
      expect(slurs.single.x1, row.glyphs[0].x);
      expect(slurs.single.x2, row.glyphs[2].x);
    });

    test('a tie joins a held note to the note before it', () {
      final hymn = MusicXmlParser.parseString(kHymn);
      final r = StaffLayout.build(SolfaBuilder.build(hymn, hymn.voices().first), width: 2000).rows.single;
      final ties = r.arcs.where((a) => a.isTie).toList();
      expect(ties.length, 1);
      expect(ties.single.x1, r.glyphs[4].x);
      expect(ties.single.x2, r.glyphs[5].x);
    });

    test('a tie across a row break is drawn in two halves', () {
      final hymn = MusicXmlParser.parseString(kHymn);
      // 100 px is so narrow that every note gets its own row, so the held
      // note (the 6th) starts a new row after the note it is tied to.
      final layout = StaffLayout.build(SolfaBuilder.build(hymn, hymn.voices().first), width: 100);
      expect(layout.rows.length, 7);
      final first = layout.rows[4].arcs.single, second = layout.rows[5].arcs.single;
      expect(first.isTie && second.isTie, isTrue);
      expect(first.x1, layout.rows[4].glyphs.single.x);
      expect(first.x2, 100); // runs to the end of the row
      expect(second.x1, layout.rows[5].headerWidth - 8); // picks up at the start
      expect(second.x2, layout.rows[5].glyphs.single.x);
    });
  });
}
