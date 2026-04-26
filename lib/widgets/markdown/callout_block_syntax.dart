import 'package:markdown/markdown.dart' as md;
import 'package:markdown/src/line.dart';

/// Parses blockquote-style Markdown callouts such as `> [!NOTE] Title`.
class CalloutBlockSyntax extends md.BlockSyntax {
  const CalloutBlockSyntax();

  static final RegExp _markerPattern = RegExp(
    r'^\s*>\s*\[!([A-Za-z][A-Za-z0-9_-]*)\]\s*(.*)?$',
  );

  static final RegExp _blockquoteLinePattern = RegExp(r'^\s*>\s?');
  static const Set<String> _knownTypes = {
    'NOTE',
    'TIP',
    'WARNING',
    'RESULT',
    'SOURCES',
  };

  @override
  RegExp get pattern => _markerPattern;

  @override
  md.Node? parse(md.BlockParser parser) {
    final match = _markerPattern.firstMatch(parser.current.content);
    if (match == null) {
      return null;
    }

    final rawType = match.group(1)!.trim().toUpperCase();
    final normalizedType = normalizeCalloutType(rawType);
    final title = (match.group(2) ?? '').trim();
    final childLines = <Line>[];

    parser.advance();

    while (!parser.isDone) {
      final content = parser.current.content;
      if (!_blockquoteLinePattern.hasMatch(content)) {
        break;
      }
      childLines.add(Line(content.replaceFirst(_blockquoteLinePattern, '')));
      parser.advance();
    }

    final children = md.BlockParser(childLines, parser.document).parseLines(
      parentSyntax: this,
    );
    final element = md.Element('callout', children);
    element.attributes['type'] = normalizedType;
    element.attributes['rawType'] = rawType;
    element.attributes['title'] = title;
    return element;
  }

  /// Normalizes known callout aliases while preserving unknown raw types.
  static String normalizeCalloutType(String rawType) {
    final type = rawType.trim().toUpperCase();
    if (_knownTypes.contains(type)) {
      return type;
    }
    return 'CALLOUT';
  }
}
