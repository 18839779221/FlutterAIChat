import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat/chat_attachment.dart';
import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_inline_step_row.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_workflow_card.dart';
import 'package:ai_chat/widgets/chat_timeline/chat_timeline_item.dart';
import 'package:ai_chat/widgets/chat_timeline/chat_timeline_row.dart';
import 'package:ai_chat/services/chat_block_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/services/tool_ui_renderer_registry.dart';
import 'package:ai_chat/widgets/tool_renderers/edit_tool_renderer.dart';

void main() {
  testWidgets(
    'tool workflow row renders from typed projection without payload step parsing',
    (tester) async {
      final sourceMessage = ChatMessage(
        id: 1,
        text: '准备写入文件',
        role: MessageRole.assistant,
        contentType: MessageContentType.toolInvocation,
      );
      final block = AssistantTurnBlock(
        id: 'turn-1-workflow-1',
        turnId: 'turn-1',
        type: AssistantTurnBlockType.toolWorkflow,
        sequence: 1,
        createdAt: DateTime(2026, 4, 28, 10, 0, 0),
        updatedAt: DateTime(2026, 4, 28, 10, 0, 0),
        status: ToolWorkflowStepStatus.running.name,
        title: '准备写入文件',
        text: '准备写入文件',
        workflowSteps: const [
          ToolWorkflowStep(
            stepId: 'step-1',
            turnId: 'turn-1',
            toolName: 'unknown_tool',
            title: '准备写入文件',
            summary: '准备写入文件',
            status: ToolWorkflowStepStatus.running,
            requiresConfirmation: false,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: ChatTimelineRow(
                item: ChatTimelineItem(
                  stableKey: 'workflow-row',
                  type: ChatTimelineItemType.assistantBlock,
                  sourceMessage: sourceMessage,
                  sourceMessages: [sourceMessage],
                  block: block,
                ),
                blockBuilder: ChatBlockBuilder(),
                currentGroupId: 1,
                onLongPressMessage: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ToolWorkflowCard), findsOneWidget);
    },
  );

  testWidgets(
    'edit workflow row does not fall back to default workflow card when renderer hides it',
    (tester) async {
      final sourceMessage = ChatMessage(
        id: 11,
        text: '准备编辑文件',
        role: MessageRole.assistant,
        contentType: MessageContentType.toolInvocation,
      );
      final block = AssistantTurnBlock(
        id: 'turn-edit-workflow-1',
        turnId: 'turn-edit',
        type: AssistantTurnBlockType.toolWorkflow,
        sequence: 1,
        createdAt: DateTime(2026, 6, 2, 10, 0, 0),
        updatedAt: DateTime(2026, 6, 2, 10, 0, 0),
        status: ToolWorkflowStepStatus.running.name,
        title: '准备编辑文件',
        text: '准备编辑文件',
        workflowSteps: const [
          ToolWorkflowStep(
            stepId: 'edit-step-1',
            turnId: 'turn-edit',
            toolName: 'Edit',
            title: '准备编辑文件',
            summary: '准备编辑文件',
            status: ToolWorkflowStepStatus.running,
            requiresConfirmation: false,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            toolUiRendererRegistryProvider.overrideWithValue(
              const ToolUiRendererRegistry(
                renderers: [EditToolUiRenderer()],
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: ChatTimelineRow(
                item: ChatTimelineItem(
                  stableKey: 'edit-workflow-row',
                  type: ChatTimelineItemType.assistantBlock,
                  sourceMessage: sourceMessage,
                  sourceMessages: [sourceMessage],
                  block: block,
                ),
                blockBuilder: ChatBlockBuilder(),
                currentGroupId: 1,
                onLongPressMessage: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ToolWorkflowCard), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
    },
  );

  testWidgets(
    'tool result row renders from typed projection without ToolResult.fromJson in row layer',
    (tester) async {
      final sourceMessage = ChatMessage(
        id: 2,
        text: '已执行：搜索历史记录',
        role: MessageRole.assistant,
        contentType: MessageContentType.toolResult,
      );
      final block = AssistantTurnBlock(
        id: 'turn-2-result-1',
        turnId: 'turn-2',
        type: AssistantTurnBlockType.toolResultSummary,
        sequence: 1,
        createdAt: DateTime(2026, 4, 28, 10, 0, 1),
        updatedAt: DateTime(2026, 4, 28, 10, 0, 1),
        status: ToolExecutionStatus.success.name,
        title: 'search_chat_history',
        text: '已执行：搜索历史记录',
        toolResult: const ToolResult(
          toolName: 'search_chat_history',
          status: ToolExecutionStatus.success,
          summary: '已执行：搜索历史记录',
          data: {'matchCount': 1},
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: ChatTimelineRow(
                item: ChatTimelineItem(
                  stableKey: 'result-row',
                  type: ChatTimelineItemType.assistantBlock,
                  sourceMessage: sourceMessage,
                  sourceMessages: [sourceMessage],
                  block: block,
                ),
                blockBuilder: ChatBlockBuilder(),
                currentGroupId: 1,
                onLongPressMessage: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ToolInlineStepRow), findsOneWidget);
    },
  );

  testWidgets(
    'user bubble row keeps image attachments on the user side',
    (tester) async {
      final sourceMessage = ChatMessage(
        id: 3,
        text: '看这张图',
        role: MessageRole.user,
        attachments: [
          ChatAttachment.image(
            localId: 'att-1',
            fileName: 'demo.png',
            mimeType: 'image/png',
            status: ChatAttachmentStatus.ready,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: ChatTimelineRow(
                item: ChatTimelineItem(
                  stableKey: 'user-row',
                  type: ChatTimelineItemType.userBubble,
                  userMessage: sourceMessage,
                  sourceMessage: sourceMessage,
                  sourceMessages: [sourceMessage],
                ),
                blockBuilder: ChatBlockBuilder(),
                currentGroupId: 1,
                onLongPressMessage: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('看这张图'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat-message-image-attachments-align')),
        findsOneWidget,
      );
    },
  );
}
