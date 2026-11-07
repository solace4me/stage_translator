// test/layout_rebuilder_test.dart
// Fake OCR boxes: 10 px per character, 20 px line height.

import 'package:flutter_test/flutter_test.dart';
import 'package:stage_translator/core/layout_rebuilder.dart';

OcrLine line(double x, double y, String text) {
  final words = <OcrWord>[];
  var cx = x;
  for (final t in text.split(' ')) {
    if (t.isNotEmpty) words.add(OcrWord(t, cx, y, cx + 10.0 * t.length, y + 20));
    cx += 10.0 * (t.length + 1);
  }
  return OcrLine(words);
}

void main() {
  test('two columns are read one after the other, title first', () {
    final left = [
      line(300, 0, 'Title Song'),
      line(0, 40, 'VERSE 1'),
      line(60, 70, 'D'),
      line(0, 95, 'word one two'),
      line(80, 120, 'Bm'),
      line(0, 145, 'three four'),
      line(0, 240, 'CHORUS'),
      line(40, 270, 'G'),
      line(0, 295, 'five six seven'),
    ];
    final right = [
      line(520, 40, 'VERSE 3'),
      line(560, 70, 'A'),
      line(520, 95, 'eight nine'),
      line(540, 120, 'G'),
      line(520, 145, 'ten eleven'),
    ];
    // OCR returns blocks in any order: interleave them.
    final mixed = <OcrLine>[];
    for (var i = 0; i < left.length; i++) {
      mixed.add(left[i]);
      if (i < right.length) mixed.add(right[i]);
    }

    expect(
      LayoutRebuilder.rebuild(mixed),
      'Title Song\n'
      '\n'
      'VERSE 1\n'
      '      D\n'
      'word one two\n'
      '        Bm\n'
      'three four\n'
      '\n'
      'CHORUS\n'
      '    G\n'
      'five six seven\n'
      '\n'
      'VERSE 3\n'
      '    A\n'
      'eight nine\n'
      '  G\n'
      'ten eleven',
    );
  });

  test('a single column keeps chord positions', () {
    final out = LayoutRebuilder.rebuild([
      line(0, 0, 'D'),
      line(150, 0, 'Bm'),
      line(0, 25, 'some lyric words over here'),
    ]);
    expect(out, 'D              Bm\nsome lyric words over here');
  });
}
