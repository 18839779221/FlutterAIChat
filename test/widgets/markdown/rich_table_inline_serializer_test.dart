import 'package:ai_chat/widgets/markdown/rich_table_inline_serializer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

void main() {
  group('RichTableInlineSerializer', () {
    String serialize(List<md.Node> nodes) =>
        RichTableInlineSerializer.serialize(nodes);

    test('plain text passes through unchanged', () {
      expect(serialize([md.Text('hello world')]), 'hello world');
    });

    test('em -> *...*', () {
      final em = md.Element('em', [md.Text('hi')]);
      expect(serialize([em]), '*hi*');
    });

    test('strong -> **...**', () {
      final s = md.Element('strong', [md.Text('hi')]);
      expect(serialize([s]), '**hi**');
    });

    test('code -> backtick wrapped', () {
      final c = md.Element('code', [md.Text('x')]);
      expect(serialize([c]), '`x`');
    });

    test('anchor -> [text](href)', () {
      final a = md.Element('a', [md.Text('site')])
        ..attributes['href'] = 'https://example.com';
      expect(serialize([a]), '[site](https://example.com)');
    });

    test('del -> ~~...~~', () {
      final d = md.Element('del', [md.Text('gone')]);
      expect(serialize([d]), '~~gone~~');
    });

    test('br -> trailing two spaces + newline', () {
      final br = md.Element.empty('br');
      expect(serialize([md.Text('a'), br, md.Text('b')]), 'a  \nb');
    });

    test('math-inline dollar delimiter is restored', () {
      final m = md.Element.text('math-inline', 'x^2')
        ..attributes['delimiter'] = r'$';
      expect(serialize([m]), r'$x^2$');
    });

    test(r'math-inline \( delimiter is restored', () {
      final m = md.Element.text('math-inline', 'x^2')
        ..attributes['delimiter'] = r'\(';
      expect(serialize([m]), r'\(x^2\)');
    });

    test('nested emphasis composes', () {
      final strong = md.Element('strong', [
        md.Text('a '),
        md.Element('em', [md.Text('b')]),
        md.Text(' c'),
      ]);
      expect(serialize([strong]), '**a *b* c**');
    });

    test('unknown element falls back to textContent', () {
      final u = md.Element('weird-tag', [md.Text('payload')]);
      expect(serialize([u]), 'payload');
    });

    test('pipe in text is escaped so it does not break a table cell', () {
      expect(serialize([md.Text('a | b')]), r'a \| b');
    });
  });
}
