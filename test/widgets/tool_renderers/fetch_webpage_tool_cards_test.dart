import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/tool_renderers/fetch_webpage_tool_result_card.dart';
import 'package:ai_chat/widgets/tool_renderers/fetch_webpage_tool_workflow_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fetch_webpage tool cards', () {
    testWidgets('workflow card summarizes url and extract mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: FetchWebpageToolWorkflowCard(
              step: ToolWorkflowStep(
                stepId: 'fetch-1',
                turnId: 'turn-1',
                toolName: 'fetch_webpage',
                title: '读取网页',
                summary: '准备读取网页',
                status: ToolWorkflowStepStatus.running,
                requiresConfirmation: false,
                details: {
                  'url': 'https://openai.com/news',
                  'extractMode': 'article',
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('读取网页'), findsOneWidget);
      expect(find.text('https://openai.com/news'), findsOneWidget);
      expect(find.text('提取模式：article'), findsOneWidget);
    });

    testWidgets('result card shows title first and content after expand', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: FetchWebpageToolResultCard(
              result: ToolResult(
                toolName: 'fetch_webpage',
                status: ToolExecutionStatus.success,
                summary: '已读取网页：OpenAI News',
                data: {
                  'url': 'https://openai.com/news',
                  'title': 'OpenAI News',
                  'content': 'OpenAI released a new update.',
                  'extractMode': 'article',
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('OpenAI News'), findsOneWidget);
      expect(find.text('openai.com'), findsOneWidget);
      expect(find.text('OpenAI released a new update.'), findsNothing);

      await tester.tap(find.text('查看正文'));
      await tester.pumpAndSettle();

      expect(find.text('OpenAI released a new update.'), findsOneWidget);
      expect(find.text('提取模式：article'), findsOneWidget);
    });
  });
}
