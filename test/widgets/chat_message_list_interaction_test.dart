import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_message_list.dart';
import 'package:ai_chat/widgets/interaction/ask_user_question_card.dart';
import 'package:ai_chat/widgets/interaction/ask_user_question_timeline_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'active ask user question prompt renders full card in message list',
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
    expect(find.byType(AskUserQuestionTimelineCard), findsNothing);
    expect(find.text('Which storage layer should we use?'), findsOneWidget);
  });

  testWidgets('manual upward browse does not show a resume-to-bottom button',
      (tester) async {
    final scrollController = ScrollController();
    final container = ProviderContainer(
      overrides: [
        hasMoreMessagesProvider.overrideWith((ref) => false),
        scrollControllerProvider.overrideWith((ref) => scrollController),
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.streamingResponse,
              isGenerating: true,
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
      for (var i = 0; i < 30; i++) ...[
        ChatMessage(
          id: i * 2 + 1,
          text: 'User message $i',
          role: MessageRole.user,
          status: MessageStatus.completed,
          contentType: MessageContentType.plainText,
        ),
        ChatMessage(
          id: i * 2 + 2,
          text: 'Assistant message $i',
          role: MessageRole.assistant,
          status: MessageStatus.completed,
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
  });

  testWidgets(
      'small manual browse from latest anchor keeps scrolling fully manual',
      (tester) async {
    final scrollController = ScrollController();
    final container = ProviderContainer(
      overrides: [
        hasMoreMessagesProvider.overrideWith((ref) => false),
        scrollControllerProvider.overrideWith((ref) => scrollController),
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.streamingResponse,
              isGenerating: true,
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
      for (var i = 0; i < 30; i++) ...[
        ChatMessage(
          id: i * 2 + 1,
          text: 'User message $i',
          role: MessageRole.user,
          status: MessageStatus.completed,
          contentType: MessageContentType.plainText,
        ),
        ChatMessage(
          id: i * 2 + 2,
          text: 'Assistant message $i',
          role: MessageRole.assistant,
          status: MessageStatus.completed,
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
  });

  testWidgets(
      'scroll offset change away from latest anchor does not trigger forced re-follow',
      (tester) async {
    final scrollController = ScrollController();
    final container = ProviderContainer(
      overrides: [
        hasMoreMessagesProvider.overrideWith((ref) => false),
        scrollControllerProvider.overrideWith((ref) => scrollController),
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.streamingResponse,
              isGenerating: true,
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
      for (var i = 0; i < 30; i++) ...[
        ChatMessage(
          id: i * 2 + 1,
          text: 'User message $i',
          role: MessageRole.user,
          status: MessageStatus.completed,
          contentType: MessageContentType.plainText,
        ),
        ChatMessage(
          id: i * 2 + 2,
          text: 'Assistant message $i',
          role: MessageRole.assistant,
          status: MessageStatus.completed,
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

    final bottomOffset = scrollController.offset;
    scrollController.jumpTo(bottomOffset + 180);
    await tester.pump();

    final browsedOffset = scrollController.offset;
    expect(browsedOffset, greaterThan(bottomOffset));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(scrollController.offset, closeTo(browsedOffset, 0.1));
  });

  testWidgets(
      'idle timeline does not snap back to latest anchor after manual browse',
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
      for (var i = 0; i < 30; i++) ...[
        ChatMessage(
          id: i * 2 + 1,
          text: 'User message $i',
          role: MessageRole.user,
          status: MessageStatus.completed,
          contentType: MessageContentType.plainText,
        ),
        ChatMessage(
          id: i * 2 + 2,
          text: 'Assistant message $i',
          role: MessageRole.assistant,
          status: MessageStatus.completed,
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

    final bottomOffset = scrollController.offset;

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pump();

    final browsedOffset = scrollController.offset;
    expect(browsedOffset, greaterThan(bottomOffset));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(scrollController.offset, closeTo(browsedOffset, 0.1));
  });

  testWidgets('loading older history preserves viewport anchor',
      (tester) async {
    final scrollController = ScrollController();
    late _LoadMoreChatController loadMoreController;
    final container = ProviderContainer(
      overrides: [
        scrollControllerProvider.overrideWith((ref) => scrollController),
        hasMoreMessagesProvider.overrideWith((ref) => true),
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.idle,
              isGenerating: false,
            ),
        ),
        chatControllerProvider.overrideWith((ref) {
          loadMoreController = _LoadMoreChatController(ref);
          return loadMoreController;
        }),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      scrollController.dispose();
    });

    container.read(messagesProvider.notifier).setMessages([
      for (var i = 20; i < 40; i++) ...[
        ChatMessage(
          id: i * 2 + 1,
          text: 'User message $i',
          role: MessageRole.user,
          status: MessageStatus.completed,
          contentType: MessageContentType.plainText,
        ),
        ChatMessage(
          id: i * 2 + 2,
          text: 'Assistant message $i',
          role: MessageRole.assistant,
          status: MessageStatus.completed,
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
    container.read(chatControllerProvider);

    final olderEdgeOffset = scrollController.position.minScrollExtent + 10;
    scrollController.jumpTo(olderEdgeOffset);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 350));

    expect(loadMoreController.loadMoreCalls, 1);
    expect(scrollController.offset, greaterThan(olderEdgeOffset));
  });

  testWidgets(
      'active ask user question keeps timeline as a single scroll surface',
      (tester) async {
    final scrollController = ScrollController();
    final container = ProviderContainer(
      overrides: [
        hasMoreMessagesProvider.overrideWith((ref) => false),
        scrollControllerProvider.overrideWith((ref) => scrollController),
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.streamingResponse,
              isGenerating: true,
            ),
        ),
        chatInteractionCoordinatorProvider.overrideWithValue(
          _NoopChatInteractionCoordinator(),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      scrollController.dispose();
    });

    final options = List.generate(
      18,
      (index) => {
        'label': 'Option ${index + 1}',
        'description': 'Description ${index + 1}',
      },
    );

    container.read(messagesProvider.notifier).setMessages([
      ChatMessage(
        id: 1001,
        text: 'Long list question',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
        contentType: MessageContentType.askUserQuestionPrompt,
        payloadJson: {
          'type': 'prompt',
          'agentTurnId': 42,
          'status': 'awaitingResponse',
          'questions': [
            {
              'id': 'long_list',
              'header': 'Long List',
              'question': 'Choose one option',
              'multiSelect': false,
              'options': options,
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AskUserQuestionCard), findsOneWidget);
    expect(find.byType(AskUserQuestionTimelineCard), findsNothing);
    final outerOffsetBefore = scrollController.offset;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(scrollController.offset, greaterThanOrEqualTo(outerOffsetBefore));
  });

  testWidgets('dragging inside active ask user question moves the outer timeline',
      (tester) async {
    final scrollController = ScrollController();
    final container = ProviderContainer(
      overrides: [
        hasMoreMessagesProvider.overrideWith((ref) => false),
        scrollControllerProvider.overrideWith((ref) => scrollController),
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.streamingResponse,
              isGenerating: true,
            ),
        ),
        chatInteractionCoordinatorProvider.overrideWithValue(
          _NoopChatInteractionCoordinator(),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      scrollController.dispose();
    });

    final options = List.generate(
      18,
      (index) => {
        'label': 'Option ${index + 1}',
        'description': 'Description ${index + 1}',
      },
    );

    container.read(messagesProvider.notifier).setMessages([
      ChatMessage(
        id: 2001,
        text: 'Long list question',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
        contentType: MessageContentType.askUserQuestionPrompt,
        payloadJson: {
          'type': 'prompt',
          'agentTurnId': 42,
          'status': 'awaitingResponse',
          'questions': [
            {
              'id': 'long_list_drag',
              'header': 'Long List',
              'question': 'Choose one option',
              'multiSelect': false,
              'options': options,
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AskUserQuestionCard), findsOneWidget);
    final outerOffsetBefore = scrollController.offset;
    await tester.drag(find.text('Option 3'), const Offset(0, -400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(scrollController.offset, greaterThan(outerOffsetBefore));
  });
}

class _NoopChatInteractionCoordinator implements ChatInteractionCoordinator {
  @override
  Future<void> cancelQuestionPrompt(ChatMessage message) async {}

  @override
  Future<void> submitQuestionAnswers(ChatMessage message) async {}
}

class _LoadMoreChatController extends ChatController {
  final Ref _ref;
  int loadMoreCalls = 0;

  _LoadMoreChatController(this._ref)
      : super(
          _ref,
          sendCoordinator: _NoopChatSendCoordinator(),
          sessionCoordinator: _NoopChatSessionCoordinator(),
          summaryController: _NoopChatSummaryController(),
          preferencesController: _NoopChatPreferencesController(),
        );

  @override
  Future<void> loadMoreMessages() async {
    loadMoreCalls += 1;
    _ref.read(messagesProvider.notifier).insertMessages(0, [
      for (var i = 0; i < 10; i++) ...[
        ChatMessage(
          id: i * 2 + 1,
          text: 'Older user $i',
          role: MessageRole.user,
          status: MessageStatus.completed,
          contentType: MessageContentType.plainText,
        ),
        ChatMessage(
          id: i * 2 + 2,
          text: 'Older assistant $i',
          role: MessageRole.assistant,
          status: MessageStatus.completed,
          contentType: MessageContentType.plainText,
        ),
      ],
    ]);
    _ref.read(hasMoreMessagesProvider.notifier).state = false;
  }
}

class _NoopChatSendCoordinator implements ChatSendCoordinator {
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

class _NoopChatSessionCoordinator implements ChatSessionCoordinator {
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

class _NoopChatSummaryController implements ChatSummaryController {
  @override
  void cancelAutoSummaryTimer() {}

  @override
  void scheduleAutoSummary() {}

  @override
  Future<String?> summarizeAndUpdateTitle() async => null;
}

class _NoopChatPreferencesController implements ChatPreferencesController {
  @override
  Future<void> setSystemPrompt(String? prompt) async {}
}
