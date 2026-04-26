import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/markdown/markdown_callout_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MarkdownCalloutBlock', () {
    testWidgets('renders known type label and title', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: MarkdownCalloutBlock(
              type: 'WARNING',
              rawType: 'WARNING',
              title: '数据限制',
              child: Text('只基于当前样本。'),
            ),
          ),
        ),
      );

      expect(find.text('WARNING'), findsOneWidget);
      expect(find.text('数据限制'), findsOneWidget);
      expect(find.text('只基于当前样本。'), findsOneWidget);
    });

    testWidgets('uses raw type for unknown generic callout without title', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: MarkdownCalloutBlock(
              type: 'CALLOUT',
              rawType: 'EXAMPLE',
              title: '',
              child: Text('具体用法。'),
            ),
          ),
        ),
      );

      expect(find.text('EXAMPLE'), findsOneWidget);
      expect(find.text('具体用法。'), findsOneWidget);
    });
  });
}
