// lib/core/solfege_engine.dart
//
// Pure Dart: no Flutter imports, so it runs in plain `dart test` and can be
// reused on a server or in a CLI later.
//
// Responsibilities
//   * parse note names and chord symbols (F#m7, Bb/D, Gsus4, C#dim ...)
//   * movable-do syllables, spelling-aware (in D, C natural is "ti♭")
//   * transpose letters from the sheet's key to the performance key
//   * detect the sheet's key from its chords
//   * process a whole sheet: label every chord, keep chords in their columns,
//     leave lyric lines and section labels alone
//   * strip labels again, so a key change can re-translate an edited sheet

import 'dart:convert';

/// A spelled note name: a letter plus an alteration (sharps > 0, flats < 0).
class NoteName {
  /// 0..6 for C D E F G A B.
  final int letter;

  /// -2..2  (bb, b, natural, #, ##)
  final int alter;

  const NoteName(this.letter, this.alter);

  static const _letters = 'CDEFGAB';
  static const naturalSemitones = [0, 2, 4, 5, 7, 9, 11];

  /// 0..11, C = 0.
  int get semitone => (naturalSemitones[letter] + alter) % 12;

  /// Parses "C", "F#", "Bb", "C##", "Ebb". Returns null when it is not a note.
  static NoteName? tryParse(String s) {
    final m = RegExp(r'^([A-G])(##|bb|#|b|♯|♭)?$').firstMatch(s.trim());
    if (m == null) return null;
    final letter = _letters.indexOf(m.group(1)!);
    final acc = m.group(2) ?? '';
    final alter = switch (acc) {
      '#' || '♯' => 1,
      '##' => 2,
      'b' || '♭' => -1,
      'bb' => -2,
      _ => 0,
    };
    return NoteName(letter, alter);
  }

  static NoteName parse(String s) {
    final n = tryParse(s);
    if (n == null) throw FormatException('Not a note name: $s');
    return n;
  }

  /// The usual sharp spelling for a semitone, used as a last-resort fallback.
  static NoteName fromSemitoneSharp(int semitone) {
    const table = [
      NoteName(0, 0), NoteName(0, 1), NoteName(1, 0), NoteName(1, 1),
      NoteName(2, 0), NoteName(3, 0), NoteName(3, 1), NoteName(4, 0),
      NoteName(4, 1), NoteName(5, 0), NoteName(5, 1), NoteName(6, 0),
    ];
    return table[semitone % 12];
  }

  @override
  String toString() {
    final acc = alter > 0 ? '#' * alter : 'b' * (-alter);
    return '${_letters[letter]}$acc';
  }

  @override
  bool operator ==(Object other) =>
      other is NoteName && other.letter == letter && other.alter == alter;

  @override
  int get hashCode => letter * 10 + alter;
}

/// A parsed chord symbol: root + suffix (quality and extensions) + optional bass.
class ChordSymbol {
  final NoteName root;
  final String suffix;
  final NoteName? bass;

  const ChordSymbol(this.root, this.suffix, [this.bass]);

  bool get isMinor {
    final s = suffix;
    if (s.startsWith('maj') || s.startsWith('M')) return false;
    return s.startsWith('m') || s.startsWith('min') || s.startsWith('-');
  }

  bool get isDiminished =>
      suffix.startsWith('dim') || suffix.startsWith('°') || suffix.startsWith('ø');

  @override
  String toString() => '$root$suffix${bass != null ? '/$bass' : ''}';
}

/// The 14 key spellings offered in the pickers.
const List<String> kKeyChoices = [
  'C', 'C#', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B',
];

class TranslateOptions {
  /// Rewrite the letters into the performance key (default) or keep them as
  /// written and label them against the performance key.
  final bool transposeLetters;

  /// "Bm [la minor]" instead of "Bm [la]".
  final bool showQuality;

  const TranslateOptions({this.transposeLetters = true, this.showQuality = false});
}

class SolfegeEngine {
  SolfegeEngine._();

