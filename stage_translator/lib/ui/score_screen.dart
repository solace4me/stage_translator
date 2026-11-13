// lib/ui/score_screen.dart
//
// The hymn stage view (from a MusicXML / MuseScore file). Two views:
//  * Sol-fa: all voices in Curwen tonic sol-fa, stacked S/A/T/B like a
//    sol-fa hymn book, with the words of the current verse. The chosen voice
//    is highlighted.
//  * Staff: one clean staff with only the chosen voice, sol-fa above each
//    note and every verse below (the current one bright).
// Toolbar: view, voice, Doh =, Play do. Repeats are followed by default. Big
// verse buttons in the corner. Menu: letters/words, key-change and minor-key
// options, text size, PDF export.
// Pedal: forward scrolls a page, then goes to the next verse, then (in a set
// list) to the next song. Back does the reverse.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/solfege_engine.dart';
import '../data/score_repository.dart';
import '../score/curwen.dart';
import '../score/musicxml_parser.dart';
import '../score/score.dart';
import '../score/solfa.dart';
import '../score/staff_layout.dart';
import '../services/score_pdf_exporter.dart';
import '../services/tone_player.dart';
import 'feedback_dialog.dart';
import 'key_picker.dart';
import 'pedal.dart';
import 'play_button.dart';
import 'set_nav.dart';
import 'sheet_style.dart';
import 'staff_painter.dart';

enum _View { solfa, staff }

class ScoreScreen extends StatefulWidget {
  final Uint8List bytes;
  final SavedScore? saved; // null = just imported, not in the library yet
  final ScoreRepository repository;

  /// Where the file came from (e.g. the built-in hymn library), kept on save.
  final String? source;

  /// Set when playing a set list: previous/next song bar, and the pedal moves
  /// on to the next song after the last verse.
  final SetNav? setNav;

  const ScoreScreen({
    super.key,
    required this.bytes,
    required this.repository,
    this.saved,
    this.source,
    this.setNav,
  });

  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> {
  Score? _written; // as in the file
  String? _error;
  int _voice = 0;
  String? _performanceKey; // null = written key
  int _verse = 1;
  _View _view = _View.solfa;
  bool _followRepeats = true;
  bool _letters = true;
  bool _laBasedMinor = true;
  bool _followKeyChanges = true;
  double _textSize = 16;
  bool _exporting = false;
  late final String _id = widget.saved?.id ?? ScoreRepository.newId();
  late bool _inLibrary = widget.saved != null;
  final _scroll = ScrollController();
  List<int> _verses = const [];

  @override
  void initState() {
    super.initState();
    if (widget.setNav == null) WakelockPlus.enable(); // a set keeps it on itself
    try {
      _written = MusicXmlParser.parseBytes(widget.bytes);
      final s = widget.saved;
      if (s != null) {
        _voice = s.voiceIndex;
        _performanceKey = s.performanceKey;
        _verse = s.verse;
      }
    } on MusicXmlFormatException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Could not read this file: $e';
    }
  }

  @override
  void dispose() {
    if (widget.setNav == null) WakelockPlus.disable();
    _scroll.dispose();
    super.dispose();
  }

  Score get _score => _followRepeats ? _written!.withRepeatsFollowed() : _written!;
  NoteName? get _perfDoh => _performanceKey == null ? null : NoteName.parse(_performanceKey!);
  SolfaOptions get _options => SolfaOptions(laBasedMinor: _laBasedMinor, followKeyChanges: _followKeyChanges);

