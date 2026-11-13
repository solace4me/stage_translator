// lib/ui/set_performance_screen.dart
//
// Plays a set list: shows one song at a time (the normal chord sheet or hymn
// screen) with a previous/next bar. Each song opens in the key saved for it.
// The screen stays awake for the whole set.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/library_repository.dart';
import '../data/score_repository.dart';
import '../data/set_list.dart';
import '../data/sheet.dart';
import 'pedal.dart';
import 'score_screen.dart';
import 'set_nav.dart';
import 'sheet_screen.dart';

class SetPerformanceScreen extends StatefulWidget {
  final SetList setList;
  final int startIndex;

  const SetPerformanceScreen({super.key, required this.setList, this.startIndex = 0});

  @override
  State<SetPerformanceScreen> createState() => _SetPerformanceScreenState();
}

class _LoadedScore {
  final SavedScore meta;
  final Uint8List bytes;
  const _LoadedScore(this.meta, this.bytes);
}

class _SetPerformanceScreenState extends State<SetPerformanceScreen> {
  final _sheets = LibraryRepository();
  final _scores = ScoreRepository();
  late int _index = widget.startIndex.clamp(0, widget.setList.items.length - 1);
  late Future<Object?> _song = _load(_index);

  List<SetItem> get _items => widget.setList.items;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  /// A Sheet, a _LoadedScore, or null if the song was deleted.
  Future<Object?> _load(int i) async {
    final item = _items[i];
    try {
      if (item.kind == SetItemKind.sheet) return await _sheets.get(item.refId);
      final meta = await _scores.get(item.refId);
      if (meta == null) return null;
      return _LoadedScore(meta, await _scores.readFile(meta.id));
    } catch (_) {
      return null;
    }
  }

  void _goTo(int i) {
    if (i < 0 || i >= _items.length) return;
    setState(() {
      _index = i;
      _song = _load(i);
    });
  }

  SetNav get _nav => SetNav(
        setName: widget.setList.name,
        index: _index,
        count: _items.length,
        nextTitle: _index + 1 < _items.length ? _items[_index + 1].title : null,
        onPrevious: _index > 0 ? () => _goTo(_index - 1) : null,
        onNext: _index + 1 < _items.length ? () => _goTo(_index + 1) : null,
      );

  @override
  Widget build(BuildContext context) {
    final nav = _nav;
    return FutureBuilder<Object?>(
      future: _song,
      builder: (context, snap) {
        final key = ValueKey('song$_index');
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: Text(_items[_index].title)),
            body: const Center(child: CircularProgressIndicator()),
            bottomNavigationBar: SetNavBar(nav: nav),
          );
        }
        final data = snap.data;
        if (data is Sheet) {
          return SheetScreen(key: key, sheet: data, repository: _sheets, setNav: nav);
        }
        if (data is _LoadedScore) {
          return ScoreScreen(key: key, bytes: data.bytes, saved: data.meta, repository: _scores, setNav: nav);
        }
        return Pedal(
          key: key,
          onPedal: (a) => (a == PedalAction.forward ? nav.onNext : nav.onPrevious)?.call(),
          child: Scaffold(
            appBar: AppBar(title: Text(_items[_index].title)),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('This song is no longer in your library.', textAlign: TextAlign.center),
              ),
            ),
            bottomNavigationBar: SetNavBar(nav: nav),
          ),
        );
      },
    );
  }
}
