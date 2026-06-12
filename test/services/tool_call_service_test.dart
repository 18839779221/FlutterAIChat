import 'package:ai_chat/models/artifact/artifact_record.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/agent/chat_turn_step.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/chat/chat_attachment.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/session/session_context_snapshot.dart';
import 'package:ai_chat/models/session/session_runtime_config.dart';
import 'package:ai_chat/models/session/session_runtime_marker.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/services/tool_call_service.dart';
import 'package:ai_chat/services/tool_executor.dart';
import 'package:ai_chat/services/tool_policy_service.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:ai_chat/tools/core/tool_argument_resolution.dart';
import 'package:ai_chat/tools/core/tool_execution_context.dart';
import 'package:ai_chat/tools/core/tool_handler.dart';
import 'package:ai_chat/tools/core/tool_runtime_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ToolCallService.executeToolInvocation', () {
    test(
        'delegates confirmed invocation to runtime handler and returns tool result only',
        () async {
      final service = ToolCallService(
        runtimeRegistry: ToolRuntimeRegistry(
          handlers: [_FakeRuntimeToolHandler()],
        ),
        toolExecutor: ToolExecutor(
          chatStorage: const _FakeChatStorage(messages: []),
        ),
        toolPolicyService: await _createToolPolicyService(),
      );

      final result = await service.executeToolInvocation(
        groupId: 10,
        invocation: const ToolInvocation(
          toolName: 'debug_runtime_tool',
          arguments: {'topic': 'runtime'},
          status: ToolInvocationStatus.awaitingConfirmation,
          summary: '准备执行工具：Runtime Debug Tool',
          requiresConfirmation: true,
        ),
      );

      expect(result.toolResult, isNotNull);
      expect(result.toolResult!.toolName, 'debug_runtime_tool');
      expect(result.toolResult!.status, ToolExecutionStatus.success);
      expect(result.toolResult!.summary, 'runtime handler executed');
      expect(result.toolResult!.data['topic'], 'runtime');
    });
  });
}

Future<ToolPolicyService> _createToolPolicyService() async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  return ToolPolicyService(
    repository: AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => null,
    ),
  );
}

class _FakeRuntimeToolHandler extends ToolHandler {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'debug_runtime_tool',
        title: 'Runtime Debug Tool',
        parameters: {
          'topic': 'string',
        },
      );

  @override
  Future<ToolResult> execute(ToolExecutionContext context) async {
    return ToolResult(
      toolName: 'debug_runtime_tool',
      status: ToolExecutionStatus.success,
      summary: 'runtime handler executed',
      data: {
        'topic': context.arguments['topic'],
      },
    );
  }

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    return ToolArgumentResolution.valid(rawArguments);
  }
}

class _FakeChatStorage implements ChatStorage {
  @override
  Future<ChatGroup?> getGroupById(int id) async => null;
  final List<ChatMessage> messages;

  const _FakeChatStorage({required this.messages});

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
  Future<List<ChatMessage>> getMessagesByGroup(int groupId) async => messages;

  @override
  Future<int> insertGroup(ChatGroup group) => throw UnimplementedError();

  @override
  Future<List<ChatGroup>> getAllGroups() => throw UnimplementedError();

  @override
  Future<ChatGroup?> getLatestGroup() => throw UnimplementedError();

  @override
  Future<void> updateGroupLastMessageTime(int groupId) =>
      throw UnimplementedError();

  @override
  Future<void> updateGroupWorkspaceId(int groupId, String? workspaceId) =>
      throw UnimplementedError();

  @override
  Future<void> updateGroupSystemPrompt(int groupId, String? systemPrompt) =>
      throw UnimplementedError();

  @override
  Future<void> updateGroupTitle(int groupId, String title,
          {bool isSummarized = true}) =>
      throw UnimplementedError();

  @override
  Future<void> deleteGroup(int groupId) => throw UnimplementedError();

