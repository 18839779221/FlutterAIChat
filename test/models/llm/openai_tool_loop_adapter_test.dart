import 'dart:convert';

import 'package:ai_chat/models/agent/model_tool_call.dart';
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

    test('does not preserve response_id when provider marks response unstored',
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
      expect(decision.providerState, isEmpty);
    });
  });
}
