// lib/score/curwen.dart
//
// Tonic sol-fa in Curwen notation, the way sol-fa hymn books print it:
//
//   Doh is F   4/4
//   S |d    :r  :m   :f# |d  :- :- :  ||
//   A |s₁   :s₁ :d   :d  |s₁ :- :- :- ||
//     |Sing  a   ho-  ly
//   T |m    :f  :s   :l  |d  :- :- :- ||
//   B |d    :-  :f₁  :-  |d₁ :- :- :- ||
//
//   |  bar line          :  between beats
//   .  splits a beat in half      ,  splits a half beat again
//   -  the note is held through this beat (also how ties show)
//   blank: a rest
//   '  ''   octave(s) up        ₁  ₂   octave(s) down
//
// The octave with no mark is chosen per voice so most of its notes need none.
// Pure Dart: tested without a phone.

import 'dart:math' as math;

import '../core/solfege_engine.dart';
import 'score.dart';
import 'solfa.dart';

class CurwenMeasure {
  final int index;

  /// cells[voice][beat]
  final List<List<String>> cells;

  /// Words for the chosen verse, one entry per beat.
  final List<String> words;

  /// "Doh is G" where the key changes (in the key you play in).
  final String? keyChange;

  const CurwenMeasure(this.index, this.cells, this.words, this.keyChange);

  int get beats => words.length;
}

class CurwenScore {
  /// "Doh is F" (the key you play in).
  final String keyLabel;
  final String? timeLabel;

  /// S, A, T, B (or the part names when the layout isn't SATB).
  final List<String> voiceLabels;
  final List<CurwenMeasure> measures;

  /// Words are printed under this voice (after alto in a SATB score).
  final int wordsAfterVoice;

  const CurwenScore({
    required this.keyLabel,
    required this.timeLabel,
    required this.voiceLabels,
    required this.measures,
    required this.wordsAfterVoice,
  });

  /// The score as text systems no wider than [maxChars] characters. Each
  /// system: an optional key-change line, then one line per voice, with the
  /// words line after [wordsAfterVoice]. Columns line up across voices.
  List<CurwenSystem> systems(int maxChars) {
    final label = voiceLabels.fold<int>(1, (w, l) => math.max(w, l.length)) + 1;
    final out = <CurwenSystem>[];
    var current = <CurwenMeasure>[];
    var width = label + 1;

    int measureWidth(CurwenMeasure m) {
      var w = 0;
      for (var b = 0; b < m.beats; b++) {
        w += _columnWidth(m, b) + 1; // "|" or ":"
      }
      return w;
    }

    void flush({required bool last}) {
      if (current.isEmpty) return;
      out.add(_render(current, label, last: last));
      current = [];
      width = label + 1;
    }

    for (var i = 0; i < measures.length; i++) {
      final m = measures[i];
      final w = measureWidth(m);
      if (current.isNotEmpty && width + w + 2 > maxChars) flush(last: false);
      current.add(m);
      width += w;
    }
    flush(last: true);
    return out;
  }

  int _columnWidth(CurwenMeasure m, int beat) {
    var w = m.words[beat].length;
    for (final v in m.cells) {
      if (beat < v.length) w = math.max(w, v[beat].length);
    }
    return w + 1;
  }

  CurwenSystem _render(List<CurwenMeasure> ms, int labelWidth, {required bool last}) {
    final voiceLines = [for (var v = 0; v < voiceLabels.length; v++) StringBuffer(voiceLabels[v].padRight(labelWidth))];
    final words = StringBuffer(''.padRight(labelWidth));
    final keys = StringBuffer(''.padRight(labelWidth));
    var hasKeyChange = false;

    for (final m in ms) {
      if (m.keyChange != null) {
        hasKeyChange = true;
        // Place the label above this measure's first bar line.
        while (keys.length < words.length) {
          keys.write(' ');
        }
        keys.write(m.keyChange);
      }
      for (var b = 0; b < m.beats; b++) {
        final sep = b == 0 ? '|' : ':';
        final w = _columnWidth(m, b);
        for (var v = 0; v < voiceLines.length; v++) {
          final cell = b < m.cells[v].length ? m.cells[v][b] : '';
          voiceLines[v].write(sep);
          voiceLines[v].write(cell.padRight(w));
        }
        words.write(b == 0 ? '|' : ' ');
        words.write(m.words[b].padRight(w));
      }
    }
    final end = last ? '||' : '|';
    for (final l in voiceLines) {
      l.write(end);
    }
    words.write(' ');

    final lines = <CurwenLine>[];
    if (hasKeyChange) lines.add(CurwenLine(keys.toString().trimRight(), CurwenLineKind.keyChange, -1));
    for (var v = 0; v < voiceLines.length; v++) {
      lines.add(CurwenLine(voiceLines[v].toString(), CurwenLineKind.voice, v));
      if (v == wordsAfterVoice && ms.any((m) => m.words.any((w) => w.isNotEmpty))) {
        lines.add(CurwenLine(words.toString().trimRight(), CurwenLineKind.words, -1));
      }
    }
    return CurwenSystem(lines);
  }
}

