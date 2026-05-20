import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// Design tokens for the `flutter_markdown` Hybrid Reader surface.
///
/// These values intentionally serve only the `FlutterMarkdownImpl` path. They
/// keep long-form assistant answers readable while preserving the compact chat
/// density expected on phones.
class FlutterMarkdownReaderTokens {
  /// Builds the document-first styles used by completed assistant answers.
  static MarkdownReaderStyles build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeSpec>()!;
    final bodyColor = theme.colorScheme.onSurface;
    final secondaryColor = bodyColor.withValues(alpha: 0.82);
    final quoteBorderColor = colors.workflowRunning.withValues(alpha: 0.18);
    final quoteBackgroundColor = colors.assistantSurface.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.28 : 0.18,
    );

    return MarkdownReaderStyles(
      body: AppTypography.documentStyle(
        color: bodyColor,
        fontSize: 13.2,
        height: 1.52,
      ),
      secondaryBody: AppTypography.documentStyle(
        color: secondaryColor,
        fontSize: 13,
        height: 1.5,
      ),
      h1: AppTypography.documentStyle(
        color: bodyColor,
        fontSize: 17,
        height: 1.18,
        fontWeight: FontWeight.w500,
      ),
      h2: AppTypography.documentStyle(
        color: bodyColor,
        fontSize: 15.2,
        height: 1.2,
        fontWeight: FontWeight.w500,
      ),
      h3: AppTypography.documentStyle(
        color: bodyColor,
        fontSize: 14,
        height: 1.22,
        fontWeight: FontWeight.w500,
      ),
      quoteBackgroundColor: quoteBackgroundColor,
      quoteBorderColor: quoteBorderColor,
    );
  }
}

/// Typography and tone values consumed by `FlutterMarkdownImpl`.
class MarkdownReaderStyles {
  /// Default paragraph style for completed assistant Markdown answers.
  final TextStyle body;

  /// Secondary body style used by list markers and quiet side-note text.
  final TextStyle secondaryBody;

  /// Highest-level heading style used rarely in chat answers.
  final TextStyle h1;

  /// Primary section heading style for long-form answers.
  final TextStyle h2;

  /// Subsection heading style for local answer structure.
  final TextStyle h3;

  /// Background tone for quiet blockquote side notes.
  final Color quoteBackgroundColor;

  /// Left border tone for quiet blockquote side notes.
  final Color quoteBorderColor;

  const MarkdownReaderStyles({
    required this.body,
    required this.secondaryBody,
    required this.h1,
    required this.h2,
    required this.h3,
    required this.quoteBackgroundColor,
    required this.quoteBorderColor,
  });
}
