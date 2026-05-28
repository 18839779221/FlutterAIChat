import 'package:ai_chat/pages/layout_debug_page.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_blocks/assistant_doc_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('layout debug page shows the first built-in case', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const LayoutDebugPage(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('文档排版调试'), findsOneWidget);
    expect(find.text('基础长文'), findsWidgets);
    expect(find.byType(AssistantDocBlock), findsWidgets);
  });

  testWidgets('layout debug page switches between built-in cases', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const LayoutDebugPage(),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复杂结构').last);
    await tester.pumpAndSettle();

    expect(find.text('复杂结构'), findsWidgets);
    expect(find.textContaining('方案评估'), findsOneWidget);
  });

  testWidgets('layout debug page shows full assistant response details', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const LayoutDebugPage(),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完整助手回复').last);
    await tester.pumpAndSettle();

    expect(find.text('RESEARCH SUMMARY'), findsOneWidget);
    expect(find.textContaining('先梳理结构，再补充关键表格'), findsOneWidget);
    expect(find.byType(AssistantDocBlock), findsNWidgets(2));
  });

  testWidgets('layout debug page supports multilingual mixed document case', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const LayoutDebugPage(),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多语言混排').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Multilingual Layout Review'), findsOneWidget);
    expect(find.textContaining('The English section is useful'), findsOneWidget);
    expect(find.textContaining('日本語の文章では'), findsOneWidget);
    expect(find.textContaining('هذه الفقرة القصيرة'), findsOneWidget);
  });
}
