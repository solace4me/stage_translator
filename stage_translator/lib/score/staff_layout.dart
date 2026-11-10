// lib/score/staff_layout.dart
//
// Pure-Dart layout for the single-staff view: works out where every note,
// accidental, bar line, key signature, beam, tie and slur goes, row by row,
// for a given screen width. The Flutter painter (ui/staff_painter.dart)
// only draws what this returns, so the maths is unit-tested without a phone.
//
// Units: x in logical pixels; vertical positions in staff "steps", where
// 0 = bottom line, 2 = second line ... 8 = top line, odd numbers = spaces.

import 'dart:math' as math;

import '../core/solfege_engine.dart';
import 'score.dart';
import 'solfa.dart';

enum Clef { treble, bass }

enum NoteValue { whole, half, quarter, eighth, sixteenth }

class StaffGlyph {
  final SolfaNote note;
  final double x;

  /// Staff step of the note head (null for rests).
  final int? step;

  /// "#", "♭", "♮", "##", "♭♭" or null when the key signature covers it.
  final String? accidental;
  final NoteValue value;
  final bool dotted;

  /// Stem direction; for beamed notes this is the whole group's direction.
  final bool stemUp;

  /// Steps of the ledger lines this note needs (e.g. -2 for middle C in treble).
  final List<int> ledgerSteps;

  const StaffGlyph({
    required this.note,
    required this.x,
    required this.step,
    required this.accidental,
    required this.value,
    required this.dotted,
    required this.stemUp,
    required this.ledgerSteps,
  });

  StaffGlyph withStem(bool up) => StaffGlyph(
        note: note,
        x: x,
        step: step,
        accidental: accidental,
        value: value,
        dotted: dotted,
        stemUp: up,
        ledgerSteps: ledgerSteps,
      );
}

/// A key change printed inside a row, after a double bar line: naturals
/// cancelling the old signature (when needed), then the new one.
class KeyChangeMark {
  final double x;
  final int fifths;
  final List<int> steps;
  final List<int> cancelSteps;
  const KeyChangeMark(this.x, this.fifths, this.steps, [this.cancelSteps = const []]);
}

/// Notes joined by a beam: indices into the row's glyph list.
class BeamGroup {
  final List<int> glyphs;
  final bool stemUp;

  /// 1 or 2 beams per note (2 = sixteenth).
  final List<int> levels;
  const BeamGroup(this.glyphs, this.stemUp, this.levels);
}

/// A tie or slur inside one row. A curve that crosses a row break is split
/// into two halves: one running to the row's end, one from its start.
class ArcSpan {
  final double x1, x2;
  final int step1, step2;
  final bool above;
  final bool isTie;
  const ArcSpan(this.x1, this.step1, this.x2, this.step2, {required this.above, required this.isTie});
}

/// The line under a syllable that is held over several notes (a melisma).
/// [fromWord] is true on the row where the syllable is printed: the line
/// then starts after the word, otherwise right at [x1].
class LyricExtender {
  final int verse;
  final double x1, x2;
  final bool fromWord;
  const LyricExtender(this.verse, this.x1, this.x2, {required this.fromWord});
}

class StaffRow {
  final List<StaffGlyph> glyphs;

  /// x of each bar line at the end of a measure in this row.
  final List<double> barlines;

  /// Width of the clef + key signature (+ time signature) block.
  final double headerWidth;

  /// Key signature printed at the start of this row.
  final int startFifths;
  final List<int> startKeySteps;

  /// Print the time signature in this row's header (first row only).
  final bool showTime;

  final List<KeyChangeMark> keyChanges;
  final List<BeamGroup> beams;
  final List<ArcSpan> arcs;
  final List<LyricExtender> extenders;

  /// Right end of the staff lines.
  final double endX;

  const StaffRow({
    required this.glyphs,
    required this.barlines,
    required this.headerWidth,
    required this.startFifths,
    required this.startKeySteps,
    required this.showTime,
    required this.keyChanges,
    required this.beams,
    required this.arcs,
    this.extenders = const [],
    required this.endX,
  });
}

class StaffLayoutResult {
  final Clef clef;
  final TimeSignature? time;
  final List<StaffRow> rows;

  const StaffLayoutResult(this.clef, this.time, this.rows);

  /// Key signature of the first row (kept for callers of the first version).
  int get fifths => rows.isEmpty ? 0 : rows.first.startFifths;
  List<int> get keySignatureSteps => rows.isEmpty ? const [] : rows.first.startKeySteps;
}

