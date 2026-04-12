import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_blocks/assistant_doc_block.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_result_summary_row.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_workflow_card.dart';
import 'package:ai_chat/widgets/chat_blocks/user_anchor_bubble.dart';
import 'package:ai_chat/widgets/markdown/flutter_markdown_impl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chat block widgets', () {
    testWidgets('renders user anchor bubble text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: UserAnchorBubble(text: '用户短消息'),
          ),
        ),
      );

      expect(find.text('用户短消息'), findsOneWidget);

      final constrainedBox = tester.widget<ConstrainedBox>(
        find.descendant(
          of: find.byType(UserAnchorBubble),
          matching: find.byType(ConstrainedBox),
        ),
      );
      expect(constrainedBox.constraints.maxWidth, 468);
    });

    testWidgets('renders assistant doc block label and content',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: AssistantDocBlock(
              label: 'Analysis',
              text: '这是一段分析内容',
            ),
          ),
        ),
      );

      expect(find.text('Analysis'), findsOneWidget);
      expect(find.text('这是一段分析内容'), findsOneWidget);
    });

    testWidgets('markdown typography favors tighter document rhythm', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: FlutterMarkdownImpl(
              data: '# Heading\n\nFirst paragraph.\n\n- item',
            ),
          ),
        ),
      );

      final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      final styleSheet = markdown.styleSheet!;

      expect(styleSheet.p!.height, lessThanOrEqualTo(1.42));
      expect(styleSheet.p!.fontFamily, 'AnthropicSans');
      expect(styleSheet.p!.fontWeight, FontWeight.w400);
      expect(
        styleSheet.p!.fontFamilyFallback,
        containsAllInOrder(
          const ['NotoSansCJKSC', 'Noto Sans SC', 'PingFang SC'],
        ),
      );
      expect(styleSheet.h2!.fontSize, lessThan(17));
      expect(styleSheet.listBullet!.height, lessThanOrEqualTo(1.36));
      expect(styleSheet.blockSpacing, lessThanOrEqualTo(6));
      expect(
          styleSheet.h2Padding!.top, greaterThan(styleSheet.h2Padding!.bottom));
    });

    testWidgets(
        'active workflow step is expanded and completed step is collapsed', (
      tester,
    ) async {
      final steps = [
        const ToolWorkflowStep(
          stepId: 'step-1',
          turnId: 'turn-1',
          toolName: 'fetch_webpage',
          title: '读取网页',
          summary: '正在读取网页内容',
          status: ToolWorkflowStepStatus.running,
          requiresConfirmation: false,
        ),
        const ToolWorkflowStep(
          stepId: 'step-2',
          turnId: 'turn-1',
          toolName: 'search_chat_history',
          title: '搜索历史',
          summary: '命中 4 条历史消息',
          status: ToolWorkflowStepStatus.completed,
          requiresConfirmation: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ToolWorkflowCard(
              title: 'Tool Workflow',
              steps: steps,
              expandedStepId: 'step-1',
            ),
          ),
        ),
      );

      expect(find.text('执行中'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      expect(find.text('正在读取网页内容'), findsOneWidget);
      expect(find.text('命中 4 条历史消息'), findsOneWidget);
    });

    testWidgets(
        'workflow confirmation actions only show on expanded confirming step', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: ToolWorkflowCard(
              title: 'Tool Workflow',
              expandedStepId: 'confirm-step',
              steps: [
                ToolWorkflowStep(
                  stepId: 'confirm-step',
                  turnId: 'turn-1',
                  toolName: 'create_reminder',
                  title: '创建提醒',
                  summary: '准备执行工具：创建提醒',
                  status: ToolWorkflowStepStatus.awaitingConfirmation,
                  requiresConfirmation: true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('继续'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('继续，以后不再确认'), findsOneWidget);
    });

    testWidgets('tool result summary shows compact status and summary',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: ToolResultSummaryRow(
              result: ToolResult(
                toolName: 'search_chat_history',
                status: ToolExecutionStatus.success,
                summary: '命中 4 条历史消息',
              ),
            ),
          ),
        ),
      );

      expect(find.text('search_chat_history'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      expect(find.text('命中 4 条历史消息'), findsOneWidget);
    });
  });
}
