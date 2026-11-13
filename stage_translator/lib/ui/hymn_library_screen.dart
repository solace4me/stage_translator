// lib/ui/hymn_library_screen.dart
//
// Browse and search the built-in hymn library (Open Hymnal, public domain).
// Search matches title, first line, tune name, author, composer and topic.
// Tap a hymn to open it; tap the bookmark there to keep it in "My hymns".
// In pick mode (adding to a set list) tapping a hymn returns it instead.

import 'package:flutter/material.dart';

import '../data/hymn_catalog.dart';
import '../data/score_repository.dart';
import 'score_screen.dart';

class HymnLibraryScreen extends StatefulWidget {
  final ScoreRepository repository;
  final bool pick;

  const HymnLibraryScreen({super.key, required this.repository, this.pick = false});

  @override
  State<HymnLibraryScreen> createState() => _HymnLibraryScreenState();
}

class _HymnLibraryScreenState extends State<HymnLibraryScreen> {
  List<HymnEntry>? _hymns;
  List<String> _categories = const [];
  String _query = '';
  String? _category;
  String? _error;

  @override
  void initState() {
    super.initState();
    HymnCatalog.load().then((h) {
      if (!mounted) return;
      setState(() {
        _hymns = h;
        _categories = HymnCatalog.categories(h);
      });
    }).catchError((Object e) {
      if (mounted) setState(() => _error = 'Could not load the hymn library: $e');
    });
  }

  Future<void> _open(HymnEntry h) async {
    if (widget.pick) {
      Navigator.pop(context, h);
      return;
    }
    // Saved before? Open your copy, with your key and voice.
    final saved = await widget.repository.findBySource(h.source);
    final bytes = saved != null ? await widget.repository.readFile(saved.id) : await HymnCatalog.bytes(h.id);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ScoreScreen(bytes: bytes, repository: widget.repository, saved: saved, source: h.source),
    ));
  }

  void _about() => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Hymn library'),
          content: Text('${_hymns?.length ?? 0} hymns in four parts with all their verses.\n\n'
              '${HymnCatalog.attribution}'),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final hymns = _hymns;
    final shown = hymns == null
        ? const <HymnEntry>[]
        : hymns.where((h) => (_category == null || h.category == _category) && h.matches(_query)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pick ? 'Choose a hymn' : 'Hymn library'),
        actions: [IconButton(onPressed: _about, icon: const Icon(Icons.info_outline), tooltip: 'About')],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: false,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Title, first line, tune or author',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final c in [null, ..._categories])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(c ?? 'All'),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(_error!)))
          : hymns == null
              ? const Center(child: CircularProgressIndicator())
              : shown.isEmpty
                  ? const Center(child: Text('No hymns match.'))
                  : ListView.builder(
                      itemCount: shown.length + 1,
                      itemBuilder: (_, i) {
                        if (i == shown.length) {
                          return Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(HymnCatalog.attribution,
                                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                          );
                        }
                        final h = shown[i];
                        final details = [
                          if (h.tune.isNotEmpty && h.tune != h.title) h.tune,
                          if (h.key.isNotEmpty) 'in ${h.key}',
                          if (h.verses > 1) '${h.verses} verses',
                        ].join(' · ');
                        return ListTile(
                          title: Text(h.title),
                          subtitle: Text(
                            [if (h.firstLine.isNotEmpty) h.firstLine, if (details.isNotEmpty) details].join('\n'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: h.firstLine.isNotEmpty && details.isNotEmpty,
                          trailing: widget.pick ? const Icon(Icons.add) : null,
                          onTap: () => _open(h),
                        );
                      },
                    ),
    );
  }
}
