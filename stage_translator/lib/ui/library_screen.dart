// lib/ui/library_screen.dart
//
// Home screen with three tabs:
//   * Chord sheets: letter chords over lyrics (D, Bm, G ...) -> "D [do]"
//   * Hymns: staff notation (notes on five lines) -> tonic sol-fa, plus the
//     built-in hymn library
//   * Sets: set lists for a service or gig
// Each tab has its own list and one + button.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/solfege_engine.dart';
import '../data/library_repository.dart';
import '../data/score_repository.dart';
import '../data/set_list.dart';
import '../data/sheet.dart';
import '../services/feedback_service.dart';
import 'feedback_dialog.dart';
import 'hymn_import_guide.dart';
import 'hymn_library_screen.dart';
import 'review_screen.dart';
import 'scan_screen.dart';
import 'score_screen.dart';
import 'set_list_screen.dart';
import 'set_performance_screen.dart';
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
  final _setsRepo = SetListRepository();
  List<Sheet> _sheets = [];
  List<SavedScore> _scores = [];
  List<SetList> _sets = [];
  String _query = '';
  bool _loading = true;
  int _tab = 0; // 0 = chord sheets, 1 = hymns, 2 = sets

  @override
  void initState() {
    super.initState();
    _reload();
    FeedbackService.flush(); // send any feedback written while offline
    // Refresh whenever anything is saved or deleted, from any screen. (New
    // sheets pass through screens that replace each other, so waiting for
    // "the screen I opened has closed" fires too early.)
    LibraryRepository.changes.addListener(_reload);
    ScoreRepository.changes.addListener(_reload);
    SetListRepository.changes.addListener(_reload);
  }

  @override
  void dispose() {
    LibraryRepository.changes.removeListener(_reload);
    ScoreRepository.changes.removeListener(_reload);
    SetListRepository.changes.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final sheets = await _sheetsRepo.list();
    final scores = await _scoresRepo.list();
    final sets = await _setsRepo.list();
    if (!mounted) return;
    setState(() {
      _sheets = sheets;
      _scores = scores;
      _sets = sets;
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
              leading: const Icon(Icons.menu_book),
              title: const Text('Hymn library'),
              subtitle: const Text('300 public-domain hymns, ready to play'),
              onTap: () {
                Navigator.pop(c);
                _openHymnLibrary();
              },
            ),
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

  void _openHymnLibrary() => _open(HymnLibraryScreen(repository: _scoresRepo));

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

  // ------------------------------------------------------------------- sets

  Future<void> _newSet() async {
    final now = DateTime.now();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final set = SetList(
      id: SetListRepository.newId(),
      name: 'Set ${now.day} ${months[now.month - 1]}',
      updatedAt: now,
    );
    await _setsRepo.save(set);
    if (!mounted) return;
    await _open(SetListScreen(setList: set, repository: _setsRepo));
  }

  /// Same songs and keys under a new name, e.g. to reuse last Sunday's set.
  Future<void> _duplicateSet(SetList s) async {
    final copy = SetList(
      id: SetListRepository.newId(),
      name: '${s.name} (copy)',
      items: [...s.items],
      updatedAt: DateTime.now(),
    );
    await _setsRepo.save(copy);
    if (!mounted) return;
    await _open(SetListScreen(setList: copy, repository: _setsRepo));
  }

  Future<void> _deleteSet(SetList s) async {
    await _setsRepo.delete(s.id);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Deleted "${s.name}"'),
      action: SnackBarAction(
        label: 'UNDO',
        onPressed: () async {
          await _setsRepo.save(s);
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
    final isSets = _tab == 2;

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
    } else if (isSets) {
      final items = _sets.where((s) => s.name.toLowerCase().contains(q)).toList();
      list = items.isEmpty && q.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Set lists\n\nPut the songs for a service or gig in order, each in its own key. '
                    'Then play straight through with next/previous, or a Bluetooth page-turner pedal.\n\n'
                    'Tap + to make one.',
                    textAlign: TextAlign.center),
              ),
            )
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) {
                final s = items[i];
                return _Swipe(
                  id: s.id,
                  onDelete: () => _deleteSet(s),
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${s.items.length}')),
                    title: Text(s.name),
                    subtitle: Text(s.items.isEmpty
                        ? 'No songs yet'
                        : s.items.take(3).map((e) => e.title).join(' · ') + (s.items.length > 3 ? ' …' : '')),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Play the set',
                        icon: const Icon(Icons.play_circle, size: 36),
                        onPressed: s.items.isEmpty ? null : () => _open(SetPerformanceScreen(setList: s)),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        onSelected: (v) {
                          if (v == 'copy') _duplicateSet(s);
                          if (v == 'delete') _deleteSet(s);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'copy',
                            child: ListTile(leading: Icon(Icons.copy), title: Text('Duplicate'), dense: true),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete'), dense: true),
                          ),
                        ],
                      ),
                    ]),
                    onTap: () => _open(SetListScreen(setList: s, repository: _setsRepo)),
                  ),
                );
              },
            );
    } else {
      final items = _scores.where((s) => s.title.toLowerCase().contains(q)).toList();
      final libraryTile = Card(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: ListTile(
          leading: const Icon(Icons.menu_book, color: Colors.cyanAccent),
          title: const Text('Hymn library'),
          subtitle: const Text('300 public-domain hymns · search by title or first line'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openHymnLibrary,
        ),
      );
      list = items.isEmpty && q.isEmpty
          ? Column(children: [
              libraryTile,
              const Expanded(child: _EmptyTab(
              title: 'Hymns',
              explain: 'For music written as notes on five lines. The app writes it out '
                  'in tonic sol-fa for every voice, in any key you choose.',
              exampleBefore: '♩ ♩ ♩ ♩ on the staff',
              exampleAfter: 'S |d  :r  :m  :f  |\nA |s₁ :t₁ :d  :d  |',
              action: 'Open one from the hymn library, or tap + to open a hymn file (.mxl from MuseScore).',
              )),
            ])
          : ListView.builder(
              itemCount: items.length + 1,
              itemBuilder: (_, j) {
                if (j == 0) return libraryTile;
                final s = items[j - 1];
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
        actions: [
          IconButton(
            tooltip: 'Send feedback',
            icon: const Icon(Icons.feedback_outlined),
            onPressed: () => showFeedbackDialog(context,
                where: switch (_tab) { 0 => 'Home: chord sheets', 1 => 'Home: hymns', _ => 'Home: sets' }),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: isChords
                    ? 'Search chord sheets'
                    : isSets
                        ? 'Search set lists'
                        : 'Search my hymns',
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
        onPressed: isChords
            ? _addChordSheet
            : isSets
                ? _newSet
                : _addHymn,
        icon: const Icon(Icons.add),
        label: Text(isChords
            ? 'Chord sheet'
            : isSets
                ? 'Set list'
                : 'Hymn'),
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
          NavigationDestination(
            icon: Icon(Icons.format_list_numbered_outlined),
            selectedIcon: Icon(Icons.format_list_numbered),
            label: 'Sets',
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
