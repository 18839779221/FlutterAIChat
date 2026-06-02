import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/agent/chat_turn_step.dart';
import 'package:ai_chat/models/artifact/artifact_record.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat/chat_attachment.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/context/planner_context_carrier.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/skill/skill_catalog_entry.dart';
import 'package:ai_chat/models/speech/speech_input_config.dart';
import 'package:ai_chat/models/session/session_context_snapshot.dart';
import 'package:ai_chat/models/session/session_runtime_marker.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/speech/aliyun_realtime_asr_client.dart';
import 'package:ai_chat/services/skills/skill_runtime_service.dart';
import 'package:ai_chat/services/skills/skill_storage_service.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        chatServiceFactoryProvider.overrideWith((ref) => expected),
        databaseProvider.overrideWithValue(_ContextSnapshotChatStorage()),
        appSettingsRepositoryProvider.overrideWithValue(
          AppSettingsRepository(
            await SharedPreferences.getInstance(),
            localDefaultsLoader: () async => null,
          ),
        ),
        skillRuntimeServiceProvider.overrideWithValue(
          _StaticSkillRuntimeService(catalog: const []),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(currentGroupProvider.notifier).state = ChatGroup(
      id: 1,
      title: 'Context Group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions);
    container.read(systemPromptProvider.notifier).state = '你是一个助手';

    final snapshot = await container.read(contextWindowSnapshotProvider.future);
    expect(snapshot, isNotNull);
    expect(snapshot!.segments, isNotEmpty);
  });

  test(
      'sessionContextServiceProvider wires runtime skill catalog into planner messages',
      () async {
    final expected = ChatService(llm: _NoopBaseLLM());
    final container = ProviderContainer(
      overrides: [
        chatServiceFactoryProvider.overrideWith((ref) => expected),
        databaseProvider.overrideWithValue(_PlannerMessageChatStorage()),
        skillRuntimeServiceProvider.overrideWithValue(
          _StaticSkillRuntimeService(
            catalog: const [
              SkillCatalogEntry(
                id: 'edge-to-edge',
                name: 'edge-to-edge',
                description: 'Improve Android edge-to-edge handling.',
                qualifiedPath: '/skills/installed/edge-to-edge',
                isEnabled: true,
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final plannerMessages =
        await container.read(sessionContextServiceProvider).buildPlannerMessages(
              groupId: 1,
              currentTurnId: 1,
              currentTurnTranscript: [
                ChatEvent(
                  turnId: 1,
                  groupId: 1,
                  sequence: 1,
                  eventType: ChatEventType.userMessage,
                  role: MessageRole.user,
                  content: '检查 skill list 是否注入',
                ),
              ],
              config: ChatConfig(systemPrompt: '你是一个助手'),
            );

    expect(
      plannerMessages[1].text,
      contains('The following skills are available for use with the Skill tool:'),
    );
    expect(
      plannerMessages[1].text,
      contains('- edge-to-edge: Improve Android edge-to-edge handling.'),
    );
  });

  test('speechInputConfigProvider resolves config from app settings repository',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repository = AppSettingsRepository(
      await SharedPreferences.getInstance(),
      localDefaultsLoader: () async => const LlmLocalDefaults(
        speechInput: SpeechInputConfig(
          enabled: true,
          provider: 'aliyun',
          endpoint: 'wss://speech.example/ws',
          apiKey: 'speech-key',
          sampleRate: 16000,
          languageHints: ['zh', 'en'],
        ),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final config = await container.read(speechInputConfigProvider.future);

    expect(config, isNotNull);
    expect(config!.provider, 'aliyun');
    expect(config.endpoint, 'wss://speech.example/ws');
    expect(config.apiKey, 'speech-key');
  });

  test('aliyunRealtimeAsrClientProvider builds realtime client for aliyun config',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repository = AppSettingsRepository(
      await SharedPreferences.getInstance(),
      localDefaultsLoader: () async => const LlmLocalDefaults(
        speechInput: SpeechInputConfig(
          enabled: true,
          provider: 'aliyun',
          endpoint: 'wss://speech.example/ws',
          apiKey: 'speech-key',
          sampleRate: 16000,
          languageHints: ['zh', 'en'],
        ),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await container.read(speechInputConfigProvider.future);
    final client = container.read(aliyunRealtimeAsrClientProvider);

    expect(client, isA<DashScopeAliyunRealtimeAsrClient>());
  });
}

class _NoopBaseLLM extends BaseLLM {
  @override
  Map<String, dynamic> get config => const {};

  @override
  String getModelName(ChatConfig config) => 'noop';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async => '';
  @override
  Future<ModelTurnDecision?> planTurnDecision({
    required List<PlannerContextCarrier> carriers,
    required ChatTurnProviderStyle activeApiStyle,
    required bool currentTurnRunning,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    void Function(LlmRetryProgress progress)? onRetryScheduled,
  }) async =>
      null;
}

class _NoopChatStorage implements ChatStorage {
  @override
  Future<void> insertMessageAttachments(
    int messageId,
    List<ChatAttachment> attachments,
  ) async {}

  @override
  Future<List<ChatAttachment>> getMessageAttachments(int messageId) async =>
      const [];

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
  Future<ChatGroup?> getLatestGroup() async => null;

  @override
  Future<ChatGroup?> getGroupById(int id) async => null;

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

class _PlannerMessageChatStorage extends _NoopChatStorage {
  final ChatTurn _turn = ChatTurn(
    id: 1,
    groupId: 1,
    status: ChatTurnStatus.running,
    userInput: '检查 skill list 是否注入',
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
}

class _StaticSkillRuntimeService extends SkillRuntimeService {
  _StaticSkillRuntimeService({required this.catalog})
      : super(
          storageService: SkillStorageService(
            rootDirectoryProvider: () async =>
                throw UnimplementedError('not used in test'),
          ),
        );

  final List<SkillCatalogEntry> catalog;

  @override
  Future<List<SkillCatalogEntry>> listSkillCatalogEntries() async => catalog;
}