enum CurwenLineKind { voice, words, keyChange }

class CurwenLine {
  final String text;
  final CurwenLineKind kind;

  /// Voice index for voice lines, -1 otherwise.
  final int voice;
  const CurwenLine(this.text, this.kind, this.voice);
}

class CurwenSystem {
  final List<CurwenLine> lines;
  const CurwenSystem(this.lines);

  @override
  String toString() => lines.map((l) => l.text).join('\n');
}

class CurwenBuilder {
  CurwenBuilder._();

  /// Builds the sol-fa for [tracks] (usually all four of score.voices()).
  /// Syllables come from the written key; [performanceDoh] only changes the
  /// "Doh is ..." labels. Words are taken from the first track that has
  /// words for [verse].
  static CurwenScore build(
    Score score,
    List<VoiceTrack> tracks, {
    NoteName? performanceDoh,
    SolfaOptions options = const SolfaOptions(),
    int verse = 1,
    bool letters = true,
  }) {
    final lines = [
      for (final t in tracks) SolfaBuilder.build(score, t, performanceDoh: performanceDoh, options: options),
    ];
    final part = score.parts.first;
    final time = score.initialTime;

    // Words: the first voice that has them for this verse.
    var wordsVoice = 0;
    for (var v = 0; v < tracks.length; v++) {
      if (tracks[v].notes.any((n) => n.lyrics.containsKey(verse))) {
        wordsVoice = v;
        break;
      }
    }

    // Unmarked octave per voice, as hymn books do it: soprano and alto read
    // from the "do" around middle C, tenor and bass from the octave below.
    final reference = [
      for (var v = 0; v < lines.length; v++) _referenceDoh(lines[v], tracks[v].role),
    ];

    final byMeasure = [
      for (final l in lines)
        <int, List<SolfaNote>>{
          for (final n in l.notes) n.source.measureIndex: [],
        },
    ];
    for (var v = 0; v < lines.length; v++) {
      for (final n in lines[v].notes) {
        byMeasure[v][n.source.measureIndex]!.add(n);
      }
    }

    final target = lines.isEmpty ? null : lines.first.performanceDoh;
    final written = lines.isEmpty ? null : lines.first.writtenDoh;
    String perfName(int measureIndex) {
      final doh = score.keyAt(measureIndex).doh(laBasedMinor: options.laBasedMinor);
      if (target == null || written == null) return doh.toString();
      return SolfegeEngine.transposeNote(doh, written, target).toString();
    }

    final measures = <CurwenMeasure>[];
    String? previousKey;
    TimeSignature? currentTime = time;
    for (final m in part.measures) {
      if (m.time != null) currentTime = m.time;
      final beat = beatLength(currentTime);
      final length = m.length > 0 ? m.length : beat * (currentTime?.beats ?? 4);
      final beats = math.max(1, (length / beat - 1e-6).ceil());

      final cells = <List<String>>[];
      for (var v = 0; v < lines.length; v++) {
        cells.add([
          for (var b = 0; b < beats; b++)
            cell(_notesAround(lines[v].notes, m.start + b * beat, beat), m.start + b * beat, beat, reference[v],
                letters: letters),
        ]);
      }

      final words = <String>[
        for (var b = 0; b < beats; b++)
          _wordsIn(byMeasure[wordsVoice < lines.length ? wordsVoice : 0][m.index] ?? const [],
              m.start + b * beat, beat, verse),
      ];

      final key = perfName(m.index);
      final change = previousKey != null && key != previousKey ? 'Doh is $key' : null;
      previousKey = key;
      measures.add(CurwenMeasure(m.index, cells, words, change));
    }

    final labels = [
      for (final t in tracks)
        switch (t.role) {
          VoiceRole.soprano => 'S',
          VoiceRole.alto => 'A',
          VoiceRole.tenor => 'T',
          VoiceRole.bass => 'B',
          VoiceRole.other => t.label.split(' ').first,
        },
    ];

    return CurwenScore(
      keyLabel: 'Doh is ${perfName(0)}',
      timeLabel: time?.toString(),
      voiceLabels: labels,
      measures: measures,
      wordsAfterVoice: tracks.length >= 4 ? 1 : (tracks.isEmpty ? 0 : wordsVoice),
    );
  }

  /// Length of one Curwen pulse in quarter notes, from the time signature's
  /// lower number: a quarter in 4/4, a half in 3/2, an eighth in 6/8 (sol-fa
  /// writes 6/8 as six pulses to the bar).
  static double beatLength(TimeSignature? t) => t == null ? 1 : 4 / t.beatType;

