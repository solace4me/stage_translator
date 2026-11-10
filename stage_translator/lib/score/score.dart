// lib/score/score.dart
//
// The app's internal model of a piece of sheet music. Every source (a
// MusicXML / MuseScore export today, a photo scan through OMR later) is turned
// into a Score, and everything else (voice picker, solfège, transposing, the
// verse view) works on this model only.
//
// Pure Dart: no Flutter imports, so it is covered by plain unit tests.

import '../core/solfege_engine.dart';

/// A pitch with its spelling kept (Bb is not A#) and its octave.
/// Octaves follow scientific pitch notation: middle C is C4.
class Pitch {
  final NoteName name;
  final int octave;

  const Pitch(this.name, this.octave);

  /// MIDI number, middle C = 60. Uses the spelled letter's octave, so
  /// Cb4 is 59 and B#3 is 60.
  int get midi => (octave + 1) * 12 + NoteName.naturalSemitones[name.letter] + name.alter;

  /// The pitch at MIDI number [midi], spelled as [newName] (the octave is
  /// worked out from the spelling).
  static Pitch fromMidi(int midi, NoteName newName) {
    final natural = NoteName.naturalSemitones[newName.letter] + newName.alter;
    return Pitch(newName, ((midi - natural) ~/ 12) - 1);
  }

  @override
  String toString() => '$name$octave';

  @override
  bool operator ==(Object other) =>
      other is Pitch && other.name == name && other.octave == octave;

  @override
  int get hashCode => name.hashCode * 31 + octave;
}

enum KeyMode { major, minor }

/// A key signature as written: number of sharps (> 0) or flats (< 0).
class KeySignature {
  final int fifths;
  final KeyMode mode;

  const KeySignature(this.fifths, [this.mode = KeyMode.major]);

  static const _majorNames = [
    'Cb', 'Gb', 'Db', 'Ab', 'Eb', 'Bb', 'F', 'C', 'G', 'D', 'A', 'E', 'B', 'F#', 'C#',
  ];
  static const _minorNames = [
    'Ab', 'Eb', 'Bb', 'F', 'C', 'G', 'D', 'A', 'E', 'B', 'F#', 'C#', 'G#', 'D#', 'A#',
  ];

  int get _index => fifths.clamp(-7, 7) + 7;

  /// The major key with this signature (1 flat -> F).
  NoteName get majorTonic => NoteName.parse(_majorNames[_index]);

  /// The minor key with this signature (1 flat -> D).
  NoteName get minorTonic => NoteName.parse(_minorNames[_index]);

  /// Sharps (> 0) or flats (< 0) of the major key whose tonic is [doh]:
  /// G = 1, F = -1, Db = -5. Rare spellings (D#, A#...) fall back to the
  /// usual enharmonic key (Eb, Bb...).
  static int fifthsOfMajor(NoteName doh) {
    final i = _majorNames.indexOf(doh.toString());
    if (i >= 0) return i - 7;
    const bySemitone = [0, -5, 2, -3, 4, -1, 6, 1, -4, 3, -2, 5];
    return bySemitone[doh.semitone];
  }

  /// The tonic the music is in: F for F major, D for D minor.
  NoteName get tonic => mode == KeyMode.minor ? minorTonic : majorTonic;

  /// Where "do" sits.
  /// [laBasedMinor] (the tonic sol-fa default): a minor key reads from la,
  /// so D minor uses F as do, the same as its relative major.
  /// Otherwise do is the minor tonic itself (D minor: D = do).
  NoteName doh({bool laBasedMinor = true}) =>
      mode == KeyMode.minor && !laBasedMinor ? minorTonic : majorTonic;

  String get displayName => mode == KeyMode.minor ? '$tonic minor' : '$tonic major';

  @override
  String toString() => displayName;
}

class TimeSignature {
  final int beats;
  final int beatType;
  const TimeSignature(this.beats, this.beatType);

  @override
  String toString() => '$beats/$beatType';
}

enum Syllabic { single, begin, middle, end }

/// One syllable of one verse, attached to a note.
class Lyric {
  final int verse;
  final String text;
  final Syllabic syllabic;

  /// True when the syllable is held over the following notes (a melisma line).
  final bool extend;

