import 'dart:io';

import 'package:ai_chat/models/agent/chat_turn_step.dart';
import 'package:ai_chat/models/artifact/artifact_record.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/session/session_context_snapshot.dart';
import 'package:ai_chat/models/session/session_runtime_marker.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/services/skills/skill_runtime_service.dart';
import 'package:ai_chat/services/skills/skill_storage_service.dart';
import 'package:ai_chat/services/tool_executor.dart';
import 'package:ai_chat/storage/chat_storage.dart';
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
  });

  test('default runtime registry exposes skill tool to planner', () async {
    final tempDir = await Directory.systemTemp.createTemp('tool-registry-skill-');
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

  test('default runtime registry exposes create_artifact guideline when wired', () {
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
  Future<int> insertSessionContextSnapshot(
          SessionContextSnapshot snapshot) async =>
      1;

  @override
  Future<int> insertSessionRuntimeMarker(SessionRuntimeMarker marker) async => 1;

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
