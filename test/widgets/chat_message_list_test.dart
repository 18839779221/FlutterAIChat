import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/widgets/chat_message_list.dart';
import 'package:ai_chat/widgets/markdown/flutter_markdown_impl.dart';
import 'package:ai_chat/widgets/structured_message/structured_summary_card_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatMessageList contentType rendering', () {
    testWidgets('plainText assistant messages still use markdown rendering', (
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

      expect(find.byType(FlutterMarkdownImpl), findsOneWidget);
      expect(find.text('assistant reply'), findsOneWidget);
    });

    testWidgets(
      'structuredCard assistant messages render the dedicated summary widget',
      (tester) async {
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

        expect(find.byType(FlutterMarkdownImpl), findsNothing);
        expect(find.byType(StructuredSummaryCardWidget), findsOneWidget);
        expect(find.text('Weekly Summary'), findsOneWidget);
      },
    );

    testWidgets(
      'toolResult assistant messages render the minimal execution status',
      (tester) async {
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
                payload: {
                  'matchCount': 2,
                },
              ).toJson(),
            ),
          ],
        );

        expect(find.byType(FlutterMarkdownImpl), findsNothing);
        expect(find.text('已执行：搜索历史记录'), findsOneWidget);
        expect(find.text('找到 2 条历史消息'), findsOneWidget);
      },
    );

    testWidgets(
      'toolResult assistant messages fall back to plain text when payload is invalid',
      (tester) async {
        await _pumpMessageList(
          tester,
          messages: [
            _buildMessage(
              text: 'Tool fallback text',
              role: MessageRole.assistant,
              contentType: MessageContentType.toolResult,
              payloadJson: {
                'unexpected': true,
              },
            ),
          ],
        );

        expect(find.byType(FlutterMarkdownImpl), findsNothing);
        expect(find.text('Tool fallback text'), findsOneWidget);
      },
    );

    testWidgets('user messages still render as plain text', (tester) async {
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

      expect(find.byType(FlutterMarkdownImpl), findsNothing);
      expect(find.text('User message'), findsOneWidget);
    });

    testWidgets(
        'debug mode exposes structured output action for completed assistant plain text messages',
        (
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

      await tester.longPress(find.text('Assistant message'));
      await tester.pumpAndSettle();

      expect(find.text('结构化整理（调试）'), findsOneWidget);
    });

    testWidgets('unsupported messages do not expose structured output action', (
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

      await tester.longPress(find.text('User message'));
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
      child: const MaterialApp(
        home: Scaffold(
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