  Future<void> _save({bool quiet = false}) async {
    final score = _written;
    if (score == null) return;
    await widget.repository.save(
      SavedScore(
        id: _id,
        title: score.title,
        performanceKey: _performanceKey,
        voiceIndex: _voice,
        verse: _verse,
        updatedAt: DateTime.now(),
        source: widget.saved?.source ?? widget.source,
      ),
      bytes: _inLibrary ? null : widget.bytes,
    );
    if (!mounted || quiet) return;
    setState(() => _inLibrary = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to your hymns')));
  }

  // ------------------------------------------------------------- play do

  int get _dohSemitone {
    final perf = _perfDoh;
    if (perf != null) return perf.semitone;
    return _written!.initialKey.doh(laBasedMinor: _laBasedMinor).semitone;
  }

  void _playDoh() => TonePlayer.play(ToneSynth.doh(_dohSemitone));

  /// First sounding note of each voice, in the key you play in.
  int? _firstMidi(Score score, VoiceTrack track) {
    final line = SolfaBuilder.build(score, track, performanceDoh: _perfDoh, options: _options);
    for (final n in line.notes) {
      if (n.pitch != null) return n.pitch!.midi;
    }
    return null;
  }

  Future<void> _playMenu(Score score, List<VoiceTrack> voices) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.music_note),
            title: const Text('Doh'),
            onTap: () => Navigator.pop(c, 'doh'),
          ),
          ListTile(
            leading: const Icon(Icons.piano),
            title: const Text('Doh chord'),
            subtitle: const Text('d  m  s  d\''),
            onTap: () => Navigator.pop(c, 'chord'),
          ),
          ListTile(
            leading: const Icon(Icons.groups),
            title: const Text('Starting notes, all voices'),
            subtitle: const Text('Give the choir their notes'),
            onTap: () => Navigator.pop(c, 'all'),
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: Text('First note, ${voices[_voice].label}'),
            onTap: () => Navigator.pop(c, 'mine'),
          ),
        ]),
      ),
    );
    switch (choice) {
      case 'doh':
        _playDoh();
      case 'chord':
        TonePlayer.play(ToneSynth.dohChord(_dohSemitone));
      case 'all':
        final midis = [for (final v in voices) _firstMidi(score, v)].whereType<int>().toList();
        TonePlayer.play(ToneSynth.rolled(midis));
      case 'mine':
        final m = _firstMidi(score, voices[_voice]);
        if (m != null) TonePlayer.play([(midi: m, start: 0.0)]);
    }
  }

  // --------------------------------------------------------- pedal / set

  void _toTop() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(0);
      });

  void _onPedal(PedalAction a) {
    if (pageScroll(_scroll, a)) return;
    final i = _verses.indexOf(_verse);
    if (a == PedalAction.forward) {
      if (i >= 0 && i < _verses.length - 1) {
        setState(() => _verse = _verses[i + 1]);
        _toTop();
      } else {
        _go(widget.setNav?.onNext);
      }
    } else {
      if (i > 0) {
        setState(() => _verse = _verses[i - 1]);
        _toTop();
      } else {
        _go(widget.setNav?.onPrevious);
      }
    }
  }

  /// In a set: remember this hymn's key/voice/verse, then move on.
  Future<void> _go(VoidCallback? move) async {
    if (move == null) return;
    if (_inLibrary) await _save(quiet: true);
    move();
  }

  Future<void> _export(Score score, List<VoiceTrack> voices) async {
    final choice = await showModalBottomSheet<_View>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.format_list_numbered),
            title: const Text('Sol-fa, all voices'),
            subtitle: Text('Verse $_verse words · like a sol-fa hymn book'),
            onTap: () => Navigator.pop(c, _View.solfa),
          ),
          ListTile(
            leading: const Icon(Icons.music_note),
            title: Text('Staff, ${voices[_voice].label} only'),
            subtitle: const Text('Notes with sol-fa above and every verse below'),
            onTap: () => Navigator.pop(c, _View.staff),
          ),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      final file = choice == _View.solfa
          ? await ScorePdfExporter.solfa(
              CurwenBuilder.build(score, voices,
                  performanceDoh: _perfDoh, options: _options, verse: _verse, letters: _letters),
              title: score.title,
              verse: _verse)
          : await () {
              final line = SolfaBuilder.build(score, voices[_voice], performanceDoh: _perfDoh, options: _options);
              const width = 900.0;
              final layout = StaffLayout.build(line, width: width - 16, charWidth: 14 * 0.62);
              return ScorePdfExporter.staff(
                layout,
                title: score.title,
                subtitle: '${voices[_voice].label} · Doh is ${line.performanceDoh}',
                verses: line.track.verses,
                currentVerse: _verse,
                width: width,
              );
            }();
      await ScorePdfExporter.share(file, score.title);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Open hymn')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('$_error\n\nMake sure it is a MusicXML file (.mxl or .musicxml).',
                textAlign: TextAlign.center),
          ),
        ),
      );
    }
    final score = _score;
    final voices = score.voices();
    if (voices.isEmpty) {
      return Scaffold(appBar: AppBar(title: Text(score.title)), body: const Center(child: Text('No notes found.')));
    }
    if (_voice >= voices.length) _voice = 0;
    final writtenDoh = score.initialKey.doh(laBasedMinor: _laBasedMinor).toString();
    final verses = <int>{for (final v in voices) ...v.verses}.toList()..sort();
    _verses = verses;
    final nav = widget.setNav;

    return Pedal(
      onPedal: _onPedal,
      child: Scaffold(
      appBar: AppBar(
        title: Text(score.title, overflow: TextOverflow.ellipsis),
        actions: [
          PlayDohButton(onTap: _playDoh, onLongPress: () => _playMenu(score, voices)),
          IconButton(
            tooltip: 'Save to your hymns',
            onPressed: _save,
            icon: Icon(_inLibrary ? Icons.bookmark : Icons.bookmark_add_outlined),
          ),
          IconButton(
            tooltip: 'Export PDF and share',
            onPressed: _exporting ? null : () => _export(score, voices),
            icon: _exporting
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'feedback') {
                showFeedbackDialog(context, where: 'Hymn: ${score.title}');
                return;
              }
              setState(() {
              switch (v) {
                case 'repeats':
                  _followRepeats = !_followRepeats;
                case 'letters':
                  _letters = !_letters;
                case 'modulate':
                  _followKeyChanges = !_followKeyChanges;
                case 'minor':
                  _laBasedMinor = !_laBasedMinor;
                case 'bigger':
                  _textSize = (_textSize + 2).clamp(10.0, 30.0);
                case 'smaller':
                  _textSize = (_textSize - 2).clamp(10.0, 30.0);
                case 'written':
                  _performanceKey = null;
              }
            });
            },
            itemBuilder: (_) => [
              if (_written!.hasRepeats)
                CheckedPopupMenuItem(value: 'repeats', checked: _followRepeats, child: const Text('Follow repeats')),
              CheckedPopupMenuItem(
                  value: 'letters', checked: _letters, child: const Text('Sol-fa as letters (d r m)')),
              CheckedPopupMenuItem(
                  value: 'modulate', checked: _followKeyChanges, child: const Text('Move do at key changes')),
              CheckedPopupMenuItem(
                  value: 'minor', checked: _laBasedMinor, child: const Text('Minor keys start on la')),
              const PopupMenuItem(value: 'bigger', child: Text('Larger sol-fa text')),
              const PopupMenuItem(value: 'smaller', child: Text('Smaller sol-fa text')),
              const PopupMenuItem(value: 'written', child: Text('Back to the written key')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'feedback', child: Text('Send feedback')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<_View>(
                  segments: const [
                    ButtonSegment(value: _View.solfa, label: Text('Sol-fa'), icon: Icon(Icons.format_list_numbered)),
                    ButtonSegment(value: _View.staff, label: Text('Staff'), icon: Icon(Icons.music_note)),
                  ],
                  selected: {_view},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _view = s.first),
                ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_view == _View.solfa ? 'Highlight' : 'Voice',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: _voice,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (var i = 0; i < voices.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(voices[i].label, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                    ],
                    onChanged: (v) => setState(() => _voice = v ?? 0),
                  ),
                ]),
                KeyPicker(
                  label: 'Doh =',
                  value: _performanceKey ?? writtenDoh,
                  onChanged: (k) => setState(() => _performanceKey = k == writtenDoh ? null : k),
                ),
                Text('written in ${score.initialKey.displayName}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Expanded(
            child: _view == _View.solfa
                ? _CurwenView(
                    curwen: CurwenBuilder.build(score, voices,
                        performanceDoh: _perfDoh, options: _options, verse: _verse, letters: _letters),
                    highlight: _voice,
                    fontSize: _textSize,
                    controller: _scroll,
                  )
                : _StaffView(
                    line: SolfaBuilder.build(score, voices[_voice], performanceDoh: _perfDoh, options: _options),
                    verse: _verse,
                    controller: _scroll,
                  ),
          ),
        ],
      ),
      floatingActionButton: _VerseButtons(
        verses: verses,
        current: _verse,
        onSelect: (v) => setState(() => _verse = v),
      ),
      bottomNavigationBar: nav == null
          ? null
          : SetNavBar(nav: nav, onPrevious: () => _go(nav.onPrevious), onNext: () => _go(nav.onNext)),
    ),
    );
  }
}

