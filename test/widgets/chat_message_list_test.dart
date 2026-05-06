import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/chat/tool_phase_visibility.dart';
import 'package:ai_chat/models/chat/tool_presentation_event.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/debug/debug_test_case.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_blocks/final_response_block.dart';
import 'package:ai_chat/widgets/chat_blocks/streaming_response_block.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_inline_step_row.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_outcome_card.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_result_summary_row.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_workflow_card.dart';
import 'package:ai_chat/widgets/chat_blocks/user_anchor_bubble.dart';
import 'package:ai_chat/widgets/chat_message_list.dart';
import 'package:ai_chat/widgets/interaction/ask_user_question_result_card.dart';
import 'package:ai_chat/widgets/interaction/ask_user_question_timeline_card.dart';
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
              'submittedAnswers': {
                'answersByQuestionId': {
                  'storage_layer': 'SQLite',
                  'offline_mode': 'Yes',
                },
              },
            },
          ),
        ],
      );

      expect(find.byType(AskUserQuestionResultCard), findsOneWidget);
      expect(find.text('已补充本回合信息'), findsOneWidget);
      expect(find.text('SQLite'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
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

      container.read(messagesProvider.notifier).setMessages([
        for (var i = 0; i < 24; i++) ...[
          _buildMessage(
            text: 'older user $i',
            role: MessageRole.user,
            contentType: MessageContentType.plainText,
          ),
          _buildMessage(
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
}) {
  return ChatMessage(
    text: text,
    role: role,
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
