import 'package:ai_chat/widgets/markdown/markdown_math_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// Renders inline `math-inline` Markdown AST nodes.
class MarkdownInlineMathBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return MarkdownInlineMath(tex: element.textContent.trim());
  }
}

/// Renders block-level `math-block` Markdown AST nodes.
class MarkdownBlockMathBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    return MarkdownBlockMath(tex: text.text.trim());
  }
}
