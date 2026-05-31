import 'package:ai_chat/widgets/markdown/markdown_callout_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

/// Renders custom Markdown `callout` elements parsed from `[!TYPE]` blocks.
class MarkdownCalloutBuilder extends MarkdownElementBuilder {
  final List<Map<String, String>> _attributeStack = <Map<String, String>>[];

  @override
  bool isBlockElement() => true;

  @override
  void visitElementBefore(md.Element element) {
    _attributeStack.add(Map<String, String>.from(element.attributes));
  }

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    final attributes = _attributeStack.isNotEmpty
        ? _attributeStack.removeLast()
        : const <String, String>{};
    final content = text.text.trim();

    return MarkdownCalloutBlock(
      type: attributes['type'] ?? 'CALLOUT',
      rawType: attributes['rawType'] ?? '',
      title: attributes['title'] ?? '',
      child: Text(
        content,
        style: preferredStyle,
      ),
    );
  }
}
