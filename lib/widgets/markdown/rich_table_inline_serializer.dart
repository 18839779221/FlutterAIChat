import 'package:markdown/markdown.dart' as md;

/// Serializes a Markdown AST inline sub-tree back to a Markdown string
/// fragment suitable for nested `MarkdownBody` rendering inside a table cell.
///
/// Only covers the inline element set produced by GFM table cell parsing:
/// `em`, `strong`, `code`, `a`, `del`, `br`, plus the project-specific
/// `math-inline` tag emitted by `MathInlineSyntax`. Unknown elements fall
/// back to their `textContent` so cell text is never silently dropped.
class RichTableInlineSerializer {
  const RichTableInlineSerializer._();

  static String serialize(List<md.Node> nodes) {
    final buffer = StringBuffer();
    for (final node in nodes) {
      _writeNode(buffer, node);
    }
    return buffer.toString();
  }

  static void _writeNode(StringBuffer buffer, md.Node node) {
    if (node is md.Text) {
      buffer.write(_escapeText(node.text));
      return;
    }
    if (node is md.Element) {
      switch (node.tag) {
        case 'em':
          buffer.write('*');
          _writeChildren(buffer, node);
          buffer.write('*');
          return;
        case 'strong':
          buffer.write('**');
          _writeChildren(buffer, node);
          buffer.write('**');
          return;
        case 'code':
          buffer.write('`');
          buffer.write(node.textContent);
          buffer.write('`');
          return;
        case 'a':
          buffer.write('[');
          _writeChildren(buffer, node);
          buffer.write('](');
          buffer.write(node.attributes['href'] ?? '');
          buffer.write(')');
          return;
        case 'del':
          buffer.write('~~');
          _writeChildren(buffer, node);
          buffer.write('~~');
          return;
        case 'br':
          buffer.write('  \n');
          return;
        case 'math-inline':
          final delimiter = node.attributes['delimiter'] ?? r'$';
          final tex = node.textContent;
          if (delimiter == r'\(') {
            buffer
              ..write(r'\(')
              ..write(tex)
              ..write(r'\)');
          } else {
            buffer
              ..write(r'$')
              ..write(tex)
              ..write(r'$');
          }
          return;
        default:
          buffer.write(node.textContent);
          return;
      }
    }
  }

  static void _writeChildren(StringBuffer buffer, md.Element element) {
    final children = element.children;
    if (children == null) return;
    for (final child in children) {
      _writeNode(buffer, child);
    }
  }

  // GFM table cells use `|` as the separator. The `markdown` parser already
  // unescapes `\|` during cell parsing, so we must re-escape pipes in raw
  // text before nesting them through MarkdownBody again. Backslashes are
  // escaped first so the pipe escape we add is not itself escaped on a
  // subsequent pass.
  static String _escapeText(String text) =>
      text.replaceAll(r'\', r'\\').replaceAll('|', r'\|');
}