  // Short syllables, to save room when a line has many chords.
  static const _diatonic = ['do', 're', 'mi', 'fa', 'so', 'la', 'ti'];
  static const _bySemitone = [
    'do', 'do#', 're', 're#', 'mi', 'fa', 'fa#', 'so', 'so#', 'la', 'la#', 'ti',
  ];
  static const _major = NoteName.naturalSemitones; // major-scale steps

  /// The flat sign used in labels (chord letters keep a plain "b").
  static const flat = '\u266D'; // ♭

  /// The seven base syllables, used to recognise the engine's own labels.
  static final Set<String> allSyllables = {..._diatonic};

  // Root, then suffix built only from chord vocabulary, then optional /bass.
  // Anchored: the whole token must be a chord, so "Bridge", "Am" inside
  // "Amazing", "Do" etc. never match.
  static final RegExp _chordToken = RegExp(
    r'^([A-G](?:##|bb|#|b|♯|♭)?)'
    r'((?:maj|min|dim|aug|sus|add|alt|no|M|m|-|\+|°|ø|Δ|\d|#|b|\(|\)|,)*)'
    r'(?:/([A-G](?:#|b|♯|♭)?))?$',
  );

  // Decoration that may wrap a chord token on a sheet: "*D", "(G)", "|Bm|".
  static final RegExp _wrap = RegExp(r'^([*(\[|]*)(.*?)([)\]|,.*:]*)$');

  // Inline chords such as "[D]Some lyric".
  static final RegExp _inlineChord = RegExp(r'\[([A-G][^\]\s]*)\]');

  // Our own labels: " [la]", " [fa/la]", " [ti♭]", " [fa#/la minor]".
  static final RegExp _label =
      RegExp(r' ?\[([a-z]+)(?:##|#|♭♭|♭)?(?:/[a-z]+(?:##|#|♭♭|♭)?)?(?: [^\]\[]*)?\]');

  // An inline chord we labelled: "[D [do]]".
  static final RegExp _inlineLabel =
      RegExp(r'\[([A-G][^\[\]\s]*) \[([a-z]+)[^\[\]]*\]\]');

  // Tokens that don't count for or against a chord line.
  static final RegExp _neutral = RegExp(r'^(?:[-–—|/:.*]+|\(?x\d+\)?|\d+x)$', caseSensitive: false);

  // ---------------------------------------------------------------- parsing

  static ChordSymbol? parseChord(String token) {
    final m = _chordToken.firstMatch(token);
    if (m == null) return null;
    final root = NoteName.tryParse(m.group(1)!);
    if (root == null) return null;
    final suffix = m.group(2) ?? '';
    // Reject unbalanced brackets such as "G)" that slipped past unwrapping.
    if ('('.allMatches(suffix).length != ')'.allMatches(suffix).length) {
      return null;
    }
    final bassStr = m.group(3);
    final bass = bassStr == null ? null : NoteName.tryParse(bassStr);
    return ChordSymbol(root, suffix, bass);
  }

  // ------------------------------------------------------------- syllables

  /// Movable-do syllable of [note] with [key] as Doh: the scale degree's
  /// syllable plus # or ♭. In C, F# is "fa#" and Bb is "ti♭";
  /// in D, C is "ti♭". The spelling of the chord decides: A# in C is
  /// "la#", Bb in C is "ti♭".
  static String syllable(NoteName note, NoteName key) {
    final degree = (note.letter - key.letter) % 7;
    final semi = (note.semitone - key.semitone) % 12;
    final diff = _signed(semi - _major[degree]);
    if (diff == 0) return _diatonic[degree];
    if (diff > 0 && diff <= 2) return '${_diatonic[degree]}${'#' * diff}';
    if (diff < 0 && diff >= -2) return '${_diatonic[degree]}${flat * -diff}';
    return _bySemitone[semi]; // only for odd spellings such as B# in Gb
  }

  /// Maps any int to -6..5 (semitone difference).
  static int _signed(int d) => ((d + 6) % 12) - 6;

  // ----------------------------------------------------------- transposing

