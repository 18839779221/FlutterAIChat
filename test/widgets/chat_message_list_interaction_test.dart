import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_message_list.dart';
import 'package:ai_chat/widgets/interaction/ask_user_question_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ask user question prompt renders interactive card in message list',
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
        chatInteractionCoordinatorProvider.overrideWithValue(
          _NoopChatInteractionCoordinator(),
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
        text: '需要更多信息',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
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
              'options': [
                {
                  'label': 'SQLite',
                  'description': 'Local relational store',
                },
              ],
            },
          ],
        },
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

    expect(find.byType(AskUserQuestionCard), findsOneWidget);
    expect(find.text('Which storage layer should we use?'), findsOneWidget);
  });
}

class _NoopChatInteractionCoordinator implements ChatInteractionCoordinator {
  @override
  Future<void> cancelQuestionPrompt(ChatMessage message) async {}

  @override
  Future<void> submitQuestionAnswers(ChatMessage message) async {}
}
