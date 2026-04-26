import 'dart:convert';

import 'package:ai_chat/models/agent/model_tool_call.dart';
import 'package:ai_chat/models/llm/tool_loop/anthropic_messages_tool_loop_adapter.dart';
import 'package:ai_chat/models/llm/tool_loop/openai_chat_completions_tool_loop_adapter.dart';
import 'package:ai_chat/models/llm/tool_loop/openai_responses_tool_loop_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OpenAIChatCompletionsToolLoopAdapter', () {
    test('keeps assistant text when tool calls are present in same message',
        () {
      const adapter = OpenAIChatCompletionsToolLoopAdapter();

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
      const adapter = OpenAIChatCompletionsToolLoopAdapter();

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
      const adapter = OpenAIChatCompletionsToolLoopAdapter();

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
      const adapter = OpenAIChatCompletionsToolLoopAdapter();

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
  });

  group('OpenAIResponsesToolLoopAdapter', () {
    test('keeps assistant text when output mixes message and function_call',
        () {
      const adapter = OpenAIResponsesToolLoopAdapter();

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
      const adapter = OpenAIResponsesToolLoopAdapter();

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
      const adapter = OpenAIResponsesToolLoopAdapter();

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
      const adapter = OpenAIResponsesToolLoopAdapter();

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

    test('preserves response_id when payload exposes a reusable response id',
        () {
      const adapter = OpenAIResponsesToolLoopAdapter();

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
      expect(decision.providerState, containsPair('response_id', 'resp_unstored'));
    });
  });

  group('AnthropicMessagesToolLoopAdapter', () {
    test('extracts thinking separately from tool calls', () {
      const adapter = AnthropicMessagesToolLoopAdapter();

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
      const adapter = AnthropicMessagesToolLoopAdapter();

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
  });
}
