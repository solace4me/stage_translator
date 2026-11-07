// lib/ui/review_screen.dart
//
// Step between OCR and translation: fix misreads in the raw text, confirm the
// key the sheet is written in (auto-detected), and pick the performance key.

import 'package:flutter/material.dart';

import '../core/solfege_engine.dart';
import '../data/library_repository.dart';
import '../data/sheet.dart';
import 'key_picker.dart';
import 'sheet_screen.dart';
import 'sheet_style.dart';

class ReviewScreen extends StatefulWidget {
  final String rawText;
  final LibraryRepository repository;

  const ReviewScreen({super.key, required this.rawText, required this.repository});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final TextEditingController _text = TextEditingController(text: widget.rawText);
  final _title = TextEditingController(text: 'Untitled song');
  String _sheetKey = 'C';
  String _performanceKey = 'C';
  bool _keyTouched = false; // stop auto-detect once the user picks a key

  @override
  void initState() {
    super.initState();
    _applyDetectedKey();
    _text.addListener(() => setState(_applyDetectedKey));
  }

  /// Sets both keys to the detected key until the user picks one by hand.
  void _applyDetectedKey() {
    if (_keyTouched) return;
    final k = SolfegeEngine.detectKey(_text.text);
    if (k == null) return;
    _sheetKey = k.toString();
    _performanceKey = _sheetKey;
  }

  void _translate() {
    final sheetKey = NoteName.parse(_sheetKey);
    final perfKey = NoteName.parse(_performanceKey);
    const options = TranslateOptions();
    final translated = SolfegeEngine.process(
      _text.text,
      sheetKey: sheetKey,
      performanceKey: perfKey,
      options: options,
    );
    final now = DateTime.now();
    final sheet = Sheet(
      id: LibraryRepository.newId(),
      title: _title.text.trim().isEmpty ? 'Untitled song' : _title.text.trim(),
      rawText: _text.text,
      translatedText: translated,
      sheetKey: _sheetKey,
      performanceKey: _performanceKey,
      lettersKey: _performanceKey, // letters were transposed into Doh's key
      createdAt: now,
      updatedAt: now,
    );
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => SheetScreen(sheet: sheet, repository: widget.repository, isNew: true),
    ));
  }

  @override
  void dispose() {
    _text.dispose();
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Check the scan')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Song title', isDense: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Wrap(
              spacing: 24,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                KeyPicker(
                  label: 'Written in',
                  value: _sheetKey,
                  onChanged: (k) => setState(() {
                    _keyTouched = true;
                    _sheetKey = k;
                  }),
                ),
                KeyPicker(
                  label: 'Doh =',
                  value: _performanceKey,
                  onChanged: (k) => setState(() {
                    _keyTouched = true;
                    _performanceKey = k;
                  }),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Fix any misread chords below (e.g. "8m" should be "Bm"), then translate.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: _text,
                maxLines: null,
                expands: true,
                keyboardType: TextInputType.multiline,
                style: kSheetTextStyle.copyWith(fontSize: 14),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Paste or type a chord sheet here...',
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: FilledButton.icon(
            onPressed: _text.text.trim().isEmpty ? null : _translate,
            icon: const Icon(Icons.translate),
            label: const Text('Translate to solfège'),
          ),
        ),
      ),
    );
  }
}
