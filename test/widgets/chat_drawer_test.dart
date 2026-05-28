import 'package:ai_chat/constants/route_constant.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/pages/layout_debug_page.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/chat_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('chat drawer no longer uses a gradient hero header', (
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
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: ChatDrawer(),
          ),
        ),
      ),
    );

    final gradientContainers = find.byWidgetPredicate((widget) {
      if (widget is! Container) {
        return false;
      }
      final decoration = widget.decoration;
      return decoration is BoxDecoration && decoration.gradient != null;
    });

    expect(gradientContainers, findsNothing);
  });

  testWidgets('chat drawer shows each group locked provider label', (
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
      ],
    );
    container.read(groupsProvider.notifier).setGroups([
      ChatGroup(
        id: 1,
        title: 'Claude session',
        lockedProviderStyle: ChatTurnProviderStyle.anthropicMessages,
      ),
      ChatGroup(
        id: 2,
        title: 'GPT session',
        lockedProviderStyle: ChatTurnProviderStyle.openaiResponses,
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: ChatDrawer(),
          ),
        ),
      ),
    );

    expect(find.text('Claude'), findsOneWidget);
    expect(find.text('GPT'), findsOneWidget);
  });

  testWidgets('chat drawer opens layout debug page from debug entry', (
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
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          routes: {
            RouteConstant.layoutDebugPage: (context) => const LayoutDebugPage(),
          },
          home: const Scaffold(
            body: ChatDrawer(),
          ),
        ),
      ),
    );

    expect(find.text('调试界面'), findsOneWidget);

    await tester.tap(find.text('调试界面'));
    await tester.pumpAndSettle();

    expect(find.byType(LayoutDebugPage), findsOneWidget);
    expect(find.text('文档排版调试'), findsOneWidget);
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

class _StubPreferencesController implements ChatPreferencesController {
  @override
  Future<void> setSystemPrompt(String? prompt) async {}
}
