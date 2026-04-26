import 'package:markdown/markdown.dart' as md;

/// Parses conservative inline TeX math spans in Markdown text.
class MathInlineSyntax extends md.InlineSyntax {
  MathInlineSyntax() : super(_pattern);

  static const String _pattern =
      r'\\\((.+?)\\\)|(?<![A-Za-z0-9])\$([^\s$](?:[^$]*?[^\s$])?)\$(?![A-Za-z0-9])';

  static final RegExp _mathSignalPattern = RegExp(
    r'(\\|\^|_|=|\+|-|\*|/|<|>|\(|\)|\[|\]|\{|\}|\d\s*[-+*/=^_<>]|\s[-+*/=^_<>]\s*)',
  );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final parenthesized = match.group(1);
    final dollar = match.group(2);
    final delimiter = parenthesized != null ? r'\(' : r'$';
    final tex = (parenthesized ?? dollar ?? '').trim();

    if (delimiter == r'$' && !_looksLikeMath(tex)) {
      parser.addNode(md.Text(match.group(0)!));
      return true;
    }

    final element = md.Element.text('math-inline', tex);
    element.attributes['delimiter'] = delimiter;
    parser.addNode(element);
    return true;
  }

  static bool _looksLikeMath(String tex) {
    if (tex.isEmpty) {
      return false;
    }
    if (RegExp(r'^\d+(?:\.\d+)?$').hasMatch(tex)) {
      return false;
    }
    if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(tex)) {
      return false;
    }
    return _mathSignalPattern.hasMatch(tex);
  }
}
