import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import 'code_block_builder.dart';

class FlutterMarkdownImpl extends StatelessWidget {
  final String data;
  const FlutterMarkdownImpl({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final bodyColor = theme.colorScheme.onSurface;
    final secondaryColor = theme.colorScheme.onSurface.withValues(alpha: 0.84);
    final quoteBorderColor = colors.workflowRunning.withValues(alpha: 0.34);
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
          blockquotePadding: const EdgeInsets.fromLTRB(12, 5, 4, 5),
          blockquoteDecoration: BoxDecoration(
            color: quoteBackgroundColor.withValues(alpha: 0.42),
            border: Border(
              left: BorderSide(
                color: quoteBorderColor.withValues(alpha: 0.88),
                width: 2,
              ),
            ),
            borderRadius: BorderRadius.circular(4),
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
          blockSpacing: 4.0,
          listIndent: 14,
          h1Padding: const EdgeInsets.only(bottom: 2),
          h2Padding: const EdgeInsets.only(top: 7, bottom: 2),
          h3Padding: const EdgeInsets.only(top: 5, bottom: 1),
          horizontalRuleDecoration: BoxDecoration(
            color: theme.dividerColor.withValues(alpha: 0.42),
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
}
