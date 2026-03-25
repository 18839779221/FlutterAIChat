import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/widgets/chat_message_list.dart';
import 'package:ai_chat/widgets/markdown/flutter_markdown_impl.dart';
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
      'structuredCard assistant messages fall back to plain text without a dedicated renderer',
      (tester) async {
        await _pumpMessageList(
          tester,
          messages: [
            _buildMessage(
              text: 'Structured fallback text',
              role: MessageRole.assistant,
              contentType: MessageContentType.structuredCard,
            ),
          ],
        );

        expect(find.byType(FlutterMarkdownImpl), findsNothing);
        expect(find.text('Structured fallback text'), findsOneWidget);
      },
    );

    testWidgets(
      'toolResult assistant messages fall back to plain text without a dedicated renderer',
      (tester) async {
        await _pumpMessageList(
          tester,
          messages: [
            _buildMessage(
              text: 'Tool fallback text',
              role: MessageRole.assistant,
              contentType: MessageContentType.toolResult,
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
}) {
  return ChatMessage(
    text: text,
    role: role,
    status: MessageStatus.completed,
    contentType: contentType,
  );
}
