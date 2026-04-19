import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
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
        chatSessionCoordinatorProvider.overrideWith((ref) => _StubSessionCoordinator()),
        chatSendCoordinatorProvider.overrideWith((ref) => _StubSendCoordinator()),
        chatSummaryControllerProvider.overrideWith(
          (ref) => _StubSummaryController(),
        ),
        chatDebugControllerProvider.overrideWith((ref) => _StubDebugController()),
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
  void setUseReasoning(bool value) {}
}
