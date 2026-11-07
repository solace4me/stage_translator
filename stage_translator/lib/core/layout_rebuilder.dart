// lib/core/layout_rebuilder.dart
//
// Pure Dart. Turns OCR word boxes back into a plain-text chord sheet:
//   1. finds a second column (gutter) if the sheet has one
//   2. reads each column top to bottom
//   3. merges words that sit on the same visual row
//   4. puts each word at the character column matching its x-position,
//      so chords land above the lyric words they belong to
//   5. keeps blank lines between sections
//
// It knows nothing about ML Kit: OcrService converts ML Kit's result into
// [OcrWord]s, which keeps this file easy to unit-test with fake boxes.

import 'dart:math' as math;

class OcrWord {
  final String text;
  final double left, top, right, bottom;

  const OcrWord(this.text, this.left, this.top, this.right, this.bottom);

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
}

/// One OCR line (a run of words ML Kit grouped together).
class OcrLine {
  final List<OcrWord> words;
  const OcrLine(this.words);

  double get left => words.map((w) => w.left).reduce(math.min);
  double get right => words.map((w) => w.right).reduce(math.max);
  double get top => words.map((w) => w.top).reduce(math.min);
  double get bottom => words.map((w) => w.bottom).reduce(math.max);
  double get centerY => (top + bottom) / 2;
  double get height => bottom - top;
}

class LayoutRebuilder {
  LayoutRebuilder._();

  static String rebuild(List<OcrLine> input) {
    final lines = input.where((l) => l.words.isNotEmpty).toList();
    if (lines.isEmpty) return '';

    final charWidth = _median(lines
        .expand((l) => l.words)
        .where((w) => w.text.isNotEmpty)
        .map((w) => w.width / w.text.length)
        .toList());
    final lineHeight = _median(lines.map((l) => l.height).toList());

    final split = _findGutter(lines, charWidth);
    if (split == null) {
      return _renderColumn(lines, charWidth, lineHeight);
    }

    // Lines that cross the gutter: a title or header above both columns.
    final crossing = lines.where((l) => l.left < split && l.right > split).toList();
    final leftCol = lines.where((l) => l.right <= split).toList();
    final rightCol = lines.where((l) => l.left >= split).toList();

    final firstColumnTop = [...leftCol, ...rightCol].map((l) => l.top).fold<double>(
          double.infinity,
          math.min,
        );
    final header = <OcrLine>[];
    for (final l in crossing) {
      if (l.bottom <= firstColumnTop + lineHeight * 0.5) {
        header.add(l);
      } else if (l.words.map((w) => w.centerX).reduce((a, b) => a + b) / l.words.length < split) {
        leftCol.add(l);
      } else {
        rightCol.add(l);
      }
    }

    final parts = <String>[
      if (header.isNotEmpty) _renderColumn(header, charWidth, lineHeight),
      if (leftCol.isNotEmpty) _renderColumn(leftCol, charWidth, lineHeight),
      if (rightCol.isNotEmpty) _renderColumn(rightCol, charWidth, lineHeight),
    ];
    return parts.join('\n\n');
  }

  /// Looks for a vertical band in the middle of the page that almost no line
  /// crosses. Returns its x, or null for a single-column sheet.
  static double? _findGutter(List<OcrLine> lines, double charWidth) {
    final minX = lines.map((l) => l.left).reduce(math.min);
    final maxX = lines.map((l) => l.right).reduce(math.max);
    final span = maxX - minX;
    if (span <= 0) return null;

    const bins = 100;
    final cover = List<int>.filled(bins, 0);
    for (final l in lines) {
      final a = ((l.left - minX) / span * (bins - 1)).floor();
      final b = ((l.right - minX) / span * (bins - 1)).ceil();
      for (var i = a; i <= b && i < bins; i++) {
        cover[i]++;
      }
    }

    // A gutter may be crossed by a few lines (a centred title, say).
    final allowed = (lines.length * 0.08).ceil();
    var bestStart = -1, bestLen = 0, runStart = -1;
    for (var i = 25; i <= 75; i++) {
      if (cover[i] <= allowed) {
        if (runStart < 0) runStart = i;
        final len = i - runStart + 1;
        if (len > bestLen) {
          bestLen = len;
          bestStart = runStart;
        }
      } else {
        runStart = -1;
      }
    }
    if (bestStart < 0) return null;

    final gapWidth = bestLen / bins * span;
    if (gapWidth < charWidth * 2) return null;
    final x = minX + (bestStart + bestLen / 2) / bins * span;

    final leftCount = lines.where((l) => l.right <= x).length;
    final rightCount = lines.where((l) => l.left >= x).length;
    if (leftCount < 3 || rightCount < 3) return null;
    return x;
  }

  static String _renderColumn(List<OcrLine> lines, double charWidth, double lineHeight) {
    final words = lines.expand((l) => l.words).toList()
      ..sort((a, b) => a.centerY.compareTo(b.centerY));
    final columnLeft = words.map((w) => w.left).reduce(math.min);

    // Group words into visual rows by vertical centre.
    final rows = <List<OcrWord>>[];
    for (final w in words) {
      if (rows.isNotEmpty) {
        final row = rows.last;
        final rowCenter = row.map((e) => e.centerY).reduce((a, b) => a + b) / row.length;
        if ((w.centerY - rowCenter).abs() < lineHeight * 0.5) {
          row.add(w);
          continue;
        }
      }
      rows.add([w]);
    }

    final out = <String>[];
    double? previousCenter;
    for (final row in rows) {
      row.sort((a, b) => a.left.compareTo(b.left));
      final center = row.map((e) => e.centerY).reduce((a, b) => a + b) / row.length;

      // A large vertical gap = a new section: keep one empty line.
      if (previousCenter != null && center - previousCenter > lineHeight * 2.4) {
        out.add('');
      }
      previousCenter = center;

      final buf = StringBuffer();
      for (final w in row) {
        final col = ((w.left - columnLeft) / charWidth).round();
        final minCol = buf.isEmpty ? 0 : buf.length + 1;
        buf.write(' ' * (math.max(col, minCol) - buf.length));
        buf.write(w.text);
      }
      out.add(buf.toString());
    }
    return out.join('\n');
  }

  static double _median(List<double> v) {
    if (v.isEmpty) return 1;
    v.sort();
    final m = v[v.length ~/ 2];
    return m <= 0 ? 1 : m;
  }
}
