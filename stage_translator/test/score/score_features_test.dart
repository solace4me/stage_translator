// test/score/score_features_test.dart
// Repeats, the Curwen tonic sol-fa view and lyric hold lines.
// Run with:  flutter test test/score

import 'package:flutter_test/flutter_test.dart';
import 'package:stage_translator/core/solfege_engine.dart';
import 'package:stage_translator/score/curwen.dart';
import 'package:stage_translator/score/musicxml_parser.dart';
import 'package:stage_translator/score/score.dart';
import 'package:stage_translator/score/solfa.dart';
import 'package:stage_translator/score/staff_layout.dart';

import 'fixtures.dart';

void main() {
  group('play order', () {
    test('a plain repeat plays the section twice', () {
      expect(PlayOrder.of(const [MeasureFlow(), MeasureFlow(repeatEnd: true), MeasureFlow()]), [0, 1, 0, 1, 2]);
    });

    test('a repeat that starts mid-way goes back to its |: sign', () {
      expect(
          PlayOrder.of(const [MeasureFlow(), MeasureFlow(repeatStart: true), MeasureFlow(repeatEnd: true)]),
          [0, 1, 2, 1, 2]);
    });

    test('1st and 2nd endings', () {
      expect(
          PlayOrder.of(const [
            MeasureFlow(repeatStart: true),
            MeasureFlow(),
            MeasureFlow(endings: [1], endingGroup: 1, repeatEnd: true),
            MeasureFlow(endings: [2], endingGroup: 2),
            MeasureFlow(),
          ]),
          [0, 1, 2, 0, 1, 3, 4]);
    });

    test('played three times', () {
      expect(PlayOrder.of(const [MeasureFlow(repeatEnd: true, times: 3), MeasureFlow()]), [0, 0, 0, 1]);
    });

    test('D.C. al Fine', () {
      expect(PlayOrder.of(const [MeasureFlow(), MeasureFlow(fine: true), MeasureFlow(daCapo: true)]),
          [0, 1, 2, 0, 1]);
    });

    test('D.S. al Coda', () {
      expect(
          PlayOrder.of(const [
            MeasureFlow(),
            MeasureFlow(segno: true),
            MeasureFlow(toCoda: true),
            MeasureFlow(dalSegno: true),
            MeasureFlow(coda: true),
          ]),
          [0, 1, 2, 3, 1, 2, 4]);
    });
  });

  group('repeats in a file', () {
    final score = MusicXmlParser.parseString(kRepeatTune);

    test('repeat signs and endings are read', () {
      final m = score.parts.single.measures;
      expect(m[0].flow.repeatStart, isTrue);
      expect(m[1].flow.endings, [1]);
      expect(m[1].flow.repeatEnd, isTrue);
      expect(m[2].flow.endings, [2]);
      expect(m[3].flow.endings, isEmpty);
      expect(score.hasRepeats, isTrue);
    });

    test('following the repeats writes the music out in playing order', () {
      final played = score.withRepeatsFollowed();
      final notes = played.voices().single.notes;
      expect(notes.map((n) => '${n.pitch}'),
          ['C4', 'D4', 'E4', 'F4', 'G4', 'C4', 'D4', 'E4', 'F4', 'A4', 'C5']);
      expect(notes.map((n) => n.onset), [0, 1, 2, 3, 4, 8, 9, 10, 11, 12, 16]);
      expect(played.parts.single.measures.map((m) => m.index), [0, 1, 2, 3, 4]);
      expect(played.parts.single.measures.first.key?.fifths, 0);
      expect(played.hasRepeats, isFalse);
    });

    test('a score without repeats is returned unchanged', () {
      final hymn = MusicXmlParser.parseString(kHymn);
      expect(identical(hymn.withRepeatsFollowed(), hymn), isTrue);
    });
  });

  group('Curwen tonic sol-fa', () {
    test('letters keep your sharp and flat style', () {
      expect(CurwenBuilder.letter('do'), 'd');
      expect(CurwenBuilder.letter('fa#'), 'f#');
      expect(CurwenBuilder.letter('ti♭'), 't♭');
    });

    test('pulse length comes from the time signature', () {
      expect(CurwenBuilder.beatLength(const TimeSignature(4, 4)), 1);
      expect(CurwenBuilder.beatLength(const TimeSignature(3, 2)), 2);
      expect(CurwenBuilder.beatLength(const TimeSignature(6, 8)), 0.5);
    });

    test('four voices stacked, words after the alto, key change marked', () {
      final score = MusicXmlParser.parseString(kHymn);
      final c = CurwenBuilder.build(score, score.voices());
      expect(c.keyLabel, 'Doh is F');
      expect(c.timeLabel, '4/4');
      expect(c.voiceLabels, ['S', 'A', 'T', 'B']);
      expect(c.systems(200).single.toString().split('\n'), [
        '                     Doh is C',
        'S |d    :r  :m   :f# |d  :- :- :  ||',
        'A |s₁   :s₁ :d   :d  |s₁ :- :- :- ||',
        '  |Sing  a   ho-  ly |',
        'T |m    :f  :s   :l  |d  :- :- :- ||',
        'B |d    :-  :f₁  :-  |d₁ :- :- :- ||',
      ]);
    });

    test('verse 2 words', () {
      final score = MusicXmlParser.parseString(kHymn);
      final lines = CurwenBuilder.build(score, score.voices(), verse: 2).systems(200).single.toString().split('\n');
      expect(lines[3], '  |Praise  the  Lord  now |');
    });

    test('Doh = D changes the labels, not the sol-fa', () {
      final score = MusicXmlParser.parseString(kHymn);
      final c = CurwenBuilder.build(score, score.voices(), performanceDoh: NoteName.parse('D'));
      expect(c.keyLabel, 'Doh is D');
      expect(c.measures[1].keyChange, 'Doh is A');
      expect(c.measures[0].cells[0], ['d', 'r', 'm', 'f#']);
    });

    test('6/8: six pulses, half-pulse split, held notes and a rest', () {
      final tune = MusicXmlParser.parseString(kBeamTune);
      final c = CurwenBuilder.build(tune, tune.voices());
      expect(c.systems(200).single.toString(), "S |d :r :m :f :s :l |s :- :- :l.t :d' : ||");
    });

    test('long scores wrap into several systems', () {
      final score = MusicXmlParser.parseString(kHymn);
      final systems = CurwenBuilder.build(score, score.voices()).systems(30);
      expect(systems.length, 2);
    });

    test('quarter-beat splits: d,r.m and d.,r', () {
      const ref = CurwenOctaves(60);
      SolfaNote n(String syl, double onset, double dur) => SolfaNote(
            ScoreNote(
                pitch: const Pitch(NoteName(0, 0), 4),
                onset: onset,
                duration: dur,
                staff: 1,
                voice: '1',
                measureIndex: 0),
            const Pitch(NoteName(0, 0), 4),
            syl,
            doh: const NoteName(0, 0));
      expect(CurwenBuilder.cell([n('do', 0, 0.25), n('re', 0.25, 0.25), n('mi', 0.5, 0.5)], 0, 1, ref), 'd,r.m');
      expect(CurwenBuilder.cell([n('do', 0, 0.75), n('re', 0.75, 0.25)], 0, 1, ref), 'd.,r');
      expect(CurwenBuilder.cell([n('do', -1, 1.5), n('re', 0.5, 0.5)], 0, 1, ref), '-.r');
    });
  });

  group('lyric hold lines', () {
    test('a held syllable gets a line to its last note', () {
      final score = MusicXmlParser.parseString(kRepeatTune);
      final line = SolfaBuilder.build(score, score.voices().single);
      final row = StaffLayout.build(line, width: 3000).rows.single;
      expect(row.extenders.length, 1);
      final e = row.extenders.single;
      expect(e.verse, 1);
      expect(e.fromWord, isTrue);
      expect(e.x1, row.glyphs[0].x);
      expect(e.x2, row.glyphs[2].x);
    });
  });

  group('divided voices', () {
    test('a short divided passage keeps the voice as one line', () {
      final score = MusicXmlParser.parseString(kDivisiAlto);
      final voices = score.voices();
      expect(voices.length, 1);
      final line = SolfaBuilder.build(score, voices.single);
      expect(line.notes.map((n) => '${n.pitch}'), ['C4', 'D4', 'E4', 'F4', 'C4', 'D4']);
    });
  });
}
