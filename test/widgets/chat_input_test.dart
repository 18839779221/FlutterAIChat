import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/models/session/context_window_segment.dart';
import 'package:ai_chat/models/session/context_window_snapshot.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('chat input shows compact reply tray when idle', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('chat-input-dock')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-input-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-input-bottom-bar')), findsOneWidget);
    expect(find.text('Balanced · 可追溯输出'), findsNothing);
    expect(find.text('深度'), findsNothing);
    expect(find.text('简洁'), findsNothing);
    expect(find.byKey(const ValueKey('chat-input-idle-note')), findsNothing);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

    final textField = tester
        .widget<TextField>(find.byKey(const ValueKey('chat-input-field')));
    expect(textField.minLines, 1);
    expect(textField.maxLines, 4);
  });

  testWidgets('chat input keeps second row reserved for context usage info', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        contextWindowSnapshotProvider.overrideWith(
          (ref) async => _contextSnapshot(0.54),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('chat-input-bottom-bar')), findsOneWidget);
    expect(find.text('54%'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('context-window-usage-indicator')),
      findsOneWidget,
    );
  });

  testWidgets('chat input does not show pending label while awaiting confirmation', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.awaitingConfirmation,
              isGenerating: false,
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
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(find.text('等待工具确认'), findsNothing);
  });

  testWidgets('chat input does not show planner hint while preparing', (tester) async {
    final container = ProviderContainer(
      overrides: [
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.preparing,
              isGenerating: false,
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
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(find.text('正在规划下一步'), findsNothing);
  });

  testWidgets('chat input shows stop icon and cancels while preparing', (
    tester,
  ) async {
    var cancelCount = 0;
    final container = ProviderContainer(
      overrides: [
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.preparing,
              isGenerating: false,
            ),
        ),
        chatControllerProvider.overrideWith(
          (ref) => _SpyChatController(ref, onCancel: () => cancelCount += 1),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.byType(FilledButton));
    expect(cancelCount, 1);
  });

  testWidgets('chat input does not show tool running helper text', (tester) async {
    final container = ProviderContainer(
      overrides: [
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.executingTool,
              isGenerating: false,
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
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(find.text('工具执行中'), findsNothing);
  });

  testWidgets('chat input shows stop icon and cancels while executing tool', (
    tester,
  ) async {
    var cancelCount = 0;
    final container = ProviderContainer(
      overrides: [
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.executingTool,
              isGenerating: false,
            ),
        ),
        chatControllerProvider.overrideWith(
          (ref) => _SpyChatController(ref, onCancel: () => cancelCount += 1),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.byType(FilledButton));
    expect(cancelCount, 1);
  });

  testWidgets('chat input shows stop icon instead of spinner while streaming', (
    tester,
  ) async {
    var cancelCount = 0;
    final container = ProviderContainer(
      overrides: [
        chatSendStateProvider.overrideWith(
          (ref) => ChatSendStateNotifier()
            ..update(
              phase: ChatSendPhase.streamingResponse,
              isGenerating: true,
            ),
        ),
        chatControllerProvider.overrideWith(
          (ref) => _SpyChatController(ref, onCancel: () => cancelCount += 1),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatInput()),
        ),
      ),
    );

    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.byType(FilledButton));
    expect(cancelCount, 1);
  });
}

class _SpyChatController extends ChatController {
  _SpyChatController(
    super.ref, {
    required this.onCancel,
  })
      : super(
          sendCoordinator: _NoopChatSendCoordinator(),
          sessionCoordinator: _NoopChatSessionCoordinator(),
          summaryController: _NoopChatSummaryController(),
          preferencesController: _NoopChatPreferencesController(),
        );

  final VoidCallback onCancel;

  @override
  void cancelStreamSubscription() {
    onCancel();
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

ContextWindowSnapshot _contextSnapshot(double ratio) {
  return ContextWindowSnapshot(
    modelName: 'GPT-5.4',
    maxContextTokens: 128000,
    usableInputBudget: 104000,
    compressionTriggerRatio: 0.8,
    totalEstimatedInputTokens: 70000,
    totalWindowUsageRatio: ratio,
    usableInputUsageRatio: 0.0,
    didCompactHistory: false,
    recentCompletedTurnCount: 0,
    segments: const <ContextWindowSegment>[],
  );
}