  const Lyric(this.verse, this.text, {this.syllabic = Syllabic.single, this.extend = false});

  /// "Je-" for the start of a word that continues, "ru" in the middle, etc.
  String get displayText => switch (syllabic) {
        Syllabic.begin || Syllabic.middle => '$text-',
        _ => text,
      };
}

class ScoreNote {
  /// Null for a rest.
  final Pitch? pitch;

  /// Start time from the beginning of the piece, in quarter notes.
  final double onset;

  /// Length in quarter notes (0 for grace notes).
  final double duration;

  /// Staff within its part (1 = upper, 2 = lower for a grand staff).
  final int staff;

  /// The voice id exactly as written in the file ("1", "2", "5", ...).
  final String voice;

  /// "up", "down" or null when the file doesn't say.
  final String? stem;

  /// True when this note sounds together with the previous note of the
  /// same voice (a chord).
  final bool isChordTone;
  final bool isGrace;
  final bool tieStart;
  final bool tieStop;

  /// Lyrics by verse number.
  final Map<int, Lyric> lyrics;

  /// 0-based measure position in the part.
  final int measureIndex;

  /// Start of this note's measure, in quarter notes from the beginning.
  final double measureOnset;

  /// Slur numbers that start / end on this note (MusicXML <slur number>).
  final List<int> slurStarts;
  final List<int> slurStops;

  const ScoreNote({
    required this.pitch,
    required this.onset,
    required this.duration,
    required this.staff,
    required this.voice,
    required this.measureIndex,
    this.measureOnset = 0,
    this.slurStarts = const [],
    this.slurStops = const [],
    this.stem,
    this.isChordTone = false,
    this.isGrace = false,
    this.tieStart = false,
    this.tieStop = false,
    this.lyrics = const {},
  });

  bool get isRest => pitch == null;

  ScoreNote copyWith({
    Pitch? pitch,
    bool clearPitch = false,
    String? voice,
    bool? isChordTone,
    Map<int, Lyric>? lyrics,
    double? onset,
    int? measureIndex,
    double? measureOnset,
  }) =>
      ScoreNote(
        pitch: clearPitch ? null : (pitch ?? this.pitch),
        onset: onset ?? this.onset,
        duration: duration,
        staff: staff,
        voice: voice ?? this.voice,
        measureIndex: measureIndex ?? this.measureIndex,
        measureOnset: measureOnset ?? this.measureOnset,
        slurStarts: slurStarts,
        slurStops: slurStops,
        stem: stem,
        isChordTone: isChordTone ?? this.isChordTone,
        isGrace: isGrace,
        tieStart: tieStart,
        tieStop: tieStop,
        lyrics: lyrics ?? this.lyrics,
      );
}

/// Repeat signs and jumps on a measure, as written.
class MeasureFlow {
  /// |: at the start of this measure.
  final bool repeatStart;

  /// :| at the end of this measure, and how many times the section plays.
  final bool repeatEnd;
  final int times;

  /// Volta brackets: this measure belongs to ending 1 (or "1, 2"...).
  final List<int> endings;

  /// Which bracket this measure is in, so a whole ending can be skipped.
  final int? endingGroup;

  final bool segno, coda, toCoda, daCapo, dalSegno, fine;

  const MeasureFlow({
    this.repeatStart = false,
    this.repeatEnd = false,
    this.times = 2,
    this.endings = const [],
    this.endingGroup,
    this.segno = false,
    this.coda = false,
    this.toCoda = false,
    this.daCapo = false,
    this.dalSegno = false,
    this.fine = false,
  });

  static const none = MeasureFlow();

  bool get hasAny =>
      repeatStart || repeatEnd || endings.isNotEmpty || segno || coda || toCoda || daCapo || dalSegno || fine;
}

class Measure {
  final int index;

  /// The bar number as printed ("1", "2", "X1" for pickups).
  final String number;

  /// Set only where the key or time changes (and on the first measure).
  final KeySignature? key;
  final TimeSignature? time;
  final List<ScoreNote> notes;
  final MeasureFlow flow;

  /// Where the measure starts and how long it lasts, in quarter notes.
  final double start;
  final double length;

