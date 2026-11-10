// lib/score/solfa.dart
//
// Solfège for staff notation, built on the v1 SolfegeEngine:
//   * each note's syllable comes from the key the music is WRITTEN in at that
//     bar (F major, 1 flat -> F = do), with your # / ♭ spelling (B natural in
//     F = fa#)
//   * transposing to a performance key moves the letters only; the syllables
//     never change
//   * key changes inside the piece can either reset do (tonic sol-fa
//     "modulation") or keep the opening do and show accidentals.

import '../core/solfege_engine.dart';
import 'score.dart';

class SolfaOptions {
  /// Minor keys read from la (D minor: F = do). Off: D minor uses D = do.
  final bool laBasedMinor;

  /// Reset do at written key changes. Off: keep the first key's do throughout.
  final bool followKeyChanges;

  const SolfaOptions({this.laBasedMinor = true, this.followKeyChanges = true});
}

/// One note of a voice line, ready to display.
class SolfaNote {
  final ScoreNote source;

  /// The pitch to show: transposed into the performance key when asked.
  final Pitch? pitch;

  /// "do", "fa#", "ti♭" ...; null for rests.
  final String? syllable;

  /// True for the first note after a tie: the note is held, not re-sung.
  final bool isTieContinuation;

  /// Key signature (sharps > 0, flats < 0) in effect at this note, in the
  /// key you are playing in. Changes where the written key changes.
  final int keyFifths;

  /// The written "do" this note was named from (changes at modulations).
  final NoteName? doh;

  const SolfaNote(this.source, this.pitch, this.syllable,
      {this.isTieContinuation = false, this.keyFifths = 0, this.doh});

  bool get isRest => source.isRest;
  Lyric? lyric(int verse) => source.lyrics[verse];
}

class SolfaLine {
  final VoiceTrack track;
  final List<SolfaNote> notes;

  /// Do of the written key at the start, and the key you play in.
  final NoteName writtenDoh;
  final NoteName performanceDoh;

  /// Beaming unit in quarter notes: 1.5 for 6/8, 9/8, 12/8, else 1.
  final double beatLength;

  /// Time signature to print at the start (null if the file has none).
  final TimeSignature? time;

  const SolfaLine(this.track, this.notes, this.writtenDoh, this.performanceDoh,
      {this.beatLength = 1, this.time});
}

class SolfaBuilder {
  SolfaBuilder._();

  /// Builds the solfège line for [track].
  /// [performanceDoh]: the key to play in (Doh =). Null keeps the written key.
  static SolfaLine build(
    Score score,
    VoiceTrack track, {
    NoteName? performanceDoh,
    SolfaOptions options = const SolfaOptions(),
  }) {
    final writtenDoh = score.keyAt(0, partId: track.partId).doh(laBasedMinor: options.laBasedMinor);
    final target = performanceDoh ?? writtenDoh;
    // Move every note by one fixed interval (the smallest way, -6..+5).
    final shift = (((target.semitone - writtenDoh.semitone) % 12) + 6) % 12 - 6;

    // Key signature to print at each note: the written key at that bar,
    // moved by the same interval as the notes.
    int fifthsAt(int measureIndex) {
      final k = score.keyAt(measureIndex, partId: track.partId);
      if (target == writtenDoh) return k.fifths;
      final major = SolfegeEngine.transposeNote(k.majorTonic, writtenDoh, target);
      return KeySignature.fifthsOfMajor(major);
    }

    final out = <SolfaNote>[];
    var previousTied = false;
    for (final n in track.notes) {
      if (n.isChordTone) continue; // a melody line sings the top note only
      final keyFifths = fifthsAt(n.measureIndex);
      final p = n.pitch;
      if (p == null) {
        out.add(SolfaNote(n, null, null, keyFifths: keyFifths));
        previousTied = false;
        continue;
      }
      final doh = options.followKeyChanges
          ? score.keyAt(n.measureIndex, partId: track.partId).doh(laBasedMinor: options.laBasedMinor)
          : writtenDoh;
      final syllable = SolfegeEngine.syllable(p.name, doh);
      final shown = shift == 0 && target == writtenDoh
          ? p
          : Pitch.fromMidi(p.midi + shift, SolfegeEngine.transposeNote(p.name, writtenDoh, target));
      out.add(SolfaNote(n, shown, syllable,
          isTieContinuation: previousTied && n.tieStop, keyFifths: keyFifths, doh: doh));
      previousTied = n.tieStart;
    }
    final time = score.initialTime;
    final compound = time != null && time.beatType == 8 && time.beats % 3 == 0 && time.beats > 3;
    return SolfaLine(track, out, writtenDoh, target, beatLength: compound ? 1.5 : 1, time: time);
  }

  /// A plain-text tonic sol-fa view of one verse, one line per system of
  /// [notesPerLine] notes: syllables on top, the verse's words below,
  /// each column as wide as its longest entry.
  static String toText(SolfaLine line, {int verse = 1, int notesPerLine = 8}) {
    final rows = <String>[];
    final notes = line.notes.where((n) => !n.isTieContinuation).toList();
    for (var i = 0; i < notes.length; i += notesPerLine) {
      final chunk = notes.sublist(i, (i + notesPerLine).clamp(0, notes.length));
      final top = StringBuffer(), bottom = StringBuffer();
      for (final n in chunk) {
        final s = n.syllable ?? '-';
        final w = n.lyric(verse)?.displayText ?? '';
        final width = (s.length > w.length ? s.length : w.length) + 2;
        top.write(s.padRight(width));
        bottom.write(w.padRight(width));
      }
      rows.add(top.toString().trimRight());
      final words = bottom.toString().trimRight();
      if (words.isNotEmpty) rows.add(words);
      rows.add('');
    }
    return rows.join('\n').trimRight();
  }
}
