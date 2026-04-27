import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/agent/chat_turn_step.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/session/session_context_snapshot.dart';
import 'package:ai_chat/models/session/session_runtime_marker.dart';
import 'package:ai_chat/providers/chat_dependency_providers.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chatServiceProvider delegates to chatServiceFactoryProvider override',
      () {
    final expected = ChatService(llm: _NoopBaseLLM());
    final container = ProviderContainer(
      overrides: [
        chatServiceFactoryProvider.overrideWith((ref) => expected),
      ],
    );
    addTearDown(container.dispose);

    expect(identical(container.read(chatServiceProvider), expected), isTrue);
  });

  test(
      'sessionContextServiceProvider can be constructed from chat service and storage overrides',
      () {
    final expected = ChatService(llm: _NoopBaseLLM());
    final container = ProviderContainer(
      overrides: [
        chatServiceFactoryProvider.overrideWith((ref) => expected),
        databaseProvider.overrideWithValue(_NoopChatStorage()),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(sessionContextServiceProvider), isNotNull);
  });

  test('contextWindowSnapshotProvider resolves inspector-backed snapshot', () async {
    final expected = ChatService(llm: _NoopBaseLLM());
    final container = ProviderContainer(
      overrides: [
        chatServiceFactoryProvider.overrideWith((ref) => expected),
        databaseProvider.overrideWithValue(_ContextSnapshotChatStorage()),
      ],
    );
    addTearDown(container.dispose);

    container.read(currentGroupProvider.notifier).state = ChatGroup(
      id: 1,
      title: 'Context Group',
    );
    container.read(systemPromptProvider.notifier).state = '你是一个助手';

    final snapshot = await container.read(contextWindowSnapshotProvider.future);
    expect(snapshot, isNotNull);
    expect(snapshot!.segments, isNotEmpty);
  });
}

class _NoopBaseLLM extends BaseLLM {
  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'noop';

  @override
  Stream<String> chatStream(
      List<ChatMessage> messages, ChatConfig config) async* {}

  @override
  Future<bool> validateApiKey(ChatConfig config) async => true;

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async => '';
  @override
  Future<ModelTurnDecision?> planTurnDecision({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    providerStyle,
    Map<String, dynamic>? providerState,
    List<Map<String, dynamic>> providerContinuationItems = const [],
  }) async =>
      null;
}

class _NoopChatStorage implements ChatStorage {
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
  Future<ChatGroup?> getLatestGroup() async => null;

  @override
  Future<SessionContextSnapshot?> getLatestSessionContextSnapshotByGroup(
    int groupId,
  ) async =>
      null;

  @override
  Future<SessionRuntimeMarker?> getLatestSessionRuntimeMarkerByGroup(
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
  Future<int> getGroupMessageCount(int groupId) async => 0;

  @override
  Future<ChatTurn?> getTurn(int id) async => null;

  @override
  Future<ChatTurnStep?> getTurnStep(int id) async => null;

  @override
  Future<List<ChatTurnStep>> getTurnSteps(int turnId) async => const [];

  @override
  Future<List<ChatTurn>> getTurnsByGroup(int groupId) async => const [];

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
  Future<void> updateGroupLastMessageTime(int groupId) async {}

  @override
  Future<void> updateGroupSystemPrompt(
      int groupId, String? systemPrompt) async {}

  @override
  Future<void> updateGroupTitle(int groupId, String title,
      {bool isSummarized = true}) async {}

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

class _ContextSnapshotChatStorage extends _NoopChatStorage {
  final ChatTurn _turn = ChatTurn(
    id: 1,
    groupId: 1,
    status: ChatTurnStatus.running,
    userInput: '继续',
  );

  @override
  Future<ChatTurn?> getTurn(int id) async => id == 1 ? _turn : null;

  @override
  Future<List<ChatTurn>> getTurnsByGroup(int groupId) async {
    if (groupId != 1) {
      return const [];
    }
    return [_turn];
  }

  @override
  Future<List<ChatEvent>> getEventsByTurn(int turnId) async {
    if (turnId != 1) {
      return const [];
    }
    return [
      ChatEvent(
        turnId: 1,
        groupId: 1,
        sequence: 1,
        eventType: ChatEventType.userMessage,
        role: MessageRole.user,
        content: '继续',
      ),
    ];
  }
}
