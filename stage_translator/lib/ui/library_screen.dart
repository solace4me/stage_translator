// lib/ui/library_screen.dart
//
// Home screen with two clearly separate tabs:
//   * Chord sheets: letter chords over lyrics (D, Bm, G ...) -> "D [do]"
//   * Hymns: staff notation (notes on five lines) -> tonic sol-fa
// Each tab has its own list, one + button, and an example of what it is for.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/solfege_engine.dart';
import '../data/library_repository.dart';
import '../data/score_repository.dart';
import '../data/sheet.dart';
import 'hymn_import_guide.dart';
import 'review_screen.dart';
import 'scan_screen.dart';
import 'score_screen.dart';
import 'sheet_screen.dart';
import 'sheet_style.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _sheetsRepo = LibraryRepository();
  final _scoresRepo = ScoreRepository();
  List<Sheet> _sheets = [];
  List<SavedScore> _scores = [];
  String _query = '';
  bool _loading = true;
  int _tab = 0; // 0 = chord sheets, 1 = hymns

  @override
  void initState() {
    super.initState();
    _reload();
    // Refresh whenever anything is saved or deleted, from any screen. (New
    // sheets pass through screens that replace each other, so waiting for
    // "the screen I opened has closed" fires too early.)
    LibraryRepository.changes.addListener(_reload);
    ScoreRepository.changes.addListener(_reload);
  }

  @override
  void dispose() {
    LibraryRepository.changes.removeListener(_reload);
    ScoreRepository.changes.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final sheets = await _sheetsRepo.list();
    final scores = await _scoresRepo.list();
    if (!mounted) return;
    setState(() {
      _sheets = sheets;
      _scores = scores;
      _loading = false;
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _reload();
  }

  // ------------------------------------------------------------ chord sheets

  void _addChordSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetTitle('New chord sheet', 'Letter chords written over the words, like D  Bm  A  G'),
            ListTile(
              leading: const Icon(Icons.document_scanner),
              title: const Text('Take a photo or choose a picture'),
              subtitle: const Text('The app reads the chords and words for you'),
              onTap: () {
                Navigator.pop(c);
                _open(ScanScreen(repository: _sheetsRepo));
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Type or paste it'),
              subtitle: const Text('For chord sheets copied from a website or chat'),
              onTap: () {
                Navigator.pop(c);
                _open(ReviewScreen(rawText: '', repository: _sheetsRepo));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSheet(Sheet s) async {
    await _sheetsRepo.delete(s.id);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Deleted "${s.title}"'),
      action: SnackBarAction(
        label: 'UNDO',
        onPressed: () async {
          await _sheetsRepo.save(s);
          _reload();
        },
      ),
    ));
  }

  // ------------------------------------------------------------------ hymns

  void _addHymn() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetTitle('New hymn', 'Music written as notes on five lines (staff notation)'),
            ListTile(
              leading: const Icon(Icons.library_music),
              title: const Text('Open a hymn file'),
              subtitle: const Text('A MuseScore file: .mxl or .musicxml'),
              onTap: () {
                Navigator.pop(c);
                _pickHymnFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('I only have a PDF or a photo'),
              subtitle: const Text('How to turn it into a hymn file, free'),
              onTap: () {
                Navigator.pop(c);
                _open(const HymnImportGuide());
              },
            ),
            ListTile(
              leading: const Icon(Icons.travel_explore),
              title: const Text('Where to find hymn files'),
              subtitle: const Text('Free sites with hymns ready to open'),
              onTap: () {
                Navigator.pop(c);
                _open(const HymnImportGuide(startOnFind: true));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickHymnFile() async {
    // Any file type: Android doesn't know .mxl, so a filter would hide them.
    final result = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (result == null || result.files.isEmpty || !mounted) return;
    final f = result.files.single;
    final name = f.name.toLowerCase();
    final isScore = name.endsWith('.mxl') || name.endsWith('.musicxml') || name.endsWith('.xml');
    if (!isScore) {
      final isPicture = ['.pdf', '.jpg', '.jpeg', '.png', '.heic', '.webp'].any(name.endsWith);
      if (isPicture) {
        await _open(const HymnImportGuide(cameFromPicture: true));
      } else if (name.endsWith('.mscz') || name.endsWith('.mscx')) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('That is MuseScore\'s own format. In MuseScore choose '
              'File › Export › MusicXML (.mxl), then open that file here.'),
          duration: Duration(seconds: 6),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This file isn\'t a hymn file. Choose a .mxl or .musicxml file.'),
        ));
      }
      return;
    }
    final bytes = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
    if (bytes == null || !mounted) return;
    await _open(ScoreScreen(bytes: bytes, repository: _scoresRepo));
  }

  Future<void> _openScore(SavedScore s) async {
    final bytes = await _scoresRepo.readFile(s.id);
    if (!mounted) return;
    await _open(ScoreScreen(bytes: bytes, repository: _scoresRepo, saved: s));
  }

  Future<void> _deleteScore(SavedScore s) async {
    final bytes = await _scoresRepo.readFile(s.id);
    await _scoresRepo.delete(s.id);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Deleted "${s.title}"'),
      action: SnackBarAction(
        label: 'UNDO',
        onPressed: () async {
          await _scoresRepo.save(s, bytes: bytes);
          _reload();
        },
      ),
    ));
  }

  // --------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final isChords = _tab == 0;

    final Widget list;
    if (_loading) {
      list = const Center(child: CircularProgressIndicator());
    } else if (isChords) {
      final items = _sheets.where((s) => s.title.toLowerCase().contains(q)).toList();
      list = items.isEmpty && q.isEmpty
          ? const _EmptyTab(
              title: 'Chord sheets',
              explain: 'For songs written with letter chords over the words. '
                  'The app adds your sol-fa next to every chord, in the key you play in.',
              exampleBefore: '   D        Bm\nAll my words fall short',
              exampleAfter: '   D [do]   Bm [la]\nAll my words fall short',
              action: 'Tap + to scan, upload or paste one.',
            )
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) {
                final s = items[i];
                return _Swipe(
                  id: s.id,
                  onDelete: () => _deleteSheet(s),
                  child: ListTile(
                    leading: CircleAvatar(child: Text(s.performanceKey)),
                    title: Text(s.title),
                    subtitle: Text('${s.notation == LabelNotation.numbers ? '1' : 'Doh'} = ${s.performanceKey}'
                        ' · ${s.notation == LabelNotation.numbers ? 'numbers' : 'sol-fa'}'
                        ' · written in ${s.sheetKey}'),
                    onTap: () => _open(SheetScreen(sheet: s, repository: _sheetsRepo)),
                  ),
                );
              },
            );
    } else {
      final items = _scores.where((s) => s.title.toLowerCase().contains(q)).toList();
      list = items.isEmpty && q.isEmpty
          ? const _EmptyTab(
              title: 'Hymns',
              explain: 'For music written as notes on five lines. The app writes it out '
                  'in tonic sol-fa for every voice, in any key you choose.',
              exampleBefore: '♩ ♩ ♩ ♩ on the staff',
              exampleAfter: 'S |d  :r  :m  :f  |\nA |s₁ :t₁ :d  :d  |',
              action: 'Tap + to open a hymn file (.mxl from MuseScore).',
            )
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) {
                final s = items[i];
                return _Swipe(
                  id: s.id,
                  onDelete: () => _deleteScore(s),
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.music_note)),
                    title: Text(s.title),
                    subtitle: Text(s.performanceKey == null ? 'Written key' : 'Doh = ${s.performanceKey}'),
                    onTap: () => _openScore(s),
                  ),
                );
              },
            );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stage Translator Pro'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: isChords ? 'Search chord sheets' : 'Search hymns',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
      ),
      body: list,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add',
        onPressed: isChords ? _addChordSheet : _addHymn,
        icon: const Icon(Icons.add),
        label: Text(isChords ? 'Chord sheet' : 'Hymn'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.queue_music_outlined),
            selectedIcon: Icon(Icons.queue_music),
            label: 'Chord sheets',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music),
            label: 'Hymns',
          ),
        ],
      ),
    );
  }
}