  /// Moves [note] from [from] to [to], keeping its scale degree and alteration,
  /// so D -> F# turns Bm into D#m (not Ebm) and G into B.
  static NoteName transposeNote(NoteName note, NoteName from, NoteName to) {
    final degree = (note.letter - from.letter) % 7;
    final newLetter = (to.letter + degree) % 7;
    final targetSemi = (to.semitone + note.semitone - from.semitone) % 12;
    final alter = _signed(targetSemi - NoteName.naturalSemitones[newLetter]);
    if (alter.abs() > 2) return NoteName.fromSemitoneSharp(targetSemi);
    return NoteName(newLetter, alter);
  }

  static ChordSymbol transposeChord(ChordSymbol c, NoteName from, NoteName to) =>
      ChordSymbol(
        transposeNote(c.root, from, to),
        c.suffix,
        c.bass == null ? null : transposeNote(c.bass!, from, to),
      );

  // --------------------------------------------------------- key detection

  /// Best-fitting major key for the chords in [text], or null if none found.
  static NoteName? detectKey(String text) {
    final chords = <ChordSymbol>[];
    var sharps = 0, flats = 0;
    for (final line in const LineSplitter().convert(stripLabels(text))) {
      for (final inline in _inlineChord.allMatches(line)) {
        final c = parseChord(inline.group(1)!);
        if (c != null) chords.add(c);
      }
      if (!isChordLine(line)) continue;
      for (final t in _tokens(line)) {
        final c = _match(t.text)?.chord;
        if (c != null) chords.add(c);
      }
    }
    if (chords.isEmpty) return null;
    for (final c in chords) {
      if (c.root.alter > 0) sharps++;
      if (c.root.alter < 0) flats++;
    }

    // Diatonic triads of a major key: I ii iii IV V vi vii°
    const qualities = ['maj', 'min', 'min', 'maj', 'maj', 'min', 'dim'];
    var bestScore = -1.0;
    var bestSemi = 0;
    for (var k = 0; k < 12; k++) {
      var score = 0.0;
      for (var i = 0; i < chords.length; i++) {
        final c = chords[i];
        final weight = (i == 0 || i == chords.length - 1) ? 2.0 : 1.0;
        final rel = (c.root.semitone - k) % 12;
        final deg = _major.indexOf(rel);
        if (deg < 0) continue;
        score += weight;
        final q = c.isDiminished ? 'dim' : (c.isMinor ? 'min' : 'maj');
        if (q == qualities[deg]) score += weight;
        if (rel == 0 && (i == 0 || i == chords.length - 1)) score += 1;
      }
      if (score > bestScore) {
        bestScore = score;
        bestSemi = k;
      }
    }
    return _spellKey(bestSemi, preferSharps: sharps > flats);
  }

