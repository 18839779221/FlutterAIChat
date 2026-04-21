import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/debug/debug_test_case.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_blocks/final_response_block.dart';
import 'package:ai_chat/widgets/chat_blocks/streaming_response_block.dart';
import 'package:ai_chat/widgets/chat_blocks/structured_output_block.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_exception_card.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_inline_step_row.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_outcome_card.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_result_summary_row.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_workflow_card.dart';
import 'package:ai_chat/widgets/chat_blocks/user_anchor_bubble.dart';
import 'package:ai_chat/widgets/chat_message_list.dart';
import 'package:ai_chat/widgets/interaction/ask_user_question_result_card.dart';
import 'package:ai_chat/widgets/interaction/ask_user_question_timeline_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatMessageList block rendering', () {
    testWidgets('empty conversations show a designed start state', (tester) async {
      await _pumpMessageList(tester, messages: const []);

      expect(find.text('开始一段新的对话'), findsOneWidget);
      expect(find.text('从一个问题开始，或让助手帮你推进下一步。'), findsOneWidget);
      expect(find.text('纯文本直答'), findsOneWidget);
      expect(find.text('单工具自动执行'), findsOneWidget);
    });

    testWidgets('empty state suggestion fills the composer without auto sending',
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

    testWidgets('structured assistant content renders as structured output block', (
      tester,
    ) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'Structured fallback text',
            role: MessageRole.assistant,
            contentType: MessageContentType.structuredCard,
            payloadJson: {
              'title': 'Weekly Summary',
              'summary': 'A short summary',
              'keyPoints': ['Point A'],
              'actionItems': ['Action B'],
              'risks': ['Risk C'],
            },
          ),
        ],
      );

      expect(find.byType(StructuredOutputBlock), findsOneWidget);
      expect(find.text('Weekly Summary'), findsOneWidget);
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
              displayText: '已执行：搜索历史记录',
              payload: {'matchCount': 2},
            ).toJson(),
          ),
        ],
      );

      expect(find.byType(ToolInlineStepRow), findsOneWidget);
      expect(find.text('已执行：搜索历史记录'), findsOneWidget);
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
              displayText: '已发起提醒创建：设计评审',
              payload: {
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
              displayText: '联网搜索失败',
              payload: {
                'query': 'latest openai',
                'reason': 'missing_api_key',
              },
              errorMessage: 'missing_api_key',
            ).toJson(),
          ),
        ],
      );

      expect(find.byType(ToolExceptionCard), findsOneWidget);
      expect(find.text('联网搜索失败'), findsOneWidget);
    });

    testWidgets('tool invocation renders as workflow card', (tester) async {
      await _pumpMessageList(
        tester,
        messages: [
          _buildMessage(
            text: 'Invocation fallback text',
            role: MessageRole.assistant,
            contentType: MessageContentType.toolInvocation,
            payloadJson: const ToolInvocation(
              toolName: 'fetch_webpage',
              arguments: {'url': 'https://example.com'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：读取网页',
              requiresConfirmation: false,
            ).toJson(),
          ),
        ],
      );

      expect(find.byType(ToolWorkflowCard), findsOneWidget);
      expect(find.text('正在执行工具：读取网页'), findsWidgets);
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

    testWidgets('action confirmation renders workflow card with action buttons', (
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
      expect(find.text('继续，以后不再确认'), findsOneWidget);
    });

    testWidgets(
        'action confirmation keeps rendering workflow actions from execution policy payload',
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
      expect(find.text('继续，以后不再确认'), findsOneWidget);
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

    testWidgets('multi-turn conversations keep the latest turn anchor near the top',
      (
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

    testWidgets('short conversations stay in the upper half instead of docking to the bottom',
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

    testWidgets('adding a new user message reanchors the newest turn near the top',
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
          autoScrollToBottomProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });

      container.read(messagesProvider.notifier).setMessages([
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

      container.read(messagesProvider.notifier).addMessage(
            _buildMessage(
              text: 'new user turn',
              role: MessageRole.user,
              contentType: MessageContentType.plainText,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final listBounds = tester.getRect(find.byType(ChatMessageList));
      final latestTurnTop = tester.getTopLeft(find.text('new user turn')).dy;
      expect(latestTurnTop, lessThan(listBounds.center.dy));
    });

    testWidgets('debug mode still exposes structured output action for assistant text', (
      tester,
    ) async {
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

      expect(find.text('结构化整理（调试）'), findsOneWidget);
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
            prompt:
                '先搜索 OpenAI 今天的最新消息，再读取你认为最相关的一篇网页，然后总结给我',
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
      if (focusNode != null)
        focusNodeProvider.overrideWith((ref) => focusNode),
      chatSendStateProvider.overrideWith(
        (ref) => ChatSendStateNotifier()
          ..update(
            phase: ChatSendPhase.idle,
            isGenerating: false,
          ),
      ),
      autoScrollToBottomProvider.overrideWith((ref) => true),
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
}) {
  return ChatMessage(
    text: text,
    role: role,
    status: status,
    contentType: contentType,
    payloadJson: payloadJson,
  );
}