/// Working state for one row while it is being filled.
class _RowBuilder {
  final List<_Placed> placed = [];
  final List<double> barlines = [];
  final List<KeyChangeMark> keyChanges = [];
  final double headerWidth;
  final int startFifths;
  final bool showTime;
  _RowBuilder(this.headerWidth, this.startFifths, this.showTime);
}

class _Placed {
  final StaffGlyph glyph;
  final int row;
  final int indexInRow;
  _Placed(this.glyph, this.row, this.indexInRow);
}

class StaffLayout {
  StaffLayout._();

  static StaffLayoutResult build(
    SolfaLine line, {
    required double width,
    double minNoteSpacing = 40,
    double charWidth = 9,
    int verseForSpacing = 0, // 0 = make room for the longest word of any verse
  }) {
    final clef = clefFor(line);

    double header(int fifths, bool showTime) => 36.0 + fifths.abs() * 11.0 + 8 + (showTime ? 22 : 0);
    // Naturals are shown when the new key drops to no accidentals or swaps
    // sharps for flats (e.g. F major to C major, or D major to F major).
    List<int> cancelFor(int from, int to, Clef c) =>
        (from != 0 && (to == 0 || from.sign != to.sign)) ? keySignatureSteps(from, c) : const [];
    double keyChangeWidth(int from, int to) =>
        14.0 + (cancelFor(from, to, clef).length + to.abs()) * 11.0 + 6;

    double noteWidth(SolfaNote n) {
      var chars = (n.syllable ?? '').length;
      for (final l in n.source.lyrics.values) {
        if (verseForSpacing == 0 || l.verse == verseForSpacing) {
          chars = math.max(chars, l.displayText.length);
        }
      }
      // Longer notes get a little more room, like printed music. A held
      // (tied) note gets the same room, so the tie has space to show.
      final durationBonus = math.min(n.source.duration, 4.0) * 6;
      const accidentalRoom = 6.0;
      return math.max(minNoteSpacing + durationBonus, chars * charWidth + 12) + accidentalRoom;
    }

    // Group notes into measures, in order.
    final measures = <int, List<SolfaNote>>{};
    for (final n in line.notes) {
      measures.putIfAbsent(n.source.measureIndex, () => []).add(n);
    }
    final measureOrder = measures.keys.toList()..sort();

    final rows = <_RowBuilder>[];
    final placed = <_Placed>[];
    final firstFifths = line.notes.isEmpty ? 0 : line.notes.first.keyFifths;
    final showTime = line.time != null;
    var current = _RowBuilder(header(firstFifths, showTime), firstFifths, showTime);
    rows.add(current);
    var x = current.headerWidth;
    var fifths = firstFifths;

    void newRow() {
      current = _RowBuilder(header(fifths, false), fifths, false);
      rows.add(current);
      x = current.headerWidth;
    }

    void place(StaffGlyph g) {
      final p = _Placed(g, rows.length - 1, current.placed.length);
      current.placed.add(p);
      placed.add(p);
    }

    for (final mIndex in measureOrder) {
      final notes = measures[mIndex]!;
      final measureFifths = notes.first.keyFifths;
      final changesKey = measureFifths != fifths;
      final oldFifths = fifths;
      final measureWidth = notes.fold<double>(0, (w, n) => w + noteWidth(n)) +
          12 +
          (changesKey ? keyChangeWidth(oldFifths, measureFifths) : 0);
      if (current.placed.isNotEmpty && x + measureWidth > width) {
        fifths = measureFifths; // the new row's header shows the new key
        newRow();
      } else if (changesKey) {
        fifths = measureFifths;
        if (current.placed.isEmpty) {
          // Nothing drawn in this row yet: show the new key in its header.
          final keepTime = current.showTime;
          rows.removeLast();
          current = _RowBuilder(header(fifths, keepTime), fifths, keepTime);
          rows.add(current);
          x = current.headerWidth;
        } else {
          final previous = current.keyChanges.isEmpty ? current.startFifths : current.keyChanges.last.fifths;
          current.keyChanges.add(KeyChangeMark(
              x + 4, fifths, keySignatureSteps(fifths, clef), cancelFor(previous, fifths, clef)));
          x += keyChangeWidth(previous, fifths);
        }
      }

      final keyAlters = keyAlterations(fifths);
      final shown = <String, int>{}; // accidentals already in force this bar

      for (final n in notes) {
        final w = noteWidth(n);
        if (current.placed.isNotEmpty && x + w > width) {
          newRow(); // a measure too long for one row breaks between notes
        }
        int? step;
        String? accidental;
        var ledgers = const <int>[];
        var stemUp = true;
        final p = n.pitch;
        if (p != null) {
          step = stepOf(p, clef);
          final id = '${p.name.letter}/${p.octave}';
          final expected = shown[id] ?? keyAlters[p.name.letter];
          if (p.name.alter != expected && !n.isTieContinuation) {
            accidental = accidentalSign(p.name.alter);
          }
          shown[id] = p.name.alter;
          ledgers = ledgerStepsFor(step);
          stemUp = step < 4;
        }
        place(StaffGlyph(
          note: n,
          x: x + w / 2,
          step: step,
          accidental: accidental,
          value: valueOf(n.source.duration),
          dotted: isDotted(n.source.duration),
          stemUp: stemUp,
          ledgerSteps: ledgers,
        ));
        x += w;
      }
      x += 12;
      current.barlines.add(x - 6);
    }

    // ---- Beams: per row, eighths and shorter inside the same beat.
    final rowGlyphs = [for (final r in rows) r.placed.map((p) => p.glyph).toList()];
    final rowBeams = [for (var i = 0; i < rows.length; i++) <BeamGroup>[]];
    for (var r = 0; r < rows.length; r++) {
      final glyphs = rowGlyphs[r];
      var group = <int>[];
      void flush() {
        if (group.length >= 2) {
          final avg = group.map((i) => glyphs[i].step!).reduce((a, b) => a + b) / group.length;
          final up = avg < 4;
          for (final i in group) {
            glyphs[i] = glyphs[i].withStem(up);
          }
          rowBeams[r].add(BeamGroup(List.of(group), up,
              [for (final i in group) glyphs[i].value == NoteValue.sixteenth ? 2 : 1]));
        }
        group = [];
      }

      for (var i = 0; i < glyphs.length; i++) {
        final g = glyphs[i];
        final beamable = g.step != null &&
            !g.note.source.isGrace &&
            (g.value == NoteValue.eighth || g.value == NoteValue.sixteenth);
        if (!beamable) {
          flush();
          continue;
        }
        if (group.isNotEmpty) {
          final prev = glyphs[group.last];
          final sameMeasure = prev.note.source.measureIndex == g.note.source.measureIndex;
          if (!sameMeasure || beatOf(prev.note, line.beatLength) != beatOf(g.note, line.beatLength)) {
            flush();
          }
        }
        group.add(i);
      }
      flush();
    }

    // ---- Ties and slurs, split across row breaks.
    final rowEnds = [
      for (final r in rows) r.barlines.isEmpty ? width : r.barlines.last,
    ];
    final rowArcs = [for (var i = 0; i < rows.length; i++) <ArcSpan>[]];
    void addArc(_Placed a, _Placed b, {required bool isTie}) {
      final ga = rowGlyphs[a.row][a.indexInRow], gb = rowGlyphs[b.row][b.indexInRow];
      if (ga.step == null || gb.step == null) return;
      final above = !ga.stemUp; // curve on the side away from the stems
      if (a.row == b.row) {
        rowArcs[a.row].add(ArcSpan(ga.x, ga.step!, gb.x, gb.step!, above: above, isTie: isTie));
      } else {
        rowArcs[a.row].add(ArcSpan(ga.x, ga.step!, rowEnds[a.row], ga.step!, above: above, isTie: isTie));
        rowArcs[b.row].add(
            ArcSpan(rows[b.row].headerWidth - 8, gb.step!, gb.x, gb.step!, above: above, isTie: isTie));
      }
    }

    _Placed? previousPitched;
    final openSlurs = <int, _Placed>{};
    for (final p in placed) {
      final n = p.glyph.note;
      if (n.isTieContinuation && previousPitched != null) addArc(previousPitched, p, isTie: true);
      for (final s in n.source.slurStops) {
        final start = openSlurs.remove(s);
        if (start != null && start != p) addArc(start, p, isTie: false);
      }
      for (final s in n.source.slurStarts) {
        openSlurs[s] = p;
      }
      if (n.pitch != null) previousPitched = p;
    }

    // ---- Lyric hold lines: from a syllable marked "extend" to the last note
    // it is sung on (the notes after it that carry no syllable of their own).
    final rowExt = [for (var i = 0; i < rows.length; i++) <LyricExtender>[]];
    final verses = <int>{for (final p in placed) ...p.glyph.note.source.lyrics.keys};
    for (final verse in verses) {
      for (var i = 0; i < placed.length; i++) {
        final l = placed[i].glyph.note.source.lyrics[verse];
        if (l == null || !l.extend) continue;
        var last = i;
        for (var j = i + 1; j < placed.length; j++) {
          final n = placed[j].glyph.note;
          if (n.source.lyrics.containsKey(verse) || n.pitch == null) break;
          last = j;
        }
        if (last == i) continue;
        final a = placed[i], b = placed[last];
        for (var r = a.row; r <= b.row; r++) {
          final x1 = r == a.row ? rowGlyphs[a.row][a.indexInRow].x : rows[r].headerWidth - 8;
          final x2 = r == b.row ? rowGlyphs[b.row][b.indexInRow].x : rowEnds[r];
          rowExt[r].add(LyricExtender(verse, x1, x2, fromWord: r == a.row));
        }
      }
    }

    return StaffLayoutResult(clef, line.time, [
      for (var r = 0; r < rows.length; r++)
        StaffRow(
          glyphs: rowGlyphs[r],
          barlines: rows[r].barlines,
          headerWidth: rows[r].headerWidth,
          startFifths: rows[r].startFifths,
          startKeySteps: keySignatureSteps(rows[r].startFifths, clef),
          showTime: rows[r].showTime,
          keyChanges: rows[r].keyChanges,
          beams: rowBeams[r],
          arcs: rowArcs[r],
          extenders: rowExt[r],
          endX: rowEnds[r],
        ),
    ]);
  }

