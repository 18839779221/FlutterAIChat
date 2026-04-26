import 'package:ai_chat/widgets/markdown/callout_block_syntax.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

void main() {
  group('CalloutBlockSyntax', () {
    List<md.Node> parse(String source) {
      final document = md.Document(
        blockSyntaxes: [const CalloutBlockSyntax()],
        extensionSet: md.ExtensionSet.gitHubFlavored,
      );
      return document.parseLines(source.split('\n'));
    }

    test('parses note callout into callout element', () {
      final nodes = parse('> [!NOTE]\n> 这是补充说明。');

      expect(nodes, hasLength(1));
      final callout = nodes.single as md.Element;
      expect(callout.tag, 'callout');
      expect(callout.attributes['type'], 'NOTE');
      expect(callout.attributes['rawType'], 'NOTE');
      expect(callout.attributes['title'], '');
      expect(callout.textContent, contains('这是补充说明。'));
    });

    test('preserves custom title', () {
      final nodes = parse('> [!WARNING] 数据限制\n> 只基于当前样本。');

      final callout = nodes.single as md.Element;
      expect(callout.attributes['type'], 'WARNING');
      expect(callout.attributes['rawType'], 'WARNING');
      expect(callout.attributes['title'], '数据限制');
      expect(callout.textContent, contains('只基于当前样本。'));
    });

    test('downgrades unknown types to generic callout', () {
      final nodes = parse('> [!EXAMPLE] 示例\n> 具体用法。');

      final callout = nodes.single as md.Element;
      expect(callout.attributes['type'], 'CALLOUT');
      expect(callout.attributes['rawType'], 'EXAMPLE');
      expect(callout.attributes['title'], '示例');
    });

    test('leaves ordinary blockquote untouched', () {
      final nodes = parse('> 普通旁注');

      final quote = nodes.single as md.Element;
      expect(quote.tag, 'blockquote');
      expect(quote.textContent, contains('普通旁注'));
    });
  });
}