  const Measure({
    required this.index,
    required this.number,
    required this.notes,
    this.key,
    this.time,
    this.flow = MeasureFlow.none,
    this.start = 0,
    this.length = 0,
  });
}

/// Turns repeat signs, 1st/2nd endings, D.C., D.S., Fine and Coda into the
/// order the measures are actually played. Follows the usual convention:
/// after a D.C. or D.S. jump, repeats are not taken again.
class PlayOrder {
  PlayOrder._();

  static List<int> of(List<MeasureFlow> m) {
    final n = m.length;
    final order = <int>[];
    var i = 0;
    var sectionStart = 0; // where a :| sends us back to
    var pass = 1; // which time through the current repeated section
    var backFromRepeat = false;
    var jumped = false; // a D.C. / D.S. has been taken
    final repeatsDone = <int, int>{};

    while (i < n && order.length < n * 20) {
      final f = m[i];
      if (f.repeatStart && !backFromRepeat) {
        sectionStart = i;
        pass = 1;
      }
      backFromRepeat = false;

      // A volta bracket not meant for this time through: skip all of it.
      if (f.endings.isNotEmpty) {
        final wanted = jumped ? _lastEndingFrom(m, i) : pass;
        if (!f.endings.contains(wanted)) {
          final group = f.endingGroup;
          while (i < n && m[i].endings.isNotEmpty && m[i].endingGroup == group) {
            i++;
          }
          continue;
        }
      }

      order.add(i);

      if (jumped && f.fine) break;
      if (jumped && f.toCoda) {
        final coda = m.indexWhere((x) => x.coda, i + 1);
        if (coda >= 0) {
          i = coda;
          continue;
        }
      }
      if (f.repeatEnd && !jumped) {
        final done = repeatsDone[i] ?? 0;
        if (done < f.times - 1) {
          repeatsDone[i] = done + 1;
          pass++;
          i = sectionStart;
          backFromRepeat = true;
          continue;
        }
        // Section finished: the next one starts after this bar.
        sectionStart = i + 1;
        pass = 1;
      }
      if (!jumped && (f.daCapo || f.dalSegno)) {
        jumped = true;
        final segno = f.dalSegno ? m.indexWhere((x) => x.segno) : -1;
        i = segno >= 0 ? segno : 0;
        continue;
      }
      i++;
    }
    return order;
  }

  /// After a D.C./D.S. the final ending is played: the highest number in
  /// the run of brackets starting at [i].
  static int _lastEndingFrom(List<MeasureFlow> m, int i) {
    var last = 1;
    for (var j = i; j < m.length && m[j].endings.isNotEmpty; j++) {
      for (final e in m[j].endings) {
        if (e > last) last = e;
      }
    }
    return last;
  }
}

class Part {
  final String id;
  final String name;
  final int staves;
  final List<Measure> measures;

  const Part({required this.id, required this.name, required this.staves, required this.measures});

  Iterable<ScoreNote> get notes => measures.expand((m) => m.notes);
}

/// Which singer a line of notes belongs to.
enum VoiceRole { soprano, alto, tenor, bass, other }

/// One melodic line: a part + staff + voice, notes in time order.
class VoiceTrack {
  final String partId;
  final int staff;
  final String voice;
  final VoiceRole role;
  final String label;
  final List<ScoreNote> notes;

  const VoiceTrack({
    required this.partId,
    required this.staff,
    required this.voice,
    required this.role,
    required this.label,
    required this.notes,
  });

  /// Verse numbers that have lyrics on this line.
  List<int> get verses {
    final s = <int>{for (final n in notes) ...n.lyrics.keys};
    return s.toList()..sort();
  }
}

class Score {
  final String title;
  final String? composer;
  final List<Part> parts;

  const Score({required this.title, required this.parts, this.composer});

  /// Key in effect at [measureIndex] (the last key change at or before it).
  KeySignature keyAt(int measureIndex, {String? partId}) {
    final part = partId == null ? parts.first : parts.firstWhere((p) => p.id == partId);
    KeySignature key = const KeySignature(0);
    for (final m in part.measures) {
      if (m.index > measureIndex) break;
      if (m.key != null) key = m.key!;
    }
    return key;
  }

