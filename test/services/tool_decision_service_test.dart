import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/trace/chat_trace_event.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/chat_trace_recorder.dart';
import 'package:ai_chat/services/tool_decision_service.dart';
import 'package:ai_chat/services/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolDecisionService', () {
    test('returns fetch_webpage when user message includes a url', () async {
      final service = ToolDecisionService(
        llm: _FakeBaseLLM(
          decisionResponse:
              '{"toolName":"fetch_webpage","arguments":{"url":"https://example.com"}}',
        ),
        toolRegistry: ToolRegistry(),
      );

      final result = await service.decideTool(
        userMessage: '请读取这个网页：https://example.com',
        history: const [],
      );

      expect(result, isNotNull);
      expect(result!.toolName, 'fetch_webpage');
      expect(result.arguments, containsPair('url', 'https://example.com'));
    });

    test('returns null when model decides none', () async {
      final service = ToolDecisionService(
        llm: _FakeBaseLLM(decisionResponse: '{"toolName":"none"}'),
        toolRegistry: ToolRegistry(),
      );

      final result = await service.decideTool(
        userMessage: '直接回答',
        history: const [],
      );

      expect(result, isNull);
    });

    test('rejects unknown tool names', () async {
      final service = ToolDecisionService(
        llm: _FakeBaseLLM(
          decisionResponse:
              '{"toolName":"unknown_tool","arguments":{"value":"x"}}',
        ),
        toolRegistry: ToolRegistry(),
      );

      final result = await service.decideTool(
        userMessage: '做点什么',
        history: const [],
      );

      expect(result, isNull);
    });

    test('rejects malformed json', () async {
      final service = ToolDecisionService(
        llm: _FakeBaseLLM(decisionResponse: 'not-json'),
        toolRegistry: ToolRegistry(),
      );

      final result = await service.decideTool(
        userMessage: '做点什么',
        history: const [],
      );

      expect(result, isNull);
    });

    test('accepts json wrapped in markdown code fences', () async {
      final service = ToolDecisionService(
        llm: _FakeBaseLLM(
          decisionResponse:
              '```json\n{"toolName":"create_reminder","arguments":{"title":"交周报","dueAt":"2026-03-31T20:00:00+08:00"}}\n```',
        ),
        toolRegistry: ToolRegistry(),
      );

      final result = await service.decideTool(
        userMessage: '提醒我交周报',
        history: const [],
      );

      expect(result, isNotNull);
      expect(result!.toolName, 'create_reminder');
      expect(result.arguments, containsPair('title', '交周报'));
    });

    test('accepts json embedded in natural language wrapper', () async {
      final service = ToolDecisionService(
        llm: _FakeBaseLLM(
          decisionResponse:
              '我建议调用工具，结果如下：{"toolName":"create_calendar_event","arguments":{"title":"项目评审","startAt":"2026-03-31T15:00:00+08:00"}}',
        ),
        toolRegistry: ToolRegistry(),
      );

      final result = await service.decideTool(
        userMessage: '明天下午三点创建项目评审会议',
        history: const [],
      );

      expect(result, isNotNull);
      expect(result!.toolName, 'create_calendar_event');
      expect(result.arguments, containsPair('title', '项目评审'));
    });

    test('keeps reminder decision even when dueAt is not iso8601 and leaves validation to runtime', () async {
      final service = ToolDecisionService(
        llm: _FakeBaseLLM(
          decisionResponse:
              '{"toolName":"create_reminder","arguments":{"title":"交周报","dueAt":"today at 8pm"}}',
        ),
        toolRegistry: ToolRegistry(),
      );

      final result = await service.decideTool(
        userMessage: '提醒我今晚 8 点交周报',
        history: const [],
      );

      expect(result, isNotNull);
      expect(result!.toolName, 'create_reminder');
      expect(result.arguments['dueAt'], 'today at 8pm');
    });

    test('keeps calendar decision even when startAt is not iso8601 and leaves validation to runtime', () async {
      final service = ToolDecisionService(
        llm: _FakeBaseLLM(
          decisionResponse:
              '{"toolName":"create_calendar_event","arguments":{"title":"项目评审","startAt":"tomorrow at 3pm"}}',
        ),
        toolRegistry: ToolRegistry(),
      );

      final result = await service.decideTool(
        userMessage: '明天下午三点创建项目评审',
        history: const [],
      );

      expect(result, isNotNull);
      expect(result!.toolName, 'create_calendar_event');
      expect(result.arguments['startAt'], 'tomorrow at 3pm');
    });

    test('keeps reminder dueAt untouched and leaves normalization to runtime handler', () async {
      final service = ToolDecisionService(
        llm: _FakeBaseLLM(
          decisionResponse:
              '{"toolName":"create_reminder","arguments":{"title":"交周报","dueAt":"2025-02-14T20:00:00+08:00"}}',
        ),
        toolRegistry: ToolRegistry(),
      );

      final result = await service.decideTool(
        userMessage: '提醒我今天晚上8点交周报',
        history: const [],
      );

      expect(result, isNotNull);
      expect(result!.toolName, 'create_reminder');
      expect(result.arguments['dueAt'], '2025-02-14T20:00:00+08:00');
    });

    test('keeps calendar startAt and endAt untouched and leaves normalization to runtime handler', () async {
      final service = ToolDecisionService(
        llm: _FakeBaseLLM(
          decisionResponse:
              '{"toolName":"create_calendar_event","arguments":{"title":"项目评审","startAt":"2025-02-14T15:00:00+08:00","endAt":"2025-02-14T16:30:00+08:00"}}',
        ),
        toolRegistry: ToolRegistry(),
      );

      final result = await service.decideTool(
        userMessage: '明天下午三点到四点半创建项目评审',
        history: const [],
      );

      expect(result, isNotNull);
      expect(result!.toolName, 'create_calendar_event');
      expect(result.arguments['startAt'], '2025-02-14T15:00:00+08:00');
      expect(result.arguments['endAt'], '2025-02-14T16:30:00+08:00');
    });

    test('rejects non-map arguments', () async {
      final service = ToolDecisionService(
        llm: _FakeBaseLLM(
          decisionResponse:
              '{"toolName":"fetch_webpage","arguments":"https://example.com"}',
        ),
        toolRegistry: ToolRegistry(),
      );

      final result = await service.decideTool(
        userMessage: '读取网页',
        history: const [],
      );

      expect(result, isNull);
    });

    test('rejects fetch_webpage when user message does not contain a url', () async {
      final service = ToolDecisionService(
        llm: _FakeBaseLLM(
          decisionResponse:
              '{"toolName":"fetch_webpage","arguments":{"url":"https://example.com"}}',
        ),
        toolRegistry: ToolRegistry(),
      );

      final result = await service.decideTool(
        userMessage: '请搜索今天关于 OpenAI 的三条最新消息',
        history: const [],
      );

      expect(result, isNull);
    });

    test('accepts search_chat_history without hardcoded history keywords', () async {
      final service = ToolDecisionService(
        llm: _FakeBaseLLM(
          decisionResponse:
              '{"toolName":"search_chat_history","arguments":{"query":"OpenAI","maxResults":3}}',
        ),
        toolRegistry: ToolRegistry(),
      );

      final result = await service.decideTool(
        userMessage: '请搜索今天关于 OpenAI 的三条最新消息',
        history: const [],
      );

      expect(result, isNotNull);
      expect(result!.toolName, 'search_chat_history');
      expect(result.arguments, containsPair('query', 'OpenAI'));
    });

    test('records tool decision trace for accepted tool calls', () async {
      final traceLogs = <Map<String, dynamic>>[];
      final recorder = ChatTraceRecorder(
        logger: (entry) => traceLogs.add(entry),
      );
      final service = ToolDecisionService(
        llm: _FakeBaseLLM(
          decisionResponse:
              '{"toolName":"web_search","arguments":{"query":"OpenAI 最新消息","maxResults":5}}',
        ),
        toolRegistry: ToolRegistry(),
        traceRecorder: recorder,
      );

      final result = await service.decideTool(
        userMessage: '请搜索 OpenAI 最新消息',
        history: const [],
        turnId: 'turn-trace-1',
      );

      expect(result, isNotNull);
      final traceLog = traceLogs.singleWhere(
        (entry) => entry['stage'] == ChatTraceStage.toolDecisionDone.name,
      );
      expect(traceLog['turnId'], 'turn-trace-1');
      expect(traceLog['status'], ChatTraceStatus.success.name);
      expect((traceLog['data'] as Map<String, dynamic>)['toolName'], 'web_search');
    });
  });
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
