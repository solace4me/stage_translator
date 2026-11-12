// test/solfege_engine_test.dart
// Run with:  flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:stage_translator/core/solfege_engine.dart';

NoteName k(String s) => NoteName.parse(s);

String one(String chord, String sheetKey, String perfKey,
        {TranslateOptions options = const TranslateOptions()}) =>
    SolfegeEngine.process(chord, sheetKey: k(sheetKey), performanceKey: k(perfKey), options: options);

void main() {
  group('labels in the performance key', () {
    test('F# examples from the brief', () {
      expect(one('F#', 'F#', 'F#'), 'F# [do]');
      expect(one('D#m', 'F#', 'F#'), 'D#m [la]');
      expect(one('B', 'F#', 'F#'), 'B [fa]');
      expect(one('C#', 'F#', 'F#'), 'C# [so]');
    });

    test('D examples from the brief', () {
      expect(one('D', 'D', 'D'), 'D [do]');
      expect(one('Bm', 'D', 'D'), 'Bm [la]');
      expect(one('G', 'D', 'D'), 'G [fa]');
      expect(one('A', 'D', 'D'), 'A [so]');
    });

    test('regression: sharp roots are not cut to the letter', () {
      expect(one('F#m', 'D', 'D'), 'F#m [mi]');
      expect(one('C#dim', 'D', 'D'), 'C#dim [ti]');
    });
  });

  group('transposing to the performance key', () {
    test('sheet in D, Doh = F#', () {
      expect(one('D', 'D', 'F#'), 'F# [do]');
      expect(one('Bm', 'D', 'F#'), 'D#m [la]');
      expect(one('G', 'D', 'F#'), 'B [fa]');
      expect(one('A', 'D', 'F#'), 'C# [so]');
    });

    test('sheet in D, Doh = C', () {
      expect(one('Bm', 'D', 'C'), 'Am [la]');
      expect(one('G/B', 'D', 'C'), 'F/A [fa/la]');
    });

    test('keep original letters', () {
      const keep = TranslateOptions(transposeLetters: false);
      expect(one('D', 'D', 'C', options: keep), 'D [re]');
    });

    test('every key gives the same syllables', () {
      for (final key in kKeyChoices) {
        expect(one('Bm', 'D', key), endsWith('[la]'), reason: key);
        expect(one('G', 'D', key), endsWith('[fa]'), reason: key);
      }
    });
  });

  group('sharps and flats on the syllable', () {
    test('raised degrees take #', () {
      expect(one('C#', 'C', 'C'), 'C# [do#]');
      expect(one('D#', 'C', 'C'), 'D# [re#]');
      expect(one('F#', 'C', 'C'), 'F# [fa#]');
      expect(one('G#', 'C', 'C'), 'G# [so#]');
      expect(one('A#', 'C', 'C'), 'A# [la#]');
    });

    test('lowered degrees take ♭', () {
      expect(one('Db', 'C', 'C'), 'Db [re♭]');
      expect(one('Eb', 'C', 'C'), 'Eb [mi♭]');
      expect(one('Gb', 'C', 'C'), 'Gb [so♭]');
      expect(one('Ab', 'C', 'C'), 'Ab [la♭]');
      expect(one('Bb', 'C', 'C'), 'Bb [ti♭]');
      expect(one('C', 'D', 'D'), 'C [ti♭]');
    });

    test('rare spellings that had no name before', () {
      expect(one('E#', 'C', 'C'), 'E# [mi#]');
      expect(one('Fb', 'C', 'C'), 'Fb [fa♭]');
    });

    test('slash chords and quality keep the accidental', () {
      expect(one('Bb/D', 'C', 'C'), 'Bb/D [ti♭/re]');
      expect(one('F#m7', 'C', 'C', options: const TranslateOptions(showQuality: true)),
          'F#m7 [fa# minor7]');
    });

    test('labels with accidentals are stripped and rebuilt', () {
      const sheet = 'C   Bb   F#\nsome words';
      final once = SolfegeEngine.process(sheet, sheetKey: k('C'), performanceKey: k('C'));
      expect(once.split('\n').first, 'C [do] Bb [ti♭] F# [fa#]');
      expect(SolfegeEngine.process(once, sheetKey: k('C'), performanceKey: k('C')), once);
      expect(SolfegeEngine.stripLabels(once).split('\n').first.trimRight(), startsWith('C '));
    });
  });

  group('chord quality', () {
    const q = TranslateOptions(showQuality: true);
    test('minor and sevenths', () {
      expect(one('Bm', 'D', 'D', options: q), 'Bm [la minor]');
      expect(one('A7', 'D', 'D', options: q), 'A7 [so 7]');
      expect(one('Gmaj7', 'D', 'D', options: q), 'Gmaj7 [fa maj7]');
    });
  });

  group('sheet layout', () {
    const sheet = 'INTRO     D    Bm    A    G\n'
        '     D              Bm\n'
        'Some lyric words here and more\n'
        'A word at the start of a lyric\n'
        'G        Bm - A   *D To Bridge\n'
        '(G)  |Bm|  A\n'
        'BRIDGE 1\n'
        'Am I the one';

    final out = SolfegeEngine.process(sheet, sheetKey: k('D'), performanceKey: k('D')).split('\n');

    test('chord lines are labelled, section names left alone', () {
      expect(out[0], 'INTRO     D [do] Bm [la] A [so] G [fa]');
      expect(out[4], 'G [fa]   Bm [la] - A [so] *D [do] To Bridge');
      expect(out[5], '(G) [fa] |Bm| [la] A [so]');
      expect(out[6], 'BRIDGE 1');
    });

    test('chords keep their columns when there is room', () {
      expect(out[1].indexOf('Bm'), 20);
    });

    test('lyric lines are never touched', () {
      expect(out[2], 'Some lyric words here and more');
      expect(out[3], 'A word at the start of a lyric');
      expect(out[7], 'Am I the one');
    });

    test('inline chords', () {
      expect(one('[D]Some lyric [Bm]more', 'D', 'D'), '[D [do]]Some lyric [Bm [la]]more');
    });

    test('re-translating a translated sheet is stable', () {
      final once = out.join('\n');
      final twice = SolfegeEngine.process(once, sheetKey: k('D'), performanceKey: k('D'));
      expect(twice, once);
    });

    test('key change keeps hand edits', () {
      final edited = '${out.join('\n')}\n(my note: repeat x2)';
      final moved = SolfegeEngine.process(edited, sheetKey: k('D'), performanceKey: k('C'));
      expect(moved, contains('Am [la]'));
      expect(moved, endsWith('(my note: repeat x2)'));
    });
  });

  group('key detection', () {
    test('Gratitude-style progression is in D', () {
      expect(SolfegeEngine.detectKey('D  Bm  A  G\nwords\nG  Bm  A  D').toString(), 'D');
    });
    test('flat keys are spelled with flats', () {
      expect(SolfegeEngine.detectKey('Bb  Gm  Eb  F\nBb').toString(), 'Bb');
    });
    test('no chords -> null', () {
      expect(SolfegeEngine.detectKey('just some words'), isNull);
    });
  });

  group('numbers instead of sol-fa', () {
    const nums = TranslateOptions(notation: LabelNotation.numbers);

    test('scale degrees, with sharps and flats in front', () {
      expect(one('D', 'D', 'D', options: nums), 'D [1]');
      expect(one('Bm', 'D', 'D', options: nums), 'Bm [6]');
      expect(one('G', 'D', 'D', options: nums), 'G [4]');
      expect(one('A', 'D', 'D', options: nums), 'A [5]');
      expect(one('C', 'D', 'D', options: nums), 'C [\u266D7]');
      expect(one('F#', 'C', 'C', options: nums), 'F# [#4]');
      expect(one('G/B', 'D', 'D', options: nums), 'G/B [4/6]');
    });

    test('transposing and chord quality work the same', () {
      expect(one('Bm', 'D', 'F#', options: nums), 'D#m [6]');
      expect(one('Bm', 'D', 'D', options: const TranslateOptions(notation: LabelNotation.numbers, showQuality: true)),
          'Bm [6 minor]');
    });

    test('switching between sol-fa and numbers keeps the sheet', () {
      const sheet = 'D    Bm   G\nAll my words';
      final solfa = SolfegeEngine.process(sheet, sheetKey: k('D'), performanceKey: k('D'));
      final numbers = SolfegeEngine.process(solfa, sheetKey: k('D'), performanceKey: k('D'), options: nums);
      expect(numbers.split('\n').first, 'D [1]  Bm [6]  G [4]');
      expect(SolfegeEngine.process(numbers, sheetKey: k('D'), performanceKey: k('D')), solfa);
      expect(SolfegeEngine.process(numbers, sheetKey: k('D'), performanceKey: k('D'), options: nums), numbers);
    });

    test('a verse number in the lyrics is never taken for a label', () {
      const sheet = '[1] Amazing grace\nverse [2] here';
      expect(SolfegeEngine.stripLabels(sheet), sheet);
    });

    test('inline chords', () {
      expect(one('[D]Some lyric [Bm]more', 'D', 'D', options: nums), '[D [1]]Some lyric [Bm [6]]more');
      expect(SolfegeEngine.stripLabels('[D [1]]Some lyric'), '[D]Some lyric');
    });
  });
}