/// All voices in Curwen sol-fa, wrapped to the screen width.
class _CurwenView extends StatelessWidget {
  final CurwenScore curwen;
  final int highlight;
  final double fontSize;
  final ScrollController controller;
  const _CurwenView(
      {required this.curwen, required this.highlight, required this.fontSize, required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, box) {
      final chars = ((box.maxWidth - 32) / (fontSize * kMonoCharWidth)).floor().clamp(20, 400);
      final systems = curwen.systems(chars);
      return ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Text('${curwen.keyLabel}${curwen.timeLabel == null ? '' : '   ${curwen.timeLabel}'}',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize, color: Colors.cyanAccent)),
          const SizedBox(height: 10),
          for (final system in systems)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in system.lines)
                    Text(
                      line.text,
                      softWrap: false,
                      style: kSheetTextStyle.copyWith(
                        fontSize: fontSize,
                        fontWeight: line.voice == highlight ? FontWeight.bold : FontWeight.normal,
                        color: switch (line.kind) {
                          CurwenLineKind.keyChange => Colors.amberAccent,
                          CurwenLineKind.words => scheme.onSurface,
                          CurwenLineKind.voice =>
                            line.voice == highlight ? Colors.cyanAccent : scheme.onSurface.withValues(alpha: 0.75),
                        },
                      ),
                    ),
                ],
              ),
            ),
          Text(
            '|  bar     :  beat     .  half beat     -  hold\n'
            "'  octave up     ₁  octave down",
            style: kSheetTextStyle.copyWith(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.5)),
          ),
        ],
      );
    });
  }
}

