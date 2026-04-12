import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/tools/core/tool_execution_context.dart';
import 'package:ai_chat/tools/handlers/share_result_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShareResultToolHandler', () {
    test('normalizes text and subject before executing share action', () async {
      final handler = ShareResultToolHandler(
        resultSharer: ({required text, subject}) async => ToolResult(
          toolName: 'share_result',
          status: ToolExecutionStatus.success,
          summary: '已发起分享',
          data: {
            'text': text,
            'subject': subject,
          },
        ),
      );

      final resolution = await handler.normalizeArguments(
        rawArguments: {
          'text': '  这是分享内容  ',
          'subject': '  分享标题  ',
        },
        userMessage: '帮我分享出去',
        history: const [],
        now: DateTime(2026, 4, 12),
      );

      expect(resolution.isValid, isTrue);
      expect(resolution.normalizedArguments['text'], '这是分享内容');
      expect(resolution.normalizedArguments['subject'], '分享标题');

      final result = await handler.execute(
        ToolExecutionContext(
          groupId: 1,
          toolName: 'share_result',
          arguments: resolution.normalizedArguments,
          history: const <ChatMessage>[],
          now: DateTime(2026, 4, 12),
        ),
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.data['text'], '这是分享内容');
      expect(result.data['subject'], '分享标题');
    });
  });
}
