import 'package:ai_chat/widgets/markdown/math_inline_syntax.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

void main() {
  group('MathInlineSyntax', () {
    test('parses dollar inline math', () {
      final document = md.Document(
        inlineSyntaxes: [MathInlineSyntax()],
        encodeHtml: false,
      );

      final nodes = document.parseInline(r'能量公式 $E = mc^2$。');
      final math = nodes.whereType<md.Element>().single;

      expect(math.tag, 'math-inline');
      expect(math.textContent, 'E = mc^2');
      expect(math.attributes['delimiter'], r'$');
    });

    test('parses escaped parenthesis inline math', () {
      final document = md.Document(
        inlineSyntaxes: [MathInlineSyntax()],
        encodeHtml: false,
      );

      final nodes = document.parseInline(r'能量公式 \( E = mc^2 \)。');
      final math = nodes.whereType<md.Element>().single;

      expect(math.tag, 'math-inline');
      expect(math.textContent, 'E = mc^2');
      expect(math.attributes['delimiter'], r'\(');
    });

    test('does not parse common dollar text as math', () {
      final document = md.Document(
        inlineSyntaxes: [MathInlineSyntax()],
        encodeHtml: false,
      );

      final mathElements = document
          .parseInline(r'价格是 $12.99，路径是 $HOME。')
          .whereType<md.Element>()
          .where((element) => element.tag == 'math-inline');

      expect(mathElements, isEmpty);
    });
  });
}
