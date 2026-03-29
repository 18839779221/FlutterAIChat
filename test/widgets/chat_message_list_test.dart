import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_blocks/structured_output_block.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_result_summary_row.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_workflow_card.dart';
import 'package:ai_chat/widgets/chat_blocks/user_anchor_bubble.dart';
import 'package:ai_chat/widgets/chat_message_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatMessageList block rendering', () {
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

      expect(find.byType(ToolResultSummaryRow), findsOneWidget);
      expect(find.text('已执行：搜索历史记录'), findsOneWidget);
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
}) async {
  final container = ProviderContainer(
    overrides: [
      hasMoreMessagesProvider.overrideWith((ref) => false),
      isGeneratingProvider.overrideWith((ref) => false),
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

ChatMessage _buildMessage({
  required String text,
  required MessageRole role,
  required MessageContentType contentType,
  Map<String, dynamic>? payloadJson,
}) {
  return ChatMessage(
    text: text,
    role: role,
    status: MessageStatus.completed,
    contentType: contentType,
    payloadJson: payloadJson,
  );
}