  /// Notes that start in, or are still sounding at the start of, a beat.
  static List<SolfaNote> _notesAround(List<SolfaNote> all, double start, double len) {
    final out = <SolfaNote>[];
    for (final n in all) {
      final s = n.source.onset, e = s + n.source.duration;
      if (n.source.isGrace) continue;
      if (e > start + 1e-6 && s < start + len - 1e-6) out.add(n);
    }
    return out;
  }

  /// One beat as Curwen text, e.g. "d", "d.r", "d,r.m,f", "-", "-.r", "d.,r".
  static String cell(List<SolfaNote> notes, double start, double len, CurwenOctaves ref, {bool letters = true}) {
    // Four quarter-of-a-beat slots: 0 = nothing, 1 = a note or rest starts,
    // 2 = a note is still sounding from before.
    final kind = List<int>.filled(4, 0);
    final text = List<String>.filled(4, '');
    final slot = len / 4;
    for (final n in notes) {
      final s = n.source.onset;
      if (s < start - 1e-6 || n.isTieContinuation) {
        // Sounding from before this beat (or tied over): held.
        if (!n.isRest) {
          final from = n.isTieContinuation && s >= start - 1e-6
              ? ((s - start) / slot).round().clamp(0, 3)
              : 0;
          if (kind[from] == 0) kind[from] = 2;
        }
        continue;
      }
      final i = ((s - start) / slot).round().clamp(0, 3);
      kind[i] = 1;
      text[i] = n.isRest ? '' : '${letters ? letter(n.syllable!) : n.syllable}${ref.mark(n)}';
    }
    final first = kind[0] == 1 ? text[0] : (kind[0] == 2 ? '-' : '');
    final halfA = kind[1] == 1 ? '$first,${text[1]}' : first;
    final hasB = kind[2] == 1 || kind[3] == 1;
    if (!hasB) return halfA;
    final b0 = kind[2] == 1 ? text[2] : '';
    final halfB = kind[3] == 1 ? '$b0,${text[3]}' : b0;
    return '$halfA.$halfB';
  }

  /// "do" -> "d", "fa#" -> "f#", "ti♭" -> "t♭": the one-letter names sol-fa
  /// books use, keeping your sharp/flat style.
  static String letter(String syllable) {
    final base = RegExp(r'^[a-z]+').firstMatch(syllable)?.group(0) ?? '';
    if (base.isEmpty) return syllable;
    return '${base[0]}${syllable.substring(base.length)}';
  }

  static String _wordsIn(List<SolfaNote> notes, double start, double len, int verse) {
    final parts = <String>[];
    for (final n in notes) {
      final s = n.source.onset;
      if (s < start - 1e-6 || s >= start + len - 1e-6) continue;
      final l = n.lyric(verse);
      if (l != null && l.text.isNotEmpty) parts.add(l.displayText);
    }
    return parts.join(' ');
  }

  static CurwenOctaves _referenceDoh(SolfaLine line, VoiceRole role) {
    final pitched = line.notes.where((n) => n.source.pitch != null && n.doh != null).toList();
    if (pitched.isEmpty) return const CurwenOctaves(60);
    final doh = pitched.first.doh!;
    switch (role) {
      case VoiceRole.soprano || VoiceRole.alto:
        return CurwenOctaves(Pitch(doh, 4).midi);
      case VoiceRole.tenor || VoiceRole.bass:
        return CurwenOctaves(Pitch(doh, 3).midi);
      case VoiceRole.other:
        break;
    }
    // Other lines: the "do" that leaves the most notes unmarked.
    var best = 4, bestCount = -1;
    for (var octave = 1; octave <= 6; octave++) {
      final ref = Pitch(doh, octave).midi;
      final count = pitched.where((n) {
        final d = n.source.pitch!.midi - ref;
        return d >= 0 && d < 12;
      }).length;
      if (count > bestCount) {
        best = octave;
        bestCount = count;
      }
    }
    return CurwenOctaves(Pitch(doh, best).midi);
  }
}

/// Where the unmarked octave starts for one voice, and the octave marks.
class CurwenOctaves {
  final int dohMidi;
  const CurwenOctaves(this.dohMidi);

  /// "", "'", "''", "₁", "₂" for a note, measured from its own "do". After a
  /// key change the new "do" is placed inside the same unmarked octave, so
  /// the marks don't jump around.
  String mark(SolfaNote n) {
    final p = n.source.pitch;
    final doh = n.doh;
    if (p == null || doh == null) return '';
    final ref = dohMidi + (doh.semitone - dohMidi) % 12;
    final octave = ((p.midi - ref) / 12).floor();
    return switch (octave) {
      0 => '',
      1 => "'",
      2 => "''",
      -1 => '₁', // ₁
      -2 => '₂', // ₂
      _ => octave > 0 ? "'" * octave : '₂',
    };
  }
}
