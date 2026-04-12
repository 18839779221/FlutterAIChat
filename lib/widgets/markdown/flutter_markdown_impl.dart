import 'package:ai_chat/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import 'code_block_builder.dart';

class FlutterMarkdownImpl extends StatefulWidget {
  final String data;
  const FlutterMarkdownImpl({
    super.key,
    required this.data,
  });

  @override
  State<StatefulWidget> createState() => _FlutterMarkdownImplState();
}

class _FlutterMarkdownImplState extends State<FlutterMarkdownImpl> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final bodyColor = theme.colorScheme.onSurface;
    final secondaryColor = theme.colorScheme.onSurface.withValues(alpha: 0.84);
    final quoteBorderColor = colors.divider.withValues(alpha: 0.42);
    final quoteBackgroundColor =
        colors.assistantSurface.withValues(alpha: 0.52);

    return MarkdownBody(
      data: widget.data,
      selectable: false,
      fitContent: false,
      onTapLink: (text, href, title) => _launchUrl(text, href),
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          color: bodyColor,
          fontSize: 13.8,
          height: 1.36,
          fontWeight: FontWeight.w400,
        ),
        h1: TextStyle(
          color: bodyColor,
          fontSize: 21,
          height: 1.1,
          fontWeight: FontWeight.w700,
        ),
        h2: TextStyle(
          color: bodyColor,
          fontSize: 16.8,
          height: 1.12,
          fontWeight: FontWeight.w600,
        ),
        h3: TextStyle(
          color: bodyColor,
          fontSize: 15.0,
          height: 1.16,
          fontWeight: FontWeight.w600,
        ),
        listBullet: TextStyle(
          color: secondaryColor,
          fontSize: 13.8,
          height: 1.3,
          fontWeight: FontWeight.w500,
        ),
        blockquote: TextStyle(
          color: secondaryColor,
          fontSize: 13.7,
          height: 1.36,
          fontStyle: FontStyle.normal,
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(12, 5, 4, 5),
        blockquoteDecoration: BoxDecoration(
          color: quoteBackgroundColor.withValues(alpha: 0.54),
          border: Border(
            left: BorderSide(
              color: quoteBorderColor.withValues(alpha: 0.82),
              width: 2,
            ),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        strong: TextStyle(
          color: bodyColor,
          fontWeight: FontWeight.w600,
        ),
        em: TextStyle(
          color: bodyColor,
          fontStyle: FontStyle.italic,
        ),
        textAlign: WrapAlignment.start,
        blockSpacing: 5.5,
        listIndent: 14,
        h1Padding: const EdgeInsets.only(bottom: 4),
        h2Padding: const EdgeInsets.only(top: 10, bottom: 2),
        h3Padding: const EdgeInsets.only(top: 6, bottom: 2),
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
