// lib/score/musicxml_parser.dart
//
// Reads MusicXML (.musicxml / .xml) and compressed MusicXML (.mxl) into a
// Score. MuseScore, Finale, Sibelius, Dorico and OMR tools such as oemer and
// Audiveris all export it.
//
// What is read: title and composer, parts and staves, key and time changes,
// pitches with their spelling, rests, durations (via <divisions>, <backup>
// and <forward>), chords, voices, stems, ties, grace notes and lyrics for
// every verse. Layout and printing details are ignored.
//
// Pure Dart (packages: xml, archive).

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../core/solfege_engine.dart';
import 'score.dart';

class MusicXmlFormatException implements Exception {
  final String message;
  const MusicXmlFormatException(this.message);
  @override
  String toString() => 'MusicXmlFormatException: $message';
}

class MusicXmlParser {
  MusicXmlParser._();

  /// Parses a file's bytes; detects .mxl (zip) automatically.
  static Score parseBytes(Uint8List bytes) {
    final isZip = bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B; // "PK"
    return parseString(isZip ? _unzipMxl(bytes) : utf8.decode(bytes, allowMalformed: true));
  }

  static Score parseString(String xmlText) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xmlText);
    } on XmlException catch (e) {
      throw MusicXmlFormatException('Not valid XML: ${e.message}');
    }
    final root = doc.rootElement;
    if (root.name.local == 'score-timewise') {
      throw const MusicXmlFormatException(
          'Timewise MusicXML is not supported. Re-export as partwise (the default).');
    }
    if (root.name.local != 'score-partwise') {
      throw MusicXmlFormatException('Not a MusicXML score (root <${root.name.local}>).');
    }

    final title = _text(root.getElement('work')?.getElement('work-title')) ??
        _text(root.getElement('movement-title')) ??
        _creditTitle(root) ??
        'Untitled';
    final composer = root
        .getElement('identification')
        ?.findElements('creator')
        .where((c) => c.getAttribute('type') == 'composer')
        .map((c) => c.innerText.trim())
        .firstWhere((t) => t.isNotEmpty, orElse: () => '');

    final names = <String, String>{};
    for (final sp in root.getElement('part-list')?.findElements('score-part') ?? const <XmlElement>[]) {
      final id = sp.getAttribute('id');
      if (id != null) names[id] = _text(sp.getElement('part-name')) ?? id;
    }

    final parts = <Part>[
      for (final p in root.findElements('part')) _parsePart(p, names),
    ];
    if (parts.isEmpty) throw const MusicXmlFormatException('The score has no parts.');

    return Score(
      title: title,
      composer: (composer == null || composer.isEmpty) ? null : composer,
      parts: parts,
    );
  }

  // ------------------------------------------------------------------ parts

  static Part _parsePart(XmlElement partEl, Map<String, String> names) {
    final id = partEl.getAttribute('id') ?? 'P${names.length + 1}';
    var divisions = 1.0; // divisions per quarter note
    var staves = 1;
    var time = 0.0; // running position in quarter notes
    final measures = <Measure>[];
    var index = 0;
    var openEnding = <int>[]; // volta bracket in progress
    int? openEndingGroup;
    var endingGroups = 0;

    for (final m in partEl.findElements('measure')) {
      KeySignature? key;
      TimeSignature? timeSig;
      final notes = <ScoreNote>[];
      final measureStart = time;
      var cursor = time;
      var measureEnd = time;
      // Last non-chord note start per voice, for chord tones.
      final lastOnset = <String, double>{};
      // Repeats and jumps found in this measure.
      var repeatStart = false, repeatEnd = false, times = 2;
      var segno = false, coda = false, toCoda = false, daCapo = false, dalSegno = false, fine = false;
      var closeEnding = false;

      void readSound(XmlElement? sound) {
        if (sound == null) return;
        if (sound.getAttribute('segno') != null) segno = true;
        if (sound.getAttribute('coda') != null) coda = true;
        if (sound.getAttribute('tocoda') != null) toCoda = true;
        if (sound.getAttribute('dacapo') == 'yes') daCapo = true;
        if (sound.getAttribute('dalsegno') != null) dalSegno = true;
        if (sound.getAttribute('fine') != null) fine = true;
      }

      for (final el in m.childElements) {
        switch (el.name.local) {
          case 'attributes':
            final d = _num(el.getElement('divisions'));
            if (d != null && d > 0) divisions = d;
            final s = _num(el.getElement('staves'));
            if (s != null) staves = s.toInt();
            final k = el.getElement('key');
            if (k != null) {
              final fifths = _num(k.getElement('fifths'))?.toInt() ?? 0;
              final mode = _text(k.getElement('mode'))?.toLowerCase() == 'minor'
                  ? KeyMode.minor
                  : KeyMode.major;
              key = KeySignature(fifths, mode);
            }
            final t = el.getElement('time');
            if (t != null) {
              final beats = int.tryParse(_text(t.getElement('beats'))?.split('+').first ?? '');
              final type = int.tryParse(_text(t.getElement('beat-type')) ?? '');
              if (beats != null && type != null) timeSig = TimeSignature(beats, type);
            }
          case 'barline':
            final r = el.getElement('repeat');
            if (r != null) {
              if (r.getAttribute('direction') == 'forward') repeatStart = true;
              if (r.getAttribute('direction') == 'backward') {
                repeatEnd = true;
                times = int.tryParse(r.getAttribute('times') ?? '') ?? 2;
              }
            }
            final e = el.getElement('ending');
            if (e != null) {
              final type = e.getAttribute('type');
              if (type == 'start') {
                openEnding = [
                  for (final part in (e.getAttribute('number') ?? '1').split(RegExp(r'[,\s]+')))
                    if (int.tryParse(part) != null) int.parse(part),
                ];
                openEndingGroup = ++endingGroups;
              } else if (type == 'stop' || type == 'discontinue') {
                closeEnding = true;
              }
            }
            if (el.getElement('segno') != null) segno = true;
            if (el.getElement('coda') != null) coda = true;
            readSound(el.getElement('sound'));
          case 'direction':
            final types = el.findAllElements('direction-type').toList();
            for (final t in types) {
              if (t.getElement('segno') != null) segno = true;
              if (t.getElement('coda') != null) coda = true;
              final words = t.findElements('words').map((w) => w.innerText.toLowerCase()).join(' ');
              // "Fine" on its own marks the end; "D.S. al Fine" is only the jump.
              if (RegExp(r'^\s*fine\b').hasMatch(words)) fine = true;
              if (words.contains('to coda')) toCoda = true;
              if (RegExp(r'd\.\s*c\.|da capo').hasMatch(words)) daCapo = true;
              if (RegExp(r'd\.\s*s\.|dal segno').hasMatch(words)) dalSegno = true;
            }
            readSound(el.getElement('sound'));
          case 'sound':
            readSound(el);
          case 'backup':
            cursor -= (_num(el.getElement('duration')) ?? 0) / divisions;
            if (cursor < measureStart) cursor = measureStart;
          case 'forward':
            cursor += (_num(el.getElement('duration')) ?? 0) / divisions;
            if (cursor > measureEnd) measureEnd = cursor;
          case 'note':
            final note = _parseNote(el, divisions, cursor, lastOnset, index, measureStart);
            notes.add(note);
            if (!note.isChordTone && !note.isGrace) {
              lastOnset[note.voice] = cursor;
              cursor += note.duration;
            }
            final end = note.onset + note.duration;
            if (end > measureEnd) measureEnd = end;
        }
      }

      measures.add(Measure(
        index: index,
        number: m.getAttribute('number') ?? '${index + 1}',
        key: key,
        time: timeSig,
        notes: notes,
        start: measureStart,
        length: measureEnd - measureStart,
        flow: MeasureFlow(
          repeatStart: repeatStart,
          repeatEnd: repeatEnd,
          times: times,
          endings: openEnding,
          endingGroup: openEnding.isEmpty ? null : openEndingGroup,
          segno: segno,
          coda: coda,
          toCoda: toCoda,
          daCapo: daCapo,
          dalSegno: dalSegno,
          fine: fine,
        ),
      ));
      if (closeEnding) {
        openEnding = [];
        openEndingGroup = null;
      }
      time = measureEnd;
      index++;
    }

    return Part(id: id, name: names[id] ?? id, staves: staves, measures: measures);
  }

  static ScoreNote _parseNote(
    XmlElement el,
    double divisions,
    double cursor,
    Map<String, double> lastOnset,
    int measureIndex,
    double measureStart,
  ) {
    final voice = _text(el.getElement('voice')) ?? '1';
    final isChord = el.getElement('chord') != null;
    final isGrace = el.getElement('grace') != null;
    final onset = isChord ? (lastOnset[voice] ?? cursor) : cursor;
    final duration = isGrace ? 0.0 : (_num(el.getElement('duration')) ?? 0) / divisions;

    Pitch? pitch;
    final p = el.getElement('pitch');
    if (p != null) {
      final step = _text(p.getElement('step'));
      final alter = (_num(p.getElement('alter')) ?? 0).round(); // quarter tones rounded
      final octave = _num(p.getElement('octave'))?.toInt() ?? 4;
      final letter = step == null ? -1 : 'CDEFGAB'.indexOf(step.toUpperCase());
      if (letter >= 0) pitch = Pitch(NoteName(letter, alter.clamp(-2, 2)), octave);
    }
    // <unpitched/> (percussion) and <rest/> both stay pitch == null.

    var tieStart = false, tieStop = false;
    for (final t in el.findElements('tie')) {
      if (t.getAttribute('type') == 'start') tieStart = true;
      if (t.getAttribute('type') == 'stop') tieStop = true;
    }

    final slurStarts = <int>[], slurStops = <int>[];
    for (final s in el.findAllElements('slur')) {
      final number = int.tryParse(s.getAttribute('number') ?? '') ?? 1;
      if (s.getAttribute('type') == 'start') slurStarts.add(number);
      if (s.getAttribute('type') == 'stop') slurStops.add(number);
    }

    final lyrics = <int, Lyric>{};
    var verseFallback = 1;
    for (final l in el.findElements('lyric')) {
      final verse = int.tryParse(l.getAttribute('number') ?? '') ?? verseFallback;
      verseFallback = verse + 1;
      // Elisions can split one lyric into several <text> elements.
      final text = l.findElements('text').map((t) => t.innerText).join(' ').trim();
      if (text.isEmpty && l.getElement('extend') == null) continue;
      final syl = switch (_text(l.getElement('syllabic'))) {
        'begin' => Syllabic.begin,
        'middle' => Syllabic.middle,
        'end' => Syllabic.end,
        _ => Syllabic.single,
      };
      lyrics[verse] = Lyric(verse, text, syllabic: syl, extend: l.getElement('extend') != null);
    }

    return ScoreNote(
      pitch: pitch,
      onset: onset,
      duration: duration,
      staff: _num(el.getElement('staff'))?.toInt() ?? 1,
      voice: voice,
      measureIndex: measureIndex,
      measureOnset: measureStart,
      slurStarts: slurStarts,
      slurStops: slurStops,
      stem: _text(el.getElement('stem')),
      isChordTone: isChord,
      isGrace: isGrace,
      tieStart: tieStart,
      tieStop: tieStop,
      lyrics: lyrics,
    );
  }

  // ------------------------------------------------------------------ .mxl

  static String _unzipMxl(Uint8List bytes) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw MusicXmlFormatException('Could not open the .mxl file: $e');
    }
    String read(ArchiveFile f) => utf8.decode(f.content, allowMalformed: true);

    // META-INF/container.xml names the main score file.
    final container = zip.findFile('META-INF/container.xml');
    if (container != null) {
      final rootPath = XmlDocument.parse(read(container))
          .findAllElements('rootfile')
          .map((r) => r.getAttribute('full-path'))
          .whereType<String>()
          .firstOrNull;
      final main = rootPath == null ? null : zip.findFile(rootPath);
      if (main != null) return read(main);
    }
    for (final f in zip.files) {
      final n = f.name.toLowerCase();
      if (f.isFile && !n.startsWith('meta-inf/') && (n.endsWith('.xml') || n.endsWith('.musicxml'))) {
        return read(f);
      }
    }
    throw const MusicXmlFormatException('No score file inside the .mxl.');
  }

  // --------------------------------------------------------------- helpers

  static String? _text(XmlElement? e) {
    final t = e?.innerText.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  static double? _num(XmlElement? e) => double.tryParse(_text(e) ?? '');

  static String? _creditTitle(XmlElement root) {
    for (final c in root.findElements('credit')) {
      if (c.getElement('credit-type')?.innerText.trim() == 'title') {
        return _text(c.getElement('credit-words'));
      }
    }
    final first = root.findElements('credit').firstOrNull?.getElement('credit-words');
    return _text(first);
  }
}
