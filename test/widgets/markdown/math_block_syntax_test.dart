import 'package:ai_chat/widgets/markdown/math_block_syntax.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

void main() {
  group('MathBlockSyntax', () {
    test('parses dollar block math', () {
      final nodes = md.Document(
        blockSyntaxes: [const MathBlockSyntax()],
        encodeHtml: false,
      ).parseLines([
        r'$$',
        r'\int_0^1 x^2 dx = \frac{1}{3}',
        r'$$',
      ]);

      final math = nodes.single as md.Element;
      expect(math.tag, 'math-block');
      expect(math.textContent, r'\int_0^1 x^2 dx = \frac{1}{3}');
      expect(math.attributes['delimiter'], r'$$');
    });

    test('parses bracket block math', () {
      final nodes = md.Document(
        blockSyntaxes: [const MathBlockSyntax()],
        encodeHtml: false,
      ).parseLines([
        r'\[',
        r'\sum_{i=1}^{n} i = \frac{n(n+1)}{2}',
        r'\]',
      ]);

      final math = nodes.single as md.Element;
      expect(math.tag, 'math-block');
      expect(math.textContent, r'\sum_{i=1}^{n} i = \frac{n(n+1)}{2}');
      expect(math.attributes['delimiter'], r'\[');
    });

    test('leaves unmatched dollar block as ordinary paragraph', () {
      final nodes = md.Document(
        blockSyntaxes: [const MathBlockSyntax()],
        encodeHtml: false,
      ).parseLines([
        r'$$',
        r'E = mc^2',
        '后续段落',
      ]);

      expect(
          nodes.whereType<md.Element>().any((node) => node.tag == 'math-block'),
          isFalse);
      expect(nodes.map((node) => (node as md.Element).textContent).join('\n'),
          contains('后续段落'));
    });
  });
}
