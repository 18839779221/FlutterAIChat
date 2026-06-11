import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/chat/active_turn_status_presentation.dart';
import 'package:ai_chat/models/chat/send_message_request.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/debug/debug_test_case.dart';
import 'package:ai_chat/models/debug/streaming_trace_snapshot.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/pages/chat_page.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/providers/streaming_trace_providers.dart';
import 'package:ai_chat/services/debug_test_case_loader.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
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
    expect(
      find.byKey(const ValueKey('header-menu-button-shell')),
      findsOneWidget,
    );

    final menuShell = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('header-menu-button-shell')),
    );
    final menuDecoration = menuShell.decoration as BoxDecoration;
    final menuGradient = menuDecoration.gradient as LinearGradient?;

    expect(menuGradient, isNotNull);
    expect(menuGradient!.colors, hasLength(3));
    expect(
      (menuGradient.colors.last.a * 255.0).round(),
      lessThan(255),
    );

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

  testWidgets('chat page shows current workspace badge', (tester) async {
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
    container.read(currentGroupProvider.notifier).state = ChatGroup(
      id: 1,
      title: 'Workspace chat',
      workspaceId: 'ws_20260602_a3k9qx',
      lockedProviderStyle: ChatTurnProviderStyle.openaiResponses,
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

    expect(find.text('Workspace ws_20260602_a3k9qx'), findsOneWidget);
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

  testWidgets('chat page overlays input on top of the message list viewport',
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

    final listBounds = tester.getRect(find.byType(ChatMessageList));
    final inputBounds =
        tester.getRect(find.byKey(const ValueKey('chat-input-dock')));
    expect(inputBounds.top, lessThan(listBounds.bottom));
  });

  testWidgets('chat page uses a solid theme background instead of a gradient',
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

    final backgroundBox = tester.widget<DecoratedBox>(
      find.byType(DecoratedBox).first,
    );
    final decoration = backgroundBox.decoration as BoxDecoration;
    final colors = Theme.of(
      tester.element(find.byType(ChatPage)),
    ).extension<AppThemeSpec>()!;

    expect(decoration.gradient, isNull);
    expect(decoration.color, equals(colors.chatBackground));
  });

  testWidgets(
      'chat page keeps a stable bottom-safe inset beneath the overlay composer',
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
        text: 'Latest user message',
        role: MessageRole.user,
        status: MessageStatus.completed,
      ),
      ChatMessage(
        id: 2,
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
    await tester.pump();

    final spacing = Theme.of(
      tester.element(find.byType(ChatPage)),
    ).extension<AppSpacing>()!;
    final overlayHeight = container.read(chatBottomOverlayHeightProvider);
    final sliverPadding =
        tester.widget<SliverPadding>(find.byType(SliverPadding));
    final padding = sliverPadding.padding as EdgeInsets;

    expect(overlayHeight, greaterThan(0));
    expect(
      padding.bottom,
      greaterThan(spacing.xl),
    );
    expect(
      padding.bottom,
      greaterThanOrEqualTo(overlayHeight + spacing.lg),
    );
  });

  testWidgets(
      'chat page lets the message list viewport extend beneath the bottom overlay band',
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
    await tester.pump();

    final pageBounds = tester.getRect(find.byType(ChatPage));
    final listBounds = tester.getRect(find.byType(ChatMessageList));
    final overlayHeight = container.read(chatBottomOverlayHeightProvider);

    expect(overlayHeight, greaterThan(0));
    expect(
      listBounds.bottom,
      closeTo(pageBounds.bottom, 0.01),
    );
  });

  testWidgets(
      'chat page shows a scroll-to-bottom button above the composer when not at the latest message',
      (tester) async {
    final scrollController = ScrollController();
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
        scrollControllerProvider.overrideWith((ref) => scrollController),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      scrollController.dispose();
    });

    final baseTime = DateTime(2026, 6, 1, 12);
    container.read(messagesProvider.notifier).setMessages([
      for (var i = 0; i < 24; i++) ...[
        ChatMessage(
          id: i * 2 + 1,
          text: 'older user $i',
          role: MessageRole.user,
          status: MessageStatus.completed,
          timestamp: baseTime.add(Duration(minutes: i * 2)),
        ),
        ChatMessage(
          id: i * 2 + 2,
          text: 'older assistant $i',
          role: MessageRole.assistant,
          status: MessageStatus.completed,
          timestamp: baseTime.add(Duration(minutes: i * 2 + 1)),
        ),
      ],
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
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('scroll-to-bottom-button')),
      findsNothing,
    );

    scrollController.jumpTo(scrollController.position.minScrollExtent);
    await tester.pump();
    await tester.pump();

    final buttonFinder = find.byKey(const ValueKey('scroll-to-bottom-button'));
    expect(buttonFinder, findsOneWidget);

    final buttonBounds = tester.getRect(buttonFinder);
    final inputBounds =
        tester.getRect(find.byKey(const ValueKey('chat-input-dock')));
    expect(buttonBounds.right, lessThanOrEqualTo(inputBounds.right + 1));
    expect(buttonBounds.bottom, lessThanOrEqualTo(inputBounds.top + 16));
    expect(buttonBounds.bottom, greaterThan(inputBounds.top - 56));

    await tester.tap(buttonFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(
      scrollController.offset,
      greaterThanOrEqualTo(scrollController.position.maxScrollExtent - 60),
    );
    expect(buttonFinder, findsNothing);
  });

  testWidgets(
      'floating status and scroll-to-bottom button share one row above composer',
      (tester) async {
    final buttonOnlyContainer = _createChatPageTestContainer(
      showScrollToBottomButton: null,
    );
    addTearDown(() {
      buttonOnlyContainer.dispose();
    });
    _seedShortChatHistory(buttonOnlyContainer);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: buttonOnlyContainer,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ChatPage(title: 'AI Chat'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    buttonOnlyContainer
        .read(scrollToBottomButtonVisibleProvider.notifier)
        .state = true;
    await tester.pump();

    final buttonOnlyInputTop =
        tester.getRect(find.byKey(const ValueKey('chat-input-dock'))).top;

    await tester.pumpWidget(const SizedBox.shrink());

    final combinedContainer = _createChatPageTestContainer(
      activeStatus: const ActiveTurnStatusPresentation(
        phase: ActiveTurnStatusPhase.planning,
        text: '正在规划下一步',
        turnId: 'turn-floating-combined',
        sourceKind: ActiveTurnStatusSourceKind.toolEvent,
        allowFloating: true,
      ),
      showFloatingStatus: true,
      showScrollToBottomButton: null,
    );
    addTearDown(() {
      combinedContainer.dispose();
    });
    _seedShortChatHistory(combinedContainer);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: combinedContainer,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ChatPage(title: 'AI Chat'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    combinedContainer.read(scrollToBottomButtonVisibleProvider.notifier).state =
        true;
    await tester.pump();

    final statusRect = tester.getRect(
      find.byKey(const ValueKey('floating-turn-status-bar')),
    );
    final buttonRect = tester.getRect(
      find.byKey(const ValueKey('scroll-to-bottom-button')),
    );
    final combinedInputTop =
        tester.getRect(find.byKey(const ValueKey('chat-input-dock'))).top;

    expect(statusRect.center.dy, closeTo(buttonRect.center.dy, 8));
    expect(combinedInputTop, closeTo(buttonOnlyInputTop, 8));
  });

  testWidgets('chat page renders a semi-transparent bottom overlay veil',
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

    final veil = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('chat-bottom-overlay-veil')),
    );
    final decoration = veil.decoration as BoxDecoration;
    final gradient = decoration.gradient as LinearGradient?;
    final veilBounds = tester.getRect(
      find.byKey(const ValueKey('chat-bottom-overlay-veil')),
    );
    final dockBounds = tester.getRect(
      find.byKey(const ValueKey('chat-input-dock')),
    );

    expect(gradient, isNotNull);
    expect((gradient!.colors.first.a * 255.0).round(), equals(0));
    expect(
      (gradient.colors[2].a * 100).round(),
      equals(50),
    );
    expect(
      (gradient.colors.last.a * 255.0).round(),
      equals((0.5 * 255.0).round()),
    );
    expect(
      dockBounds.top - veilBounds.top,
      greaterThan(32),
    );
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

  testWidgets('debug cases panel can inject a stable idle status copy',
      (tester) async {
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
            DebugTestCaseLibrary(allCases: []),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(messagesProvider.notifier).setMessages([
      ChatMessage(
        id: 1,
        text: '测试状态浮层',
        role: MessageRole.user,
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
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('debug-test-cases-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('debug-idle-status-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('测试边界状态'), findsOneWidget);
  });

  testWidgets('debug turn inspector opens from header', (tester) async {
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

    expect(find.byKey(const ValueKey('debug-turn-inspector-button')),
        findsOneWidget);
  });

  testWidgets(
      'long pressing debug header button shows streaming timeline overlay and tapping outside dismisses it',
      (tester) async {
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
      ],
    );
    addTearDown(container.dispose);

    container.read(streamingTraceRecorderProvider.notifier).recordStage(
          traceId: 'trace_1',
          turnId: 'turn_1',
          stage: StreamingTraceStage.finalTakeover,
          timestamp: DateTime(2026, 5, 31, 12, 0, 0),
        );
    container.read(streamingTraceRecorderProvider.notifier).markCompleted(
          traceId: 'trace_1',
          takeoverAt: DateTime(2026, 5, 31, 12, 0, 0, 0, 50),
        );

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

    final debugButton =
        find.byKey(const ValueKey('debug-turn-inspector-button'));
    expect(debugButton, findsOneWidget);

    await tester.longPress(debugButton);
    await tester.pumpAndSettle();
    expect(find.text('Streaming Timeline'), findsOneWidget);

    await tester.tapAt(const Offset(16, 220));
    await tester.pumpAndSettle();
    expect(find.text('Streaming Timeline'), findsNothing);
  });

  testWidgets(
      'chat page shows floating status above composer when anchor is not visible',
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
        activeTurnStatusPresentationProvider.overrideWith(
          (ref) => const ActiveTurnStatusPresentation(
            phase: ActiveTurnStatusPhase.planning,
            text: '正在规划下一步',
            turnId: 'turn-floating',
            sourceKind: ActiveTurnStatusSourceKind.toolEvent,
            allowFloating: true,
          ),
        ),
        activeTurnStatusFloatingVisibilityProvider.overrideWith(
          (ref) => true,
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
    await tester.pump();

    expect(
        find.byKey(const ValueKey('floating-turn-status-bar')), findsOneWidget);
    expect(find.text('正在规划下一步'), findsOneWidget);
    final floatingRect = tester.getRect(
      find.byKey(const ValueKey('floating-turn-status-bar')),
    );
    expect(floatingRect.width, lessThan(360));
  });

  testWidgets('chat page hides floating status when inline anchor is visible',
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
        activeTurnStatusPresentationProvider.overrideWith(
          (ref) => const ActiveTurnStatusPresentation(
            phase: ActiveTurnStatusPhase.planning,
            text: '正在规划下一步',
            turnId: 'turn-inline',
            sourceKind: ActiveTurnStatusSourceKind.toolEvent,
            allowFloating: true,
          ),
        ),
        activeTurnStatusFloatingVisibilityProvider.overrideWith(
          (ref) => false,
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
    await tester.pump();

    expect(
        find.byKey(const ValueKey('floating-turn-status-bar')), findsNothing);
  });

  testWidgets(
      'chat page omits floating status when no active turn status exists',
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

    expect(
        find.byKey(const ValueKey('floating-turn-status-bar')), findsNothing);
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

ProviderContainer _createChatPageTestContainer({
  ScrollController? scrollController,
  ActiveTurnStatusPresentation? activeStatus,
  bool showFloatingStatus = false,
  bool? showScrollToBottomButton,
}) {
  return ProviderContainer(
    overrides: [
      chatSessionCoordinatorProvider
          .overrideWith((ref) => _StubSessionCoordinator()),
      chatSendCoordinatorProvider.overrideWith((ref) => _StubSendCoordinator()),
      chatSummaryControllerProvider.overrideWith(
        (ref) => _StubSummaryController(),
      ),
      chatPreferencesControllerProvider.overrideWith(
        (ref) => _StubPreferencesController(),
      ),
      hasMoreMessagesProvider.overrideWith((ref) => false),
      if (scrollController != null)
        scrollControllerProvider.overrideWith((ref) => scrollController),
      if (activeStatus != null)
        activeTurnStatusPresentationProvider.overrideWith(
          (ref) => activeStatus,
        ),
      if (activeStatus != null)
        activeTurnStatusFloatingVisibilityProvider.overrideWith(
          (ref) => showFloatingStatus,
        ),
      if (showScrollToBottomButton != null)
        scrollToBottomButtonVisibleProvider.overrideWith(
          (ref) => showScrollToBottomButton,
        ),
    ],
  );
}

void _seedShortChatHistory(ProviderContainer container) {
  final baseTime = DateTime(2026, 6, 1, 12);
  container.read(messagesProvider.notifier).setMessages([
    ChatMessage(
      id: 1,
      text: 'hello',
      role: MessageRole.user,
      status: MessageStatus.completed,
      timestamp: baseTime,
    ),
    ChatMessage(
      id: 2,
      text: 'hi',
      role: MessageRole.assistant,
      status: MessageStatus.completed,
      timestamp: baseTime.add(const Duration(minutes: 1)),
    ),
  ]);
}

class _StubSendCoordinator implements ChatSendCoordinator {
  @override
  Future<void> sendMessageRequest(
    SendMessageRequest request, {
    required void Function() scheduleAutoSummary,
    required void Function() cancelActiveStream,
  }) async {}

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

  @override
  Future<void> updateCurrentGroupWorkspace(String? workspaceId) async {}

  @override
  Future<void> syncDraftGroupProviderStyle() async {}
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
