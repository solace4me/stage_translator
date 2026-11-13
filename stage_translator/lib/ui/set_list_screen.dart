// lib/ui/set_list_screen.dart
//
// Edit a set list: rename it, add songs (chord sheets, your hymns, or hymns
// from the built-in library), drag to reorder, remove. Every change is saved
// straight away. Play starts the set; tapping a song starts from that song.

import 'package:flutter/material.dart';

import '../data/hymn_catalog.dart';
import '../data/library_repository.dart';
import '../data/score_repository.dart';
import '../data/set_list.dart';
import '../data/sheet.dart';
import '../core/solfege_engine.dart';
import 'hymn_library_screen.dart';
import 'set_performance_screen.dart';

class SetListScreen extends StatefulWidget {
  final SetList setList;
  final SetListRepository repository;

  const SetListScreen({super.key, required this.setList, required this.repository});

  @override
  State<SetListScreen> createState() => _SetListScreenState();
}

class _SetListScreenState extends State<SetListScreen> {
  late SetList _set = widget.setList;
  late final TextEditingController _name = TextEditingController(text: _set.name);
  final _sheetsRepo = LibraryRepository();
  final _scoresRepo = ScoreRepository();
  Map<String, Sheet> _sheets = {};
  Map<String, SavedScore> _scores = {};
  bool _deleted = false; // don't re-save the name after deleting

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  @override
  void dispose() {
    _commitName();
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadSongs() async {
    final sheets = await _sheetsRepo.list();
    final scores = await _scoresRepo.list();
    if (!mounted) return;
    setState(() {
      _sheets = {for (final s in sheets) s.id: s};
      _scores = {for (final s in scores) s.id: s};
      // Keep remembered titles up to date with renames.
      _set = _set.copyWith(items: [for (final i in _set.items) i.withTitle(_title(i) ?? i.title)]);
    });
  }

  String? _title(SetItem i) =>
      i.kind == SetItemKind.sheet ? _sheets[i.refId]?.title : _scores[i.refId]?.title;

  void _update(SetList next) {
    setState(() => _set = next);
    widget.repository.save(next);
  }

  void _commitName() {
    if (_deleted) return;
    final name = _name.text.trim();
    if (name.isNotEmpty && name != _set.name) {
      _set = _set.copyWith(name: name);
      widget.repository.save(_set);
    }
  }

  String _detail(SetItem i) {
    if (i.kind == SetItemKind.sheet) {
      final s = _sheets[i.refId];
      if (s == null) return 'Deleted from your library';
      return '${s.notation == LabelNotation.numbers ? '1' : 'Doh'} = ${s.performanceKey} · chord sheet';
    }
    final s = _scores[i.refId];
    if (s == null) return 'Deleted from your hymns';
    return '${s.performanceKey == null ? 'Written key' : 'Doh = ${s.performanceKey}'} · hymn';
  }

  Future<void> _add() async {
    final added = await Navigator.of(context).push<List<SetItem>>(MaterialPageRoute(
      builder: (_) => _AddSongsScreen(already: _set.items.toSet()),
      fullscreenDialog: true,
    ));
    final fresh = added?.where((a) => !_set.items.contains(a)).toList() ?? const <SetItem>[];
    if (fresh.isEmpty) return;
    _update(_set.copyWith(items: [..._set.items, ...fresh]));
    _loadSongs();
  }

  /// Asks first. Only the set is deleted, never the songs in it.
  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete "${_name.text.trim().isEmpty ? _set.name : _name.text.trim()}"?'),
        content: const Text('The songs stay in your library. Only this set list is removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    _deleted = true;
    await widget.repository.delete(_set.id);
    if (mounted) Navigator.pop(context);
  }

  void _play(int start) {
    _commitName();
    if (_set.items.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SetPerformanceScreen(setList: _set, startIndex: start),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final items = _set.items;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _name,
          style: Theme.of(context).textTheme.titleMedium,
          decoration: const InputDecoration(border: InputBorder.none, isDense: true, hintText: 'Set list name'),
          onSubmitted: (_) => _commitName(),
          onTapOutside: (_) {
            FocusScope.of(context).unfocus();
            _commitName();
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Play the set',
            onPressed: items.isEmpty ? null : () => _play(0),
            icon: const Icon(Icons.play_arrow),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _delete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete this set')),
            ],
          ),
        ],
      ),
      body: items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Add the songs for your service or gig, in order.\n\n'
                    'Each song keeps the key you chose for it. While playing, use the '
                    'next/previous buttons or a Bluetooth page-turner pedal.',
                    textAlign: TextAlign.center),
              ),
            )
          : ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: items.length,
              onReorder: (from, to) {
                final list = [...items];
                if (to > from) to -= 1;
                list.insert(to, list.removeAt(from));
                _update(_set.copyWith(items: list));
              },
              itemBuilder: (_, i) {
                final item = items[i];
                return ListTile(
                  key: ValueKey('${item.kind.name}:${item.refId}'),
                  leading: CircleAvatar(child: Text('${i + 1}')),
                  title: Text(item.title),
                  subtitle: Text(_detail(item)),
                  onTap: () => _play(i),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'Remove from set',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => _update(_set.copyWith(items: [...items]..removeAt(i))),
                    ),
                    ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                  ]),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addsongs',
        onPressed: _add,
        icon: const Icon(Icons.playlist_add),
        label: const Text('Add songs'),
      ),
    );
  }
}

