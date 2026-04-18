import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/pages/chat_page.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_message_list.dart';
import 'package:ai_chat/widgets/interaction/ask_user_question_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('chat page uses floating controls instead of a traditional AppBar', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        chatSessionCoordinatorProvider.overrideWith((ref) => _StubSessionCoordinator()),
        chatSendCoordinatorProvider.overrideWith((ref) => _StubSendCoordinator()),
        chatSummaryControllerProvider.overrideWith(
          (ref) => _StubSummaryController(),
        ),
        chatDebugControllerProvider.overrideWith((ref) => _StubDebugController()),
        chatPreferencesControllerProvider.overrideWith(
          (ref) => _StubPreferencesController(),
        ),
        hasMoreMessagesProvider.overrideWith((ref) => false),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ChatPage(title: 'AI Chat'),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AppBar), findsNothing);
    expect(find.byIcon(Icons.menu), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.text('AI Chat'), findsNothing);

    final headerSize = tester.getSize(find.byKey(const ValueKey('ghost-header')));
    expect(headerSize.height, lessThanOrEqualTo(56));
  });

  testWidgets('chat page anchors viewport near the latest turn end',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        chatSessionCoordinatorProvider.overrideWith((ref) => _StubSessionCoordinator()),
        chatSendCoordinatorProvider.overrideWith((ref) => _StubSendCoordinator()),
        chatSummaryControllerProvider.overrideWith(
          (ref) => _StubSummaryController(),
        ),
        chatDebugControllerProvider.overrideWith((ref) => _StubDebugController()),
        chatPreferencesControllerProvider.overrideWith(
          (ref) => _StubPreferencesController(),
        ),
        hasMoreMessagesProvider.overrideWith((ref) => false),
      ],
    );
    addTearDown(container.dispose);

    container.read(messagesProvider.notifier).setMessages([
      ChatMessage(
        id: 1,
        text: 'Earlier user message',
        role: MessageRole.user,
        status: MessageStatus.completed,
      ),
      ChatMessage(
        id: 2,
        text: 'Earlier assistant message',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
      ),
      ChatMessage(
        id: 3,
        text: 'Latest user message',
        role: MessageRole.user,
        status: MessageStatus.completed,
      ),
      ChatMessage(
        id: 4,
        text: 'Latest assistant message',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
      ),
    ]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ChatPage(title: 'AI Chat'),
        ),
      ),
    );
    await tester.pump();

    final listBounds = tester.getRect(find.byType(ChatMessageList));
    final latestAssistantBottom =
        tester.getBottomLeft(find.text('Latest assistant message')).dy;
    expect(latestAssistantBottom, lessThanOrEqualTo(listBounds.bottom));
  });

  testWidgets('chat page renders active ask-user-question in timeline',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        chatSessionCoordinatorProvider.overrideWith((ref) => _StubSessionCoordinator()),
        chatSendCoordinatorProvider.overrideWith((ref) => _StubSendCoordinator()),
        chatSummaryControllerProvider.overrideWith(
          (ref) => _StubSummaryController(),
        ),
        chatDebugControllerProvider.overrideWith((ref) => _StubDebugController()),
        chatPreferencesControllerProvider.overrideWith(
          (ref) => _StubPreferencesController(),
        ),
        hasMoreMessagesProvider.overrideWith((ref) => false),
      ],
    );
    addTearDown(container.dispose);

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
          home: const ChatPage(title: 'AI Chat'),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AskUserQuestionCard), findsOneWidget);
    expect(find.text('Which storage layer should we use?'), findsOneWidget);
  });

  testWidgets('resolved ask-user-question prompt does not stay active in timeline',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        chatSessionCoordinatorProvider.overrideWith((ref) => _StubSessionCoordinator()),
        chatSendCoordinatorProvider.overrideWith((ref) => _StubSendCoordinator()),
        chatSummaryControllerProvider.overrideWith(
          (ref) => _StubSummaryController(),
        ),
        chatDebugControllerProvider.overrideWith((ref) => _StubDebugController()),
        chatPreferencesControllerProvider.overrideWith(
          (ref) => _StubPreferencesController(),
        ),
        hasMoreMessagesProvider.overrideWith((ref) => false),
      ],
    );
    addTearDown(container.dispose);

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
              'options': [],
            },
          ],
        },
      ),
      ChatMessage(
        id: 2,
        text: '已提交答案',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
        contentType: MessageContentType.askUserQuestionResult,
        payloadJson: const {
          'type': 'result',
          'agentTurnId': 42,
          'status': 'submitted',
          'submittedAnswers': {
            'answersByQuestionId': {
              'storage_layer': 'SQLite',
            },
          },
        },
      ),
    ]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ChatPage(title: 'AI Chat'),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AskUserQuestionCard), findsNothing);
  });
}

class _StubSendCoordinator implements ChatSendCoordinator {
  @override
  Future<void> cancelToolInvocation(ChatMessage message) async {}

  @override
  Future<void> confirmToolInvocation(
    ChatMessage message, {
    bool trustTool = false,
  }) async {}

  @override
  Future<void> sendMessage(
    String text, {
    required void Function() scheduleAutoSummary,
    required void Function() cancelActiveStream,
  }) async {}

  @override
  Future<void> submitQuestionAnswers(
    ChatMessage message, {
    required AskUserQuestionResponse response,
  }) async {}
}

class _StubSessionCoordinator implements ChatSessionCoordinator {
  @override
  Future<void> createNewGroup() async {}

  @override
  Future<void> deleteGroup(int id) async {}

  @override
  Future<void> loadCurrentGroup() async {}

  @override
  Future<void> loadGroups() async {}

  @override
  Future<void> loadMessages() async {}

  @override
  Future<void> loadMoreMessages() async {}

  @override
  Future<void> selectGroup(ChatGroup group) async {}
}

class _StubSummaryController implements ChatSummaryController {
  @override
  void cancelAutoSummaryTimer() {}

  @override
  void scheduleAutoSummary() {}

  @override
  Future<String?> summarizeAndUpdateTitle() async => null;
}

class _StubDebugController implements ChatDebugController {
  @override
  Future<void> structureMessageForDebug(ChatMessage message) async {}
}

class _StubPreferencesController implements ChatPreferencesController {
  @override
  Future<void> setSystemPrompt(String? prompt) async {}

  @override
  void setUseConciseMode(bool value) {}

  @override
  void setUseReasoning(bool value) {}
}
