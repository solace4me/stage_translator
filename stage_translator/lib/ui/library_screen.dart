// lib/ui/library_screen.dart
//
// Home screen: saved sheets (offline), search, swipe to delete,
// and the entry points for a new sheet.

import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../data/sheet.dart';
import 'review_screen.dart';
import 'scan_screen.dart';
import 'sheet_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _repo = LibraryRepository();
  List<Sheet> _sheets = [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final sheets = await _repo.list();
    if (!mounted) return;
    setState(() {
      _sheets = sheets;
      _loading = false;
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _reload(); // a sheet may have been saved or deleted
  }

  Future<void> _delete(Sheet s) async {
    await _repo.delete(s.id);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Deleted "${s.title}"'),
      action: SnackBarAction(
        label: 'UNDO',
        onPressed: () async {
          await _repo.save(s);
          _reload();
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final visible = _sheets.where((s) => s.title.toLowerCase().contains(q)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Stage Translator Pro')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search your library',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : visible.isEmpty
                    ? const _EmptyLibrary()
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (_, i) {
                          final s = visible[i];
                          return Dismissible(
                            key: ValueKey(s.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: Colors.red.shade700,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              child: const Icon(Icons.delete),
                            ),
                            onDismissed: (_) => _delete(s),
                            child: ListTile(
                              leading: CircleAvatar(child: Text(s.performanceKey)),
                              title: Text(s.title),
                              subtitle: Text(
                                'Doh = ${s.performanceKey} · written in ${s.sheetKey}',
                              ),
                              onTap: () => _open(SheetScreen(sheet: s, repository: _repo)),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'paste',
            tooltip: 'Type or paste a sheet',
            onPressed: () => _open(ReviewScreen(rawText: '', repository: _repo)),
            child: const Icon(Icons.edit_note),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'scan',
            onPressed: () => _open(ScanScreen(repository: _repo)),
            icon: const Icon(Icons.document_scanner),
            label: const Text('Scan sheet'),
          ),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No sheets yet.\nScan a chord sheet or paste one to get started.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}
