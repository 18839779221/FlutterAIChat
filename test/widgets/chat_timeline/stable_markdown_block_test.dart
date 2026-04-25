import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/markdown/flutter_markdown_impl.dart';
import 'package:ai_chat/widgets/chat_timeline/stable_markdown_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'stable markdown block keeps markdown subtree identity for unchanged content',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: StableMarkdownBlock(
            cacheKey: 'message-2',
            child: FlutterMarkdownImpl(
              data: '# Title\n\nParagraph',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(FlutterMarkdownImpl), findsOneWidget);
  });
}
