import 'dart:convert';

import 'package:ai_chat/models/agent/model_tool_call.dart';
import 'package:ai_chat/models/llm/adapters/anthropic_messages_adapter.dart';
import 'package:ai_chat/models/llm/adapters/responses_adapter.dart';
import 'package:ai_chat/models/llm/adapters/sdk_chat_completions_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SdkChatCompletionsAdapter.parseDecision', () {
    test('keeps assistant text when tool calls are present in same message',
        () {
      const adapter = SdkChatCompletionsAdapter();

      final decision = adapter.parseDecision({
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': '我先读取这个页面。',
              'tool_calls': [
                {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {
                    'name': 'fetch_webpage',
                    'arguments': jsonEncode({'url': 'https://example.com'}),
                  },
                },
              ],
            },
          },
        ],
      });

      expect(decision, isNotNull);
      expect(decision!.assistantMessage, '我先读取这个页面。');
      expect(decision.toolCalls.single.toolName, 'fetch_webpage');
      expect(decision.isTerminal, isFalse);
    });

    test('keeps reasoning content separate from tool-use assistant text', () {
      const adapter = SdkChatCompletionsAdapter();

      final decision = adapter.parseDecision({
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'reasoning_content': '我需要先读取页面确认内容。',
              'content': '我先读取这个页面。',
              'tool_calls': [
                {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {
                    'name': 'fetch_webpage',
                    'arguments': jsonEncode({'url': 'https://example.com'}),
                  },
                },
              ],
            },
          },
        ],
      });

      expect(decision, isNotNull);
      expect(decision!.visibleReasoning, '我需要先读取页面确认内容。');
      expect(decision.assistantMessage, '我先读取这个页面。');
      expect(decision.toolCalls.single.toolName, 'fetch_webpage');
    });

    test('parses multiple tool calls from one assistant message', () {
      const adapter = SdkChatCompletionsAdapter();

      final decision = adapter.parseDecision({
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'tool_calls': [
                {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {
                    'name': 'search_chat_history',
                    'arguments': jsonEncode({'query': '数据库版本'}),
                  },
                },
                {
                  'id': 'call_2',
                  'type': 'function',
                  'function': {
                    'name': 'Write',
                    'arguments': jsonEncode({'title': '数据库版本确认'}),
                  },
                },
              ],
            },
          },
        ],
      });

      expect(decision, isNotNull);
      expect(decision!.toolCalls, hasLength(2));
      expect(
        decision.toolCalls,
        [
          isA<ModelToolCall>()
              .having(
                  (value) => value.providerCallId, 'providerCallId', 'call_1')
              .having(
                  (value) => value.toolName, 'toolName', 'search_chat_history')
              .having((value) => value.sequence, 'sequence', 0),
          isA<ModelToolCall>()
              .having(
                  (value) => value.providerCallId, 'providerCallId', 'call_2')
              .having((value) => value.toolName, 'toolName', 'Write')
              .having((value) => value.sequence, 'sequence', 1),
        ],
      );
      expect(decision.assistantMessage, isNull);
      expect(decision.isTerminal, isFalse);
    });

    test('returns terminal assistant message when no tool calls exist', () {
      const adapter = SdkChatCompletionsAdapter();

      final decision = adapter.parseDecision({
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': '我已经完成所有步骤。',
            },
          },
        ],
      });

      expect(decision, isNotNull);
      expect(decision!.toolCalls, isEmpty);
      expect(decision.assistantMessage, '我已经完成所有步骤。');
      expect(decision.isTerminal, isTrue);
    });

    test('preserves markdown whitespace across split content parts', () {
      const adapter = SdkChatCompletionsAdapter();

      final decision = adapter.parseDecision({
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': [
                {'type': 'text', 'text': '# 标题\n\n'},
                {'type': 'text', 'text': '正文段落。\n\n'},
                {'type': 'text', 'text': '```dart\n'},
                {'type': 'text', 'text': 'ListView.builder();\n```'},
              ],
            },
          },
        ],
      });

      expect(decision, isNotNull);
      expect(
        decision!.assistantMessage,
        '# 标题\n\n正文段落。\n\n```dart\nListView.builder();\n```',
      );
    });

    test('extracts inline think tag from terminal assistant message', () {
      const adapter = SdkChatCompletionsAdapter();

      final decision = adapter.parseDecision({
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': '<think>先判断这个问题是否需要工具。</think>\n\n直接回答。',
            },
          },
        ],
      });

      expect(decision, isNotNull);
      expect(decision!.visibleReasoning, '先判断这个问题是否需要工具。');
      expect(decision.assistantMessage, '直接回答。');
      expect(decision.toolCalls, isEmpty);
      expect(decision.isTerminal, isTrue);
    });

    test('extracts inline think tag when tool calls share the same message',
        () {
      const adapter = SdkChatCompletionsAdapter();

      final decision = adapter.parseDecision({
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': '<think>需要先读取页面确认内容。</think>\n\n我先读取这个页面。',
              'tool_calls': [
                {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {
                    'name': 'fetch_webpage',
                    'arguments': jsonEncode({'url': 'https://example.com'}),
                  },
                },
              ],
            },
          },
        ],
      });

      expect(decision, isNotNull);
      expect(decision!.visibleReasoning, '需要先读取页面确认内容。');
      expect(decision.assistantMessage, '我先读取这个页面。');
      expect(decision.toolCalls.single.toolName, 'fetch_webpage');
      expect(decision.isTerminal, isFalse);
    });
  });

  group('ResponsesAdapter.parseDecision', () {
    test('keeps assistant text when output mixes message and function_call',
        () {
      const adapter = ResponsesAdapter();

      final decision = adapter.parseDecision({
        'id': 'resp_mixed',
        'output': [
          {
            'type': 'message',
            'content': [
              {
                'type': 'output_text',
                'text': '我先搜索一下。',
              },
            ],
          },
          {
            'type': 'function_call',
            'call_id': 'fc_1',
            'name': 'web_search',
            'arguments': jsonEncode({'query': 'OpenAI 最新发布'}),
          },
        ],
      });

      expect(decision, isNotNull);
      expect(decision!.assistantMessage, '我先搜索一下。');
      expect(decision.toolCalls.single.toolName, 'web_search');
      expect(decision.providerState, containsPair('response_id', 'resp_mixed'));
      expect(decision.isTerminal, isFalse);
    });

    test('extracts reasoning summary separately from tool calls', () {
      const adapter = ResponsesAdapter();

      final decision = adapter.parseDecision({
        'id': 'resp_reasoning_tool',
        'output': [
          {
            'type': 'reasoning',
            'summary': [
              {'type': 'summary_text', 'text': '需要先联网确认最新信息。'},
            ],
          },
          {
            'type': 'function_call',
            'call_id': 'fc_1',
            'name': 'web_search',
            'arguments': jsonEncode({'query': 'OpenAI 最新发布'}),
          },
        ],
      });

      expect(decision, isNotNull);
      expect(decision!.visibleReasoning, '需要先联网确认最新信息。');
      expect(decision.toolCalls.single.toolName, 'web_search');
      expect(decision.isTerminal, isFalse);
    });

    test('parses multiple function calls from one response output', () {
      const adapter = ResponsesAdapter();

      final decision = adapter.parseDecision({
        'id': 'resp_123',
        'output': [
          {
            'type': 'function_call',
            'call_id': 'fc_1',
            'name': 'search_chat_history',
            'arguments': jsonEncode({'query': '数据库版本'}),
          },
          {
            'type': 'function_call',
            'call_id': 'fc_2',
            'name': 'create_reminder',
            'arguments': jsonEncode({'title': '同步结论给测试同学'}),
          },
        ],
      });

      expect(decision, isNotNull);
      expect(decision!.providerState, containsPair('response_id', 'resp_123'));
      expect(decision.toolCalls, hasLength(2));
      expect(decision.toolCalls.first.providerCallId, 'fc_1');
      expect(decision.toolCalls.last.providerCallId, 'fc_2');
      expect(decision.isTerminal, isFalse);
    });

    test('returns terminal assistant message when output contains message', () {
      const adapter = ResponsesAdapter();

      final decision = adapter.parseDecision({
        'id': 'resp_456',
        'output': [
          {
            'type': 'message',
            'content': [
              {
                'type': 'output_text',
                'text': '三件事都已经处理完毕。',
              },
            ],
          },
        ],
      });

      expect(decision, isNotNull);
      expect(decision!.toolCalls, isEmpty);
      expect(decision.assistantMessage, '三件事都已经处理完毕。');
      expect(decision.isTerminal, isTrue);
      expect(decision.providerState, containsPair('response_id', 'resp_456'));
    });

    test('preserves markdown whitespace across split output text parts', () {
      const adapter = ResponsesAdapter();

      final decision = adapter.parseDecision({
        'id': 'resp_markdown_parts',
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': '# 标题\n\n'},
              {'type': 'output_text', 'text': '1. 第一项\n'},
              {'type': 'output_text', 'text': '2. 第二项'},
            ],
          },
        ],
      });

      expect(decision, isNotNull);
      expect(
        decision!.assistantMessage,
        '# 标题\n\n1. 第一项\n2. 第二项',
      );
    });

    test('preserves response_id when payload exposes a reusable response id',
        () {
      const adapter = ResponsesAdapter();

      final decision = adapter.parseDecision({
        'id': 'resp_unstored',
        'store': false,
        'output': [
          {
            'type': 'function_call',
            'call_id': 'fc_1',
            'name': 'Write',
            'arguments': jsonEncode({
              'file_path': 'personal_profile.md',
              'content': '# 个人资料',
            }),
          },
        ],
      });

      expect(decision, isNotNull);
      expect(decision!.toolCalls, hasLength(1));
      expect(
          decision.providerState, containsPair('response_id', 'resp_unstored'));
    });
  });

  group('AnthropicMessagesAdapter.parseDecision', () {
    test('extracts thinking separately from tool calls', () {
      const adapter = AnthropicMessagesAdapter();

      final decision = adapter.parseDecision({
        'id': 'msg_1',
        'content': [
          {'type': 'thinking', 'thinking': '应该先读取文件再回答。'},
          {
            'type': 'tool_use',
            'id': 'toolu_1',
            'name': 'read_file',
            'input': {'path': 'README.md'},
          },
        ],
      });

      expect(decision, isNotNull);
      expect(decision!.visibleReasoning, '应该先读取文件再回答。');
      expect(decision.assistantMessage, isNull);
      expect(decision.toolCalls.single.toolName, 'read_file');
    });

    test('extracts final thinking separately from final text', () {
      const adapter = AnthropicMessagesAdapter();

      final decision = adapter.parseDecision({
        'id': 'msg_final',
        'content': [
          {'type': 'thinking', 'thinking': '我已经有足够信息，可以总结。'},
          {'type': 'text', 'text': '最终回答。'},
        ],
      });

      expect(decision, isNotNull);
      expect(decision!.visibleReasoning, '我已经有足够信息，可以总结。');
      expect(decision.assistantMessage, '最终回答。');
      expect(decision.isTerminal, isTrue);
    });

    test('preserves markdown whitespace across split text blocks', () {
      const adapter = AnthropicMessagesAdapter();

      final decision = adapter.parseDecision({
        'id': 'msg_markdown_parts',
        'content': [
          {'type': 'text', 'text': '## 方案\n\n'},
          {'type': 'text', 'text': '- 外层滚动\n'},
          {'type': 'text', 'text': '- 内层固定高度'},
        ],
      });

      expect(decision, isNotNull);
      expect(
        decision!.assistantMessage,
        '## 方案\n\n- 外层滚动\n- 内层固定高度',
      );
    });
  });
}
