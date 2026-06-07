import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/tool_renderers/research_tool_card_shell.dart';
import 'package:ai_chat/widgets/tool_renderers/tool_running_effects.dart';
import 'package:ai_chat/widgets/tool_renderers/web_search_tool_result_card.dart';
import 'package:ai_chat/widgets/tool_renderers/web_search_tool_workflow_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('web_search tool cards', () {
    testWidgets('workflow card summarizes query without exposing max results', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: WebSearchToolWorkflowCard(
              steps: [
                ToolWorkflowStep(
                  stepId: 'web-1',
                  turnId: 'turn-1',
                  toolName: 'web_search',
                  title: '联网搜索',
                  summary: '准备搜索 OpenAI latest',
                  status: ToolWorkflowStepStatus.running,
                  requiresConfirmation: false,
                  details: {
                    'query': 'OpenAI latest',
                    'maxResults': 5,
                  },
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('联网搜索'), findsOneWidget);
      expect(find.text('OpenAI latest'), findsOneWidget);
      expect(find.textContaining('最多'), findsNothing);

      final shell = tester.widget<ResearchToolCardShell>(
        find.byType(ResearchToolCardShell),
      );
      expect(shell.usePreciseSweepBounds, isTrue);

      final sweep = tester.widget<RunningSweepSurface>(
        find.byType(RunningSweepSurface),
      );
      expect(sweep.usePreciseChildExtent, isTrue);
      expect(sweep.widthFactor, 0.56);
      expect(sweep.duration, const Duration(milliseconds: 2600));
      expect(sweep.sweepAngle, closeTo(-0.24, 0.0001));
      expect(sweep.sweepColor, const Color(0xFFF6F6F2));
      expect(sweep.activeSweepFraction, 1.0);
      expect(sweep.sweepOpacity, 1.08);
    });

    testWidgets('result card shows overview first and sources after expand', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: WebSearchToolResultCard(
              result: ToolResult(
                toolName: 'web_search',
                status: ToolExecutionStatus.success,
                summary: '已执行联网搜索',
                data: {
                  'query': 'OpenAI latest',
                  'results': [
                    {
                      'title': 'OpenAI News',
                      'source': 'openai.com',
                      'snippet': 'Latest OpenAI update',
                      'url': 'https://openai.com/news',
                    },
                  ],
                },
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('OpenAI latest'), findsOneWidget);
      expect(find.textContaining('1 个来源'), findsOneWidget);
      expect(find.text('查看来源'), findsOneWidget);
      expect(find.text('openai.com'), findsNothing);
      expect(find.text('OpenAI News'), findsNothing);

      await tester.tap(find.text('查看来源'));
      await tester.pumpAndSettle();

      expect(find.text('OpenAI News'), findsOneWidget);
      expect(find.text('Latest OpenAI update'), findsOneWidget);
    });
  });
}