  // -------------------------------------------------------------- pieces

  /// Which beat of its bar a note starts on, for beaming.
  static int beatOf(SolfaNote n, double beatLength) =>
      ((n.source.onset - n.source.measureOnset + 1e-6) / beatLength).floor();

  /// Treble for lines that mostly sit at or above A3, bass otherwise.
  static Clef clefFor(SolfaLine line) {
    final pitched = line.notes.where((n) => n.pitch != null).toList();
    if (pitched.isEmpty) return Clef.treble;
    final avg = pitched.map((n) => n.pitch!.midi).reduce((a, b) => a + b) / pitched.length;
    return avg >= 57 ? Clef.treble : Clef.bass;
  }

  /// 0 = bottom line. Treble bottom line E4, bass bottom line G2.
  static int stepOf(Pitch p, Clef clef) {
    final diatonic = p.octave * 7 + p.name.letter;
    return diatonic - (clef == Clef.treble ? 4 * 7 + 2 : 2 * 7 + 4);
  }

  static List<int> ledgerStepsFor(int step) => [
        for (var s = -2; s >= step; s -= 2) s,
        for (var s = 10; s <= step; s += 2) s,
      ];

  static NoteValue valueOf(double quarters) {
    if (quarters >= 4) return NoteValue.whole;
    if (quarters >= 2) return NoteValue.half;
    if (quarters >= 1) return NoteValue.quarter;
    if (quarters >= 0.5) return NoteValue.eighth;
    return NoteValue.sixteenth;
  }