  @override
  Future<int> insertTurn(ChatTurn turn) => throw UnimplementedError();

  @override
  Future<ChatTurn?> getTurn(int id) => throw UnimplementedError();

  @override
  Future<List<ChatTurn>> getTurnsByGroup(int groupId) =>
      throw UnimplementedError();

  @override
  Future<ChatTurnStep?> getTurnStep(int id) => throw UnimplementedError();

  @override
  Future<List<ChatTurnStep>> getTurnSteps(int turnId) =>
      throw UnimplementedError();

  @override
  Future<void> updateTurn(ChatTurn turn) => throw UnimplementedError();

  @override
  Future<int> insertTurnStep(ChatTurnStep step) => throw UnimplementedError();

  @override
  Future<void> updateTurnStep(ChatTurnStep step) => throw UnimplementedError();

  @override
  Future<int> insertEvent(ChatEvent event) => throw UnimplementedError();

  @override
  Future<List<ChatEvent>> getEventsByTurn(int turnId) =>
      throw UnimplementedError();

  @override
  Future<int> getNextEventSequence(int turnId) async => 1;

  @override
  Future<List<ChatEvent>> getEventsByGroup(int groupId) =>
      throw UnimplementedError();

  @override
  Future<int> insertMessage(ChatMessage message, int groupId) =>
      throw UnimplementedError();

  @override
  Future<void> insertMessageAttachments(
    int messageId,
    List<ChatAttachment> attachments,
  ) => throw UnimplementedError();

  @override
  Future<List<ChatAttachment>> getMessageAttachments(int messageId) =>
      throw UnimplementedError();

  @override
  Future<int> insertSessionContextSnapshot(SessionContextSnapshot snapshot) =>
      throw UnimplementedError();

  @override
  Future<int> insertSessionRuntimeConfig(SessionRuntimeConfig config) =>
      throw UnimplementedError();

  @override
  Future<int> insertSessionRuntimeMarker(SessionRuntimeMarker marker) =>
      throw UnimplementedError();

  @override
  Future<SessionContextSnapshot?> getLatestSessionContextSnapshotByGroup(
    int groupId,
  ) =>
      throw UnimplementedError();

  @override
  Future<SessionRuntimeConfig?> getSessionRuntimeConfigByGroup(int groupId) =>
      throw UnimplementedError();

  @override
  Future<List<ChatMessage>> getMessagesByGroupWithPagination({
    required int groupId,
    required int limit,
    required int offset,
  }) =>
      throw UnimplementedError();

  @override
  Future<SessionRuntimeMarker?> getLatestSessionRuntimeMarkerByGroup(
    int groupId,
  ) =>
      throw UnimplementedError();

  @override
  Future<int> getGroupMessageCount(int groupId) => throw UnimplementedError();

  @override
  Future<void> deleteGroupMessages(int groupId) => throw UnimplementedError();

  @override
  Future<void> updateMessage(int id, String newText) =>
      throw UnimplementedError();

  @override
  Future<void> updateMessageReasoning(int id, String? reasoningContent) =>
      throw UnimplementedError();

  @override
  Future<bool> testDatabaseConnection() => throw UnimplementedError();

  @override
  Future<void> updateMessageStatus(int id, MessageStatus status) =>
      throw UnimplementedError();

  @override
  Future<void> updateStructuredMessage(
    int id, {
    required String text,
    required MessageStatus status,
    required MessageContentType contentType,
    String? payloadJson,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteMessage(int id) => throw UnimplementedError();

  @override
  Future<void> updateSessionContextSnapshot(
    SessionContextSnapshot snapshot,
  ) =>
      throw UnimplementedError();

  @override
  Future<void> updateSessionRuntimeConfig(SessionRuntimeConfig config) =>
      throw UnimplementedError();

  @override
  Future<void> updateSessionRuntimeMarker(SessionRuntimeMarker marker) =>
      throw UnimplementedError();
}
