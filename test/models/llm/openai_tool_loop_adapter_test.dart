import 'dart:convert';

import 'package:ai_chat/models/agent/model_tool_call.dart';
import 'package:ai_chat/models/llm/tool_loop/openai_chat_completions_tool_loop_adapter.dart';
import 'package:ai_chat/models/llm/tool_loop/openai_responses_tool_loop_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OpenAIChatCompletionsToolLoopAdapter', () {
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
                    'name': 'save_note',
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
              .having((value) => value.toolName, 'toolName', 'save_note')
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
  });
}
