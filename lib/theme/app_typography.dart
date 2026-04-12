import 'package:flutter/material.dart';

/// Centralized typography roles for the chat experience.
///
/// We keep the product chrome on Anthropic Sans, while the document reader
/// layer uses a CJK-oriented fallback chain that can be tuned independently.
class AppTypography {
  static const String uiFontFamily = 'AnthropicSans';
  static const String codeFontFamily = 'JetBrainsMono';

  /// Project-safe packaged CJK family used as the durable production fallback.
  static const String documentPackagedCjkFamily = 'NotoSansCJKSC';

  static const List<String> documentFontFallback = <String>[
    documentPackagedCjkFamily,
    'Noto Sans SC',
    'PingFang SC',
    'HarmonyOS Sans SC',
    'Hiragino Sans GB',
    'Microsoft YaHei',
    'Noto Sans CJK SC',
    'sans-serif',
  ];

  static TextStyle documentStyle({
    required Color color,
    required double fontSize,
    required double height,
    FontWeight fontWeight = FontWeight.w400,
    FontStyle fontStyle = FontStyle.normal,
  }) {
    return TextStyle(
      fontFamily: uiFontFamily,
      fontFamilyFallback: documentFontFallback,
      color: color,
      fontSize: fontSize,
      height: height,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
    );
  }

  static TextStyle uiStyle({
    required Color color,
    required double fontSize,
    required double height,
    FontWeight fontWeight = FontWeight.w400,
    FontStyle fontStyle = FontStyle.normal,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: uiFontFamily,
      fontFamilyFallback: documentFontFallback,
      color: color,
      fontSize: fontSize,
      height: height,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle codeStyle({
    required Color color,
    required double fontSize,
    required double height,
    FontWeight fontWeight = FontWeight.w400,
  }) {
    return TextStyle(
      fontFamily: codeFontFamily,
      color: color,
      fontSize: fontSize,
      height: height,
      fontWeight: fontWeight,
    );
  }
}
