import 'dart:io';

import 'package:ai_chat/models/agent/chat_turn_step.dart';
import 'package:ai_chat/models/artifact/artifact_record.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat/chat_attachment.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_provider_model.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/session/session_context_snapshot.dart';
import 'package:ai_chat/models/session/session_runtime_config.dart';
import 'package:ai_chat/models/session/session_runtime_marker.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:ai_chat/services/skills/skill_runtime_service.dart';
import 'package:ai_chat/services/skills/skill_storage_service.dart';
import 'package:ai_chat/services/tool_executor.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:ai_chat/tools/core/tool_execution_context.dart';
import 'package:ai_chat/tools/default_tool_runtime_registry.dart';
import 'package:ai_chat/tools/handlers/create_artifact_guideline_tool_handler.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('default runtime registry exposes ask_user_question to planner', () {
    final registry = buildDefaultToolRuntimeRegistry(
      toolExecutor: ToolExecutor(chatStorage: _FakeChatStorage()),
    );

    final definitions = registry.getDefinitionsForPlatform('android');

    expect(
      definitions.map((item) => item.name),
      contains('ask_user_question'),
    );
    expect(
      definitions.map((item) => item.name),
      contains('Delete'),
    );
  });

  test('default runtime registry exposes generate_image to planner', () {
    final registry = buildDefaultToolRuntimeRegistry(
      toolExecutor: ToolExecutor(chatStorage: _FakeChatStorage()),
    );

    final definitions = registry.getDefinitionsForPlatform('android');

    expect(
      definitions.map((item) => item.name),
      contains('generate_image'),
    );
  });

  test('generate_image uses configured image provider instead of chat provider',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settingsRepository = AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => const LlmLocalDefaults(
        defaultProviderId: 'chat-provider',
        defaultModelId: 'chat-model',
        providers: [
          LlmProviderConfig(
            id: 'chat-provider',
            name: 'Chat Provider',
            apiKey: 'chat-key',
            baseUrl: 'https://chat.example/v1',
            models: [
              LlmProviderModel(id: 'chat-model', name: 'Chat Model'),
            ],
          ),
          LlmProviderConfig(
            id: 'beehears',
            name: 'Beehears',
            apiKey: 'image-key',
            baseUrl: 'https://ai.beehears.com/v1',
            models: [
              LlmProviderModel(
                id: 'gpt-image-2',
                name: 'GPT Image 2',
                supportsImageGeneration: true,
              ),
            ],
          ),
        ],
        additionalConfig: {
          'image_generation.default_provider_id': 'beehears',
          'image_generation.default_model_id': 'gpt-image-2',
        },
      ),
    );
    Map<String, dynamic>? captured;
    final registry = buildDefaultToolRuntimeRegistry(
      toolExecutor: ToolExecutor(
        chatStorage: _FakeChatStorage(),
        imageGenerator: ({
          required prompt,
          required model,
          required size,
          required quality,
          apiKey,
          baseUrl,
        }) async {
          captured = {
            'prompt': prompt,
            'model': model,
            'size': size,
            'quality': quality,
            'apiKey': apiKey,
            'baseUrl': baseUrl,
          };
          return const ToolResult(
            toolName: 'generate_image',
            status: ToolExecutionStatus.success,
            summary: '已生成图片',
          );
        },
      ),
      appSettingsRepository: settingsRepository,
    );

    final handler = registry.findHandler('generate_image')!;
    await handler.execute(
      ToolExecutionContext(
        groupId: 1,
        toolName: 'generate_image',
        arguments: const {
          'prompt': 'A paper-cut orange fox',
          'size': '1024x1024',
        },
        history: const <ChatMessage>[],
        now: DateTime(2026, 6, 12),
        cwd: '/',
      ),
    );

    expect(captured, {
      'prompt': 'A paper-cut orange fox',
      'model': 'gpt-image-2',
      'size': '1024x1024',
      'quality': 'low',
      'apiKey': 'image-key',
      'baseUrl': 'https://ai.beehears.com/v1',
    });
  });

  test('generate_image fails without configured image provider', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settingsRepository = AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => const LlmLocalDefaults(
        defaultProviderId: 'chat-provider',
        defaultModelId: 'chat-model',
        providers: [
          LlmProviderConfig(
            id: 'chat-provider',
            name: 'Chat Provider',
            apiKey: 'chat-key',
            baseUrl: 'https://chat.example/v1',
            models: [
              LlmProviderModel(
                id: 'chat-model',
                name: 'Chat Model',
                supportsImageInput: true,
              ),
            ],
          ),
        ],
      ),
    );
    var generatorCalled = false;
    final registry = buildDefaultToolRuntimeRegistry(
      toolExecutor: ToolExecutor(
        chatStorage: _FakeChatStorage(),
        imageGenerator: ({
          required prompt,
          required model,
          required size,
          required quality,
          apiKey,
          baseUrl,
        }) async {
          generatorCalled = true;
          return const ToolResult(
            toolName: 'generate_image',
            status: ToolExecutionStatus.success,
            summary: '已生成图片',
          );
        },
      ),
      appSettingsRepository: settingsRepository,
    );

    final handler = registry.findHandler('generate_image')!;
    final result = await handler.execute(
      ToolExecutionContext(
        groupId: 1,
        toolName: 'generate_image',
        arguments: const {
          'prompt': 'A paper-cut orange fox',
          'size': '1024x1024',
        },
        history: const <ChatMessage>[],
        now: DateTime(2026, 6, 12),
        cwd: '/',
      ),
    );

    expect(generatorCalled, isFalse);
    expect(result.status, ToolExecutionStatus.failure);
    expect(result.errorMessage, 'image_generation_not_configured');
  });

  test('default runtime registry exposes skill tool to planner', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('tool-registry-skill-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final storageService = SkillStorageService(
      rootDirectoryProvider: () async => tempDir,
    );
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settingsRepository = AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => null,
    );
    final skillRuntimeService = SkillRuntimeService(
      storageService: storageService,
      settingsRepository: settingsRepository,
    );

    final registry = buildDefaultToolRuntimeRegistry(
      toolExecutor: ToolExecutor(chatStorage: _FakeChatStorage()),
      skillRuntimeService: skillRuntimeService,
    );

    final definitions = registry.getDefinitionsForPlatform('android');

    expect(
      definitions.map((item) => item.name),
      contains('skill'),
    );
  });

  test('default runtime registry exposes create_artifact guideline when wired',
      () {
    final registry = buildDefaultToolRuntimeRegistry(
      toolExecutor: ToolExecutor(chatStorage: _FakeChatStorage()),
      createArtifactGuidelineHandler: CreateArtifactGuidelineToolHandler(
        activeThemeSpecProvider: () => AppThemeSpec.claude(),
      ),
    );

    final definitions = registry.getDefinitionsForPlatform('android');

    expect(
      definitions.map((item) => item.name),
      contains('create_artifact__guideline'),
    );
  });
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
  Future<ChatGroup?> getGroupById(int id) async => null;

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
  Future<int> insertSessionRuntimeConfig(SessionRuntimeConfig config) async =>
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
  Future<SessionRuntimeConfig?> getSessionRuntimeConfigByGroup(
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
  Future<void> updateSessionRuntimeConfig(SessionRuntimeConfig config) async {}

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
