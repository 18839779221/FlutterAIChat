import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// Inline TeX formula rendered inside Markdown paragraphs.
class MarkdownInlineMath extends StatelessWidget {
  /// Raw TeX expression without surrounding Markdown delimiters.
  final String tex;

  const MarkdownInlineMath({
    super.key,
    required this.tex,
  });

  @override
  Widget build(BuildContext context) {
    final fallbackStyle = _fallbackStyle(context);
    final mathStyle = DefaultTextStyle.of(context).style.copyWith(
          color: fallbackStyle.color,
          fontSize: fallbackStyle.fontSize,
          height: 1.0,
        );

    return Math.tex(
      tex,
      mathStyle: MathStyle.text,
      textStyle: mathStyle,
      onErrorFallback: (_) => Text(tex, style: fallbackStyle),
    );
  }
}

/// Block-level TeX formula rendered as a full-width Markdown document block.
class MarkdownBlockMath extends StatelessWidget {
  /// Raw TeX expression without surrounding Markdown delimiters.
  final String tex;

  const MarkdownBlockMath({
    super.key,
    required this.tex,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fallbackStyle = _fallbackStyle(context);
    final mathStyle = fallbackStyle.copyWith(
      color: colors.primaryText.withValues(alpha: isDark ? 0.94 : 0.9),
      fontSize: 14,
      height: 1.0,
    );

    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.structuredSurface.withValues(alpha: isDark ? 0.3 : 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Center(
            child: Math.tex(
              tex,
              mathStyle: MathStyle.display,
              textStyle: mathStyle,
              onErrorFallback: (_) => Text(tex, style: fallbackStyle),
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _fallbackStyle(BuildContext context) {
  final colors = Theme.of(context).extension<AppColors>()!;
  return AppTypography.documentStyle(
    color: colors.primaryText.withValues(alpha: 0.88),
    fontSize: 13,
    height: 1.45,
  );
}
