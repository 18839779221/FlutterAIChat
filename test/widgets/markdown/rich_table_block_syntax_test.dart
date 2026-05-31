import 'package:ai_chat/widgets/markdown/rich_table_block_syntax.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

void main() {
  group('RichTableBlockSyntax', () {
    List<md.Node> parse(String source) {
      final document = md.Document(
        blockSyntaxes: const [RichTableBlockSyntax()],
        extensionSet: md.ExtensionSet.gitHubFlavored,
      );
      return document.parseLines(source.split('\n'));
    }

    md.Element findFirstElement(List<md.Node> nodes, String tag) {
      for (final n in nodes) {
        if (n is md.Element && n.tag == tag) return n;
      }
      throw StateError('No element <$tag> in parsed nodes');
    }

    test('basic GFM table parses into <rich-table> with rich-* subtree', () {
      final nodes = parse('''
| a | b |
|---|---|
| 1 | 2 |
''');

      final table = findFirstElement(nodes, 'rich-table');
      expect(table.tag, 'rich-table');

      final thead = table.children![0] as md.Element;
      expect(thead.tag, 'rich-thead');
      final headerRow = thead.children![0] as md.Element;
      expect(headerRow.tag, 'rich-tr');
      final th = headerRow.children![0] as md.Element;
      expect(th.tag, 'rich-th');

      final tbody = table.children![1] as md.Element;
      expect(tbody.tag, 'rich-tbody');
      final bodyRow = tbody.children![0] as md.Element;
      expect(bodyRow.tag, 'rich-tr');
      final td = bodyRow.children![0] as md.Element;
      expect(td.tag, 'rich-td');
    });

    test('no <table>/<thead>/<tbody>/<tr>/<th>/<td> remain in tree', () {
      final nodes = parse('''
| a | b |
|---|---|
| 1 | 2 |
''');

      void assertNoLegacyTag(md.Node node) {
        if (node is md.Element) {
          expect(
            const {'table', 'thead', 'tbody', 'tr', 'th', 'td'},
            isNot(contains(node.tag)),
            reason: 'legacy tag ${node.tag} leaked into tree',
          );
          for (final c in node.children ?? const <md.Node>[]) {
            assertNoLegacyTag(c);
          }
        }
      }

      for (final n in nodes) {
        assertNoLegacyTag(n);
      }
    });

    test('alignment attributes are preserved on body cells', () {
      final nodes = parse('''
| L | C | R |
|:--|:-:|--:|
| 1 | 2 | 3 |
''');

      final table = findFirstElement(nodes, 'rich-table');
      final tbody = table.children![1] as md.Element;
      final row = tbody.children![0] as md.Element;
      final cells = row.children!.cast<md.Element>();

      expect(cells[0].attributes['align'], 'left');
      expect(cells[1].attributes['align'], 'center');
      expect(cells[2].attributes['align'], 'right');
    });

    test('cell inline children are preserved (em/strong/code)', () {
      final nodes = parse('''
| h |
|---|
| **b** *i* `c` |
''');

      final table = findFirstElement(nodes, 'rich-table');
      final tbody = table.children![1] as md.Element;
      final row = tbody.children![0] as md.Element;
      final cell = row.children![0] as md.Element;

      final cellTags = cell.children!
          .whereType<md.Element>()
          .map((e) => e.tag)
          .toList();
      expect(cellTags, containsAll(['strong', 'em', 'code']));
    });

    test('invalid table (no separator row) is not parsed as table', () {
      final nodes = parse('''
| a | b |
| 1 | 2 |
''');

      expect(
        nodes.whereType<md.Element>().any((e) => e.tag == 'rich-table'),
        isFalse,
      );
    });
  });
}
