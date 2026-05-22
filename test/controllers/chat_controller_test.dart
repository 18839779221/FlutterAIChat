import 'dart:async';

import 'package:ai_chat/models/agent/chat_turn_step.dart';
import 'package:ai_chat/models/artifact/artifact_record.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/session/session_context_snapshot.dart';
import 'package:ai_chat/models/session/session_runtime_marker.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('controller initialization does not attach scroll listeners directly',
      () {
    final scrollController = _TrackingScrollController();
    final container = ProviderContainer(
      overrides: [
        scrollControllerProvider.overrideWith((ref) => scrollController),
        databaseProvider.overrideWithValue(_FakeChatStorage()),
        chatControllerProvider.overrideWith(
          (ref) => ChatController(
            ref,
            sendCoordinator: _NoopChatSendCoordinator(),
            sessionCoordinator: _NoopChatSessionCoordinator(),
            summaryController: _NoopChatSummaryController(),
            preferencesController: _NoopChatPreferencesController(),
          ),
        ),
      ],
    );
    addTearDown(() {
      scrollController.dispose();
      container.dispose();
    });

    container.read(chatControllerProvider);

    expect(scrollController.addListenerCalls, 0);
  });

  test(
      'cancelStreamSubscription resets send state and interrupts assistant message',
      () async {
    final subscription = _FakeStreamSubscription();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(_FakeChatStorage()),
        chatControllerProvider.overrideWith(
          (ref) => ChatController(
            ref,
            sendCoordinator: _NoopChatSendCoordinator(),
            sessionCoordinator: _NoopChatSessionCoordinator(),
            summaryController: _NoopChatSummaryController(),
            preferencesController: _NoopChatPreferencesController(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(chatSendStateProvider.notifier).update(
          phase: ChatSendPhase.streamingResponse,
          isGenerating: true,
        );
    container.read(streamSubscriptionProvider.notifier).state = subscription;
    container.read(messagesProvider.notifier).setMessages([
      ChatMessage(
        id: 1,
        text: 'partial answer',
        role: MessageRole.assistant,
        status: MessageStatus.generating,
      ),
    ]);

    container.read(chatControllerProvider).cancelStreamSubscription();

    expect(subscription.cancelled, isTrue);
    expect(container.read(streamSubscriptionProvider), isNull);
    expect(container.read(sendPhaseProvider), ChatSendPhase.idle);
    expect(container.read(isGeneratingProvider), isFalse);
    expect(container.read(messagesProvider).single.status,
        MessageStatus.interrupted);
  });

  group('group switches cancel auto-summary timer', () {
    Future<void> runCase(
      String description,
      Future<void> Function(ChatController controller) action,
    ) async {
      final summarySpy = _SpyChatSummaryController();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(_FakeChatStorage()),
          chatControllerProvider.overrideWith(
            (ref) => ChatController(
              ref,
              sendCoordinator: _NoopChatSendCoordinator(),
              sessionCoordinator: _NoopChatSessionCoordinator(),
              summaryController: summarySpy,
              preferencesController: _NoopChatPreferencesController(),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider);
      await action(controller);

      expect(
        summarySpy.cancelCalls,
        1,
        reason: '$description should cancel auto-summary timer exactly once',
      );
    }

    test('loadCurrentGroup cancels', () async {
      await runCase('loadCurrentGroup', (c) => c.loadCurrentGroup());
    });
    test('createNewGroup cancels', () async {
      await runCase('createNewGroup', (c) => c.createNewGroup());
    });
    test('deleteGroup cancels', () async {
      await runCase('deleteGroup', (c) => c.deleteGroup(1));
    });
    test('selectGroup cancels', () async {
      final group = ChatGroup(id: 1, title: '新对话 1', systemPrompt: '', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions);
      await runCase('selectGroup', (c) => c.selectGroup(group));
    });
  });
}

class _SpyChatSummaryController implements ChatSummaryController {
  int cancelCalls = 0;

  @override
  void cancelAutoSummaryTimer() {
    cancelCalls += 1;
  }

  @override
  void scheduleAutoSummary() {}

  @override
  Future<String?> summarizeAndUpdateTitle() async => null;
}

class _FakeStreamSubscription implements StreamSubscription<void> {
  bool cancelled = false;

  @override
  Future<void> cancel() async {
    cancelled = true;
  }

  @override
  void onData(void Function(void data)? handleData) {}

  @override
  void onDone(void Function()? handleDone) {}

  @override
  void onError(Function? handleError) {}

  @override
  void pause([Future<void>? resumeSignal]) {}

  @override
  void resume() {}

  @override
  bool get isPaused => false;

  @override
  Future<E> asFuture<E>([E? futureValue]) async => futureValue as E;
}

class _TrackingScrollController extends ScrollController {
  int addListenerCalls = 0;

  @override
  void addListener(VoidCallback listener) {
    addListenerCalls += 1;
    super.addListener(listener);
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

class _FakeChatStorage implements ChatStorage {
  @override
  Future<int> insertOrReplaceArtifactRecord(ArtifactRecord record) async => 1;

  @override
  Future<ArtifactRecord?> getArtifactRecord({
    required int groupId,
    required String artifactId,
  }) async =>
      null;

  @override
  Future<ArtifactRecord?> getArtifactRecordByPath({
    required int groupId,
    required String sourcePath,
  }) async =>
      null;

  @override
  Future<List<ArtifactRecord>> listArtifactRecordsForGroup(int groupId) async =>
      const [];

  @override
  Future<void> updateArtifactRecord(ArtifactRecord record) async {}

  @override
  Future<void> deleteGroup(int groupId) async {}

  @override
  Future<void> deleteGroupMessages(int groupId) async {}

  @override
  Future<void> deleteMessage(int id) async {}

  @override
  Future<List<ChatGroup>> getAllGroups() async => const [];

  @override
  Future<List<ChatEvent>> getEventsByGroup(int groupId) async => const [];

  @override
  Future<List<ChatEvent>> getEventsByTurn(int turnId) async => const [];

  @override
  Future<int> getNextEventSequence(int turnId) async => 1;

  @override
  Future<int> getGroupMessageCount(int groupId) async => 0;

  @override
  Future<ChatGroup?> getLatestGroup() async => null;

  @override
  Future<SessionContextSnapshot?> getLatestSessionContextSnapshotByGroup(
    int groupId,
  ) async =>
      null;

  @override
  Future<List<ChatMessage>> getMessagesByGroup(int groupId) async => const [];

  @override
  Future<List<ChatMessage>> getMessagesByGroupWithPagination({
    required int groupId,
    required int limit,
    required int offset,
  }) async =>
      const [];

  @override
  Future<ChatTurn?> getTurn(int id) async => null;

  @override
  Future<List<ChatTurn>> getTurnsByGroup(int groupId) async => const [];

  @override
  Future<ChatTurnStep?> getTurnStep(int id) async => null;

  @override
  Future<List<ChatTurnStep>> getTurnSteps(int turnId) async => const [];

  @override
  Future<int> insertEvent(ChatEvent event) async => 1;

  @override
  Future<int> insertGroup(ChatGroup group) async => 1;

  @override
  Future<int> insertMessage(ChatMessage message, int groupId) async => 1;

  @override
  Future<int> insertSessionContextSnapshot(
          SessionContextSnapshot snapshot) async =>
      1;

  @override
  Future<int> insertSessionRuntimeMarker(SessionRuntimeMarker marker) async =>
      1;

  @override
  Future<int> insertTurn(ChatTurn turn) async => 1;

  @override
  Future<int> insertTurnStep(ChatTurnStep step) async => 1;

  @override
  Future<bool> testDatabaseConnection() async => true;

  @override
  Future<SessionRuntimeMarker?> getLatestSessionRuntimeMarkerByGroup(
    int groupId,
  ) async =>
      null;

  @override
  Future<void> updateGroupLastMessageTime(int groupId) async {}

  @override
  Future<void> updateGroupSystemPrompt(
      int groupId, String? systemPrompt) async {}

  @override
  Future<void> updateGroupTitle(
    int groupId,
    String title, {
    bool isSummarized = true,
  }) async {}

  @override
  Future<void> updateMessage(int id, String newText) async {}

  @override
  Future<void> updateMessageReasoning(int id, String? reasoningContent) async {}

  @override
  Future<void> updateMessageStatus(int id, MessageStatus status) async {}

  @override
  Future<void> updateSessionContextSnapshot(
    SessionContextSnapshot snapshot,
  ) async {}

  @override
  Future<void> updateSessionRuntimeMarker(SessionRuntimeMarker marker) async {}

  @override
  Future<void> updateStructuredMessage(
    int id, {
    required String text,
    required MessageStatus status,
    required MessageContentType contentType,
    String? payloadJson,
  }) async {}

  @override
  Future<void> updateTurn(ChatTurn turn) async {}

  @override
  Future<void> updateTurnStep(ChatTurnStep step) async {}
}
