import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/tools/core/tool_execution_context.dart';
import 'package:ai_chat/tools/handlers/fetch_webpage_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FetchWebpageToolHandler', () {
    test('normalizes url and extractMode before executing webpage fetch', () async {
      final handler = FetchWebpageToolHandler(
        webpageFetcher: ({required url, extractMode}) async => ToolResult(
          toolName: 'fetch_webpage',
          status: ToolExecutionStatus.success,
          summary: '已读取网页：Example',
          data: {
            'url': url,
            'title': 'Example',
            'content': '网页正文',
            'extractMode': extractMode,
          },
        ),
      );

      final resolution = await handler.normalizeArguments(
        rawArguments: {
          'url': ' https://example.com/article ',
          'extractMode': ' readable_text ',
        },
        userMessage: '读取这个网页',
        history: const [],
        now: DateTime(2026, 4, 12),
      );

      expect(resolution.isValid, isTrue);
      expect(resolution.normalizedArguments['url'], 'https://example.com/article');
      expect(resolution.normalizedArguments['extractMode'], 'readable_text');

      final result = await handler.execute(
        ToolExecutionContext(
          groupId: 1,
          toolName: 'fetch_webpage',
          arguments: resolution.normalizedArguments,
          history: const <ChatMessage>[],
          now: DateTime(2026, 4, 12),
        ),
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.data['url'], 'https://example.com/article');
      expect(result.data['extractMode'], 'readable_text');
    });
  });
}
