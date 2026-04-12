import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/tools/core/tool_execution_context.dart';
import 'package:ai_chat/tools/handlers/search_chat_history_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SearchChatHistoryToolHandler', () {
    test('normalizes query and maxResults before executing history search', () async {
      final handler = SearchChatHistoryToolHandler(
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
                'text': '数据库版本已经升级到 6',
                'role': 'assistant',
              },
            ],
            'maxResults': maxResults,
          },
        ),
      );

      final resolution = await handler.normalizeArguments(
        rawArguments: {'query': '  数据库  '},
        userMessage: '我刚才提过数据库版本吗？',
        history: const [],
        now: DateTime(2026, 4, 12),
      );

      expect(resolution.isValid, isTrue);
      expect(resolution.normalizedArguments['query'], '数据库');
      expect(resolution.normalizedArguments['maxResults'], 3);

      final result = await handler.execute(
        ToolExecutionContext(
          groupId: 1,
          toolName: 'search_chat_history',
          arguments: resolution.normalizedArguments,
          history: const <ChatMessage>[],
          now: DateTime(2026, 4, 12),
        ),
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.data['query'], '数据库');
      expect(result.data['maxResults'], 3);
    });
  });
}
