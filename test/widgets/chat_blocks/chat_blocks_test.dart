import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/tools/core/tool_display_names.dart';
import 'package:ai_chat/widgets/chat_blocks/assistant_doc_block.dart';
import 'package:ai_chat/widgets/chat_blocks/streaming_response_block.dart';
import 'package:ai_chat/widgets/chat_timeline/stable_markdown_block.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_inline_step_row.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_result_summary_row.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_workflow_card.dart';
import 'package:ai_chat/widgets/chat_blocks/user_anchor_bubble.dart';
import 'package:ai_chat/widgets/markdown/flutter_markdown_impl.dart';
import 'package:ai_chat/widgets/markdown/code_widget.dart';
import 'package:ai_chat/widgets/markdown/markdown_widget_impl.dart';
import 'package:ai_chat/widgets/markdown/table_edge_fade_scroll_shell.dart';
import 'package:ai_chat/widgets/technical_content_surface.dart';
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
      expect(find.byType(StableMarkdownBlock), findsOneWidget);
    });

    testWidgets('markdown typography follows hybrid reader rhythm', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: FlutterMarkdownImpl(
              data: '# Heading\n\n## Section\n\nFirst paragraph.\n\n- item',
            ),
          ),
        ),
      );

      final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      final styleSheet = markdown.styleSheet!;

      expect(styleSheet.p!.fontSize, 13.2);
      expect(styleSheet.p!.height, 1.52);
      expect(styleSheet.p!.fontFamily, 'AnthropicSans');
      expect(styleSheet.p!.fontWeight, FontWeight.w400);
      expect(
        styleSheet.p!.fontFamilyFallback,
        containsAllInOrder(
          const ['NotoSansCJKSC', 'Noto Sans SC', 'PingFang SC'],
        ),
      );
      expect(styleSheet.strong!.fontWeight, FontWeight.w500);
      expect(styleSheet.h1!.fontSize, 17);
      expect(styleSheet.h1!.fontWeight, FontWeight.w500);
      expect(styleSheet.h2!.fontSize, 15.2);
      expect(styleSheet.h2!.fontWeight, FontWeight.w500);
      expect(styleSheet.h3!.fontSize, 14);
      expect(styleSheet.blockSpacing, 10);
      expect(
          styleSheet.h2Padding!.top, greaterThan(styleSheet.h2Padding!.bottom));
      expect(
          styleSheet.h3Padding!.top, greaterThan(styleSheet.h3Padding!.bottom));
      expect(styleSheet.listIndent, lessThanOrEqualTo(17));
      expect(styleSheet.listBullet!.height, 1.46);
    });

    testWidgets('markdown blockquote reads as a quiet side note', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: FlutterMarkdownImpl(
              data: '> 压缩边界应优先选择已完成 turn。',
            ),
          ),
        ),
      );

      final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      final styleSheet = markdown.styleSheet!;
      final decoration = styleSheet.blockquoteDecoration! as BoxDecoration;
      final border = decoration.border! as Border;

      expect(styleSheet.blockquote!.fontSize, 13);
      expect(styleSheet.blockquote!.height, 1.5);
      expect(
          styleSheet.blockquotePadding, const EdgeInsets.fromLTRB(13, 8, 9, 8));
      expect(decoration.borderRadius, BorderRadius.circular(8));
      expect(border.left.width, 1.4);
    });

    testWidgets('streaming response stays close to completed markdown rhythm', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: StreamingResponseBlock(
              text: '这是一段正在生成的长回答，用来验证流式态和完成态之间不会出现明显视觉断层。',
            ),
          ),
        ),
      );

      final text = tester.widget<SelectableText>(find.byType(SelectableText));

      expect(text.style!.fontSize, 13.2);
      expect(text.style!.height, 1.48);
      expect(text.style!.fontFamily, 'AnthropicSans');
    });

    testWidgets('markdown content is isolated by repaint boundary', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: FlutterMarkdownImpl(
              data: 'A paragraph with **markdown** content.',
            ),
          ),
        ),
      );

      expect(
        find.ancestor(
          of: find.byType(MarkdownBody),
          matching: find.byType(RepaintBoundary),
        ),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('markdown tables use the table-focused renderer',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: FlutterMarkdownImpl(
              data: '''
| Plan | Owner | Status |
| --- | --- | --- |
| Table polish | UI | In progress |
| Width behavior | UX | Planned |
''',
            ),
          ),
        ),
      );

      expect(find.byType(MarkdownWidgetImpl), findsOneWidget);
      expect(find.byType(MarkdownBody), findsNothing);
      expect(find.byType(Table), findsOneWidget);
      expect(find.byType(TableEdgeFadeScrollShell), findsOneWidget);
    });

    testWidgets('plain markdown keeps the default document renderer', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: FlutterMarkdownImpl(
              data: '# Heading\n\nA paragraph without table syntax.',
            ),
          ),
        ),
      );

      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.byType(MarkdownWidgetImpl), findsNothing);
    });

    testWidgets('code blocks use shared technical content surface', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: CodeBlockWidget(
              code: 'const value = 42;',
              language: 'dart',
            ),
          ),
        ),
      );

      expect(find.byType(TechnicalContentSurface), findsOneWidget);
    });

    testWidgets('table edge fades react to horizontal scroll extent', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(260, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SizedBox(
              width: 240,
              child: TableEdgeFadeScrollShell(
                child: SizedBox(
                  width: 720,
                  height: 80,
                  child: Placeholder(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('table-edge-fade-left')), findsNothing);
      expect(
          find.byKey(const ValueKey('table-edge-fade-right')), findsOneWidget);

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(-220, 0),
      );
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('table-edge-fade-left')), findsOneWidget);
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
      expect(find.byType(ToolInlineStepRow), findsOneWidget);
    });

    testWidgets('workflow confirmation step no longer renders action buttons', (
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

      expect(find.text('待确认'), findsOneWidget);
      expect(find.text('继续'), findsNothing);
      expect(find.text('取消'), findsNothing);
      expect(find.text('继续，以后不再确认'), findsNothing);
    });

    testWidgets(
        'workflow confirmation snapshot still renders confirmation status without buttons',
        (tester) async {
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
                  requiresConfirmation: false,
                  toolAccess: {
                    'toolName': 'create_reminder',
                    'executionPolicy': 'require_confirmation',
                    'isVisibleToPlanner': true,
                  },
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('待确认'), findsOneWidget);
      expect(find.text('继续'), findsNothing);
      expect(find.text('取消'), findsNothing);
      expect(find.text('继续，以后不再确认'), findsNothing);
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

      expect(
        find.text(resolveToolDisplayName('search_chat_history')),
        findsOneWidget,
      );
      expect(find.text('完成'), findsOneWidget);
      expect(find.text('命中 4 条历史消息'), findsOneWidget);
    });
  });
}
