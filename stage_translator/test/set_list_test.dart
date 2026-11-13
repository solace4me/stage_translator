import 'package:flutter_test/flutter_test.dart';
import 'package:stage_translator/data/hymn_catalog.dart';
import 'package:stage_translator/data/set_list.dart';

void main() {
  test('set list survives a save and load', () {
    final set = SetList(
      id: 'set1',
      name: 'Sunday 16 Nov',
      updatedAt: DateTime(2026, 11, 12),
      items: const [
        SetItem(kind: SetItemKind.score, refId: 's1', title: 'It Is Well With My Soul'),
        SetItem(kind: SetItemKind.sheet, refId: 'abc', title: 'Gratitude'),
      ],
    );
    final back = SetList.fromJson(set.toJson());
    expect(back.name, 'Sunday 16 Nov');
    expect(back.items, set.items);
    expect(back.items.first.kind, SetItemKind.score);
    expect(back.items.last.title, 'Gratitude');
  });

  test('hymn search matches words in any order, ignoring punctuation', () {
    final h = HymnEntry.fromJson({
      'id': 'x',
      'title': 'It Is Well With My Soul',
      'firstLine': 'When peace, like a river, attendeth my way',
      'tune': 'Ville Du Havre',
      'author': 'Spafford, Horatio Gates',
    });
    expect(h.matches('peace like a river'), isTrue);
    expect(h.matches('soul well'), isTrue);
    expect(h.matches('Spafford'), isTrue);
    expect(h.matches('amazing grace'), isFalse);
    expect(h.source, 'openhymnal:x');
  });
}
