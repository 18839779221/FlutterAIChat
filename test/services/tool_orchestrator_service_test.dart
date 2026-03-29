import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/tool_decision_service.dart';
import 'package:ai_chat/services/tool_executor.dart';
import 'package:ai_chat/services/tool_orchestrator_service.dart';
import 'package:ai_chat/services/tool_policy_service.dart';
import 'package:ai_chat/services/tool_registry.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ToolOrchestratorService', () {
    test('returns no tool when model decides none', () async {
      final service = await _createService(
        decisionResponse: '{"toolName":"none"}',
      );

      final result = await service.prepareToolContext(
        groupId: 1,
        userMessage: '直接回答',
        history: const [],
      );

      expect(result.toolResult, isNull);
      expect(result.toolInvocation, isNull);
      expect(result.additionalContextMessages, isEmpty);
    });

    test('auto-run tool path executes and returns context', () async {
      final service = await _createService(
        decisionResponse:
            '{"toolName":"search_chat_history","arguments":{"query":"数据库"}}',
        storageMessages: [
          ChatMessage(
            id: 1,
            text: '数据库版本已经升级到 6',
            role: MessageRole.assistant,
            timestamp: DateTime(2026, 3, 27, 10),
            status: MessageStatus.completed,
          ),
        ],
      );

      final result = await service.prepareToolContext(
        groupId: 1,
        userMessage: '我刚才提过数据库版本吗？',
        history: const [],
      );

      expect(result.toolInvocation, isNotNull);
      expect(result.toolInvocation!.status, ToolInvocationStatus.running);
      expect(result.toolResult, isNotNull);
      expect(result.toolResult!.toolName, 'search_chat_history');
      expect(result.additionalContextMessages.single.text, contains('数据库版本已经升级到 6'));
    });

    test('confirmation-required tools return awaiting confirmation state', () async {
      final service = await _createService(
        decisionResponse:
            '{"toolName":"create_reminder","arguments":{"title":"交周报"}}',
      );

      final result = await service.prepareToolContext(
        groupId: 1,
        userMessage: '提醒我交周报',
        history: const [],
      );

      expect(result.toolResult, isNull);
      expect(result.toolInvocation, isNotNull);
      expect(
        result.toolInvocation!.status,
        ToolInvocationStatus.awaitingConfirmation,
      );
      expect(result.toolInvocation!.requiresConfirmation, isTrue);
    });

    test('trusting a tool makes future calls auto-run', () async {
      final service = await _createService(
        decisionResponse:
            '{"toolName":"create_reminder","arguments":{"title":"交周报"}}',
        reminderCreator: ({required title, dueAt, note}) async => ToolResult(
          toolName: 'create_reminder',
          status: ToolExecutionStatus.success,
          summary: '已创建提醒：$title',
          data: {'title': title},
        ),
      );

      await service.trustTool('create_reminder');

      final result = await service.prepareToolContext(
        groupId: 1,
        userMessage: '提醒我交周报',
        history: const [],
      );

      expect(result.toolInvocation, isNotNull);
      expect(result.toolInvocation!.status, ToolInvocationStatus.running);
      expect(result.toolResult, isNotNull);
      expect(result.toolResult!.summary, contains('已创建提醒'));
    });
  });
}

Future<ToolOrchestratorService> _createService({
  required String decisionResponse,
  List<ChatMessage> storageMessages = const [],
  ReminderCreator? reminderCreator,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final repository = AppSettingsRepository(
    preferences,
    localDefaultsLoader: () async => null,
  );

  return ToolOrchestratorService(
    toolRegistry: ToolRegistry(),
    toolDecisionService: ToolDecisionService(
      llm: _FakeBaseLLM(decisionResponse: decisionResponse),
      toolRegistry: ToolRegistry(),
    ),
    toolPolicyService: ToolPolicyService(repository: repository),
    toolExecutor: ToolExecutor(
      chatStorage: _FakeChatStorage(messages: storageMessages),
      reminderCreator: reminderCreator,
    ),
  );
}

class _FakeBaseLLM implements BaseLLM {
  final String decisionResponse;

  _FakeBaseLLM({required this.decisionResponse});

  @override
  Map<String, dynamic> get config => const {};

  @override
  Stream<String> chatStream(List<ChatMessage> messages, ChatConfig config) async* {}

  @override
  Future<String> decideToolCall({
    required String userMessage,
    required List<ChatMessage> history,
    required List<ToolDefinition> tools,
  }) async {
    return decisionResponse;
  }

  @override
  String getModelName(ChatConfig config) => 'fake-model';

  @override
  Future<String> structureSummaryCard(String sourceText) {
    throw UnimplementedError();
  }

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async => 'summary';

  @override
  Future<bool> validateApiKey(ChatConfig config) async => true;
}

class _FakeChatStorage implements ChatStorage {
  final List<ChatMessage> messages;

  const _FakeChatStorage({required this.messages});

  @override
  Future<List<ChatMessage>> getMessagesByGroup(int groupId) async => messages;

  @override
  Future<int> insertGroup(ChatGroup group) => throw UnimplementedError();

  @override
  Future<List<ChatGroup>> getAllGroups() => throw UnimplementedError();

  @override
  Future<ChatGroup?> getLatestGroup() => throw UnimplementedError();

  @override
  Future<void> updateGroupLastMessageTime(int groupId) => throw UnimplementedError();

  @override
  Future<void> updateGroupSystemPrompt(int groupId, String? systemPrompt) =>
      throw UnimplementedError();

  @override
  Future<void> updateGroupTitle(int groupId, String title, {bool isSummarized = true}) =>
      throw UnimplementedError();

  @override
  Future<void> deleteGroup(int groupId) => throw UnimplementedError();

  @override
  Future<int> insertMessage(ChatMessage message, int groupId) => throw UnimplementedError();

  @override
  Future<List<ChatMessage>> getMessagesByGroupWithPagination({
    required int groupId,
    required int limit,
    required int offset,
  }) =>
      throw UnimplementedError();

  @override
  Future<int> getGroupMessageCount(int groupId) => throw UnimplementedError();

  @override
  Future<void> deleteGroupMessages(int groupId) => throw UnimplementedError();

  @override
  Future<void> updateMessage(int id, String newText) => throw UnimplementedError();

  @override
  Future<void> updateMessageReasoning(int id, String? reasoningContent) =>
      throw UnimplementedError();

  @override
  Future<void> updateMessageStatus(int id, MessageStatus status) =>
      throw UnimplementedError();

  @override
  Future<void> updateStructuredMessage(
    int id, {
    required String text,
    required MessageStatus status,
    required contentType,
    String? payloadJson,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteMessage(int id) => throw UnimplementedError();

  @override
  Future<bool> testDatabaseConnection() async => true;
}
