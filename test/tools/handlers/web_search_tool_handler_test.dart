import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/tools/core/tool_execution_context.dart';
import 'package:ai_chat/tools/handlers/web_search_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebSearchToolHandler', () {
    test('normalizes maxResults and executes search adapter', () async {
      final handler = WebSearchToolHandler(
        webSearcher: ({required query, maxResults}) async => ToolResult(
          toolName: 'web_search',
          status: ToolExecutionStatus.success,
          summary: '已执行联网搜索',
          data: {
            'query': query,
            'maxResults': maxResults,
            'results': const [],
          },
        ),
      );

      final resolution = await handler.normalizeArguments(
        rawArguments: {'query': 'OpenAI 最新消息'},
        userMessage: '请搜索 OpenAI 最新消息',
        history: const [],
        now: DateTime(2026, 4, 12),
      );

      expect(resolution.isValid, isTrue);
      expect(resolution.normalizedArguments['query'], 'OpenAI 最新消息');
      expect(resolution.normalizedArguments['maxResults'], 5);

      final result = await handler.execute(
        ToolExecutionContext(
          groupId: 1,
          toolName: 'web_search',
          arguments: resolution.normalizedArguments,
          history: const <ChatMessage>[],
          now: DateTime(2026, 4, 12),
        ),
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.data['query'], 'OpenAI 最新消息');
      expect(result.data['maxResults'], 5);
    });

    test('accepts planner num_results alias and clamps it into maxResults', () async {
      final handler = WebSearchToolHandler(
        webSearcher: ({required query, maxResults}) async => ToolResult(
          toolName: 'web_search',
          status: ToolExecutionStatus.success,
          summary: '已执行联网搜索',
          data: {
            'query': query,
            'maxResults': maxResults,
            'results': const [],
          },
        ),
      );

      final resolution = await handler.normalizeArguments(
        rawArguments: {
          'query': 'OpenAI latest news',
          'num_results': 12,
        },
        userMessage: '搜索 OpenAI latest news',
        history: const [],
        now: DateTime(2026, 4, 13),
      );

      expect(resolution.isValid, isTrue);
      expect(resolution.normalizedArguments['query'], 'OpenAI latest news');
      expect(resolution.normalizedArguments['maxResults'], 10);
    });

    test('description includes current month-year and sources requirement', () {
      final handler = WebSearchToolHandler(
        webSearcher: ({required query, maxResults}) async => const ToolResult(
          toolName: 'web_search',
          status: ToolExecutionStatus.success,
          summary: 'ok',
        ),
        currentMonthYearProvider: () => 'April 2026',
      );

      final description = handler.definition.descriptionForModel;

      expect(description, contains('Sources:'));
      expect(description, contains('April 2026'));
      expect(description, contains('You MUST use this year'));
      expect(description, contains('fetch_webpage'));
      expect(description, contains('search_chat_history'));
    });
  });
}