  static NoteName _spellKey(int semi, {required bool preferSharps}) {
    const flatSpelling = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];
    const sharpSpelling = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];
    return NoteName.parse((preferSharps ? sharpSpelling : flatSpelling)[semi]);
  }

  // ------------------------------------------------------- line handling

  /// True when at least 60% of the line's meaningful tokens are chords.
  static bool isChordLine(String line) {
    var chords = 0, words = 0;
    for (final t in _tokens(line)) {
      if (_neutral.hasMatch(t.text)) continue;
      if (_match(t.text) != null) {
        chords++;
      } else {
        words++;
      }
    }
    return chords > 0 && chords / (chords + words) >= 0.6;
  }

  /// Removes every label this engine adds, leaving the letter chords.
  /// Labels on chord lines become spaces, so each chord keeps its column and
  /// re-translating an edited sheet does not drift.
  static String stripLabels(String text) => text.split('\n').map((line) {
        var l = line.replaceAllMapped(_inlineLabel, (m) {
          return allSyllables.contains(m.group(2)) ? '[${m.group(1)}]' : m.group(0)!;
        });
        l = l.replaceAllMapped(_label, (m) {
          return allSyllables.contains(m.group(1)) ? ' ' * m.group(0)!.length : m.group(0)!;
        });
        return l == line ? line : l.trimRight();
      }).join('\n');

  // ------------------------------------------------------------ the sheet

  /// Labels every chord in [text].
  ///
  /// [sheetKey] is the key the chords are written in; [performanceKey] is Doh.
  /// Any existing labels are stripped first, so this is safe to run again on an
  /// already translated (and hand-edited) sheet.
  static String process(
    String text, {
    required NoteName sheetKey,
    required NoteName performanceKey,
    TranslateOptions options = const TranslateOptions(),
  }) {
    if (text.isEmpty) return '';
    final clean = stripLabels(text);
    final out = <String>[];
    for (final line in const LineSplitter().convert(clean)) {
      out.add(_processLine(line, sheetKey, performanceKey, options));
    }
    return out.join('\n');
  }

  static String _processLine(
    String line,
    NoteName sheetKey,
    NoteName perfKey,
    TranslateOptions o,
  ) {
    // 1. Inline chords "[D]word" anywhere in the line.
    var result = line.replaceAllMapped(_inlineChord, (m) {
      final c = parseChord(m.group(1)!);
      if (c == null) return m.group(0)!;
      return '[${_render(c, sheetKey, perfKey, o)}]';
    });
    if (result != line) return result;

    // 2. Chord-over-lyric lines: rebuild with each token kept at its column.
    if (!isChordLine(line)) return line;
    final buf = StringBuffer();
    for (final t in _tokens(line)) {
      final w = _match(t.text);
      final text = w == null
          ? t.text
          : _render(w.chord, sheetKey, perfKey, o, pre: w.pre, post: w.post);
      final minCol = buf.isEmpty ? 0 : buf.length + 1;
      final col = t.start > minCol ? t.start : minCol;
      buf.write(' ' * (col - buf.length));
      buf.write(text);
    }
    return buf.toString();
  }

  /// "Bm" -> "Bm [la]"; with transposition D->F#: "D#m [la]".
  /// Decoration stays on the chord, the label goes after it: "(G) [fa]".
  static String _render(
    ChordSymbol c,
    NoteName sheetKey,
    NoteName perfKey,
    TranslateOptions o, {
    String pre = '',
    String post = '',
  }) {
    final shown = o.transposeLetters ? transposeChord(c, sheetKey, perfKey) : c;
    final root = syllable(shown.root, perfKey);
    final bass = shown.bass == null ? '' : '/${syllable(shown.bass!, perfKey)}';
    final quality = o.showQuality ? _describe(shown.suffix) : '';
    return '$pre$shown$post [$root$bass${quality.isEmpty ? '' : ' $quality'}]';
  }

  static String _describe(String suffix) {
    if (suffix.isEmpty) return '';
    if (suffix.startsWith('maj') || suffix.startsWith('M') || suffix.startsWith('Δ')) {
      return suffix;
    }
    if (suffix.startsWith('min')) return 'minor${suffix.substring(3)}';
    if (suffix.startsWith('m') || suffix.startsWith('-')) {
      return 'minor${suffix.substring(1)}';
    }
    return suffix;
  }

  // ----------------------------------------------------------- tokenising

  static Iterable<_Tok> _tokens(String line) sync* {
    for (final m in RegExp(r'\S+').allMatches(line)) {
      yield _Tok(m.group(0)!, m.start);
    }
  }

  /// Finds the chord in a token, allowing decoration around it: "*D", "(G)".
  /// The whole token is tried first so "C(add9)" keeps its bracket.
  static _Match? _match(String token) {
    final whole = parseChord(token);
    if (whole != null) return _Match('', whole, '');
    final m = _wrap.firstMatch(token)!;
    final c = parseChord(m.group(2)!);
    return c == null ? null : _Match(m.group(1)!, c, m.group(3)!);
  }
}

class _Tok {
  final String text;
  final int start;
  const _Tok(this.text, this.start);
}

class _Match {
  final String pre, post;
  final ChordSymbol chord;
  const _Match(this.pre, this.chord, this.post);
}