  static bool isDotted(double quarters) {
    const dottedLengths = [6.0, 3.0, 1.5, 0.75];
    return dottedLengths.any((d) => (quarters - d).abs() < 0.01);
  }

  static String? accidentalSign(int alter) => switch (alter) {
        2 => '##',
        1 => '#',
        0 => '♮', // ♮
        -1 => '♭', // ♭
        -2 => '♭♭',
        _ => null,
      };

  /// Sharps or flats in a major key signature: G = 1, F = -1, Db = -5.
  static int fifthsOf(NoteName doh) => KeySignature.fifthsOfMajor(doh);

  /// Alteration of each letter (C..B) under a key signature.
  static List<int> keyAlterations(int fifths) {
    final alters = List<int>.filled(7, 0);
    const sharpOrder = [3, 0, 4, 1, 5, 2, 6]; // F C G D A E B
    const flatOrder = [6, 2, 5, 1, 4, 0, 3]; // B E A D G C F
    for (var i = 0; i < fifths.abs() && i < 7; i++) {
      if (fifths > 0) alters[sharpOrder[i]] = 1;
      if (fifths < 0) alters[flatOrder[i]] = -1;
    }
    return alters;
  }

  /// Where key-signature symbols sit, in the standard printed pattern.
  static List<int> keySignatureSteps(int fifths, Clef clef) {
    const sharps = [8, 5, 9, 6, 3, 7, 4]; // treble: F5 C5 G5 D5 A4 E5 B4
    const flats = [4, 7, 3, 6, 2, 5, 1]; // treble: B4 E5 A4 D5 G4 C5 F4
    final shift = clef == Clef.treble ? 0 : -2;
    final src = fifths > 0 ? sharps : flats;
    return [for (var i = 0; i < fifths.abs() && i < 7; i++) src[i] + shift];
  }
}
