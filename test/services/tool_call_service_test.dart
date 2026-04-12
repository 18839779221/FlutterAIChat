import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/tool_call_service.dart';
import 'package:ai_chat/services/tool_executor.dart';
import 'package:ai_chat/services/tool_registry.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:ai_chat/tools/core/tool_argument_resolution.dart';
import 'package:ai_chat/tools/core/tool_execution_context.dart';
import 'package:ai_chat/tools/core/tool_handler.dart';
import 'package:ai_chat/tools/core/tool_runtime_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolCallService.prepareToolContext', () {
    test('模型返回合法工具调用 json 时执行工具并产出附加上下文', () async {
      final service = ToolCallService(
        llm: _FakeBaseLLM(
          decisionResponse:
              '{"toolName":"search_chat_history","arguments":{"query":"数据库","maxResults":2}}',
        ),
        toolRegistry: ToolRegistry(),
        toolExecutor: ToolExecutor(
          chatStorage: _FakeChatStorage(
            messages: [
              ChatMessage(
                id: 1,
                text: '数据库版本已经升级到 6',
                role: MessageRole.assistant,
                timestamp: DateTime(2026, 3, 27, 10, 0),
                status: MessageStatus.completed,
              ),
            ],
          ),
        ),
      );

      final result = await service.prepareToolContext(
        groupId: 10,
        userMessage: '我刚才提过数据库版本吗？',
        history: const [],
      );

      expect(result.toolResult, isNotNull);
      expect(result.toolResult!.toolName, 'search_chat_history');
      expect(result.toolResult!.status, ToolExecutionStatus.success);
      expect(result.additionalContextMessages, isNotEmpty);
      expect(result.additionalContextMessages.single.role, MessageRole.system);
      expect(result.additionalContextMessages.single.text,
          contains('数据库版本已经升级到 6'));
    });

    test('模型返回 none 时不触发工具执行', () async {
      final service = ToolCallService(
        llm: _FakeBaseLLM(
          decisionResponse: '{"toolName":"none"}',
        ),
        toolRegistry: ToolRegistry(),
        toolExecutor: ToolExecutor(
          chatStorage: const _FakeChatStorage(messages: []),
        ),
      );

      final result = await service.prepareToolContext(
        groupId: 10,
        userMessage: '直接回答这个问题',
        history: const [],
      );

      expect(result.toolResult, isNull);
      expect(result.additionalContextMessages, isEmpty);
    });

    test('模型返回非法 json 时安全回退为不调用工具', () async {
      final service = ToolCallService(
        llm: _FakeBaseLLM(
          decisionResponse: 'not-json',
        ),
        toolRegistry: ToolRegistry(),
        toolExecutor: ToolExecutor(
          chatStorage: const _FakeChatStorage(messages: []),
        ),
      );

      final result = await service.prepareToolContext(
        groupId: 10,
        userMessage: '这个问题需要查历史吗？',
        history: const [],
      );

      expect(result.toolResult, isNull);
      expect(result.additionalContextMessages, isEmpty);
    });

    test('模型返回未知工具名时安全回退为不调用工具', () async {
      final service = ToolCallService(
        llm: _FakeBaseLLM(
          decisionResponse:
              '{"toolName":"extract_todos","arguments":{"query":"todo"}}',
        ),
        toolRegistry: ToolRegistry(),
        toolExecutor: ToolExecutor(
          chatStorage: const _FakeChatStorage(messages: []),
        ),
      );

      final result = await service.prepareToolContext(
        groupId: 10,
        userMessage: '帮我看看 todo',
        history: const [],
      );

      expect(result.toolResult, isNull);
      expect(result.additionalContextMessages, isEmpty);
    });

    test('仅提供 runtime registry 时也能识别并执行运行时工具', () async {
      final service = ToolCallService(
        llm: _FakeBaseLLM(
          decisionResponse:
              '{"toolName":"debug_runtime_tool","arguments":{"topic":"runtime"}}',
        ),
        runtimeRegistry: ToolRuntimeRegistry(
          handlers: [
            _FakeRuntimeToolHandler(),
          ],
        ),
        toolExecutor: ToolExecutor(
          chatStorage: const _FakeChatStorage(messages: []),
        ),
      );

      final result = await service.prepareToolContext(
        groupId: 10,
        userMessage: '请执行 runtime 调试工具',
        history: const [],
      );

      expect(result.toolResult, isNotNull);
      expect(result.toolResult!.toolName, 'debug_runtime_tool');
      expect(result.additionalContextMessages.single.text, contains('runtime-debug-ok'));
    });
  });
}

class _FakeRuntimeToolHandler implements ToolHandler {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'debug_runtime_tool',
        title: 'Runtime Debug Tool',
        description: 'Only exists in the runtime registry for testing.',
        parameters: {
          'topic': 'string',
        },
      );

  @override
  List<ChatMessage> buildContextMessages({
    required ToolResult result,
    required ToolExecutionContext context,
  }) {
    return [
      ChatMessage(
        text: 'runtime-debug-ok',
        role: MessageRole.system,
        status: MessageStatus.completed,
      ),
    ];
  }

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
    final topic = rawArguments['topic'];
    if (topic is! String || topic.trim().isEmpty) {
      return ToolArgumentResolution.invalid(
        errorCode: 'invalid_topic',
        errorSummary: 'missing topic',
      );
    }
    return ToolArgumentResolution.valid({
      'topic': topic.trim(),
    });
  }
}

class _FakeBaseLLM implements BaseLLM {
  final String decisionResponse;

  _FakeBaseLLM({required this.decisionResponse});

  @override
  Map<String, dynamic> get config => const {};

  @override
  Stream<String> chatStream(
      List<ChatMessage> messages, ChatConfig config) async* {}

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
  Future<String> summarizeConversation(List<ChatMessage> messages) async =>
      'summary';

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
  Future<void> updateGroupLastMessageTime(int groupId) =>
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
  Future<int> insertMessage(ChatMessage message, int groupId) =>
      throw UnimplementedError();

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
  Future<void> updateMessage(int id, String newText) =>
      throw UnimplementedError();

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
  Future<bool> testDatabaseConnection() => throw UnimplementedError();
}
