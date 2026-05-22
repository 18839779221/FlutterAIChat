import 'package:ai_chat/models/llm/adapters/sdk_chat_completions_adapter.dart';
import 'package:ai_chat/models/llm/streaming_decision_accumulator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SdkChatCompletionsAdapter.extractRawAssistantMessage', () {
    const adapter = SdkChatCompletionsAdapter();

    test('保留 content + tool_calls + reasoning_content 三类字段', () {
      final raw = adapter.extractRawAssistantMessage(const {
        'id': 'resp_1',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': 'Let me search',
              'reasoning_content': 'think first',
              'tool_calls': [
                {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {'name': 'search', 'arguments': '{"q":"x"}'},
                },
              ],
            },
          },
        ],
      });
      expect(raw, isNotNull);
      expect(raw!['role'], 'assistant');
      expect(raw['content'], 'Let me search');
      expect(raw['reasoning_content'], 'think first');
      expect((raw['tool_calls'] as List).first['id'], 'call_1');
    });

    test('空 choices 返回 null', () {
      final raw = adapter.extractRawAssistantMessage(const {'choices': []});
      expect(raw, isNull);
    });

    test('未来 provider 新增字段也透传', () {
      final raw = adapter.extractRawAssistantMessage(const {
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': 'hi',
              'future_provider_field': 'whatever',
            },
          },
        ],
      });
      expect(raw!['future_provider_field'], 'whatever');
    });
  });

  group('SdkChatCompletionsAdapter.assembleRawFromStreamingSnapshot', () {
    const adapter = SdkChatCompletionsAdapter();

    test('累积 text + reasoning + 一条 tool_call 拼成完整 message', () {
      const snapshot = StreamingDecisionAccumulatorSnapshot(
        text: 'final',
        reasoning: 'why',
        toolCalls: [
          StreamingToolCallDraft(
            id: 'c1',
            toolName: 's',
            argumentsBuffer: '{"q":"x"}',
            sequence: 0,
            isDone: true,
          ),
        ],
        providerState: {},
      );
      final raw = adapter.assembleRawFromStreamingSnapshot(snapshot);
      expect(raw, isNotNull);
      expect(raw!['role'], 'assistant');
      expect(raw['content'], 'final');
      expect(raw['reasoning_content'], 'why');
      final tc = (raw['tool_calls'] as List).first as Map;
      expect(tc['id'], 'c1');
      expect(tc['type'], 'function');
      expect((tc['function'] as Map)['arguments'], '{"q":"x"}');
    });

    test('text-only snapshot 不输出 tool_calls 字段', () {
      const snapshot = StreamingDecisionAccumulatorSnapshot(
        text: 'hi',
        reasoning: null,
        toolCalls: [],
        providerState: {},
      );
      final raw = adapter.assembleRawFromStreamingSnapshot(snapshot);
      expect(raw, isNotNull);
      expect(raw!['content'], 'hi');
      expect(raw.containsKey('tool_calls'), isFalse);
      expect(raw.containsKey('reasoning_content'), isFalse);
    });

    test('完全空 snapshot 返回 null', () {
      const snapshot = StreamingDecisionAccumulatorSnapshot(
        text: null,
        reasoning: null,
        toolCalls: [],
        providerState: {},
      );
      expect(adapter.assembleRawFromStreamingSnapshot(snapshot), isNull);
    });
  });
}
