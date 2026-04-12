import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/trace/chat_trace_event.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/chat_trace_recorder.dart';
import 'package:ai_chat/services/tool_decision_service.dart';
import 'package:ai_chat/services/tool_executor.dart';
import 'package:ai_chat/services/tool_orchestrator_service.dart';
import 'package:ai_chat/services/tool_policy_service.dart';
import 'package:ai_chat/services/tool_registry.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:ai_chat/tools/core/tool_runtime_registry.dart';
import 'package:ai_chat/tools/default_tool_runtime_registry.dart';
import 'package:ai_chat/tools/handlers/fetch_webpage_tool_handler.dart';
import 'package:ai_chat/tools/handlers/save_note_tool_handler.dart';
import 'package:ai_chat/tools/handlers/search_chat_history_tool_handler.dart';
import 'package:ai_chat/tools/handlers/share_result_tool_handler.dart';
import 'package:ai_chat/tools/handlers/create_calendar_event_tool_handler.dart';
import 'package:ai_chat/tools/handlers/create_reminder_tool_handler.dart';
import 'package:ai_chat/tools/handlers/web_search_tool_handler.dart';
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

    test('web_search auto-run path executes and returns structured context', () async {
      final longSnippet = List.filled(80, '这是很长的搜索结果摘要').join(' ');
      final traceRecorder = ChatTraceRecorder();
      final service = await _createService(
        decisionResponse:
            '{"toolName":"web_search","arguments":{"query":"OpenAI 最新消息"}}',
        traceRecorder: traceRecorder,
        runtimeRegistry: ToolRuntimeRegistry(
          handlers: [
            WebSearchToolHandler(
              webSearcher: ({required query, maxResults}) async => ToolResult(
                toolName: 'web_search',
                status: ToolExecutionStatus.success,
                summary: '已执行联网搜索',
                data: {
                  'query': query,
                  'provider': 'tavily',
                  'results': [
                    {
                      'title': 'OpenAI launches new feature',
                      'url': 'https://example.com/openai',
                      'snippet': longSnippet,
                      'source': 'example.com',
                    },
                  ],
                  'maxResults': maxResults,
                },
              ),
            ),
          ],
        ),
      );

      final result = await service.prepareToolContext(
        groupId: 1,
        userMessage: '请搜索 OpenAI 最新消息',
        history: const [],
        turnId: 'turn-tool-1',
      );

      expect(result.toolInvocation, isNotNull);
      expect(result.toolInvocation!.status, ToolInvocationStatus.running);
      expect(result.toolResult, isNotNull);
      expect(result.toolResult!.toolName, 'web_search');
      expect(result.toolResult!.data['provider'], 'tavily');
      expect(result.toolResult!.data['maxResults'], 5);
      expect(
        result.additionalContextMessages.single.text,
        contains('OpenAI launches new feature'),
      );
      expect(
        result.additionalContextMessages.single.text.length,
        lessThan(longSnippet.length + 200),
      );
      final events = traceRecorder.eventsForTurn('turn-tool-1');
      final stages = events.map((event) => event.stage).toList();
      final executeTrace = events.singleWhere(
        (event) => event.stage == ChatTraceStage.toolExecuteDone,
      );
      final contextTrace = events.singleWhere(
        (event) => event.stage == ChatTraceStage.toolContextBuilt,
      );
      expect(
        stages,
        containsAllInOrder([
          ChatTraceStage.toolPrepareStart,
          ChatTraceStage.toolDecisionDone,
          ChatTraceStage.toolExecuteDone,
          ChatTraceStage.toolContextBuilt,
        ]),
      );
      expect(executeTrace.turnId, 'turn-tool-1');
      expect(executeTrace.status, ChatTraceStatus.success);
      expect(contextTrace.turnId, 'turn-tool-1');
      expect(contextTrace.data?['toolName'], 'web_search');
    });

    test('confirmation-required tools return awaiting confirmation state', () async {
      final service = await _createService(
        decisionResponse:
            '{"toolName":"create_reminder","arguments":{"title":"交周报","dueAt":"2026-03-31T20:00:00+08:00"}}',
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
            '{"toolName":"create_reminder","arguments":{"title":"交周报","dueAt":"2026-03-31T20:00:00+08:00"}}',
        runtimeRegistry: ToolRuntimeRegistry(
          handlers: [
            CreateReminderToolHandler(
              reminderCreator: ({required title, dueAt, note}) async => ToolResult(
                toolName: 'create_reminder',
                status: ToolExecutionStatus.success,
                summary: '已创建提醒：$title',
                data: {
                  'title': title,
                  'dueAt': dueAt,
                },
              ),
            ),
          ],
        ),
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

    test('runtime reminder handler normalizes relative dueAt before confirmation', () async {
      final service = await _createService(
        decisionResponse:
            '{"toolName":"create_reminder","arguments":{"title":"交周报","dueAt":"2025-02-14T20:00:00+08:00"}}',
        runtimeRegistry: ToolRuntimeRegistry(
          handlers: [
            CreateReminderToolHandler(
              reminderCreator: ({required title, dueAt, note}) async => ToolResult(
                toolName: 'create_reminder',
                status: ToolExecutionStatus.success,
                summary: '已创建提醒：$title',
                data: {'title': title, 'dueAt': dueAt},
              ),
              nowProvider: () => DateTime.parse('2026-03-31T09:00:00+08:00'),
            ),
          ],
        ),
      );

      final result = await service.prepareToolContext(
        groupId: 1,
        userMessage: '提醒我今天晚上8点交周报',
        history: const [],
      );

      expect(result.toolInvocation, isNotNull);
      expect(result.toolInvocation!.arguments['dueAt'], '2026-03-31T20:00:00+08:00');
    });

    test('runtime calendar handler normalizes relative startAt before confirmation', () async {
      final service = await _createService(
        decisionResponse:
            '{"toolName":"create_calendar_event","arguments":{"title":"项目评审","startAt":"2025-02-14T15:00:00+08:00","endAt":"2025-02-14T16:30:00+08:00"}}',
        runtimeRegistry: ToolRuntimeRegistry(
          handlers: [
            CreateCalendarEventToolHandler(
              calendarEventCreator: ({
                required title,
                required startAt,
                endAt,
                location,
                notes,
              }) async =>
                  ToolResult(
                toolName: 'create_calendar_event',
                status: ToolExecutionStatus.success,
                summary: '已创建日历事件：$title',
                data: {
                  'title': title,
                  'startAt': startAt,
                  'endAt': endAt,
                },
              ),
              nowProvider: () => DateTime.parse('2026-03-31T09:00:00+08:00'),
            ),
          ],
        ),
      );

      final result = await service.prepareToolContext(
        groupId: 1,
        userMessage: '明天下午三点到四点半创建项目评审',
        history: const [],
      );

      expect(result.toolInvocation, isNotNull);
      expect(result.toolInvocation!.arguments['startAt'], '2026-04-01T15:00:00+08:00');
      expect(result.toolInvocation!.arguments['endAt'], '2026-04-01T16:30:00+08:00');
    });

    test('runtime search history handler executes and builds compact context', () async {
      final service = await _createService(
        decisionResponse:
            '{"toolName":"search_chat_history","arguments":{"query":"数据库"}}',
        runtimeRegistry: ToolRuntimeRegistry(
          handlers: [
            SearchChatHistoryToolHandler(
              searcher: ({required groupId, required query, required maxResults}) async => ToolResult(
                toolName: 'search_chat_history',
                status: ToolExecutionStatus.success,
                summary: '已执行：搜索历史记录',
                data: {
                  'query': query,
                  'matchCount': 1,
                  'matches': const [
                    {
                      'id': 1,
                      'role': 'assistant',
                      'text': '数据库版本已经升级到 6',
                    },
                  ],
                },
              ),
            ),
          ],
        ),
      );

      final result = await service.prepareToolContext(
        groupId: 1,
        userMessage: '我刚才提过数据库版本吗？',
        history: const [],
      );

      expect(result.toolResult, isNotNull);
      expect(result.toolResult!.toolName, 'search_chat_history');
      expect(
        result.additionalContextMessages.single.text,
        contains('数据库版本已经升级到 6'),
      );
    });

    test('runtime fetch webpage handler executes and builds webpage context', () async {
      final service = await _createService(
        decisionResponse:
            '{"toolName":"fetch_webpage","arguments":{"url":"https://example.com/article"}}',
        runtimeRegistry: ToolRuntimeRegistry(
          handlers: [
            FetchWebpageToolHandler(
              webpageFetcher: ({required url, extractMode}) async => ToolResult(
                toolName: 'fetch_webpage',
                status: ToolExecutionStatus.success,
                summary: '已读取网页：Example',
                data: {
                  'url': url,
                  'title': 'Example',
                  'content': '这是网页正文内容',
                  'extractMode': extractMode ?? 'readable_text',
                },
              ),
            ),
          ],
        ),
      );

      final result = await service.prepareToolContext(
        groupId: 1,
        userMessage: '读取这个网页内容 https://example.com/article',
        history: const [],
      );

      expect(result.toolResult, isNotNull);
      expect(result.toolResult!.toolName, 'fetch_webpage');
      expect(result.additionalContextMessages.single.text, contains('Example'));
      expect(result.additionalContextMessages.single.text, contains('这是网页正文内容'));
    });

    test('runtime save note handler auto-runs after trust and returns summary context', () async {
      final service = await _createService(
        decisionResponse:
            '{"toolName":"save_note","arguments":{"title":"Tool Runtime","content":"继续推进 runtime 重构"}}',
        runtimeRegistry: ToolRuntimeRegistry(
          handlers: [
            SaveNoteToolHandler(
              noteSaver: ({required title, required content, folder}) async => ToolResult(
                toolName: 'save_note',
                status: ToolExecutionStatus.success,
                summary: '已保存笔记：$title',
                data: {
                  'title': title,
                  'content': content,
                  'folder': folder,
                },
              ),
            ),
          ],
        ),
      );

      await service.trustTool('save_note');

      final result = await service.prepareToolContext(
        groupId: 1,
        userMessage: '帮我记下来',
        history: const [],
      );

      expect(result.toolResult, isNotNull);
      expect(result.toolResult!.toolName, 'save_note');
      expect(result.additionalContextMessages.single.text, contains('已保存笔记'));
    });

    test('runtime share result handler auto-runs after trust and returns share context', () async {
      final service = await _createService(
        decisionResponse:
            '{"toolName":"share_result","arguments":{"text":"这是一段要分享的内容","subject":"分享标题"}}',
        runtimeRegistry: ToolRuntimeRegistry(
          handlers: [
            ShareResultToolHandler(
              resultSharer: ({required text, subject}) async => ToolResult(
                toolName: 'share_result',
                status: ToolExecutionStatus.success,
                summary: '已发起分享',
                data: {
                  'text': text,
                  'subject': subject,
                  'shareStatus': 'success',
                },
              ),
            ),
          ],
        ),
      );

      await service.trustTool('share_result');

      final result = await service.prepareToolContext(
        groupId: 1,
        userMessage: '分享这段内容',
        history: const [],
      );

      expect(result.toolResult, isNotNull);
      expect(result.toolResult!.toolName, 'share_result');
      expect(result.additionalContextMessages.single.text, contains('已发起分享'));
    });

    test('confirmed invocation also uses runtime handler context builder', () async {
      final service = await _createService(
        decisionResponse: '{"toolName":"none"}',
        runtimeRegistry: ToolRuntimeRegistry(
          handlers: [
            ShareResultToolHandler(
              resultSharer: ({required text, subject}) async => ToolResult(
                toolName: 'share_result',
                status: ToolExecutionStatus.success,
                summary: '已发起分享',
                data: {
                  'text': text,
                  'subject': subject,
                  'shareStatus': 'success',
                },
              ),
            ),
          ],
        ),
      );

      final result = await service.executeToolInvocation(
        groupId: 1,
        invocation: const ToolInvocation(
          toolName: 'share_result',
          arguments: {
            'text': '这是一段要分享的内容',
            'subject': '分享标题',
          },
          status: ToolInvocationStatus.awaitingConfirmation,
          summary: '准备执行工具：分享结果',
          requiresConfirmation: true,
        ),
      );

      expect(result.toolResult, isNotNull);
      expect(result.toolResult!.toolName, 'share_result');
      expect(result.additionalContextMessages.single.text, contains('分享状态：success'));
    });
  });
}

