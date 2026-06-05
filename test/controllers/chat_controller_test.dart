import 'dart:async';

import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/agent/chat_turn_step.dart';
import 'package:ai_chat/models/artifact/artifact_record.dart';
import 'package:ai_chat/models/chat/chat_attachment.dart';
import 'package:ai_chat/models/chat/send_message_request.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/context/planner_context_carrier.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/session/session_context_snapshot.dart';
import 'package:ai_chat/models/session/session_runtime_marker.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/session_context_projector.dart';
import 'package:ai_chat/services/session_context_service.dart';
import 'package:ai_chat/services/session_summary_service.dart';
import 'package:ai_chat/services/session_token_budget_service.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:ai_chat/repositories/session_context_snapshot_repository.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

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
      final group = ChatGroup(
          id: 1,
          title: '新对话 1',
          systemPrompt: '',
          lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions);
      await runCase('selectGroup', (c) => c.selectGroup(group));
    });
  });

  test('createNewGroup locks provider style from current settings', () async {
    SharedPreferences.setMockInitialValues({});
    final settingsRepository = AppSettingsRepository(
      await SharedPreferences.getInstance(),
      localDefaultsLoader: () async => const LlmLocalDefaults(
        defaultProviderId: 'claude',
        defaultModelId: 'claude-sonnet',
        providers: [
          LlmProviderConfig(
            id: 'claude',
            name: 'Claude',
            apiKey: 'test-key',
            baseUrl: 'https://example.com/v1/messages',
            models: [
              LlmProviderModel(id: 'claude-sonnet', name: 'Claude Sonnet'),
            ],
          ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(settingsRepository),
        databaseProvider.overrideWithValue(_FakeChatStorage()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(chatSessionCoordinatorProvider).createNewGroup();

    expect(
      container.read(currentGroupProvider)?.lockedProviderStyle,
      ChatTurnProviderStyle.anthropicMessages,
    );
  });

  test(
      'createNewGroup falls back to chat completions when settings are unavailable',
      () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(
          AppSettingsRepository(
            await SharedPreferences.getInstance(),
            localDefaultsLoader: () async => null,
          ),
        ),
        databaseProvider.overrideWithValue(_FakeChatStorage()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(chatSessionCoordinatorProvider).createNewGroup();

    expect(
      container.read(currentGroupProvider)?.lockedProviderStyle,
      ChatTurnProviderStyle.openaiChatCompletions,
    );
  });

  test('loadMoreMessages prepends older page and clears exhausted pagination',
      () async {
    final storage = _FakeChatStorage(
      groupMessageCount: 3,
      paginatedMessages: [
        ChatMessage(
          id: 1,
          text: 'Older message',
          role: MessageRole.user,
          status: MessageStatus.completed,
          timestamp: DateTime(2026, 1, 1, 10),
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    container.read(currentGroupProvider.notifier).state = ChatGroup(
      id: 7,
      title: 'group',
      lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions,
    );
    container.read(hasMoreMessagesProvider.notifier).state = true;
    container.read(messagesProvider.notifier).setMessages([
      ChatMessage(
        id: 2,
        text: 'Newer message 1',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
        timestamp: DateTime(2026, 1, 1, 11),
      ),
      ChatMessage(
        id: 3,
        text: 'Newer message 2',
        role: MessageRole.user,
        status: MessageStatus.completed,
        timestamp: DateTime(2026, 1, 1, 12),
      ),
    ]);

    await container.read(chatSessionCoordinatorProvider).loadMoreMessages();

    expect(
      container.read(messagesProvider).map((message) => message.text).toList(),
      ['Older message', 'Newer message 1', 'Newer message 2'],
    );
    expect(container.read(hasMoreMessagesProvider), isFalse);
  });

  test('selectGroup clears stale messages before loading the next group',
      () async {
    final storage = _FakeChatStorage(
      messagesByGroup: {
        2: [
          ChatMessage(
            id: 2,
            text: 'Next group message',
            role: MessageRole.user,
            status: MessageStatus.completed,
            timestamp: DateTime(2026, 1, 1, 11),
          ),
        ],
      },
      groupMessageCount: 1,
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    container.read(messagesProvider.notifier).setMessages([
      ChatMessage(
        id: 1,
        text: 'Previous group message',
        role: MessageRole.user,
        status: MessageStatus.completed,
        timestamp: DateTime(2026, 1, 1, 10),
      ),
    ]);
    final selectFuture = container
        .read(chatSessionCoordinatorProvider)
        .selectGroup(
          ChatGroup(
            id: 2,
            title: 'Next group',
            lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions,
          ),
        );

    expect(container.read(messagesProvider), isEmpty);

    await selectFuture;
    expect(
      container.read(messagesProvider).map((message) => message.text).toList(),
      ['Next group message'],
    );
  });

  test('database stores and loads message attachments', () async {
    final databaseHelper = DatabaseHelper(
      databaseName:
          'chat_attachment_test_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final groupId = await databaseHelper.insertGroup(
      ChatGroup(
        title: 'group',
        lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions,
      ),
    );
    final message = ChatMessage(
      text: 'look at this image',
      role: MessageRole.user,
      status: MessageStatus.completed,
    );
    final messageId = await databaseHelper.insertMessage(message, groupId);
    final attachment = ChatAttachment.image(
      localId: 'att-1',
      fileName: 'demo.png',
      mimeType: 'image/png',
      byteSize: 128,
      localPath: '/tmp/demo.png',
      status: ChatAttachmentStatus.ready,
    );

    await databaseHelper.insertMessageAttachments(messageId, [attachment]);

    final loaded = await databaseHelper.getMessagesByGroup(groupId);
    expect(loaded.single.attachments, hasLength(1));
    expect(loaded.single.referenceJson?['attachments'], isNotNull);
    expect(
      (loaded.single.referenceJson?['attachments'] as List).single['fileName'],
      'demo.png',
    );
  });

  test('chat controller forwards send request with attachments', () async {
    final sendCoordinator = _RecordingChatSendCoordinator();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(_FakeChatStorage()),
        chatControllerProvider.overrideWith(
          (ref) => ChatController(
            ref,
            sendCoordinator: sendCoordinator,
            sessionCoordinator: _NoopChatSessionCoordinator(),
            summaryController: _NoopChatSummaryController(),
            preferencesController: _NoopChatPreferencesController(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final request = SendMessageRequest(
      text: '看下这张图',
      attachments: [
        ChatAttachment.image(
          localId: 'att-1',
          fileName: 'demo.png',
          mimeType: 'image/png',
          status: ChatAttachmentStatus.selected,
        ),
      ],
    );

    await container.read(chatControllerProvider).sendMessageRequest(request);

    expect(sendCoordinator.lastRequest?.attachments, hasLength(1));
    expect(sendCoordinator.lastRequest?.text, '看下这张图');
  });

  test('chat controller triggers manual compaction for current group',
      () async {
    final compactService = _SpySessionContextService();
    final sessionCoordinator = _RecordingChatSessionCoordinator();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(_FakeChatStorage()),
        sessionContextServiceProvider.overrideWith((ref) => compactService),
        chatControllerProvider.overrideWith(
          (ref) => ChatController(
            ref,
            sendCoordinator: _NoopChatSendCoordinator(),
            sessionCoordinator: sessionCoordinator,
            summaryController: _NoopChatSummaryController(),
            preferencesController: _NoopChatPreferencesController(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(currentGroupProvider.notifier).state = ChatGroup(
      id: 42,
      title: 'active group',
      lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions,
    );

    final result =
        await container.read(chatControllerProvider).compactCurrentSession();

    expect(compactService.lastGroupId, 42);
    expect(result.didCompactHistory, isTrue);
    expect(sessionCoordinator.loadMessagesCalls, 1);
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

class _RecordingChatSendCoordinator extends _NoopChatSendCoordinator {
  SendMessageRequest? lastRequest;

  @override
  Future<void> sendMessageRequest(
    SendMessageRequest request, {
    required void Function() scheduleAutoSummary,
    required void Function() cancelActiveStream,
  }) async {
    lastRequest = request;
  }
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

  @override
  Future<void> updateCurrentGroupWorkspace(String? workspaceId) async {}
}

class _RecordingChatSessionCoordinator extends _NoopChatSessionCoordinator {
  int loadMessagesCalls = 0;

  @override
  Future<void> loadMessages() async {
    loadMessagesCalls += 1;
  }
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

class _SpySessionContextService extends SessionContextService {
  _SpySessionContextService()
      : super(
          chatTurnRepository: _NoopChatTurnRepository(),
          chatEventRepository: _NoopChatEventRepository(),
          snapshotRepository: _NoopSessionContextSnapshotRepository(),
          chatStorage: _FakeChatStorage(),
          contextProjector: SessionContextProjector(),
          tokenBudgetService: SessionTokenBudgetService(),
          summaryService: SessionSummaryService(
            summaryGenerator: (_) async => '',
          ),
          chatService: ChatService(llm: _ControllerFakeBaseLlm()),
        );

  int? lastGroupId;

  @override
  Future<ManualSessionCompactionResult> compactCompletedHistoryForGroup({
    required int groupId,
    int? keepRecentCompletedTurns,
  }) async {
    lastGroupId = groupId;
    return ManualSessionCompactionResult(
      snapshot: SessionContextSnapshot(
        groupId: groupId,
        summaryText: 'manual summary',
        coveredUntilTurnId: 1,
      ),
      didCompactHistory: true,
    );
  }
}

class _ControllerFakeBaseLlm implements BaseLLM {
  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'gpt-5.4';

  @override
  Future<ModelTurnDecision?> planTurnDecision({
    required List<PlannerContextCarrier> carriers,
    required ChatTurnProviderStyle activeApiStyle,
    required bool currentTurnRunning,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    void Function(LlmRetryProgress progress)? onRetryScheduled,
  }) async {
    return null;
  }

  @override
  Future<String> processWebpageContent({
    required String webpageContent,
    required String prompt,
  }) async =>
      '';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async => '';
}

class _NoopChatTurnRepository extends ChatTurnRepository {
  _NoopChatTurnRepository() : super(_FakeChatStorage());
}

class _NoopChatEventRepository extends ChatEventRepository {
  _NoopChatEventRepository() : super(_FakeChatStorage());
}

class _NoopSessionContextSnapshotRepository
    extends SessionContextSnapshotRepository {
  _NoopSessionContextSnapshotRepository() : super(_FakeChatStorage());
}

class _FakeChatStorage implements ChatStorage {
  _FakeChatStorage({
    this.messagesByGroup = const {},
    this.paginatedMessages = const [],
    this.groupMessageCount = 0,
  });

  final Map<int, List<ChatMessage>> messagesByGroup;
  final List<ChatMessage> paginatedMessages;
  final int groupMessageCount;

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
  Future<int> getGroupMessageCount(int groupId) async => groupMessageCount;

  @override
  Future<ChatGroup?> getLatestGroup() async => null;

  @override
  Future<ChatGroup?> getGroupById(int id) async => null;

  @override
  Future<SessionContextSnapshot?> getLatestSessionContextSnapshotByGroup(
    int groupId,
  ) async =>
      null;

  @override
  Future<List<ChatMessage>> getMessagesByGroup(int groupId) async =>
      messagesByGroup[groupId] ?? const [];

  @override
  Future<List<ChatMessage>> getMessagesByGroupWithPagination({
    required int groupId,
    required int limit,
    required int offset,
  }) async =>
      paginatedMessages;

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
  Future<void> insertMessageAttachments(
    int messageId,
    List<ChatAttachment> attachments,
  ) async {}

  @override
  Future<List<ChatAttachment>> getMessageAttachments(int messageId) async =>
      const [];

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
  Future<void> updateGroupWorkspaceId(int groupId, String? workspaceId) async {}

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