  KeySignature get initialKey => keyAt(0);

  /// True when the score has repeat signs, endings or D.C./D.S. jumps.
  bool get hasRepeats => parts.first.measures.any((m) => m.flow.hasAny);

  /// The same score with repeats written out in the order they are played:
  /// a repeated section appears twice, 1st and 2nd endings each on their
  /// pass, D.C./D.S. jump back, Fine and Coda are followed.
  Score withRepeatsFollowed() {
    if (!hasRepeats) return this;
    final order = PlayOrder.of([for (final m in parts.first.measures) m.flow]);
    return Score(
      title: title,
      composer: composer,
      parts: [for (final p in parts) _unroll(p, order)],
    );
  }

  Part _unroll(Part part, List<int> order) {
    final out = <Measure>[];
    var t = 0.0;
    KeySignature? lastKey;
    TimeSignature? lastTime;
    for (var k = 0; k < order.length; k++) {
      final idx = order[k];
      if (idx >= part.measures.length) continue;
      final m = part.measures[idx];
      final shift = t - m.start;
      final key = keyAt(idx, partId: part.id);
      final time = _timeAt(part, idx);
      final keyChanged = lastKey == null || key.fifths != lastKey.fifths || key.mode != lastKey.mode;
      final timeChanged = time != null &&
          (lastTime == null || time.beats != lastTime.beats || time.beatType != lastTime.beatType);
      out.add(Measure(
        index: out.length,
        number: m.number,
        key: keyChanged ? key : null,
        time: timeChanged ? time : null,
        start: t,
        length: m.length,
        notes: [
          for (final n in m.notes)
            n.copyWith(onset: n.onset + shift, measureIndex: out.length, measureOnset: t),
        ],
      ));
      lastKey = key;
      if (time != null) lastTime = time;
      t += m.length;
    }
    return Part(id: part.id, name: part.name, staves: part.staves, measures: out);
  }

  static TimeSignature? _timeAt(Part part, int measureIndex) {
    TimeSignature? t;
    for (final m in part.measures) {
      if (m.index > measureIndex) break;
      if (m.time != null) t = m.time;
    }
    return t;
  }

  TimeSignature? get initialTime {
    for (final m in parts.first.measures) {
      if (m.time != null) return m.time;
    }
    return null;
  }

  /// Every melodic line in the score, labelled Soprano/Alto/Tenor/Bass where
  /// the layout makes that clear:
  ///  * one part on a grand staff with two voices per staff (a hymn):
  ///    staff 1 = S (upper voice) + A, staff 2 = T (upper voice) + B
  ///  * four single-line parts: S, A, T, B in score order, unless the part
  ///    names say otherwise
  /// Within a staff, a voice whose stems mostly point up is the upper one;
  /// without stem marks, the voice with the higher average pitch is.
  /// A voice written as two-note chords (soprano and alto sharing stems,
  /// common in hymn files) is split into an upper and a lower line.
  List<VoiceTrack> voices() {
    final tracks = <VoiceTrack>[];
    for (final part in parts) {
      final byStaff = <int, Map<String, List<ScoreNote>>>{};
      for (final n in part.notes) {
        byStaff.putIfAbsent(n.staff, () => {}).putIfAbsent(n.voice, () => []).add(n);
      }
      for (final staff in byStaff.keys.toList()..sort()) {
        final voicesOnStaff = byStaff[staff]!;
        final order = voicesOnStaff.keys.toList();
        order.sort((a, b) => _upness(voicesOnStaff[b]!).compareTo(_upness(voicesOnStaff[a]!)));
        for (final v in order) {
          final notes = voicesOnStaff[v]!..sort((a, b) => a.onset.compareTo(b.onset));
          // Split into two lines only when the voice is written as chords
          // throughout (soprano + alto sharing stems). A few chords (a
          // short divided passage) stay in one line: its first note is used.
          final lines = _isChordVoice(notes) ? _splitChords(notes, v) : [(v, notes)];
          for (final (id, line) in lines) {
            tracks.add(VoiceTrack(
              partId: part.id,
              staff: staff,
              voice: id,
              role: VoiceRole.other,
              label: part.name,
              notes: line,
            ));
          }
        }
      }
    }
    return _assignRoles(tracks);
  }