Future<ToolOrchestratorService> _createService({
  required String decisionResponse,
  List<ChatMessage> storageMessages = const [],
  ReminderCreator? reminderCreator,
  CalendarEventCreator? calendarEventCreator,
  WebSearcher? webSearcher,
  ToolRuntimeRegistry? runtimeRegistry,
  ChatTraceRecorder? traceRecorder,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final repository = AppSettingsRepository(
    preferences,
    localDefaultsLoader: () async => null,
  );
  final resolvedExecutor = ToolExecutor(
    chatStorage: _FakeChatStorage(messages: storageMessages),
    webSearcher: webSearcher,
    reminderCreator: reminderCreator,
    calendarEventCreator: calendarEventCreator,
  );
  final resolvedRuntimeRegistry =
      runtimeRegistry ?? buildDefaultToolRuntimeRegistry(toolExecutor: resolvedExecutor);
  final resolvedToolRegistry = ToolRegistry(
    runtimeRegistry: resolvedRuntimeRegistry,
  );

  return ToolOrchestratorService(
    toolRegistry: resolvedToolRegistry,
    runtimeRegistry: resolvedRuntimeRegistry,
    toolDecisionService: ToolDecisionService(
      llm: _FakeBaseLLM(decisionResponse: decisionResponse),
      toolRegistry: resolvedToolRegistry,
      traceRecorder: traceRecorder,
    ),
    traceRecorder: traceRecorder,
    toolPolicyService: ToolPolicyService(repository: repository),
    toolExecutor: resolvedExecutor,
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
