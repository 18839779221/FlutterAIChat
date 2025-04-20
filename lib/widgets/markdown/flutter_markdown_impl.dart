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
    return MarkdownBody(
      data: widget.data,
      selectable: true,
      fitContent: false,
      onTapLink: (text, href, title) => _launchUrl(text, href),
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(fontSize: 16),
        codeblockDecoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
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