/// Tick the songs to add, in the order you want them.
class _AddSongsScreen extends StatefulWidget {
  final Set<SetItem> already;
  const _AddSongsScreen({required this.already});

  @override
  State<_AddSongsScreen> createState() => _AddSongsScreenState();
}

class _AddSongsScreenState extends State<_AddSongsScreen> {
  final _sheetsRepo = LibraryRepository();
  final _scoresRepo = ScoreRepository();
  List<Sheet> _sheets = [];
  List<SavedScore> _scores = [];
  final List<SetItem> _picked = [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sheets = await _sheetsRepo.list();
    final scores = await _scoresRepo.list();
    if (!mounted) return;
    setState(() {
      _sheets = sheets;
      _scores = scores;
      _loading = false;
    });
  }

  void _toggle(SetItem item) => setState(() {
        if (!_picked.remove(item)) _picked.add(item);
      });

  /// A hymn from the built-in library: save it to "My hymns" (once) so the
  /// set can remember its key, then tick it.
  Future<void> _fromLibrary() async {
    final h = await Navigator.of(context).push<HymnEntry>(MaterialPageRoute(
      builder: (_) => HymnLibraryScreen(repository: _scoresRepo, pick: true),
    ));
    if (h == null) return;
    var saved = await _scoresRepo.findBySource(h.source);
    if (saved == null) {
      saved = SavedScore(id: ScoreRepository.newId(), title: h.title, updatedAt: DateTime.now(), source: h.source);
      await _scoresRepo.save(saved, bytes: await HymnCatalog.bytes(h.id));
    }
    await _load();
    final item = SetItem(kind: SetItemKind.score, refId: saved.id, title: saved.title);
    if (!_picked.contains(item) && !widget.already.contains(item)) setState(() => _picked.add(item));
  }

  Widget _tile(SetItem item, String subtitle) {
    final order = _picked.indexOf(item);
    final inSet = widget.already.contains(item);
    return ListTile(
      leading: order >= 0
          ? CircleAvatar(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black, child: Text('${order + 1}'))
          : const CircleAvatar(child: Icon(Icons.add)),
      title: Text(item.title),
      subtitle: Text(inSet ? '$subtitle · already in this set' : subtitle),
      enabled: !inSet,
      onTap: () => _toggle(item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final sheets = _sheets.where((s) => s.title.toLowerCase().contains(q)).toList();
    final scores = _scores.where((s) => s.title.toLowerCase().contains(q)).toList();
    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(t, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.cyanAccent)),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add songs'),
        actions: [
          TextButton(
            onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, _picked),
            child: Text(_picked.isEmpty ? 'Add' : 'Add ${_picked.length}'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search your songs',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                ListTile(
                  leading: const Icon(Icons.menu_book),
                  title: const Text('From the hymn library'),
                  subtitle: const Text('300 public-domain hymns'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _fromLibrary,
                ),
                if (scores.isNotEmpty) header('My hymns'),
                for (final s in scores)
                  _tile(SetItem(kind: SetItemKind.score, refId: s.id, title: s.title),
                      s.performanceKey == null ? 'Written key' : 'Doh = ${s.performanceKey}'),
                if (sheets.isNotEmpty) header('Chord sheets'),
                for (final s in sheets)
                  _tile(SetItem(kind: SetItemKind.sheet, refId: s.id, title: s.title),
                      '${s.notation == LabelNotation.numbers ? '1' : 'Doh'} = ${s.performanceKey}'),
                if (sheets.isEmpty && scores.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No saved songs yet. Pick from the hymn library above, '
                        'or save chord sheets and hymns first.', textAlign: TextAlign.center),
                  ),
              ],
            ),
    );
  }
}