class _Swipe extends StatelessWidget {
  final String id;
  final VoidCallback onDelete;
  final Widget child;
  const _Swipe({required this.id, required this.onDelete, required this.child});

  @override
  Widget build(BuildContext context) => Dismissible(
        key: ValueKey(id),
        direction: DismissDirection.endToStart,
        background: Container(
          color: Colors.red.shade700,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          child: const Icon(Icons.delete),
        ),
        onDismissed: (_) => onDelete(),
        child: child,
      );
}

class _SheetTitle extends StatelessWidget {
  final String title, subtitle;
  const _SheetTitle(this.title, this.subtitle);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

/// What a tab is for, with a before/after example, shown until it has items.
class _EmptyTab extends StatelessWidget {
  final String title, explain, exampleBefore, exampleAfter, action;
  const _EmptyTab({
    required this.title,
    required this.explain,
    required this.exampleBefore,
    required this.exampleAfter,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget box(String label, String text, Color color) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 4),
              Text(text, style: kSheetTextStyle.copyWith(fontSize: 14, color: color)),
            ],
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(explain),
        const SizedBox(height: 16),
        box('Your sheet', exampleBefore, scheme.onSurface),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Center(child: Icon(Icons.arrow_downward)),
        ),
        box('In the app', exampleAfter, Colors.cyanAccent),
        const SizedBox(height: 16),
        Text(action, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