  /// True when at least 30% of the voice's notes are chords.
  static bool _isChordVoice(List<ScoreNote> notes) {
    final starts = notes.where((n) => !n.isChordTone && !n.isRest).length;
    final chords = notes.where((n) => n.isChordTone).map((n) => n.onset).toSet().length;
    return starts > 0 && chords / starts >= 0.3;
  }

  /// Splits a chorded voice into its highest and lowest notes at each moment.
  /// Lyrics go to both lines; rests appear in both.
  static List<(String, List<ScoreNote>)> _splitChords(List<ScoreNote> notes, String voice) {
    final groups = <double, List<ScoreNote>>{};
    for (final n in notes) {
      groups.putIfAbsent(n.onset, () => []).add(n);
    }
    final upper = <ScoreNote>[], lower = <ScoreNote>[];
    for (final onset in groups.keys.toList()..sort()) {
      final g = groups[onset]!;
      final lyrics = <int, Lyric>{for (final n in g) ...n.lyrics};
      final pitched = g.where((n) => !n.isRest).toList()
        ..sort((a, b) => a.pitch!.midi.compareTo(b.pitch!.midi));
      if (pitched.isEmpty) {
        upper.add(g.first.copyWith(voice: voice, isChordTone: false, lyrics: lyrics));
        lower.add(g.first.copyWith(voice: '$voice-low', isChordTone: false, lyrics: lyrics));
        continue;
      }
      upper.add(pitched.last.copyWith(voice: voice, isChordTone: false, lyrics: lyrics));
      lower.add(pitched.first.copyWith(voice: '$voice-low', isChordTone: false, lyrics: lyrics));
    }
    return [(voice, upper), ('$voice-low', lower)];
  }

  /// +1 per note with stem up, -1 per stem down, then by first appearance.
  static double _upness(List<ScoreNote> notes) {
    var score = 0.0;
    for (final n in notes) {
      if (n.stem == 'up') score += 1;
      if (n.stem == 'down') score -= 1;
    }
    // Tie-break: the voice with the higher average pitch is the upper one.
    final pitched = notes.where((n) => !n.isRest).toList();
    if (pitched.isNotEmpty) {
      score += pitched.map((n) => n.pitch!.midi).reduce((a, b) => a + b) / pitched.length / 1000;
    }
    return score;
  }

  List<VoiceTrack> _assignRoles(List<VoiceTrack> tracks) {
    VoiceRole? byName(String name) {
      final n = name.toLowerCase();
      if (n.contains('soprano') || n.startsWith('s.') || n == 's') return VoiceRole.soprano;
      if (n.contains('alto') || n.startsWith('a.') || n == 'a') return VoiceRole.alto;
      if (n.contains('tenor') || n.startsWith('t.') || n == 't') return VoiceRole.tenor;
      if (n.contains('bass') || n.startsWith('b.') || n == 'b') return VoiceRole.bass;
      return null;
    }

    const satb = [VoiceRole.soprano, VoiceRole.alto, VoiceRole.tenor, VoiceRole.bass];
    final named = tracks.map((t) => byName(t.label)).toList();
    final useNames = named.every((r) => r != null) && named.toSet().length == tracks.length;

    final roles = <VoiceRole>[
      for (var i = 0; i < tracks.length; i++)
        useNames ? named[i]! : (tracks.length == 4 ? satb[i] : VoiceRole.other),
    ];

    return [
      for (var i = 0; i < tracks.length; i++)
        VoiceTrack(
          partId: tracks[i].partId,
          staff: tracks[i].staff,
          voice: tracks[i].voice,
          role: roles[i],
          label: roles[i] == VoiceRole.other
              ? '${tracks[i].label} · staff ${tracks[i].staff} · voice ${tracks[i].voice}'
              : _roleName(roles[i]),
          notes: tracks[i].notes,
        ),
    ];
  }

  static String _roleName(VoiceRole r) => switch (r) {
        VoiceRole.soprano => 'Soprano',
        VoiceRole.alto => 'Alto',
        VoiceRole.tenor => 'Tenor',
        VoiceRole.bass => 'Bass',
        VoiceRole.other => 'Voice',
      };
}
