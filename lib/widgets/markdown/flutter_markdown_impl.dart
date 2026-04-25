import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import 'code_block_builder.dart';
import 'markdown_widget_impl.dart';

class FlutterMarkdownImpl extends StatelessWidget {
  final String data;
  const FlutterMarkdownImpl({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    if (_containsMarkdownTable(data)) {
      return RepaintBoundary(
        child: MarkdownWidgetImpl(data: data),
      );
    }

    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final bodyColor = theme.colorScheme.onSurface;
    final secondaryColor = theme.colorScheme.onSurface.withValues(alpha: 0.84);
    final quoteBorderColor = colors.workflowRunning.withValues(alpha: 0.22);
    const quoteBackgroundColor = Color(0xFFDDE4E8);

    return RepaintBoundary(
      child: MarkdownBody(
        data: data,
        selectable: false,
        fitContent: false,
        onTapLink: (text, href, title) => _launchUrl(text, href),
        styleSheet: MarkdownStyleSheet(
          // Prefer integer font metrics here to reduce visible glyph shimmer
          // while list items slide across fractional scroll offsets.
          p: AppTypography.documentStyle(
            color: bodyColor,
            fontSize: 13,
            height: 1.4,
          ),
          h1: AppTypography.documentStyle(
            color: bodyColor,
            fontSize: 18,
            height: 1.12,
          ),
          h2: AppTypography.documentStyle(
            color: bodyColor,
            fontSize: 15,
            height: 1.14,
          ),
          h3: AppTypography.documentStyle(
            color: bodyColor,
            fontSize: 14,
            height: 1.16,
          ),
          listBullet: AppTypography.documentStyle(
            color: secondaryColor,
            fontSize: 13,
            height: 1.34,
          ),
          blockquote: AppTypography.documentStyle(
            color: secondaryColor,
            fontSize: 13,
            height: 1.4,
          ),
          blockquotePadding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          blockquoteDecoration: BoxDecoration(
            color: quoteBackgroundColor.withValues(alpha: 0.24),
            border: Border(
              left: BorderSide(
                color: quoteBorderColor.withValues(alpha: 0.82),
                width: 1.5,
              ),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          strong: AppTypography.documentStyle(
            color: bodyColor,
            fontWeight: FontWeight.w500,
            fontSize: 13,
            height: 1.4,
          ),
          em: AppTypography.documentStyle(
            color: bodyColor,
            fontStyle: FontStyle.italic,
            fontSize: 13,
            height: 1.4,
          ),
          textAlign: WrapAlignment.start,
          blockSpacing: 9.0,
          listIndent: 18,
          h1Padding: const EdgeInsets.only(top: 4, bottom: 6),
          h2Padding: const EdgeInsets.only(top: 14, bottom: 6),
          h3Padding: const EdgeInsets.only(top: 11, bottom: 5),
          horizontalRuleDecoration: BoxDecoration(
            color: theme.dividerColor.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
          ),
          codeblockDecoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        builders: {
          'code': CodeElementBuilder(),
          'pre': CodeBlockBuilder(),
        },
      ),
    );
  }

  Future<void> _launchUrl(String text, String? href) async {
    String url = href ?? text;
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.platformDefault)) {
      throw Exception('无法打开链接: $url');
    }
  }

  static bool _containsMarkdownTable(String input) {
    final lines = input.split('\n');
    for (var i = 0; i < lines.length - 1; i++) {
      final header = lines[i].trim();
      final divider = lines[i + 1].trim();
      if (!header.contains('|')) {
        continue;
      }
      if (_tableDividerPattern.hasMatch(divider)) {
        return true;
      }
    }
    return false;
  }

  static final RegExp _tableDividerPattern = RegExp(
    r'^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$',
  );
}
