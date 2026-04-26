import 'package:markdown/markdown.dart' as md;

/// Parses block-level TeX math fenced by `$$` or `\[...\]`.
class MathBlockSyntax extends md.BlockSyntax {
  const MathBlockSyntax();

  static final RegExp _startPattern = RegExp(r'^\s*(\$\$|\\\[)\s*$');

  @override
  RegExp get pattern => _startPattern;

  @override
  md.Node? parse(md.BlockParser parser) {
    final startMatch = _startPattern.firstMatch(parser.current.content);
    if (startMatch == null) {
      return null;
    }

    final openingLine = parser.current.content;
    final delimiter = startMatch.group(1)!;
    final closingDelimiter = delimiter == r'$$' ? r'$$' : r'\]';
    final lines = <String>[];
    var offset = 1;
    var foundClosingDelimiter = false;

    while (parser.peek(offset) != null) {
      final line = parser.peek(offset)!.content;
      if (line.trim() == closingDelimiter) {
        foundClosingDelimiter = true;
        break;
      }
      lines.add(line);
      offset += 1;
    }

    if (!foundClosingDelimiter) {
      parser.advance();
      return md.Element.text('p', openingLine);
    }

    parser.advance();
    for (var i = 0; i < lines.length; i++) {
      parser.advance();
    }
    parser.advance();

    final element = md.Element('math-block', <md.Node>[
      md.Text(lines.join('\n').trim()),
    ]);
    element.attributes['delimiter'] = delimiter;
    return element;
  }
}
