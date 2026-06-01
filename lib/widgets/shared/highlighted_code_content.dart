import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/a11y-dark.dart';
import 'package:flutter_highlight/themes/a11y-light.dart';

class HighlightedCodeContent extends StatelessWidget {
  const HighlightedCodeContent({
    super.key,
    required this.code,
    required this.language,
    this.autoLineBreak = true,
    this.fontSize = 12.5,
    this.lineHeight = 1.45,
  });

  final String code;
  final String language;
  final bool autoLineBreak;
  final double fontSize;
  final double lineHeight;

  @override
  Widget build(BuildContext context) {
    final child = HighlightView(
      code,
      language: language,
      theme: _highlightTheme(context),
      padding: EdgeInsets.zero,
      textStyle: AppTypography.codeStyle(
        color: AppThemeSpec.of(context).markdown.codeForeground,
        fontSize: fontSize,
        height: lineHeight,
      ),
    );

    if (autoLineBreak) {
      return child;
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: child,
    );
  }

  Map<String, TextStyle> _highlightTheme(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseTheme = isDark ? a11yDarkTheme : a11yLightTheme;
    final highlightTheme = Map<String, TextStyle>.from(baseTheme);
    final rootStyle = highlightTheme['root'] ?? const TextStyle();
    highlightTheme['root'] = rootStyle.copyWith(
      backgroundColor: Colors.transparent,
    );
    return highlightTheme;
  }
}
