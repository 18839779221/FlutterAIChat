import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/tools/core/tool_execution_context.dart';
import 'package:ai_chat/tools/handlers/fetch_webpage_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FetchWebpageToolHandler', () {
    test('definition exposes only url and prompt arguments', () {
      final handler = FetchWebpageToolHandler(
        webpageFetcher: ({required url, required prompt}) async => ToolResult(
          toolName: 'fetch_webpage',
          status: ToolExecutionStatus.success,
          summary: 'ok',
          data: {'url': url, 'prompt': prompt},
        ),
      );

      expect(handler.definition.parameters, {
        'url': 'string',
        'prompt': 'string',
      });
      expect(handler.definition.argumentSchema!.required, ['url', 'prompt']);
      expect(
        handler.definition.argumentSchema!.properties['prompt']?.description,
        contains('extract, summarize, inspect, compare, or transform'),
      );
    });

    test(
        'descriptionForModel mentions internal side model and does not repeat Input section',
        () {
      final definition = FetchWebpageToolHandler(
        webpageFetcher: ({required url, required prompt}) async =>
            const ToolResult(
          toolName: 'fetch_webpage',
          status: ToolExecutionStatus.success,
          summary: 'ok',
        ),
      ).definition;

      expect(definition.descriptionForModel, contains('internal side model'));
      expect(definition.descriptionForModel, isNot(contains('Input:')));
    });

    test('normalizeArguments requires both url and prompt', () async {
      final handler = FetchWebpageToolHandler(
        webpageFetcher: ({required url, required prompt}) async =>
            const ToolResult(
          toolName: 'fetch_webpage',
          status: ToolExecutionStatus.success,
          summary: 'ok',
        ),
      );

      final invalid = await handler.normalizeArguments(
        rawArguments: {'url': 'https://flutter.dev'},
        userMessage: 'read it',
        history: const [],
        now: DateTime(2026, 4, 25),
      );

      expect(invalid.isValid, isFalse);
      expect(invalid.errorSummary, contains('prompt'));
    });

    test('execute passes url and prompt to webpageFetcher', () async {
      late String capturedUrl;
      late String capturedPrompt;
      final handler = FetchWebpageToolHandler(
        webpageFetcher: ({required url, required prompt}) async {
          capturedUrl = url;
          capturedPrompt = prompt;
          return ToolResult(
            toolName: 'fetch_webpage',
            status: ToolExecutionStatus.success,
            summary: '已返回网页处理结果',
            data: {
              'url': url,
              'host': 'flutter.dev',
              'prompt': prompt,
              'processedContent': '处理后的正文',
            },
          );
        },
      );

      await handler.execute(
        ToolExecutionContext(
          groupId: 1,
          toolName: 'fetch_webpage',
          arguments: const {
            'url': 'https://flutter.dev',
            'prompt': '提取文中和 TextField 焦点问题相关的信息',
          },
          history: const <ChatMessage>[],
          now: DateTime(2026, 4, 25),
        ),
      );

      expect(capturedUrl, 'https://flutter.dev');
      expect(capturedPrompt, contains('TextField'));
    });

    test('buildContextMessages uses processed result instead of raw webpage body label',
        () {
      final handler = FetchWebpageToolHandler(
        webpageFetcher: ({required url, required prompt}) async =>
            const ToolResult(
          toolName: 'fetch_webpage',
          status: ToolExecutionStatus.success,
          summary: 'ok',
        ),
      );

      final messages = handler.buildContextMessages(
        result: const ToolResult(
          toolName: 'fetch_webpage',
          status: ToolExecutionStatus.success,
          summary: '已返回网页处理结果',
          data: {
            'url': 'https://flutter.dev',
            'prompt': '总结动画抖动成因',
            'processedContent': '页面提到频繁 rebuild 可能导致抖动。',
          },
        ),
        context: ToolExecutionContext(
          groupId: 1,
          toolName: 'fetch_webpage',
          arguments: const {},
          history: const <ChatMessage>[],
          now: DateTime(2026, 4, 25),
        ),
      );

      expect(messages.single.text, contains('处理结果'));
      expect(messages.single.text, isNot(contains('网页正文')));
    });
  });
}
