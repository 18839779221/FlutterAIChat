import 'package:ai_chat/models/chat/active_turn_status_presentation.dart';
import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/chat/tool_phase_visibility.dart';
import 'package:ai_chat/models/chat/tool_presentation_event.dart';
import 'package:ai_chat/models/chat/runtime_streaming_preview_state.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/debug/debug_test_case.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_blocks/final_response_block.dart';
import 'package:ai_chat/widgets/chat_blocks/artifact_preview_surface.dart';
import 'package:ai_chat/widgets/chat_blocks/streaming_response_block.dart';
import 'package:ai_chat/widgets/chat_blocks/unified_turn_status_bar.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_inline_step_row.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_outcome_card.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_result_summary_row.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_workflow_card.dart';
import 'package:ai_chat/widgets/chat_blocks/user_anchor_bubble.dart';
import 'package:ai_chat/widgets/chat_message_list.dart';
import 'package:ai_chat/widgets/animations/message_growth_animation.dart';
import 'package:ai_chat/widgets/interaction/ask_user_question_result_card.dart';
import 'package:ai_chat/widgets/interaction/ask_user_question_timeline_card.dart';
import 'package:ai_chat/widgets/tool_renderers/compact_tool_row_renderer.dart';
import 'package:ai_chat/widgets/tool_renderers/web_search_tool_result_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatMessageList block rendering', () {
    testWidgets('empty conversations show a designed start state',
        (tester) async {
      await _pumpMessageList(tester, messages: const []);

      expect(find.text('开始一段新的对话'), findsOneWidget);
      expect(find.text('从一个问题开始，或让助手帮你推进下一步。'), findsOneWidget);
      expect(find.text('纯文本直答'), findsOneWidget);
      expect(find.text('单工具自动执行'), findsOneWidget);
    });

    testWidgets(
        'empty state suggestion fills the composer without auto sending',
        (tester) async {
      final textController = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(textController.dispose);
      addTearDown(focusNode.dispose);

      await _pumpMessageList(
        tester,
        messages: const [],
        textController: textController,
        focusNode: focusNode,
      );

      await tester.tap(find.text('纯文本直答'));
      await tester.pump();

      expect(
        textController.text,
        '用一句话解释什么是 SQLite',
      );
      expect(
        textController.selection,
        TextSelection.collapsed(offset: textController.text.length),
      );
    });

    testWidgets('multi-round suggestion fills the updated planner prompt',
        (tester) async {
      final textController = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(textController.dispose);
      addTearDown(focusNode.dispose);

      await _pumpMessageList(
        tester,
        messages: const [],
        textController: textController,
        focusNode: focusNode,
      );

      await tester.tap(find.text('多工具串行执行'));
      await tester.pump();

      expect(
        textController.text,
        '先搜索 OpenAI 今天的最新消息，再读取你认为最相关的一篇网页，然后总结给我',
      );
      expect(
        textController.selection,
        TextSelection.collapsed(offset: textController.text.length),
      );
    });

    testWidgets('plain assistant text stays visible in the timeline', (
      tester,
    ) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: '**assistant** reply',
            role: MessageRole.assistant,
            contentType: MessageContentType.plainText,
          ),
        ],
      );

      expect(find.text('assistant reply'), findsOneWidget);
    });

    testWidgets(
        'runtime preview text block renders as streaming response without generating assistant message',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我回答',
            role: MessageRole.user,
            status: MessageStatus.completed,
            contentType: MessageContentType.plainText,
          ),
        ],
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'preview_message_1',
              createdAt: DateTime(2026, 5, 5, 10, 0, 1),
              updatedAt: DateTime(2026, 5, 5, 10, 0, 2),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'preview_message_1:text',
                  blockType: StreamingContentBlockType.text,
                  createdAt: DateTime(2026, 5, 5, 10, 0, 1),
                  updatedAt: DateTime(2026, 5, 5, 10, 0, 2),
                  text: '这是运行中的正文',
                ),
              ],
            ),
          ],
        ),
      );

      expect(find.byType(StreamingResponseBlock), findsOneWidget);
      expect(find.byType(FinalResponseBlock), findsNothing);
      expect(find.text('这是运行中的正文'), findsOneWidget);
    });

    testWidgets(
        'runtime preview thinking block renders visible analysis without persisted assistant message',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我回答',
            role: MessageRole.user,
            status: MessageStatus.completed,
            contentType: MessageContentType.plainText,
          ),
        ],
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'preview_message_2',
              createdAt: DateTime(2026, 5, 5, 10, 0, 1),
              updatedAt: DateTime(2026, 5, 5, 10, 0, 2),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'preview_message_2:thinking',
                  blockType: StreamingContentBlockType.thinking,
                  createdAt: DateTime(2026, 5, 5, 10, 0, 1),
                  updatedAt: DateTime(2026, 5, 5, 10, 0, 2),
                  text: '先整理答案结构',
                ),
              ],
            ),
          ],
        ),
      );

      expect(find.text('思考过程'), findsOneWidget);
      expect(find.text('先整理答案结构'), findsOneWidget);
    });

    testWidgets(
        'runtime create_artifact debug stream stays out of the normal timeline',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          ChatMessage(
            id: 30,
            text: '帮我做个 artifact',
            role: MessageRole.user,
            status: MessageStatus.completed,
            contentType: MessageContentType.plainText,
          ),
        ],
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'planner_runtime',
              createdAt: DateTime(2026, 5, 5, 10, 0, 1),
              updatedAt: DateTime(2026, 5, 5, 10, 0, 1),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'planner_runtime:tool:0',
                  blockType: StreamingContentBlockType.toolUse,
                  toolUseId: 'call_artifact_1',
                  toolName: 'create_artifact',
                  createdAt: DateTime(2026, 5, 5, 10, 0, 1),
                  updatedAt: DateTime(2026, 5, 5, 10, 0, 1),
                  text: '{"source":"<div>调试流内容</div>"}',
                ),
              ],
            ),
          ],
        ),
      );

      expect(find.text('Analysis'), findsNothing);
      expect(find.textContaining('调试流内容'), findsNothing);
    });

    testWidgets(
        'runtime response preview can coexist with runtime create_artifact preview',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          ChatMessage(
            id: 30,
            text: '边回答边生成 artifact',
            role: MessageRole.user,
            status: MessageStatus.completed,
            contentType: MessageContentType.plainText,
          ),
        ],
        runtimePreviewState: RuntimeStreamingPreviewState(
          messages: [
            RuntimeStreamingPreviewMessage(
              messageId: 'planner_runtime',
              createdAt: DateTime(2026, 5, 5, 10, 0, 1),
              updatedAt: DateTime(2026, 5, 5, 10, 0, 2),
              blocks: [
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'planner_runtime:text',
                  blockType: StreamingContentBlockType.text,
                  createdAt: DateTime(2026, 5, 5, 10, 0, 1),
                  updatedAt: DateTime(2026, 5, 5, 10, 0, 2),
                  text: '先给你正文说明',
                ),
                RuntimeStreamingPreviewBlock(
                  contentBlockId: 'planner_runtime:tool:0',
                  blockType: StreamingContentBlockType.toolUse,
                  toolUseId: 'call_artifact_1',
                  toolName: 'create_artifact',
                  createdAt: DateTime(2026, 5, 5, 10, 0, 1),
                  updatedAt: DateTime(2026, 5, 5, 10, 0, 2),
                  text:
                      '{"id":"demo-artifact","type":"html","title":"Demo","source":"<div>artifact body</div>"}',
                ),
              ],
            ),
          ],
        ),
      );

      expect(find.byType(StreamingResponseBlock), findsOneWidget);
      expect(find.text('先给你正文说明'), findsOneWidget);
      expect(find.byType(ArtifactPreviewSurface), findsOneWidget);
    });

    testWidgets('completed final-answer reasoning stays collapsed until tapped',
        (
      tester,
    ) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: '最终回答',
            role: MessageRole.assistant,
            contentType: MessageContentType.plainText,
            reasoningContent: '先确认上下文，再给出答案。',
          ),
        ],
      );

      expect(find.text('思考过程'), findsOneWidget);
      expect(find.text('先确认上下文，再给出答案。'), findsNothing);
      expect(find.text('最终回答'), findsOneWidget);

      await tester.tap(find.text('思考过程'));
      await tester.pumpAndSettle();

      expect(find.text('先确认上下文，再给出答案。'), findsOneWidget);
    });

    testWidgets('tool-use reasoning stays directly visible', (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: '',
            role: MessageRole.assistant,
            contentType: MessageContentType.plainText,
            reasoningContent: '需要先读取文件。',
            payloadJson: const {'reasoningScope': 'tool_use'},
          ),
        ],
      );

      expect(find.text('思考过程'), findsOneWidget);
      expect(find.text('需要先读取文件。'), findsOneWidget);
    });

    testWidgets('streaming assistant reasoning content is visible', (
      tester,
    ) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: '正在回答',
            role: MessageRole.assistant,
            contentType: MessageContentType.plainText,
            status: MessageStatus.generating,
            reasoningContent: '正在整理依据。',
          ),
        ],
      );

      expect(find.byType(StreamingResponseBlock), findsOneWidget);
      expect(find.text('思考过程'), findsOneWidget);
      expect(find.text('正在整理依据。'), findsOneWidget);
      expect(find.text('正在回答'), findsOneWidget);
    });

    testWidgets('idle assistant message does not show running tail', (
      tester,
    ) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'assistant reply',
            role: MessageRole.assistant,
            contentType: MessageContentType.plainText,
          ),
        ],
      );

      expect(find.byKey(const ValueKey('latest-message-running-tail')),
          findsNothing);
    });

    testWidgets(
        'chat message list attaches unified status to the active anchor row',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          ChatMessage(
            id: 1,
            text: '问题',
            role: MessageRole.user,
            status: MessageStatus.completed,
            contentType: MessageContentType.plainText,
          ),
          ChatMessage(
            id: 4,
            text: '回答',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            contentType: MessageContentType.plainText,
          ),
        ],
        activeTurnStatus: const ActiveTurnStatusPresentation(
          phase: ActiveTurnStatusPhase.planning,
          text: '正在规划下一步',
          turnId: 'turn-4',
          sourceMessageId: 4,
          sourceKind: ActiveTurnStatusSourceKind.toolEvent,
          allowFloating: true,
        ),
      );

      expect(find.byType(UnifiedTurnStatusBar), findsOneWidget);
      expect(find.text('正在规划下一步'), findsOneWidget);
    });

    testWidgets(
        'chat timeline row only renders status for the designated anchor item',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          ChatMessage(
            id: 1,
            text: '第一轮问题',
            role: MessageRole.user,
            status: MessageStatus.completed,
            contentType: MessageContentType.plainText,
          ),
          ChatMessage(
            id: 2,
            text: '第一轮回答',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            contentType: MessageContentType.plainText,
          ),
          ChatMessage(
            id: 3,
            text: '第二轮问题',
            role: MessageRole.user,
            status: MessageStatus.completed,
            contentType: MessageContentType.plainText,
          ),
          ChatMessage(
            id: 4,
            text: '第二轮回答',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            contentType: MessageContentType.plainText,
          ),
        ],
        activeTurnStatus: const ActiveTurnStatusPresentation(
          phase: ActiveTurnStatusPhase.planning,
          text: '正在规划下一步',
          turnId: 'turn-4',
          sourceMessageId: 4,
          sourceKind: ActiveTurnStatusSourceKind.toolEvent,
          allowFloating: true,
        ),
      );

      expect(find.byType(UnifiedTurnStatusBar), findsOneWidget);
      expect(find.text('正在规划下一步'), findsOneWidget);
      expect(find.text('第一轮回答'), findsOneWidget);
      expect(find.text('第二轮回答'), findsOneWidget);
    });

    testWidgets('generating assistant text uses lightweight streaming block', (
      tester,
    ) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'streaming reply',
            role: MessageRole.assistant,
            contentType: MessageContentType.plainText,
            status: MessageStatus.generating,
          ),
        ],
      );

      expect(find.byType(StreamingResponseBlock), findsOneWidget);
      expect(find.byType(FinalResponseBlock), findsNothing);
      expect(find.text('streaming reply'), findsOneWidget);
    });

    testWidgets(
        'streaming assistant message shows running tail on latest block',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'streaming reply',
            role: MessageRole.assistant,
            contentType: MessageContentType.plainText,
            status: MessageStatus.generating,
          ),
        ],
        sendPhase: ChatSendPhase.streamingResponse,
      );

      expect(find.byKey(const ValueKey('latest-message-running-tail')),
          findsOneWidget);
      expect(find.text('正在生成回复'), findsOneWidget);
    });

    testWidgets('preparing phase shows running tail under latest user message',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: '帮我总结一下',
            role: MessageRole.user,
            contentType: MessageContentType.plainText,
          ),
        ],
        sendPhase: ChatSendPhase.preparing,
      );

      expect(find.byKey(const ValueKey('latest-message-running-tail')),
          findsOneWidget);
      expect(find.text('正在请求模型'), findsOneWidget);
    });

    testWidgets('idle phase can render explicit testing status copy',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: '帮我总结一下',
            role: MessageRole.user,
            contentType: MessageContentType.plainText,
          ),
        ],
        sendPhase: ChatSendPhase.idle,
        sendStatusText: '测试边界状态',
      );

      expect(find.byKey(const ValueKey('latest-message-running-tail')),
          findsOneWidget);
      expect(find.text('测试边界状态'), findsOneWidget);
    });

    testWidgets('preparing phase after assistant output shows planning text',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'OpenAI 最近有什么新闻？',
            role: MessageRole.user,
            contentType: MessageContentType.plainText,
          ),
          _buildMessage(
            text: '准备执行工具',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const ToolInvocation(
              toolName: 'web_search',
              arguments: {'query': 'OpenAI latest news'},
              status: ToolInvocationStatus.proposed,
              summary: '准备执行工具：联网搜索',
              requiresConfirmation: false,
            ).toJson(),
          ),
        ],
        sendPhase: ChatSendPhase.preparing,
      );

      expect(find.byKey(const ValueKey('latest-message-running-tail')),
          findsOneWidget);
      expect(find.text('正在规划下一步'), findsOneWidget);
    });

    testWidgets('preparing phase uses transient retry status text when present',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'OpenAI 最近有什么新闻？',
            role: MessageRole.user,
            contentType: MessageContentType.plainText,
          ),
          _buildMessage(
            text: '准备执行工具',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const ToolInvocation(
              toolName: 'web_search',
              arguments: {'query': 'OpenAI latest news'},
              status: ToolInvocationStatus.proposed,
              summary: '准备执行工具：联网搜索',
              requiresConfirmation: false,
            ).toJson(),
          ),
        ],
        sendPhase: ChatSendPhase.preparing,
        sendStatusText: '请求超时，正在重试 1/5',
      );

      expect(find.byKey(const ValueKey('latest-message-running-tail')),
          findsOneWidget);
      expect(find.text('请求超时，正在重试 1/5'), findsOneWidget);
      expect(find.text('正在规划下一步'), findsNothing);
    });

    testWidgets('tool result renders as collapsed summary row', (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'Tool fallback text',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            payloadJson: const ToolResult(
              toolName: 'search_chat_history',
              status: ToolExecutionStatus.success,
              summary: '已执行：搜索历史记录',
              data: {'matchCount': 2},
            ).toJson(),
          ),
        ],
      );

      expect(find.byType(ToolInlineStepRow), findsOneWidget);
      expect(find.text('已执行：搜索历史记录'), findsOneWidget);
      expect(find.byType(AnimatedSwitcher), findsOneWidget);
    });

    testWidgets('newly appended assistant row uses restrained growth motion',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: '先前消息',
            role: MessageRole.assistant,
            contentType: MessageContentType.plainText,
          ),
        ],
      );

      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: '先前消息',
            role: MessageRole.assistant,
            contentType: MessageContentType.plainText,
          ),
          _buildMessage(
            text: '新消息',
            role: MessageRole.assistant,
            contentType: MessageContentType.plainText,
          ),
        ],
      );

      final animation = tester.widget<MessageGrowthAnimation>(
        find.byType(MessageGrowthAnimation).last,
      );
      expect(animation.offsetY, 10);
      expect(animation.beginScale, 0.985);
    });

    testWidgets(
        'completed assistant markdown block exposes a stable timeline key',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          ChatMessage(
            id: 1,
            text: '问题',
            role: MessageRole.user,
            status: MessageStatus.completed,
            contentType: MessageContentType.plainText,
          ),
          ChatMessage(
            id: 2,
            text: '# Title\n\nParagraph',
            role: MessageRole.assistant,
            status: MessageStatus.completed,
            contentType: MessageContentType.plainText,
          ),
        ],
      );

      expect(
        find.byKey(const ValueKey('timeline-block-0_1-analysis-1')),
        findsOneWidget,
      );
    });

    testWidgets(
        'runtime preview block keeps the same timeline row key when updatedAt changes',
        (tester) async {
      const previewBlockId = 'preview_message:block:0:toolUse';
      final initialPreviewState = RuntimeStreamingPreviewState(
        messages: [
          RuntimeStreamingPreviewMessage(
            messageId: 'preview_message',
            createdAt: DateTime(2026, 5, 29, 14, 0, 0),
            updatedAt: DateTime(2026, 5, 29, 14, 0, 0),
            blocks: [
              RuntimeStreamingPreviewBlock(
                contentBlockId: previewBlockId,
                blockType: StreamingContentBlockType.toolUse,
                createdAt: DateTime(2026, 5, 29, 14, 0, 0),
                updatedAt: DateTime(2026, 5, 29, 14, 0, 0),
                toolUseId: 'call_preview_1',
                toolName: 'create_artifact',
                text:
                    '{"id":"demo-artifact","type":"html","title":"Demo","source":"<div>1</div>"}',
              ),
            ],
          ),
        ],
      );

      await _pumpMessageList(
        tester,
        messages: [
          ChatMessage(
            id: 1,
            text: '做个 artifact',
            role: MessageRole.user,
            status: MessageStatus.completed,
            contentType: MessageContentType.plainText,
          ),
        ],
        runtimePreviewState: initialPreviewState,
      );

      expect(
        find.byKey(const ValueKey('timeline-block-preview_message:block:0:toolUse')),
        findsOneWidget,
      );

      final updatedPreviewState = RuntimeStreamingPreviewState(
        messages: [
          RuntimeStreamingPreviewMessage(
            messageId: 'preview_message',
            createdAt: DateTime(2026, 5, 29, 14, 0, 0),
            updatedAt: DateTime(2026, 5, 29, 14, 0, 1),
            blocks: [
              RuntimeStreamingPreviewBlock(
                contentBlockId: previewBlockId,
                blockType: StreamingContentBlockType.toolUse,
                createdAt: DateTime(2026, 5, 29, 14, 0, 0),
                updatedAt: DateTime(2026, 5, 29, 14, 0, 1),
                toolUseId: 'call_preview_1',
                toolName: 'create_artifact',
                text:
                    '{"id":"demo-artifact","type":"html","title":"Demo","source":"<div>12</div>"}',
              ),
            ],
          ),
        ],
      );

      final element = tester.element(find.byType(ChatMessageList));
      final container = ProviderScope.containerOf(element);
      final notifier =
          container.read(runtimeStreamingPreviewStateProvider.notifier);
      notifier.state = updatedPreviewState;
      await tester.pump();

      expect(
        find.byKey(const ValueKey('timeline-block-preview_message:block:0:toolUse')),
        findsOneWidget,
      );
    });

    testWidgets(
        'adding a later streaming message does not downgrade previous completed markdown block',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          hasMoreMessagesProvider.overrideWith((ref) => false),
          chatSendStateProvider.overrideWith(
            (ref) => ChatSendStateNotifier()
              ..update(
                phase: ChatSendPhase.idle,
                isGenerating: false,
              ),
          ),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });

      container.read(messagesProvider.notifier).setMessages([
        ChatMessage(
          id: 1,
          text: '问题一',
          role: MessageRole.user,
          status: MessageStatus.completed,
          contentType: MessageContentType.plainText,
        ),
        ChatMessage(
          id: 2,
          text: '# Title\n\nParagraph',
          role: MessageRole.assistant,
          status: MessageStatus.completed,
          contentType: MessageContentType.plainText,
        ),
      ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: ChatMessageList(),
            ),
          ),
        ),
      );

      expect(find.byType(FinalResponseBlock), findsOneWidget);
      expect(find.byType(StreamingResponseBlock), findsNothing);
      expect(find.text('Title'), findsOneWidget);

      container.read(messagesProvider.notifier).addMessage(
            ChatMessage(
              id: 3,
              text: '问题二',
              role: MessageRole.user,
              status: MessageStatus.completed,
              contentType: MessageContentType.plainText,
            ),
          );
      container.read(messagesProvider.notifier).addMessage(
            ChatMessage(
              id: 4,
              text: '还在生成',
              role: MessageRole.assistant,
              status: MessageStatus.generating,
              contentType: MessageContentType.plainText,
            ),
          );
      container.read(chatSendStateProvider.notifier).update(
            phase: ChatSendPhase.streamingResponse,
            isGenerating: true,
          );
      await tester.pump();

      expect(find.byType(FinalResponseBlock), findsOneWidget);
      expect(find.byType(StreamingResponseBlock), findsOneWidget);
      expect(
        find.byKey(const ValueKey('timeline-block-0_1-analysis-1')),
        findsOneWidget,
      );
      expect(find.text('Title'), findsOneWidget);
    });

    testWidgets('latest tool workflow shows running tail on the tool block',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'Custom invocation',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const ToolInvocation(
              toolName: 'web_search',
              arguments: {'query': 'OpenAI latest news'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：联网搜索',
              requiresConfirmation: false,
            ).toJson(),
          ),
        ],
        sendPhase: ChatSendPhase.executingTool,
      );

      expect(find.byKey(const ValueKey('latest-message-running-tail')),
          findsOneWidget);
      expect(find.text('正在联网搜索'), findsOneWidget);
    });

    testWidgets('parallel active tools degrade to generic running text',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: '帮我查一下并读取网页',
            role: MessageRole.user,
            contentType: MessageContentType.plainText,
          ),
          _buildMessage(
            text: '正在执行工具：联网搜索',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const ToolInvocation(
              toolName: 'web_search',
              arguments: {'query': 'OpenAI latest news'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：联网搜索',
              requiresConfirmation: false,
            ).toJson(),
          ),
          _buildMessage(
            text: '正在执行工具：读取网页',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const ToolInvocation(
              toolName: 'fetch_webpage',
              arguments: {'url': 'https://openai.com'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：读取网页',
              requiresConfirmation: false,
            ).toJson(),
          ),
        ],
        sendPhase: ChatSendPhase.executingTool,
      );

      expect(find.byKey(const ValueKey('latest-message-running-tail')),
          findsOneWidget);
      expect(find.text('正在执行工具'), findsOneWidget);
    });

    testWidgets('single remaining tool keeps specific text after other result',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: '帮我查一下并读取网页',
            role: MessageRole.user,
            contentType: MessageContentType.plainText,
          ),
          _buildMessage(
            text: '正在执行工具：联网搜索',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const ToolInvocation(
              toolName: 'web_search',
              arguments: {'query': 'OpenAI latest news'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：联网搜索',
              requiresConfirmation: false,
            ).toJson(),
          ),
          _buildMessage(
            text: '正在执行工具：读取网页',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const ToolInvocation(
              toolName: 'fetch_webpage',
              arguments: {'url': 'https://openai.com'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：读取网页',
              requiresConfirmation: false,
            ).toJson(),
          ),
          _buildMessage(
            text: '已找到 5 条结果',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            payloadJson: const ToolResult(
              toolName: 'web_search',
              status: ToolExecutionStatus.success,
              summary: '已找到 5 条结果',
            ).toJson(),
          ),
        ],
        sendPhase: ChatSendPhase.executingTool,
      );

      expect(find.byKey(const ValueKey('latest-message-running-tail')),
          findsOneWidget);
      expect(find.text('正在读取网页'), findsOneWidget);
    });

    testWidgets(
        'completed tool falls back to planning text instead of stale tool text',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: '帮我搜一下',
            role: MessageRole.user,
            contentType: MessageContentType.plainText,
          ),
          _buildMessage(
            text: '准备执行工具：联网搜索',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const ToolInvocation(
              toolName: 'web_search',
              arguments: {'query': 'OpenAI latest news'},
              status: ToolInvocationStatus.proposed,
              summary: '准备执行工具：联网搜索',
              requiresConfirmation: false,
            ).toJson(),
          ),
          _buildMessage(
            text: '正在执行工具：联网搜索',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const ToolInvocation(
              toolName: 'web_search',
              arguments: {'query': 'OpenAI latest news'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：联网搜索',
              requiresConfirmation: false,
            ).toJson(),
          ),
          _buildMessage(
            text: '已找到 5 条结果',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            payloadJson: const ToolResult(
              toolName: 'web_search',
              status: ToolExecutionStatus.success,
              summary: '已找到 5 条结果',
            ).toJson(),
          ),
        ],
        sendPhase: ChatSendPhase.executingTool,
      );

      expect(find.byKey(const ValueKey('latest-message-running-tail')),
          findsOneWidget);
      expect(find.text('正在规划下一步'), findsOneWidget);
      expect(find.text('正在联网搜索'), findsNothing);
    });

    testWidgets('external action tool result renders as outcome card',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'Reminder created',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            payloadJson: const ToolResult(
              toolName: 'create_reminder',
              status: ToolExecutionStatus.success,
              summary: '已发起提醒创建：设计评审',
              data: {
                'title': '设计评审',
                'dueAt': '明天 09:00',
              },
            ).toJson(),
          ),
        ],
      );

      expect(find.byType(ToolOutcomeCard), findsOneWidget);
      expect(find.text('已发起提醒创建：设计评审'), findsOneWidget);
    });

    testWidgets('actionable tool failure renders as exception card',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'Search failed',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            payloadJson: const ToolResult(
              toolName: 'web_search',
              status: ToolExecutionStatus.failure,
              summary: '联网搜索失败',
              data: {
                'query': 'latest openai',
                'reason': 'missing_api_key',
              },
              errorMessage: 'missing_api_key',
            ).toJson(),
          ),
        ],
      );

      expect(find.byType(WebSearchToolResultCard), findsOneWidget);
      expect(find.textContaining('latest openai'), findsOneWidget);
    });

    testWidgets(
        'unregistered tool invocation still renders fallback workflow card',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'Invocation fallback text',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const ToolInvocation(
              toolName: 'Read',
              arguments: {'file_path': 'README.md'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：读取文件',
              requiresConfirmation: false,
            ).toJson(),
          ),
        ],
        registry: const ToolUiRendererRegistry(renderers: []),
      );

      expect(find.byType(ToolWorkflowCard), findsOneWidget);
      expect(find.text('正在执行工具：读取文件'), findsWidgets);
    });

    testWidgets('registered tool renderer overrides workflow fallback', (
      tester,
    ) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'Custom invocation',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const ToolInvocation(
              toolName: 'Write',
              arguments: {'file_path': 'docs/plan.md'},
              status: ToolInvocationStatus.running,
              summary: '准备写入 docs/plan.md',
              requiresConfirmation: false,
            ).toJson(),
          ),
        ],
        registry: const ToolUiRendererRegistry(
          renderers: [_FakeWriteWorkflowRenderer()],
        ),
      );

      expect(find.text('custom workflow renderer'), findsOneWidget);
      expect(find.byType(ToolWorkflowCard), findsNothing);
    });

    testWidgets(
        'create artifact guideline shows a lightweight hint instead of fallback workflow card',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: '读取 artifact guideline',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const ToolInvocation(
              toolName: 'create_artifact__guideline',
              arguments: {},
              status: ToolInvocationStatus.running,
              summary: '正在读取 artifact guideline',
              requiresConfirmation: false,
            ).toJson(),
          ),
          _buildMessage(
            text: '已返回 artifact guideline',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            payloadJson: const ToolResult(
              toolName: 'create_artifact__guideline',
              status: ToolExecutionStatus.success,
              summary: '已返回 artifact guideline',
              data: {
                'host': {'rootSelector': '#artifact-root'},
                'tokens': {'surface': 'artifactSurface'},
              },
            ).toJson(),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.byType(CompactToolRow), findsAtLeastNWidgets(1));
      expect(find.text('已加载可视化规范'), findsAtLeastNWidgets(1));
      expect(find.byType(ToolWorkflowCard), findsNothing);
      expect(find.text('#artifact-root'), findsNothing);
      expect(find.text('artifactSurface'), findsNothing);
    });

    testWidgets('renderer phase visibility can hide proposed workflow blocks', (
      tester,
    ) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'Custom invocation',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const ToolInvocation(
              toolName: 'Write',
              arguments: {'file_path': 'docs/plan.md'},
              status: ToolInvocationStatus.proposed,
              summary: '准备写入 docs/plan.md',
              requiresConfirmation: false,
            ).toJson(),
          ),
        ],
        registry: const ToolUiRendererRegistry(
          renderers: [_FakeHideProposedWorkflowRenderer()],
        ),
      );

      expect(find.text('custom workflow renderer'), findsNothing);
      expect(find.byType(ToolWorkflowCard), findsNothing);
    });

    testWidgets('write proposed phase stays hidden with real renderer', (
      tester,
    ) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: '准备写入 docs/plan.md',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const ToolInvocation(
              toolName: 'Write',
              arguments: {'file_path': 'docs/plan.md'},
              status: ToolInvocationStatus.proposed,
              summary: '准备写入 docs/plan.md',
              requiresConfirmation: false,
            ).toJson(),
          ),
        ],
      );

      expect(find.byType(ToolWorkflowCard), findsNothing);
      expect(find.text('准备写入 docs/plan.md'), findsNothing);
    });

    testWidgets('web search proposed phase stays hidden with real renderer', (
      tester,
    ) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: '准备搜索 OpenAI 最新消息',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const ToolInvocation(
              toolName: 'web_search',
              arguments: {'query': 'latest openai'},
              status: ToolInvocationStatus.proposed,
              summary: '准备搜索 OpenAI 最新消息',
              requiresConfirmation: false,
            ).toJson(),
          ),
        ],
      );

      expect(find.byType(ToolWorkflowCard), findsNothing);
      expect(find.text('准备搜索 OpenAI 最新消息'), findsNothing);
    });

    testWidgets('ask user question proposed workflow stays hidden', (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: '请先补充信息',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const {
              'toolName': 'ask_user_question',
              'arguments': {
                'questions': [
                  {
                    'id': 'storage_layer',
                    'header': 'Storage',
                    'question': 'Which storage layer should we use?',
                    'multiSelect': false,
                    'options': [],
                  },
                ],
              },
              'status': 'proposed',
              'summary': '请先补充信息',
              'requiresConfirmation': false,
            },
          ),
        ],
      );

      expect(find.byType(ToolWorkflowCard), findsNothing);
      expect(find.text('请先补充信息'), findsNothing);
    });

    testWidgets('ask user question prompt renders compact placeholder card',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: '需要更多信息',
            role: MessageRole.assistant,
            contentType: MessageContentType.askUserQuestionPrompt,
            payloadJson: const {
              'type': 'prompt',
              'agentTurnId': 42,
              'status': 'awaitingResponse',
              'questions': [
                {
                  'id': 'storage_layer',
                  'header': 'Storage',
                  'question': 'Which storage layer should we use?',
                  'multiSelect': false,
                  'options': [],
                },
              ],
            },
          ),
        ],
      );

      expect(find.byType(AskUserQuestionTimelineCard), findsOneWidget);
      expect(find.text('等待你补充信息'), findsOneWidget);
    });

    testWidgets('ask user question result renders compact answer card',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: '已提交答案',
            role: MessageRole.assistant,
            contentType: MessageContentType.askUserQuestionResult,
            payloadJson: const {
              'type': 'result',
              'agentTurnId': 42,
              'status': 'submitted',
              'questions': [
                {
                  'id': 'storage_layer',
                  'header': 'Storage',
                  'question': 'Which storage layer should we use?',
                  'multiSelect': false,
                  'options': [],
                },
                {
                  'id': 'offline_mode',
                  'header': 'Offline',
                  'question': 'Do we need offline mode?',
                  'multiSelect': false,
                  'options': [],
                },
              ],
              'submittedAnswers': {
                'answersByQuestionId': {
                  'storage_layer': 'SQLite',
                  'offline_mode': '',
                },
              },
            },
          ),
        ],
      );

      expect(find.byType(AskUserQuestionResultCard), findsOneWidget);
      expect(find.text('已补充本回合信息'), findsOneWidget);
      expect(find.text('Which storage layer should we use?'), findsOneWidget);
      expect(find.text('Do we need offline mode?'), findsOneWidget);
      expect(find.text('SQLite'), findsOneWidget);
      expect(find.text('已跳过'), findsOneWidget);
      expect(find.text('storage_layer'), findsNothing);
      expect(find.text('offline_mode'), findsNothing);
    });

    testWidgets(
        'action confirmation renders workflow card without inline actions', (
      tester,
    ) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'Confirmation fallback text',
            role: MessageRole.assistant,
            contentType: MessageContentType.actionConfirmation,
            payloadJson: const ToolInvocation(
              toolName: 'create_reminder',
              arguments: {'title': '交周报'},
              status: ToolInvocationStatus.awaitingConfirmation,
              summary: '准备执行工具：创建提醒',
              requiresConfirmation: true,
            ).toJson(),
          ),
        ],
      );

      expect(find.byType(ToolWorkflowCard), findsOneWidget);
      expect(find.text('待确认'), findsOneWidget);
      expect(find.text('继续'), findsNothing);
    });

    testWidgets(
        'action confirmation keeps workflow status from execution policy payload',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'Confirmation fallback text',
            role: MessageRole.assistant,
            contentType: MessageContentType.actionConfirmation,
            payloadJson: {
              ...const ToolInvocation(
                toolName: 'create_reminder',
                arguments: {'title': '交周报'},
                status: ToolInvocationStatus.awaitingConfirmation,
                summary: '准备执行工具：创建提醒',
                requiresConfirmation: false,
              ).toJson(),
              'executionPolicy': 'require_confirmation',
              'toolAccess': const {
                'toolName': 'create_reminder',
                'executionPolicy': 'require_confirmation',
                'isVisibleToPlanner': true,
              },
            },
          ),
        ],
      );

      expect(find.byType(ToolWorkflowCard), findsOneWidget);
      expect(find.text('待确认'), findsOneWidget);
      expect(find.text('继续'), findsNothing);
    });

    testWidgets('invalid tool result payload falls back to plain text', (
      tester,
    ) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'Tool fallback text',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolResult,
            payloadJson: {'unexpected': true},
          ),
        ],
      );

      expect(find.byType(ToolResultSummaryRow), findsNothing);
      expect(find.text('Tool fallback text'), findsOneWidget);
    });

    testWidgets('user messages render as anchor bubbles', (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'User message',
            role: MessageRole.user,
            contentType: MessageContentType.toolResult,
          ),
        ],
      );

      expect(find.byType(UserAnchorBubble), findsOneWidget);
      expect(find.text('User message'), findsOneWidget);
    });

    testWidgets(
        'multi-turn conversations keep the latest turn anchor near the top', (
      tester,
    ) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'older user',
            role: MessageRole.user,
            contentType: MessageContentType.plainText,
          ),
          _buildMessage(
            text: 'older assistant',
            role: MessageRole.assistant,
            contentType: MessageContentType.plainText,
          ),
          _buildMessage(
            text: 'newer user',
            role: MessageRole.user,
            contentType: MessageContentType.plainText,
          ),
          _buildMessage(
            text: 'newer assistant',
            role: MessageRole.assistant,
            contentType: MessageContentType.plainText,
          ),
        ],
      );

      final listBounds = tester.getRect(find.byType(ChatMessageList));
      final latestTurnTop = tester.getTopLeft(find.text('newer user')).dy;

      expect(latestTurnTop, lessThan(listBounds.center.dy));
    });

    testWidgets(
        'short conversations stay in the upper half instead of docking to the bottom',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'Short user turn',
            role: MessageRole.user,
            contentType: MessageContentType.plainText,
          ),
          _buildMessage(
            text: 'Short assistant turn',
            role: MessageRole.assistant,
            contentType: MessageContentType.plainText,
          ),
        ],
      );

      final listBounds = tester.getRect(find.byType(ChatMessageList));
      final bubbleTop = tester.getTopLeft(find.byType(UserAnchorBubble)).dy;

      expect(bubbleTop, lessThan(listBounds.center.dy));
    });

    testWidgets('adding a new user message does not auto-scroll the timeline',
        (tester) async {
      final scrollController = ScrollController();
      final container = ProviderContainer(
        overrides: [
          hasMoreMessagesProvider.overrideWith((ref) => false),
          scrollControllerProvider.overrideWith((ref) => scrollController),
          chatSendStateProvider.overrideWith(
            (ref) => ChatSendStateNotifier()
              ..update(
                phase: ChatSendPhase.idle,
                isGenerating: false,
              ),
          ),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        scrollController.dispose();
      });

      final baseTime = DateTime(2026, 5, 31, 12);
      container.read(messagesProvider.notifier).setMessages([
        for (var i = 0; i < 24; i++) ...[
          _buildMessage(
            id: i * 2 + 1,
            timestamp: baseTime.add(Duration(minutes: i * 2)),
            text: 'older user $i',
            role: MessageRole.user,
            contentType: MessageContentType.plainText,
          ),
          _buildMessage(
            id: i * 2 + 2,
            timestamp: baseTime.add(Duration(minutes: i * 2 + 1)),
            text: 'older assistant $i',
            role: MessageRole.assistant,
            contentType: MessageContentType.plainText,
          ),
        ],
      ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: ChatMessageList()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialOffset = scrollController.offset;
      scrollController.jumpTo(initialOffset + 180);
      await tester.pump();

      container.read(messagesProvider.notifier).addMessage(
            _buildMessage(
              text: 'new user turn',
              role: MessageRole.user,
              contentType: MessageContentType.plainText,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(scrollController.offset, closeTo(initialOffset + 180, 0.1));
    });

    testWidgets(
        'floating visibility turns on when the inline status anchor scrolls out of view',
        (tester) async {
      final scrollController = ScrollController();
      final container = ProviderContainer(
        overrides: [
          hasMoreMessagesProvider.overrideWith((ref) => false),
          scrollControllerProvider.overrideWith((ref) => scrollController),
          chatSendStateProvider.overrideWith(
            (ref) => ChatSendStateNotifier()
              ..update(
                phase: ChatSendPhase.preparing,
                isGenerating: false,
              ),
          ),
          activeTurnStatusPresentationProvider.overrideWith(
            (ref) => const ActiveTurnStatusPresentation(
              phase: ActiveTurnStatusPhase.planning,
              text: '正在规划下一步',
              turnId: 'turn-scroll',
              sourceMessageId: 48,
              sourceKind: ActiveTurnStatusSourceKind.toolEvent,
              allowFloating: true,
            ),
          ),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        scrollController.dispose();
      });

      final baseTime = DateTime(2026, 5, 31, 12);
      container.read(messagesProvider.notifier).setMessages([
        for (var i = 0; i < 24; i++) ...[
          _buildMessage(
            id: i * 2 + 1,
            timestamp: baseTime.add(Duration(minutes: i * 2)),
            text: 'older user $i',
            role: MessageRole.user,
            contentType: MessageContentType.plainText,
          ),
          _buildMessage(
            id: i * 2 + 2,
            timestamp: baseTime.add(Duration(minutes: i * 2 + 1)),
            text: 'older assistant $i',
            role: MessageRole.assistant,
            contentType: MessageContentType.plainText,
          ),
        ],
      ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: SizedBox(
                height: 420,
                child: ChatMessageList(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();
      await tester.pump();

      expect(
        container.read(activeTurnStatusFloatingVisibilityProvider),
        isFalse,
      );

      scrollController.jumpTo(scrollController.position.minScrollExtent);
      await tester.pump();
      await tester.pump();

      expect(
        container.read(activeTurnStatusFloatingVisibilityProvider),
        isTrue,
      );
    });

    testWidgets(
        'floating visibility turns off when the inline status anchor becomes visible again',
        (tester) async {
      final scrollController = ScrollController();
      final container = ProviderContainer(
        overrides: [
          hasMoreMessagesProvider.overrideWith((ref) => false),
          scrollControllerProvider.overrideWith((ref) => scrollController),
          chatSendStateProvider.overrideWith(
            (ref) => ChatSendStateNotifier()
              ..update(
                phase: ChatSendPhase.preparing,
                isGenerating: false,
              ),
          ),
          activeTurnStatusPresentationProvider.overrideWith(
            (ref) => const ActiveTurnStatusPresentation(
              phase: ActiveTurnStatusPhase.planning,
              text: '正在规划下一步',
              turnId: 'turn-scroll-back',
              sourceMessageId: 48,
              sourceKind: ActiveTurnStatusSourceKind.toolEvent,
              allowFloating: true,
            ),
          ),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        scrollController.dispose();
      });

      final baseTime = DateTime(2026, 5, 31, 12);
      container.read(messagesProvider.notifier).setMessages([
        for (var i = 0; i < 24; i++) ...[
          _buildMessage(
            id: i * 2 + 1,
            timestamp: baseTime.add(Duration(minutes: i * 2)),
            text: 'older user $i',
            role: MessageRole.user,
            contentType: MessageContentType.plainText,
          ),
          _buildMessage(
            id: i * 2 + 2,
            timestamp: baseTime.add(Duration(minutes: i * 2 + 1)),
            text: 'older assistant $i',
            role: MessageRole.assistant,
            contentType: MessageContentType.plainText,
          ),
        ],
      ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: SizedBox(
                height: 420,
                child: ChatMessageList(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();
      await tester.pump();
      expect(
        container.read(activeTurnStatusFloatingVisibilityProvider),
        isFalse,
      );

      scrollController.jumpTo(scrollController.position.minScrollExtent);
      await tester.pump();
      await tester.pump();
      expect(
        container.read(activeTurnStatusFloatingVisibilityProvider),
        isTrue,
      );

      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();
      await tester.pump();

      expect(
        container.read(activeTurnStatusFloatingVisibilityProvider),
        isFalse,
      );
    });

    testWidgets(
        'floating visibility updates when the active row grows after inline expansion',
        (tester) async {
      final scrollController = ScrollController();
      final container = ProviderContainer(
        overrides: [
          hasMoreMessagesProvider.overrideWith((ref) => false),
          scrollControllerProvider.overrideWith((ref) => scrollController),
          activeTurnStatusPresentationProvider.overrideWith(
            (ref) => const ActiveTurnStatusPresentation(
              phase: ActiveTurnStatusPhase.planning,
              text: '测试边界状态',
              turnId: 'turn-expand',
              sourceMessageId: 2,
              sourceKind: ActiveTurnStatusSourceKind.toolEvent,
              allowFloating: true,
            ),
          ),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        scrollController.dispose();
      });

      container.read(messagesProvider.notifier).setMessages([
        ChatMessage(
          id: 1,
          text: '问题',
          role: MessageRole.user,
          status: MessageStatus.completed,
          contentType: MessageContentType.plainText,
        ),
        ChatMessage(
          id: 2,
          text: '这是回答',
          role: MessageRole.assistant,
          status: MessageStatus.completed,
          contentType: MessageContentType.plainText,
          reasoningContent: List.filled(80, '这里是额外展开后的长分析内容，会把状态条顶到屏幕外').join('\n'),
        ),
      ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: SizedBox(
                height: 180,
                child: ChatMessageList(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();
      await tester.pump();

      expect(
        container.read(activeTurnStatusFloatingVisibilityProvider),
        isFalse,
      );

      await tester.ensureVisible(find.text('思考过程'));
      await tester.pump();
      await tester.tap(find.text('思考过程'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      final listRect = tester.getRect(find.byType(ChatMessageList));
      final statusRect =
          tester.getRect(find.byKey(const ValueKey('latest-message-running-tail')));
      expect(statusRect.bottom, greaterThan(listRect.bottom));

      expect(
        container.read(activeTurnStatusFloatingVisibilityProvider),
        isTrue,
      );
    });

    testWidgets('assistant text does not expose removed structured output action',
        (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'Assistant message',
            role: MessageRole.assistant,
            contentType: MessageContentType.plainText,
          ),
        ],
      );

      await tester.longPress(find.text('Assistant message').first);
      await tester.pumpAndSettle();

      expect(find.text('结构化整理（调试）'), findsNothing);
    });

    testWidgets('user anchor does not expose structured output action', (
      tester,
    ) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'User message',
            role: MessageRole.user,
            contentType: MessageContentType.plainText,
          ),
        ],
      );

      await tester.longPress(find.text('User message').first);
      await tester.pumpAndSettle();

      expect(find.text('结构化整理（调试）'), findsNothing);
    });
  });
}

Future<void> _pumpMessageList(
  WidgetTester tester, {
  required List<ChatMessage> messages,
  RuntimeStreamingPreviewState runtimePreviewState =
      const RuntimeStreamingPreviewState(),
  ActiveTurnStatusPresentation? activeTurnStatus,
  TextEditingController? textController,
  FocusNode? focusNode,
  ToolUiRendererRegistry? registry,
  ChatSendPhase sendPhase = ChatSendPhase.idle,
  String? sendStatusText,
}) async {
  final container = ProviderContainer(
    overrides: [
      hasMoreMessagesProvider.overrideWith((ref) => false),
      featuredDebugTestCasesProvider.overrideWith(
        (ref) => const [
          DebugTestCase(
            id: 'plain-answer',
            group: 'tool-call',
            title: '纯文本直答',
            summary: '验证无需工具时能直接结束回答。',
            prompt: '用一句话解释什么是 SQLite',
            tags: ['agent-loop'],
            featured: true,
            enabled: true,
            setup: _debugCaseEmptySetup,
            checkpoints: ['finalAnswer'],
            assertions: _debugCaseCompletedAssertions,
          ),
          DebugTestCase(
            id: 'memory-search',
            group: 'tool-call',
            title: '单工具自动执行',
            summary: '验证历史检索类工具执行后再收敛回答。',
            prompt: '我刚才提过数据库版本吗？',
            tags: ['agent-loop'],
            featured: true,
            enabled: true,
            setup: _debugCaseEmptySetup,
            checkpoints: ['tool:search_chat_history:success', 'finalAnswer'],
            assertions: _debugCaseCompletedAssertions,
          ),
          DebugTestCase(
            id: 'tool-chain',
            group: 'tool-call',
            title: '多工具串行执行',
            summary: '验证联网搜索和网页读取串行发生。',
            prompt: '先搜索 OpenAI 今天的最新消息，再读取你认为最相关的一篇网页，然后总结给我',
            tags: ['agent-loop'],
            featured: true,
            enabled: true,
            setup: _debugCaseEmptySetup,
            checkpoints: [
              'tool:web_search:success',
              'tool:fetch_webpage:success',
              'finalAnswer',
            ],
            assertions: _debugCaseCompletedAssertions,
          ),
        ],
      ),
      if (textController != null)
        textControllerProvider.overrideWith((ref) => textController),
      if (focusNode != null) focusNodeProvider.overrideWith((ref) => focusNode),
      chatSendStateProvider.overrideWith(
        (ref) => ChatSendStateNotifier()
          ..update(
            phase: sendPhase,
            isGenerating: sendPhase == ChatSendPhase.streamingResponse,
            statusText: sendStatusText,
          ),
      ),
      runtimeStreamingPreviewStateProvider.overrideWith(
        (ref) =>
            RuntimeStreamingPreviewController(ref)..state = runtimePreviewState,
      ),
      if (activeTurnStatus != null)
        activeTurnStatusPresentationProvider.overrideWith(
          (ref) => activeTurnStatus,
        ),
      if (registry != null)
        toolUiRendererRegistryProvider.overrideWith((ref) => registry),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  container.read(messagesProvider.notifier).setMessages(messages);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: ChatMessageList(),
        ),
      ),
    ),
  );
}

const _debugCaseEmptySetup = DebugTestCaseSetup(
  historyMessages: [],
  files: [],
  mutationsAfterCheckpoints: [],
);

const _debugCaseCompletedAssertions = DebugTestCaseAssertions(
  endStatus: ['completed'],
  mustContainEvents: [],
  mustNotContainEvents: [],
  mustContainErrorCodes: [],
  mustContainAnyErrorCodes: [],
  forbidErrorCodes: [],
  finalAnswerContainsAll: [],
  finalFileContains: [],
  finalFileUnchanged: [],
  mustNotFalseClaimWriteSuccess: false,
  mustNotFalseClaimReadSuccess: false,
  mustNotHang: true,
);

ChatMessage _buildMessage({
  required String text,
  required MessageRole role,
  required MessageContentType contentType,
  MessageStatus status = MessageStatus.completed,
  Map<String, dynamic>? payloadJson,
  String? reasoningContent,
  int? id,
  DateTime? timestamp,
}) {
  return ChatMessage(
    id: id,
    text: text,
    role: role,
    timestamp: timestamp,
    status: status,
    reasoningContent: reasoningContent,
    contentType: contentType,
    payloadJson: payloadJson,
  );
}

class _FakeWriteWorkflowRenderer extends ToolUiRenderer {
  const _FakeWriteWorkflowRenderer();

  @override
  Widget? buildResult(
    BuildContext context, {
    required ToolResult result,
    required ChatMessage? sourceMessage,
  }) {
    return null;
  }

  @override
  Widget? buildWorkflowStep(
    BuildContext context, {
    required List<ToolWorkflowStep> steps,
    required ChatMessage? sourceMessage,
    required bool isExpanded,
    required VoidCallback? onTap,
  }) {
    return const Text('custom workflow renderer');
  }

  @override
  bool supportsResult(String toolName) => false;

  @override
  bool supportsWorkflowStep(String toolName) => toolName == 'Write';
}

class _FakeHideProposedWorkflowRenderer extends ToolUiRenderer {
  const _FakeHideProposedWorkflowRenderer();

  @override
  Widget? buildResult(
    BuildContext context, {
    required ToolResult result,
    required ChatMessage? sourceMessage,
  }) {
    return null;
  }

  @override
  Widget? buildWorkflowStep(
    BuildContext context, {
    required List<ToolWorkflowStep> steps,
    required ChatMessage? sourceMessage,
    required bool isExpanded,
    required VoidCallback? onTap,
  }) {
    return const Text('custom workflow renderer');
  }

  @override
  bool supportsResult(String toolName) => false;

  @override
  bool supportsWorkflowStep(String toolName) => toolName == 'Write';

  @override
  ToolPhaseVisibility visibilityForPhase(
    String toolName,
    ToolPresentationEventPhase phase,
  ) {
    if (toolName == 'Write' && phase == ToolPresentationEventPhase.proposed) {
      return ToolPhaseVisibility.hidden;
    }
    return ToolPhaseVisibility.visible;
  }
}
