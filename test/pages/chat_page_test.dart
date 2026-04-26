import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/debug/debug_test_case.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/pages/chat_page.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/services/debug_test_case_loader.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_message_list.dart';
import 'package:ai_chat/widgets/interaction/ask_user_question_card.dart';
import 'package:ai_chat/widgets/tool_confirmation/tool_confirmation_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'chat page uses floating controls instead of a traditional AppBar', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        chatSessionCoordinatorProvider
            .overrideWith((ref) => _StubSessionCoordinator()),
        chatSendCoordinatorProvider
            .overrideWith((ref) => _StubSendCoordinator()),
        chatSummaryControllerProvider.overrideWith(
          (ref) => _StubSummaryController(),
        ),
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

    final headerSize =
        tester.getSize(find.byKey(const ValueKey('ghost-header')));
    expect(headerSize.height, lessThanOrEqualTo(56));
  });

  testWidgets('chat page more actions no longer exposes reasoning mode toggle',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        chatSessionCoordinatorProvider
            .overrideWith((ref) => _StubSessionCoordinator()),
        chatSendCoordinatorProvider
            .overrideWith((ref) => _StubSendCoordinator()),
        chatSummaryControllerProvider.overrideWith(
          (ref) => _StubSummaryController(),
        ),
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

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

    expect(find.text('设置系统提示词'), findsOneWidget);
    expect(find.text('开启深度模式'), findsNothing);
    expect(find.text('关闭深度模式'), findsNothing);
  });

  testWidgets('chat page anchors viewport near the latest turn end',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        chatSessionCoordinatorProvider
            .overrideWith((ref) => _StubSessionCoordinator()),
        chatSendCoordinatorProvider
            .overrideWith((ref) => _StubSendCoordinator()),
        chatSummaryControllerProvider.overrideWith(
          (ref) => _StubSummaryController(),
        ),
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
        chatSessionCoordinatorProvider
            .overrideWith((ref) => _StubSessionCoordinator()),
        chatSendCoordinatorProvider
            .overrideWith((ref) => _StubSendCoordinator()),
        chatSummaryControllerProvider.overrideWith(
          (ref) => _StubSummaryController(),
        ),
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

  testWidgets(
      'resolved ask-user-question prompt does not stay active in timeline',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        chatSessionCoordinatorProvider
            .overrideWith((ref) => _StubSessionCoordinator()),
        chatSendCoordinatorProvider
            .overrideWith((ref) => _StubSendCoordinator()),
        chatSummaryControllerProvider.overrideWith(
          (ref) => _StubSummaryController(),
        ),
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

  testWidgets(
      'chat page renders bottom confirmation bar for active tool confirmation',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        chatSessionCoordinatorProvider
            .overrideWith((ref) => _StubSessionCoordinator()),
        chatSendCoordinatorProvider
            .overrideWith((ref) => _StubSendCoordinator()),
        chatSummaryControllerProvider.overrideWith(
          (ref) => _StubSummaryController(),
        ),
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
        text: '准备写入文件',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
        contentType: MessageContentType.actionConfirmation,
        payloadJson: const ToolInvocation(
          toolName: 'Write',
          arguments: {'file_path': 'docs/plan.md'},
          status: ToolInvocationStatus.awaitingConfirmation,
          summary: '准备写入 docs/plan.md',
          requiresConfirmation: true,
        ).toJson(),
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

    expect(find.byType(ToolConfirmationBottomBar), findsOneWidget);
    expect(
        find.descendant(
          of: find.byType(ToolConfirmationBottomBar),
          matching: find.text('写入文件'),
        ),
        findsOneWidget);
    expect(
        find.descendant(
          of: find.byType(ToolConfirmationBottomBar),
          matching: find.text('准备写入 docs/plan.md'),
        ),
        findsOneWidget);
  });

  testWidgets('debug cases picker populates input', (tester) async {
    final container = ProviderContainer(
      overrides: [
        chatSessionCoordinatorProvider.overrideWith(
          (ref) => _StubSessionCoordinator(),
        ),
        chatSendCoordinatorProvider
            .overrideWith((ref) => _StubSendCoordinator()),
        chatSummaryControllerProvider.overrideWith(
          (ref) => _StubSummaryController(),
        ),
        chatPreferencesControllerProvider.overrideWith(
          (ref) => _StubPreferencesController(),
        ),
        hasMoreMessagesProvider.overrideWith((ref) => false),
        debugTestCaseLoaderProvider.overrideWith(
          (ref) => const _FakeDebugTestCaseLoader(
            DebugTestCaseLibrary(
              allCases: [
                DebugTestCase(
                  id: 'plain-answer',
                  group: 'tool-call',
                  title: '纯文本直答',
                  summary: '无需工具时直接回答。',
                  prompt: '用一句话解释什么是 SQLite',
                  tags: ['agent-loop'],
                  featured: true,
                  enabled: true,
                  setup: _debugCaseEmptySetup,
                  checkpoints: ['finalAnswer'],
                  assertions: _debugCaseCompletedAssertions,
                ),
                DebugTestCase(
                  id: 'single-follow-up',
                  group: 'ask-user-question',
                  title: '单题问答',
                  summary: '先追问一个关键澄清问题。',
                  prompt: '请先提一个关键澄清问题',
                  tags: ['clarification'],
                  featured: false,
                  enabled: true,
                  setup: _debugCaseEmptySetup,
                  checkpoints: ['askUser:prompted'],
                  assertions: _debugCaseAwaitingInteractionAssertions,
                ),
              ],
            ),
          ),
        ),
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
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('debug-test-cases-button')));
    await tester.pumpAndSettle();

    expect(find.text('纯文本直答'), findsWidgets);
    expect(find.text('无需工具时直接回答。'), findsOneWidget);
    expect(find.text('工具调用'), findsOneWidget);
    expect(find.text('澄清提问'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('debug-test-case-plain-answer')));
    await tester.pumpAndSettle();

    final input = tester.widget<TextField>(
      find.byKey(const ValueKey('chat-input-field')),
    );
    expect(input.controller?.text, '用一句话解释什么是 SQLite');
  });
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

const _debugCaseAwaitingInteractionAssertions = DebugTestCaseAssertions(
  endStatus: ['awaitingUserInteraction'],
  mustContainEvents: [],
  mustNotContainEvents: ['finalAnswer'],
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

class _StubPreferencesController implements ChatPreferencesController {
  @override
  Future<void> setSystemPrompt(String? prompt) async {}
}

class _FakeDebugTestCaseLoader implements DebugTestCaseLoader {
  final DebugTestCaseLibrary library;

  const _FakeDebugTestCaseLoader(this.library);

  @override
  Future<DebugTestCaseLibrary> load() async => library;
}
