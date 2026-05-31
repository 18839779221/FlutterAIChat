import 'package:markdown/markdown.dart' as md;

/// GFM table syntax that produces private `rich-*` AST tags instead of
/// the standard `<table>` / `<thead>` / etc.
///
/// This indirection lets `FlutterMarkdownImpl` take over table rendering
/// through `builders['rich-table']`, bypassing flutter_markdown_plus's
/// hard-coded `<table>` widget construction path while preserving GFM's
/// alignment and inline-content semantics.
class RichTableBlockSyntax extends md.TableSyntax {
  const RichTableBlockSyntax();

  static const Map<String, String> _tagRename = {
    'table': 'rich-table',
    'thead': 'rich-thead',
    'tbody': 'rich-tbody',
    'tr': 'rich-tr',
    'th': 'rich-th',
    'td': 'rich-td',
  };

  @override
  md.Node? parse(md.BlockParser parser) {
    final node = super.parse(parser);
    if (node is md.Element) {
      return _rebuildWithRename(node);
    }
    return node;
  }

  // md.Element.tag is final in the markdown 7.x package, so we rebuild the
  // sub-tree top-down instead of mutating in place. Attributes (including
  // the GFM `align` value on cells) are preserved verbatim.
  static md.Element _rebuildWithRename(md.Element element) {
    final newTag = _tagRename[element.tag] ?? element.tag;
    final originalChildren = element.children;
    final List<md.Node>? newChildren = originalChildren == null
        ? null
        : [
            for (final child in originalChildren)
              child is md.Element ? _rebuildWithRename(child) : child,
          ];
    final rebuilt = newChildren == null
        ? md.Element.empty(newTag)
        : md.Element(newTag, newChildren);
    rebuilt.attributes.addAll(element.attributes);
    return rebuilt;
  }
}
