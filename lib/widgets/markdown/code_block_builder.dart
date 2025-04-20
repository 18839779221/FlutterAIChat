import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/vs2015.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

class CodeConfig {
  static Map<String, TextStyle> theme = vs2015Theme;
  static TextStyle codeTextStyle = TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: 14,
  );

  bool autoLineBreak = false;
}

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
  final CodeConfig _codeConfig = CodeConfig();

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (element.tag != 'code') return null;
    if (element.footnoteLabel == CodeBlockBuilder.labelCodeBlock) {
      String language = 'javascript';
      // 获取代码块的语言
      if (element.attributes['class'] != null) {
        String lg = element.attributes['class'] as String;
        language = lg.substring(9); // 移除 'language-' 前缀
      }
      return codeBlockWidget(element.textContent, language);
    } else {
      return codeSegmentWidget(element.textContent);
    }
  }

  Widget codeSegmentWidget(String code) {
    return Container(
        padding: const EdgeInsets.all(4.0),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(4.0),
        ),
        child: Text(code,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              backgroundColor: Colors.grey[200],
            )));
  }

  Widget codeBlockWidget(String code, String language) {
    return Row(children: [
      Expanded(
        child: _codeConfig.autoLineBreak
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: highLightWidget(code, language))
            : highLightWidget(code, language),
      )
    ]);
  }

  Widget highLightWidget(String code, String language) {
    return HighlightView(
      code,
      language: language,
      theme: CodeConfig.theme,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      textStyle: CodeConfig.codeTextStyle,
    );
  }
}