class _StaffView extends StatelessWidget {
  final SolfaLine line;
  final int verse;
  final ScrollController controller;
  const _StaffView({required this.line, required this.verse, required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final verses = line.track.verses;
    final metrics = StaffMetrics(verseCount: verses.isEmpty ? 0 : verses.length);
    return LayoutBuilder(builder: (context, box) {
      final layout = StaffLayout.build(line, width: box.maxWidth - 16, charWidth: metrics.lyricFontSize * 0.62);
      return SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.only(bottom: 120), // room for the verse buttons
        child: CustomPaint(
          size: Size(box.maxWidth, layout.rows.length * metrics.rowHeight),
          painter: StaffPainter(
            layout: layout,
            m: metrics,
            verses: verses,
            currentVerse: verse,
            ink: scheme.onSurface,
            accent: Colors.cyanAccent,
            dim: scheme.onSurface.withValues(alpha: 0.35),
          ),
        ),
      );
    });
  }
}

/// Big round buttons, one per verse, easy to hit with a thumb mid-song.
class _VerseButtons extends StatelessWidget {
  final List<int> verses;
  final int current;
  final ValueChanged<int> onSelect;
  const _VerseButtons({required this.verses, required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    if (verses.length < 2) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final v in verses.take(6))
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: SizedBox.square(
              dimension: 60,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                  backgroundColor: v == current ? Colors.cyanAccent : scheme.surfaceContainerHighest,
                  foregroundColor: v == current ? Colors.black : scheme.onSurface,
                ),
                onPressed: () => onSelect(v),
                child: Text('$v', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
      ],
    );
  }
}
