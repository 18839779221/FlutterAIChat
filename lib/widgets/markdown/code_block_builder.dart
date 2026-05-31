import 'package:ai_chat/widgets/markdown/code_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

class CodeBlockBuilder extends MarkdownElementBuilder {
  static const String labelCodeBlock = 'pre-child';

  @override
  visitElementBefore(md.Element element) {
    element.children?.forEach((item) {
      if (item is md.Element && item.tag == 'code') {
        item.footnoteLabel = labelCodeBlock;
      }
    });
  }
}

class CodeElementBuilder extends MarkdownElementBuilder {

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (element.tag != 'code') return null;
    if (element.footnoteLabel == CodeBlockBuilder.labelCodeBlock) {
      String language = 'text';
      // 获取代码块的语言
      if (element.attributes['class'] != null) {
        String lg = element.attributes['class'] as String;
        language = lg.substring(9); // 移除 'language-' 前缀
      }
      return CodeBlockWidget(code: element.textContent, language: language);
    } else {
      return CodeSegmentWidget(code: element.textContent);
    }
  }
}

