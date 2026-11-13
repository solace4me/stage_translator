// lib/ui/sheet_screen.dart
//
// The live sheet: pick Doh and the sheet re-translates instantly, keeping any
// hand edits. Editable monospace text that fits the screen width, text size
// controls, screen kept awake, save to library, PDF export and share.
// Play do (tap) / do chord (hold). Pedal: forward scrolls a page, and at the
// end moves to the next song of a set list (only while not typing).

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/solfege_engine.dart';
import '../data/library_repository.dart';
import '../data/sheet.dart';
import '../services/pdf_exporter.dart';
import '../services/tone_player.dart';
import 'feedback_dialog.dart';
import 'key_picker.dart';
import 'pedal.dart';
import 'play_button.dart';
import 'set_nav.dart';
import 'sheet_style.dart';

class SheetScreen extends StatefulWidget {
  final Sheet sheet;
  final LibraryRepository repository;
  final bool isNew;

  /// Set when playing a set list (previous/next bar, pedal goes to next song).
  final SetNav? setNav;

  const SheetScreen({
    super.key,
    required this.sheet,
    required this.repository,
    this.isNew = false,
    this.setNav,
  });

  @override
  State<SheetScreen> createState() => _SheetScreenState();
}

class _SheetScreenState extends State<SheetScreen> {
  late Sheet _sheet = widget.sheet;
  late final TextEditingController _text = TextEditingController(text: _sheet.translatedText);
  late final TextEditingController _title = TextEditingController(text: _sheet.title);
  late bool _dirty = widget.isNew;
  bool _fitWidth = true;
  double _fontSize = 16;
  bool _sharing = false;
  final _scroll = ScrollController();
  final _textFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.setNav == null) WakelockPlus.enable(); // keep the screen on (a set does it itself)
    // Rebuild on every edit: the fit-to-width size depends on the longest line.
    // (The controller also fires on cursor moves, so compare the text.)
    var last = _text.text;
    _text.addListener(() {
      if (_text.text == last) return;
      last = _text.text;
      setState(() => _dirty = true);
    });
  }

  @override
  void dispose() {
    if (widget.setNav == null) WakelockPlus.disable();
    _scroll.dispose();
    _textFocus.dispose();
    _text.dispose();
    _title.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ re-translate
  //
  // All of these work on the text in the editor (hand edits included):
  // labels are stripped and rebuilt, letters are moved from the key they are
  // currently written in (lettersKey).

  TranslateOptions get _options => TranslateOptions(
        transposeLetters: _sheet.transposeLetters,
        showQuality: _sheet.showQuality,
        notation: _sheet.notation,
      );

  bool get _numbers => _sheet.notation == LabelNotation.numbers;

  /// Switch between sol-fa and numbers, keeping hand edits.
  void _setNotation(LabelNotation notation) {
    if (notation == _sheet.notation) return;
    final next = _sheet.copyWith(notation: notation);
    final text = SolfegeEngine.process(
      _text.text,
      sheetKey: NoteName.parse(_sheet.lettersKey),
      performanceKey: NoteName.parse(_sheet.performanceKey),
      options: TranslateOptions(
        transposeLetters: next.transposeLetters,
        showQuality: next.showQuality,
        notation: notation,
      ),
    );
    _apply(text, next);
  }

  void _apply(String text, Sheet next) {
    setState(() {
      _sheet = next;
      _text.value = TextEditingValue(text: text);
      _dirty = true;
    });
  }

  void _changePerformanceKey(String key) {
    final from = NoteName.parse(_sheet.lettersKey);
    final to = NoteName.parse(key);
    final text = SolfegeEngine.process(_text.text,
        sheetKey: from, performanceKey: to, options: _options);
    _apply(
      text,
      _sheet.copyWith(
        performanceKey: key,
        lettersKey: _sheet.transposeLetters ? key : _sheet.lettersKey,
      ),
    );
  }

  void _toggleQuality(bool on) {
    final next = _sheet.copyWith(showQuality: on);
    final text = SolfegeEngine.process(
      _text.text,
      sheetKey: NoteName.parse(_sheet.lettersKey),
      performanceKey: NoteName.parse(_sheet.performanceKey),
      options: TranslateOptions(transposeLetters: next.transposeLetters, showQuality: on, notation: next.notation),
    );
    _apply(text, next);
  }

  void _toggleTranspose(bool on) {
    final perf = NoteName.parse(_sheet.performanceKey);
    final sheetKey = NoteName.parse(_sheet.sheetKey);
    final letters = NoteName.parse(_sheet.lettersKey);
    String text;
    if (on) {
      // Letters (in the sheet key) -> performance key.
      text = SolfegeEngine.process(_text.text,
          sheetKey: letters,
          performanceKey: perf,
          options: TranslateOptions(showQuality: _sheet.showQuality, notation: _sheet.notation));
    } else {
      // Move letters back to the sheet key, then label them against Doh.
      final back = SolfegeEngine.process(_text.text, sheetKey: letters, performanceKey: sheetKey);
      text = SolfegeEngine.process(back,
          sheetKey: sheetKey,
          performanceKey: perf,
          options: TranslateOptions(
              transposeLetters: false, showQuality: _sheet.showQuality, notation: _sheet.notation));
    }
    _apply(
      text,
      _sheet.copyWith(transposeLetters: on, lettersKey: on ? _sheet.performanceKey : _sheet.sheetKey),
    );
  }

  Future<void> _retranslateFromScan() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Re-translate from the scan?'),
        content: const Text('This replaces your edits with a fresh translation of the scanned text.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Re-translate')),
        ],
      ),
    );
    if (ok != true) return;
    final text = SolfegeEngine.process(_sheet.rawText,
        sheetKey: NoteName.parse(_sheet.sheetKey),
        performanceKey: NoteName.parse(_sheet.performanceKey),
        options: _options);
    _apply(
      text,
      _sheet.copyWith(lettersKey: _sheet.transposeLetters ? _sheet.performanceKey : _sheet.sheetKey),
    );
  }

  // -------------------------------------------------------- save and share

  Sheet get _current => _sheet.copyWith(
        title: _title.text.trim().isEmpty ? 'Untitled song' : _title.text.trim(),
        translatedText: _text.text,
        updatedAt: DateTime.now(),
      );

  Future<void> _save() async {
    final s = _current;
    await widget.repository.save(s);
    if (!mounted) return;
    setState(() {
      _sheet = s;
      _dirty = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to library')));
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      await PdfExporter.share(_current);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Save changes?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'discard'), child: const Text('Discard')),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Save')),
        ],
      ),
    );
    if (choice == 'save') await _save();
    return choice != null;
  }

  // ------------------------------------------------------- play do / set

  int get _dohSemitone => NoteName.parse(_sheet.performanceKey).semitone;

  void _onPedal(PedalAction a) {
    if (pageScroll(_scroll, a)) return;
    _go(a == PedalAction.forward ? widget.setNav?.onNext : widget.setNav?.onPrevious);
  }

  /// In a set: keep any change (key, edits) and move on without asking.
  Future<void> _go(VoidCallback? move) async {
    if (move == null) return;
    if (_dirty) await _save();
    move();
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final nav = widget.setNav;
    return Pedal(
      onPedal: _onPedal,
      enabled: () => !_textFocus.hasFocus, // typing on a keyboard still works
      child: PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _title,
            style: Theme.of(context).textTheme.titleMedium,
            decoration: const InputDecoration(border: InputBorder.none, isDense: true),
            onChanged: (_) => setState(() => _dirty = true),
          ),
          actions: [
            PlayDohButton(
              label: _numbers ? '1' : 'do',
              onTap: () => TonePlayer.play(ToneSynth.doh(_dohSemitone)),
              onLongPress: () => TonePlayer.play(ToneSynth.dohChord(_dohSemitone)),
            ),
            IconButton(
              tooltip: 'Save to library',
              onPressed: _save,
              icon: Icon(_dirty ? Icons.save : Icons.check),
            ),
            IconButton(
              tooltip: 'Export PDF and share',
              onPressed: _sharing ? null : _share,
              icon: _sharing
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.ios_share),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'solfege':
                    _setNotation(LabelNotation.solfege);
                  case 'numbers':
                    _setNotation(LabelNotation.numbers);
                  case 'quality':
                    _toggleQuality(!_sheet.showQuality);
                  case 'transpose':
                    _toggleTranspose(!_sheet.transposeLetters);
                  case 'fit':
                    setState(() => _fitWidth = !_fitWidth);
                  case 'rescan':
                    _retranslateFromScan();
                  case 'feedback':
                    showFeedbackDialog(context, where: 'Chord sheet: ${_sheet.title}');
                }
              },
              itemBuilder: (_) => [
                // Either/or: exactly one of these two is ticked.
                CheckedPopupMenuItem(
                    value: 'solfege', checked: !_numbers, child: const Text('Sol-fa (do re mi)')),
                CheckedPopupMenuItem(
                    value: 'numbers', checked: _numbers, child: const Text('Numbers (1 2 3)')),
                const PopupMenuDivider(),
                CheckedPopupMenuItem(
                    value: 'quality', checked: _sheet.showQuality, child: const Text('Show chord quality')),
                CheckedPopupMenuItem(
                    value: 'transpose',
                    checked: _sheet.transposeLetters,
                    child: const Text('Transpose letters to Doh')),
                CheckedPopupMenuItem(value: 'fit', checked: _fitWidth, child: const Text('Fit to screen width')),
                const PopupMenuItem(value: 'rescan', child: Text('Re-translate from scan')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'feedback', child: Text('Send feedback')),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  KeyPicker(
                    label: _numbers ? '1 =' : 'Doh =',
                    value: _sheet.performanceKey,
                    onChanged: _changePerformanceKey,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'written in ${_sheet.sheetKey}',
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Smaller text',
                    onPressed: () => setState(() => _fontSize = (_fontSize - 2).clamp(12.0, 28.0)),
                    icon: const Icon(Icons.text_decrease),
                  ),
                  IconButton(
                    tooltip: 'Larger text',
                    onPressed: () => setState(() => _fontSize = (_fontSize + 2).clamp(12.0, 28.0)),
                    icon: const Icon(Icons.text_increase),
                  ),
                ],
              ),
            ),
            Expanded(child: _editor()),
          ],
        ),
        bottomNavigationBar: nav == null
            ? null
            : SetNavBar(nav: nav, onPrevious: () => _go(nav.onPrevious), onNext: () => _go(nav.onNext)),
      ),
    ),
    );
  }

  /// Fit mode shrinks the font so the longest line fits (down to 10 pt).
  /// Otherwise lines never wrap and the sheet scrolls sideways, which keeps
  /// chords exactly above their words.
  Widget _editor() {
    return LayoutBuilder(builder: (context, box) {
      const padding = 24.0;
      final lines = _text.text.split('\n');
      final longest = lines.fold<int>(1, (m, l) => l.length > m ? l.length : m);
      final available = box.maxWidth - padding * 2;
      final fitted = available / (longest * kMonoCharWidth);
      final size = _fitWidth ? fitted.clamp(10.0, _fontSize) : _fontSize;
      final contentWidth = longest * kMonoCharWidth * size + 32;

      final field = TextField(
        controller: _text,
        focusNode: _textFocus,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        style: kSheetTextStyle.copyWith(fontSize: size),
        decoration: const InputDecoration(border: InputBorder.none),
      );

      return Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        padding: const EdgeInsets.symmetric(horizontal: padding - 8, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          controller: _scroll,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth > available ? contentWidth : available,
              child: field,
            ),
          ),
        ),
      );
    });
  }
}
