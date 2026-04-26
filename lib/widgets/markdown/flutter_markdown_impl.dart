import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import 'callout_block_syntax.dart';
import 'code_block_builder.dart';
import 'flutter_markdown_reader_tokens.dart';
import 'markdown_callout_builder.dart';
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
    final reader = FlutterMarkdownReaderTokens.build(context);

    return RepaintBoundary(
      child: MarkdownBody(
        data: data,
        selectable: false,
        fitContent: false,
        onTapLink: (text, href, title) => _launchUrl(text, href),
        blockSyntaxes: const [
          CalloutBlockSyntax(),
        ],
        styleSheet: MarkdownStyleSheet(
          p: reader.body,
          h1: reader.h1,
          h2: reader.h2,
          h3: reader.h3,
          listBullet: reader.secondaryBody.copyWith(height: 1.46),
          blockquote: reader.secondaryBody,
          blockquotePadding: const EdgeInsets.fromLTRB(13, 8, 9, 8),
          blockquoteDecoration: BoxDecoration(
            color: reader.quoteBackgroundColor,
            border: Border(
              left: BorderSide(
                color: reader.quoteBorderColor,
                width: 1.4,
              ),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          strong: reader.body.copyWith(fontWeight: FontWeight.w500),
          em: reader.body.copyWith(fontStyle: FontStyle.italic),
          textAlign: WrapAlignment.start,
          blockSpacing: 10,
          listIndent: 17,
          h1Padding: const EdgeInsets.only(top: 5, bottom: 6),
          h2Padding: const EdgeInsets.only(top: 15, bottom: 6),
          h3Padding: const EdgeInsets.only(top: 12, bottom: 5),
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
          'callout': MarkdownCalloutBuilder(),
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
